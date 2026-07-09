'use client'

import { Fragment, useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, ClipboardList, Wrench, PlusCircle, Trash2, CheckCircle2, Loader2, Package, Ticket, Printer,
  ChevronDown, ChevronRight,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getNcRecepcion, planificarNcEquipo, asignarRecursosNcEquipo, getNcMaterialesEquipo,
  registrarNcAdhoc, generarNcDesdeRecepcion,
  getRecepcionesParaNc, getActivosParaNc, subirFotoNc, type NcRecepcion, type NcMaterial,
} from '@/lib/services/no-conformidades'
import { getProductos } from '@/lib/services/inventario'
import {
  getRecursosPorHallazgo, getRecursosOT, validarRecurso, agregarRecursoJefe, subirFotoRecurso,
  getSeguimientoRecursos,
  RECURSO_ESTADO_LABEL, type OTRecurso, type OTRecursoSeguimiento,
} from '@/lib/services/ot-recursos'
import { buscarProductos } from '@/lib/services/ot-materiales'
import { subirFirmaTicket, crearTicket } from '@/lib/services/bodega-tickets'
import { SignaturePad } from '@/components/ui/signature-pad'
import { getCategoriasProducto } from '@/lib/services/producto-categorias'
import { solicitarMaterialBodega } from '@/lib/services/bodega-solicitudes'
import { MECANICOS } from '@/lib/taller-grupos'
import { cn } from '@/lib/utils'

const ESTADO_BADGE: Record<string, { v: any; t: string }> = {
  registrada: { v: 'default', t: 'Registrada' },
  con_recursos: { v: 'asignada', t: 'Con recursos' },
  planificada: { v: 'en_ejecucion', t: 'Planificada' },
  en_ejecucion: { v: 'en_ejecucion', t: 'En ejecución' },
  resuelta: { v: 'operativo', t: 'Resuelta' },
  descartada: { v: 'default', t: 'Descartada' },
}
// Estado del CONJUNTO del equipo (el peor manda)
const ESTADO_EQUIPO: Record<string, { v: any; t: string }> = {
  registrada: { v: 'default', t: 'Sin recursos' },
  con_recursos: { v: 'asignada', t: 'Con recursos' },
  planificada: { v: 'en_ejecucion', t: 'Planificado' },
  en_ejecucion: { v: 'en_ejecucion', t: 'En ejecución' },
  resuelta: { v: 'operativo', t: 'Resuelto' },
  descartada: { v: 'default', t: 'Descartado' },
}
const ORDEN_ESTADO = ['registrada', 'con_recursos', 'planificada', 'en_ejecucion', 'resuelta', 'descartada']
const ORDEN_SEV = ['critica', 'alta', 'media', 'baja']
const FILTROS = [['', 'Todas'], ['registrada', 'Sin recursos'], ['con_recursos', 'Con recursos'], ['planificada', 'Planificadas']] as const

// Conjunto de NC de una patente: en el taller TODO se gestiona por equipo (MIG209)
type EquipoNC = {
  activoId: string
  patente: string
  nombre: string | null
  ncs: NcRecepcion[]
  pendientes: NcRecepcion[]   // sin OT correctiva todavía (planificables)
  sevMax: string
  estado: string
  grupos: string | null
  horas: number
  dias: number
  nMateriales: number
  nInsumosOperador: number
}

export default function NoConformidadesPage() {
  useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [filtro, setFiltro] = useState('')
  const { data: ncs = [], isLoading } = useQuery({ queryKey: ['nc-recepcion', filtro], queryFn: () => getNcRecepcion(filtro || undefined), staleTime: 20_000 })
  const [recursosEquipo, setRecursosEquipo] = useState<EquipoNC | null>(null)
  const [genOpen, setGenOpen] = useState(false)
  const [adhocOpen, setAdhocOpen] = useState(false)
  const [valeOpen, setValeOpen] = useState(false)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [expandido, setExpandido] = useState<Record<string, boolean>>({})

  // Equipos con insumos aprobados/recibidos listos para vale (botón grande)
  const { data: seguimiento = [] } = useQuery({
    queryKey: ['vale-equipos-listos'],
    queryFn: getSeguimientoRecursos,
    staleTime: 20_000,
  })
  const equiposListos = useMemo(() => {
    const m = new Map<string, { otId: string; otFolio: string; patente: string; nombre: string | null; items: OTRecursoSeguimiento[] }>()
    for (const f of seguimiento) {
      if (f.estado !== 'aprobado' && f.estado !== 'recibido') continue
      const g = m.get(f.ot_id) ?? {
        otId: f.ot_id, otFolio: f.ot_folio,
        patente: f.activo_patente ?? f.activo_codigo ?? '—', nombre: f.activo_nombre, items: [],
      }
      g.items.push(f)
      m.set(f.ot_id, g)
    }
    return Array.from(m.values())
  }, [seguimiento])

  // ── Agrupar las NC por equipo (patente): así trabaja el taller ─────────────
  const equipos = useMemo<EquipoNC[]>(() => {
    const m = new Map<string, EquipoNC>()
    for (const nc of ncs) {
      const g = m.get(nc.activo_id) ?? {
        activoId: nc.activo_id, patente: nc.patente ?? nc.codigo ?? '—', nombre: nc.equipo,
        ncs: [], pendientes: [], sevMax: 'baja', estado: 'descartada',
        grupos: null, horas: 0, dias: 0, nMateriales: 0, nInsumosOperador: 0,
      }
      g.ncs.push(nc)
      if (!nc.plan_ot_id && ['registrada', 'con_recursos'].includes(nc.estado_planificacion)) g.pendientes.push(nc)
      if (ORDEN_SEV.indexOf(nc.severidad) < ORDEN_SEV.indexOf(g.sevMax as any)) g.sevMax = nc.severidad
      if (ORDEN_ESTADO.indexOf(nc.estado_planificacion) < ORDEN_ESTADO.indexOf(g.estado)) g.estado = nc.estado_planificacion
      if (nc.grupo_trabajo && !(g.grupos ?? '').includes(nc.grupo_trabajo)) g.grupos = g.grupos ? `${g.grupos}, ${nc.grupo_trabajo}` : nc.grupo_trabajo
      g.horas += nc.horas_estimadas ?? 0
      g.dias = Math.max(g.dias, nc.tiempo_estimado_dias ?? 0)
      g.nMateriales += nc.n_materiales
      g.nInsumosOperador += nc.n_recursos_operador
      m.set(nc.activo_id, g)
    }
    return Array.from(m.values()).sort((a, b) =>
      ORDEN_ESTADO.indexOf(a.estado) - ORDEN_ESTADO.indexOf(b.estado) || a.patente.localeCompare(b.patente))
  }, [ncs])

  const invalidar = () => qc.invalidateQueries({ queryKey: ['nc-recepcion'] })

  const kpi = useMemo(() => ({
    total: equipos.length,
    sin: equipos.filter((e) => e.estado === 'registrada').length,
    con: equipos.filter((e) => e.estado === 'con_recursos').length,
    plan: equipos.filter((e) => ['planificada', 'en_ejecucion'].includes(e.estado)).length,
  }), [equipos])

  const planificar = async (eq: EquipoNC) => {
    setBusyId(eq.activoId)
    try {
      const r = await planificarNcEquipo(eq.activoId)
      if (!r.ot_id) { toast.error(r.mensaje ?? 'Sin NC pendientes'); return }
      toast.success(r.ot_reutilizada
        ? `${r.n_ncs} NC de ${eq.patente} sumadas a la OT correctiva ya abierta`
        : `OT correctiva creada para ${eq.patente} con ${r.n_ncs} NC`)
      invalidar(); qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] }); qc.invalidateQueries({ queryKey: ['nc-ot-por-agendar'] })
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al planificar') } finally { setBusyId(null) }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2"><AlertTriangle className="h-6 w-6 text-orange-600" /> No Conformidades por equipo</h1>
          <p className="text-sm text-muted-foreground">
            Las NC llegan solas desde el taller y la recepción, y aquí se trabajan como el taller:
            TODO el conjunto de la patente junto — recursos, vale de bodega y UNA OT correctiva por equipo.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Button variant="outline" onClick={() => setGenOpen(true)}
                  title="Convierte en NC los ítems malos de un checklist de recepción de equipo (cuando vuelve de arriendo)">
            <ClipboardList className="h-4 w-4 mr-1" /> NC desde recepción de equipo
          </Button>
          <Button variant="outline" onClick={() => setAdhocOpen(true)}
                  title="Registrar a mano un daño/falla detectado fuera de un checklist (foto obligatoria)">
            <PlusCircle className="h-4 w-4 mr-1" /> NC manual (con foto)
          </Button>
          <Button onClick={() => setValeOpen(true)} disabled={equiposListos.length === 0}
                  className="bg-orange-600 hover:bg-orange-700 text-white font-bold px-5"
                  title="Elegir la patente, revisar lo aprobado y emitir el vale de bodega (llega a bodega y se imprime para el retiro)">
            <Ticket className="h-5 w-5 mr-1.5" /> Vale para bodega{equiposListos.length > 0 ? ` (${equiposListos.length})` : ''}
          </Button>
        </div>
      </div>

      <div className="grid gap-3 grid-cols-2 md:grid-cols-4">
        <Kpi label="Equipos con NC" value={kpi.total} />
        <Kpi label="Sin recursos" value={kpi.sin} warn={kpi.sin > 0} />
        <Kpi label="Con recursos" value={kpi.con} />
        <Kpi label="Planificados" value={kpi.plan} />
      </div>

      <div className="flex gap-2">
        {FILTROS.map(([k, l]) => (
          <button key={k} onClick={() => setFiltro(k)} className={cn('rounded-full border px-3 py-1 text-xs', filtro === k ? 'bg-orange-600 text-white border-orange-600' : 'hover:bg-muted')}>{l}</button>
        ))}
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {isLoading && <div className="p-4"><Spinner className="h-5 w-5" /></div>}
          <table className="w-full text-sm">
            <thead><tr className="text-xs text-muted-foreground border-b">
              <th className="text-left p-2">Equipo</th><th className="p-2">NC</th><th className="p-2">Sev.</th>
              <th className="text-left p-2">Recursos del conjunto</th>
              <th className="p-2">Estado</th><th className="p-2"></th>
            </tr></thead>
            <tbody>
              {equipos.map((eq) => {
                const abierto = expandido[eq.activoId] ?? false
                const eb = ESTADO_EQUIPO[eq.estado] ?? { v: 'default', t: eq.estado }
                return (
                  <Fragment key={eq.activoId}>
                    <tr className="border-b hover:bg-muted/40 cursor-pointer"
                        onClick={() => setExpandido((p) => ({ ...p, [eq.activoId]: !abierto }))}>
                      <td className="p-2 whitespace-nowrap">
                        <span className="inline-flex items-center gap-1 font-bold">
                          {abierto ? <ChevronDown className="h-3.5 w-3.5 text-gray-400" /> : <ChevronRight className="h-3.5 w-3.5 text-gray-400" />}
                          {eq.patente}
                        </span>
                        {eq.nombre && <span className="ml-1.5 text-[11px] text-muted-foreground">{eq.nombre}</span>}
                      </td>
                      <td className="p-2 text-center">
                        <span className="rounded-full bg-orange-100 px-2 py-0.5 text-[11px] font-bold text-orange-700">{eq.ncs.length}</span>
                      </td>
                      <td className="p-2 text-center"><Badge variant={eq.sevMax as any} className="text-[10px]">{eq.sevMax}</Badge></td>
                      <td className="p-2 text-xs text-muted-foreground">
                        {eq.grupos || eq.horas > 0 || eq.nMateriales > 0
                          ? `${eq.grupos ?? '—'}${eq.horas ? ` · ${eq.horas}h` : ''}${eq.dias ? ` · ${eq.dias}d` : ''}${eq.nMateriales ? ` · ${eq.nMateriales} mat.` : ''}`
                          : <span className="text-amber-600">sin asignar</span>}
                        {eq.nInsumosOperador > 0 && (
                          <span className="ml-1.5 rounded bg-orange-100 px-1.5 py-0.5 text-[10px] font-semibold text-orange-700 whitespace-nowrap">
                            {eq.nInsumosOperador} insumo{eq.nInsumosOperador > 1 ? 's' : ''} pedido{eq.nInsumosOperador > 1 ? 's' : ''} por operador
                          </span>
                        )}
                      </td>
                      <td className="p-2 text-center"><Badge variant={eb.v} className="text-[10px]">{eb.t}</Badge></td>
                      <td className="p-2 whitespace-nowrap text-right" onClick={(e) => e.stopPropagation()}>
                        <Button size="sm" variant="outline" onClick={() => setRecursosEquipo(eq)}>
                          <Package className="h-3.5 w-3.5 mr-1" /> Recursos
                        </Button>
                        {eq.pendientes.length > 0 ? (
                          <Button size="sm" className="ml-1" disabled={busyId === eq.activoId} onClick={() => planificar(eq)}>
                            {busyId === eq.activoId ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Wrench className="h-3.5 w-3.5 mr-1" />}
                            Planificar equipo ({eq.pendientes.length})
                          </Button>
                        ) : (
                          <Badge variant="en_ejecucion" className="ml-1 text-[10px]">OT creada</Badge>
                        )}
                      </td>
                    </tr>
                    {abierto && eq.ncs.map((nc) => (
                      <tr key={nc.id} className="border-b bg-muted/20 text-xs">
                        <td className="p-2 pl-8 text-muted-foreground" colSpan={2}>
                          {nc.foto_url && (
                            <a href={nc.foto_url} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()} className="mr-2 inline-block align-middle">
                              {/* eslint-disable-next-line @next/next/no-img-element */}
                              <img src={nc.foto_url} alt="foto" className="h-8 w-8 rounded border object-cover hover:opacity-80" />
                            </a>
                          )}
                          {nc.descripcion}
                        </td>
                        <td className="p-2 text-center"><Badge variant={nc.severidad as any} className="text-[10px]">{nc.severidad}</Badge></td>
                        <td className="p-2 text-[11px] text-muted-foreground">
                          {nc.origen === 'recepcion_adhoc' ? 'ad-hoc' : 'checklist'}
                          {nc.n_recursos_operador > 0 && ` · ${nc.n_recursos_operador} insumo(s) del operador`}
                        </td>
                        <td className="p-2 text-center">
                          <Badge variant={(ESTADO_BADGE[nc.estado_planificacion]?.v) ?? 'default'} className="text-[10px]">
                            {ESTADO_BADGE[nc.estado_planificacion]?.t ?? nc.estado_planificacion}
                          </Badge>
                        </td>
                        <td />
                      </tr>
                    ))}
                  </Fragment>
                )
              })}
              {!isLoading && equipos.length === 0 && <tr><td colSpan={6} className="p-6 text-center text-muted-foreground">Sin No Conformidades. Genera desde un checklist de recepción o registra una ad-hoc.</td></tr>}
            </tbody>
          </table>
        </CardContent>
      </Card>

      {recursosEquipo && <RecursosEquipoModal equipo={recursosEquipo} onClose={() => setRecursosEquipo(null)} onDone={() => { setRecursosEquipo(null); invalidar() }} />}
      {genOpen && <GenerarDesdeRecepcionModal onClose={() => setGenOpen(false)} onDone={() => { setGenOpen(false); invalidar() }} />}
      {adhocOpen && <RegistrarNcModal onClose={() => setAdhocOpen(false)} onDone={() => { setAdhocOpen(false); invalidar() }} />}
      {valeOpen && (
        <ValeBodegaModal equipos={equiposListos}
                         onClose={() => setValeOpen(false)}
                         onDone={() => {
                           setValeOpen(false)
                           qc.invalidateQueries({ queryKey: ['vale-equipos-listos'] })
                           qc.invalidateQueries({ queryKey: ['nc-insumos-operador'] })
                         }} />
      )}
    </div>
  )
}

function Kpi({ label, value, warn }: { label: string; value: number; warn?: boolean }) {
  return <Card><CardContent className="p-3"><div className="text-xs text-muted-foreground">{label}</div><div className={cn('text-2xl font-bold', warn && 'text-amber-600')}>{value}</div></CardContent></Card>
}

// Botón grande "Vale para bodega" (MIG205): elegir la patente, revisar todo lo
// aprobado del equipo, firmar y emitir. Bodega recibe la campanita y el vale
// queda imprimible para que el operador retire.
type EquipoVale = { otId: string; otFolio: string; patente: string; nombre: string | null; items: OTRecursoSeguimiento[] }

function ValeBodegaModal({ equipos, onClose, onDone }: {
  equipos: EquipoVale[]; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [sel, setSel] = useState<EquipoVale | null>(equipos.length === 1 ? equipos[0] : null)
  const [firma, setFirma] = useState('')
  const [busy, setBusy] = useState(false)
  const [emitido, setEmitido] = useState<{ folio: string; ticketId: string; items: number } | null>(null)

  async function emitir() {
    if (!firma || !sel) return
    setBusy(true)
    try {
      const url = await subirFirmaTicket(firma, 'vale-nc')
      const r = await crearTicket({ otId: sel.otId, firmaJefeUrl: url })
      setEmitido({ folio: r.folio, ticketId: r.ticket_id, items: r.items })
      toast.success(`Vale ${r.folio} emitido — bodega ya recibió la solicitud`)
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  // Pantalla de éxito: imprimir para el retiro
  if (emitido) {
    return (
      <Modal open onClose={() => { onDone() }} title={`Vale ${emitido.folio} emitido ✓`}>
        <div className="space-y-3 text-center py-2">
          <CheckCircle2 className="mx-auto h-12 w-12 text-green-600" />
          <p className="text-sm text-gray-700">
            {emitido.items} ítem{emitido.items !== 1 ? 's' : ''} para <b>{sel?.patente}</b>. Bodega ya
            recibió la solicitud por campanita. Imprime el vale y entrégaselo al operador para el retiro.
          </p>
          <Button onClick={() => window.open(`/vale/${emitido.ticketId}`, '_blank')} className="w-full bg-[#0b2a4a]">
            <Printer className="h-4 w-4 mr-1.5" /> Imprimir vale
          </Button>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => { onDone() }}>Cerrar</Button>
        </ModalFooter>
      </Modal>
    )
  }

  return (
    <Modal open onClose={onClose} title="Vale para bodega">
      <div className="space-y-3">
        {equipos.length === 0 ? (
          <p className="py-4 text-center text-sm text-gray-500">
            No hay insumos aprobados pendientes de vale. Aprueba primero los pedidos en cada NC.
          </p>
        ) : (
          <>
            <div>
              <label className="text-xs font-medium">1. Elige la patente / equipo</label>
              <div className="mt-1 grid gap-1.5">
                {equipos.map((e) => (
                  <button key={e.otId} type="button" onClick={() => setSel(e)}
                          className={`flex items-center gap-3 rounded-lg border px-3 py-2 text-left ${
                            sel?.otId === e.otId ? 'border-orange-500 bg-orange-50' : 'border-gray-200 bg-white hover:bg-gray-50'}`}>
                    <span className="text-base font-bold text-gray-800">{e.patente}</span>
                    <span className="flex-1 text-xs text-gray-500">{e.nombre} · {e.otFolio}</span>
                    <span className="rounded-full bg-green-100 px-2 py-0.5 text-[11px] font-semibold text-green-700">
                      {e.items.length} ítem{e.items.length !== 1 ? 's' : ''}
                    </span>
                  </button>
                ))}
              </div>
            </div>

            {sel && (
              <>
                <div>
                  <label className="text-xs font-medium">2. Lo que se está pidiendo</label>
                  <div className="mt-1 max-h-44 space-y-1 overflow-y-auto rounded-lg border border-gray-100 bg-gray-50 p-2">
                    {sel.items.map((r) => (
                      <div key={r.id} className="flex items-center gap-2 rounded border border-gray-100 bg-white px-2 py-1.5 text-xs">
                        <span className="flex-1 font-medium text-gray-800">{r.producto_nombre ?? r.descripcion}</span>
                        <span className="text-gray-600 whitespace-nowrap">{r.cantidad_aprobada ?? r.cantidad} {r.unidad ?? 'un'}</span>
                        {r.estado === 'recibido' && (
                          <span className="rounded-full bg-teal-100 px-1.5 py-0.5 text-[10px] font-medium text-teal-700">recibido</span>
                        )}
                        {r.solicitado_nombre && <span className="text-[10px] text-gray-400">{r.solicitado_nombre}</span>}
                      </div>
                    ))}
                  </div>
                  <p className="mt-1 text-[10px] text-gray-500">
                    Se incluyen también los materiales de NC pendientes de este equipo, si los hay.
                  </p>
                </div>
                <div>
                  <label className="text-xs font-medium">3. Firma y emite</label>
                  <SignaturePad label="Firma del jefe de taller (obligatoria)" onCapture={setFirma} />
                </div>
              </>
            )}
          </>
        )}
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={busy}>Cancelar</Button>
        <Button disabled={!sel || !firma || busy} onClick={emitir} className="bg-orange-600 hover:bg-orange-700">
          {busy ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Ticket className="h-4 w-4 mr-1" />}
          Emitir vale{sel ? ` — ${sel.patente}` : ''}
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// Gestión COMPLETA de los insumos del taller desde la NC (MIG204): aprobar /
// rechazar / ajustar cantidad / agregar ítems y emitir el vale de bodega, sin
// tener que ir al Plan Taller. En el modal por equipo se muestra TODO lo de la
// OT de una vez (todaOT).
type ProductoLiteNC = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }

function InsumosOperadorNC({ nc, todaOT }: { nc: NcRecepcion; todaOT?: boolean }) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: recursos = [] } = useQuery({
    queryKey: ['nc-insumos-operador', nc.id],
    // Con OT: todos los insumos de la OT (el vale es por OT); sin OT, los del hallazgo.
    queryFn: () => nc.ot_id ? getRecursosOT(nc.ot_id) : getRecursosPorHallazgo(nc.checklist_item_ref!),
    enabled: !!nc.ot_id || !!nc.checklist_item_ref,
    staleTime: 10_000,
  })
  const invalidar = () => qc.invalidateQueries({ queryKey: ['nc-insumos-operador', nc.id] })

  const [cantidades, setCantidades] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  // En modo equipo se ve TODO de una; por hallazgo, solo lo suyo (expandible).
  const [verTodaLaOT, setVerTodaLaOT] = useState(!!todaOT)
  // Agregar ítem
  const [agregarOpen, setAgregarOpen] = useState(false)
  const [q, setQ] = useState('')
  const [resultados, setResultados] = useState<ProductoLiteNC[]>([])
  const [prod, setProd] = useState<ProductoLiteNC | null>(null)
  const [cant, setCant] = useState('')
  const [fotoItem, setFotoItem] = useState<File | null>(null)
  // Vale con firma
  const [valeOpen, setValeOpen] = useState(false)
  const [firma, setFirma] = useState('')

  useEffect(() => {
    if (prod || q.trim().length < 2) { setResultados([]); return }
    const t = setTimeout(async () => {
      try {
        const { data } = await buscarProductos(q, 8)
        setResultados((data ?? []) as ProductoLiteNC[])
      } catch { setResultados([]) }
    }, 300)
    return () => clearTimeout(t)
  }, [q, prod])

  // Insumos que nacen de ESTE hallazgo vs el resto de la OT
  const delHallazgo = nc.checklist_item_ref
    ? recursos.filter((r) => r.instance_item_id === nc.checklist_item_ref)
    : recursos
  const lista = verTodaLaOT ? recursos : delHallazgo
  const otrosOT = recursos.length - delHallazgo.length

  const valeables = recursos.filter((r) => r.estado === 'aprobado' || r.estado === 'recibido').length
  const pendientes = lista.filter((r) => r.estado === 'solicitado').length

  async function validar(r: OTRecurso, accion: 'aprobar' | 'rechazar') {
    setBusy(true)
    try {
      const cantTxt = cantidades[r.id]
      const nota = accion === 'rechazar' ? (window.prompt('Motivo del rechazo (lo verá el mecánico):') ?? undefined) : undefined
      await validarRecurso({
        recursoId: r.id, accion,
        cantidadAprobada: accion === 'aprobar' ? (cantTxt !== undefined && cantTxt !== '' ? Number(cantTxt) : r.cantidad) : null,
        nota: nota?.trim() || null,
      })
      invalidar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }
  async function agregarItem() {
    const n = Number(cant)
    if (!n || n <= 0 || (!prod && q.trim().length < 3) || !nc.ot_id) return
    setBusy(true)
    try {
      const fotos = fotoItem ? [await subirFotoRecurso(nc.ot_id, fotoItem)] : null
      await agregarRecursoJefe({
        otId: nc.ot_id, cantidad: n,
        productoId: prod?.id ?? null, descripcion: prod ? null : q.trim(),
        unidad: prod?.unidad_medida ?? null,
        instanceItemId: nc.checklist_item_ref ?? null,
        fotos,
      })
      setQ(''); setProd(null); setCant(''); setFotoItem(null); setAgregarOpen(false)
      invalidar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }
  async function emitirVale() {
    if (!firma || !nc.ot_id) return
    setBusy(true)
    try {
      const url = await subirFirmaTicket(firma, 'vale-nc')
      const r = await crearTicket({ otId: nc.ot_id, firmaJefeUrl: url })
      toast.success(`Vale ${r.folio} emitido (${r.items} ítems) — bodega ya recibió la solicitud`)
      window.open(`/vale/${r.ticket_id}`, '_blank')  // imprimible para el retiro
      setValeOpen(false); setFirma('')
      invalidar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  if (!nc.ot_id && !nc.checklist_item_ref) return null

  return (
    <div className="rounded-lg border border-orange-200 bg-orange-50/50 p-2.5">
      <div className="flex flex-wrap items-center justify-between gap-2 mb-1.5">
        <p className="text-xs font-semibold text-orange-800 flex items-center gap-1">
          <Package className="h-3.5 w-3.5" /> Insumos del taller
          {pendientes > 0 && (
            <span className="rounded-full bg-amber-200 px-1.5 py-0.5 text-[10px] font-bold text-amber-900">
              {pendientes} por validar
            </span>
          )}
        </p>
        <div className="flex gap-1.5">
          <button type="button" onClick={() => setAgregarOpen((v) => !v)} disabled={!nc.ot_id}
                  className="rounded border border-orange-300 bg-white px-2 py-1 text-[11px] font-semibold text-orange-700 disabled:opacity-50">
            + Ítem
          </button>
          <button type="button" onClick={() => setValeOpen(true)} disabled={valeables === 0 || busy}
                  className="rounded bg-orange-600 px-2 py-1 text-[11px] font-semibold text-white disabled:opacity-50">
            Generar vale ({valeables})
          </button>
        </div>
      </div>

      {lista.length === 0 ? (
        <p className="text-[11px] text-gray-400">
          {recursos.length === 0 ? 'Sin insumos pedidos para esta OT todavía.' : 'Este hallazgo no tiene insumos pedidos.'}
        </p>
      ) : (
        <div className="space-y-1.5">
          {lista.map((r) => {
            const chip = RECURSO_ESTADO_LABEL[r.estado]
            const deEsteHallazgo = !!nc.checklist_item_ref && r.instance_item_id === nc.checklist_item_ref
            return (
              <div key={r.id} className="rounded border border-orange-100 bg-white px-2 py-1.5">
                <div className="flex flex-wrap items-center gap-2 text-xs">
                  <span className="flex-1 font-medium text-gray-800">
                    {r.producto_nombre ?? r.descripcion}
                    {verTodaLaOT && !todaOT && deEsteHallazgo && (
                      <span className="ml-1 rounded bg-red-100 px-1 py-0.5 text-[9px] font-semibold text-red-700">este hallazgo</span>
                    )}
                  </span>
                  <span className="text-gray-600 whitespace-nowrap">{r.cantidad_aprobada ?? r.cantidad} {r.unidad ?? 'un'}</span>
                  <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${chip.cls}`}>
                    {chip.label}{r.estado === 'en_vale' && r.ticket_folio ? ` · ${r.ticket_folio}` : ''}
                  </span>
                </div>
                {(r.solicitado_nombre || r.comentario) && (
                  <p className="mt-0.5 text-[10px] text-gray-500">
                    {r.solicitado_nombre}{r.comentario ? ` · «${r.comentario}»` : ''}
                  </p>
                )}
                {(r.fotos?.length ?? 0) > 0 && (
                  <div className="mt-1 flex gap-1">
                    {(r.fotos ?? []).map((url, i) => (
                      <a key={i} href={url} target="_blank" rel="noreferrer">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={url} alt="foto" className="h-12 w-12 rounded border object-cover hover:opacity-80" />
                      </a>
                    ))}
                  </div>
                )}
                {r.estado === 'solicitado' && (
                  <div className="mt-1 flex items-center gap-1.5">
                    <input type="number" min="0" step="any"
                           value={cantidades[r.id] ?? String(r.cantidad)}
                           onChange={(e) => setCantidades((p) => ({ ...p, [r.id]: e.target.value }))}
                           className="w-16 rounded border border-gray-300 px-1.5 py-0.5 text-xs" />
                    <button type="button" onClick={() => validar(r, 'aprobar')} disabled={busy}
                            className="rounded bg-green-600 px-2 py-1 text-[11px] font-semibold text-white disabled:opacity-50">
                      Aprobar
                    </button>
                    <button type="button" onClick={() => validar(r, 'rechazar')} disabled={busy}
                            className="rounded bg-red-600 px-2 py-1 text-[11px] font-semibold text-white disabled:opacity-50">
                      Rechazar
                    </button>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}

      {agregarOpen && (
        <div className="mt-2 space-y-1.5 rounded border border-orange-200 bg-white p-2">
          {prod ? (
            <div className="flex items-center gap-2 rounded border border-green-200 bg-green-50 px-2 py-1 text-xs">
              <span className="flex-1 font-medium text-green-800">{prod.nombre}</span>
              <button type="button" onClick={() => { setProd(null); setQ('') }} className="text-green-700 text-[11px]">cambiar</button>
            </div>
          ) : (
            <div>
              <input value={q} onChange={(e) => setQ(e.target.value)}
                     placeholder="Busca en bodega o describe el material…"
                     className="w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
              {resultados.length > 0 && (
                <div className="mt-1 overflow-hidden rounded border border-gray-200 bg-white">
                  {resultados.map((p) => (
                    <button key={p.id} type="button" onClick={() => { setProd(p); setResultados([]) }}
                            className="flex w-full items-center gap-2 border-b border-gray-100 px-2 py-1.5 text-left text-xs last:border-0 hover:bg-gray-50">
                      <span className="flex-1">{p.nombre}</span>
                      {p.codigo && <span className="font-mono text-[10px] text-gray-400">{p.codigo}</span>}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
          <div className="flex items-center gap-1.5">
            <input type="number" min="0" value={cant} onChange={(e) => setCant(e.target.value)}
                   placeholder="Cantidad" className="w-24 rounded border border-gray-300 px-2 py-1.5 text-sm" />
            <button type="button" disabled={busy || !Number(cant) || (!prod && q.trim().length < 3)} onClick={agregarItem}
                    className="rounded bg-orange-600 px-2.5 py-1.5 text-[11px] font-semibold text-white disabled:opacity-50">
              Agregar aprobado
            </button>
          </div>
          <label className="block text-[11px] text-gray-600">
            Foto del repuesto (opcional — bodega la ve)
            <input type="file" accept="image/*" capture="environment"
                   onChange={(e) => setFotoItem(e.target.files?.[0] ?? null)}
                   className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1 text-xs" />
            {fotoItem && <span className="text-[10px] text-green-600">✓ {fotoItem.name}</span>}
          </label>
        </div>
      )}

      {!todaOT && nc.checklist_item_ref && otrosOT > 0 && (
        <button type="button" onClick={() => setVerTodaLaOT((v) => !v)}
                className="mt-1.5 text-[11px] font-medium text-orange-700 hover:underline">
          {verTodaLaOT
            ? 'Ver solo este hallazgo'
            : `Ver los ${otrosOT} insumos de las otras NC de esta OT (el vale los incluye a todos)`}
        </button>
      )}
      <p className="mt-1.5 text-[10px] text-gray-500">
        Aprueba/ajusta y emite el vale aquí mismo (el vale es UNO por OT e incluye todo lo aprobado
        del equipo). Si un insumo aprobado no tiene stock, sigue en Bodega → Seguimiento repuestos
        (solicitud de OC) y vuelve como «Recibido» para el vale.
      </p>

      {valeOpen && (
        <Modal open onClose={() => setValeOpen(false)} title="Vale de bodega — firma del jefe">
          <div className="space-y-3">
            <p className="text-sm text-gray-600">
              Se emite un ticket QR con los {valeables} insumos aprobados/recibidos de la OT (más los
              materiales de NC pendientes). Bodega lo despacha escaneándolo.
            </p>
            <SignaturePad label="Firma del jefe de taller (obligatoria)" onCapture={setFirma} />
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setValeOpen(false)}>Cancelar</Button>
            <Button disabled={!firma || busy} onClick={emitirVale}>
              {busy ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <CheckCircle2 className="h-4 w-4 mr-1" />}
              Emitir vale
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}

// Recursos del CONJUNTO del equipo (MIG209): un solo modal por patente con
// todas sus NC, los insumos del taller de sus OT, grupo/horas/días compartidos
// y UNA lista de materiales para todo el equipo.
function RecursosEquipoModal({ equipo, onClose, onDone }: { equipo: EquipoNC; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const { data: prodRes } = useQuery({ queryKey: ['productos-nc'], queryFn: () => getProductos(), staleTime: 300_000 })
  const productos = (prodRes?.data ?? []) as Array<{ id: string; codigo: string; nombre: string; categoria: string }>
  const { data: categorias = [] } = useQuery({ queryKey: ['producto-categorias-activas'], queryFn: () => getCategoriasProducto(true), staleTime: 300_000 })

  // NC abiertas del equipo (las que reciben los recursos) y sus materiales actuales
  const ncsAbiertas = useMemo(() => equipo.ncs.filter((n) => !['resuelta', 'descartada'].includes(n.estado_planificacion)), [equipo.ncs])
  const idsAbiertas = useMemo(() => ncsAbiertas.map((n) => n.id), [ncsAbiertas])
  const { data: matsGuardados, isLoading: cargandoMats } = useQuery({
    queryKey: ['nc-materiales-equipo', equipo.activoId],
    queryFn: () => getNcMaterialesEquipo(idsAbiertas),
    enabled: idsAbiertas.length > 0,
  })

  // Una OT de origen puede repetirse entre NC: un bloque de insumos por OT distinta
  const ncsInsumos = useMemo(() => {
    const vistos = new Set<string>()
    const res: NcRecepcion[] = []
    for (const n of ncsAbiertas) {
      const clave = n.ot_id ?? (n.checklist_item_ref ? `item:${n.checklist_item_ref}` : null)
      if (!clave || vistos.has(clave)) continue
      vistos.add(clave)
      res.push(n)
    }
    return res
  }, [ncsAbiertas])

  type MatRow = NcMaterial & { solicitar?: boolean; foto?: File | null }
  const [mecanicos, setMecanicos] = useState<string[]>(() =>
    (equipo.grupos ?? '').split(',').map((s) => s.trim()).filter((s) => (MECANICOS as readonly string[]).includes(s)))
  const [horas, setHoras] = useState(equipo.horas ? String(equipo.horas) : '')
  const [dias, setDias] = useState(equipo.dias ? String(equipo.dias) : '')
  const [catFiltro, setCatFiltro] = useState('')
  const [mats, setMats] = useState<MatRow[] | null>(null)
  const [saving, setSaving] = useState(false)

  // Precargar los materiales ya guardados del conjunto (una sola vez)
  useEffect(() => {
    if (mats !== null || cargandoMats) return
    const previos = (matsGuardados ?? []).map((m: any) => ({
      producto_id: m.producto_id ?? '', descripcion: m.descripcion ?? '', cantidad: Number(m.cantidad) || 1, nc_id: m.no_conformidad_id,
    }))
    setMats(previos.length ? previos : [{ producto_id: '', descripcion: '', cantidad: 1 }])
  }, [matsGuardados, cargandoMats, mats])

  const filas = mats ?? []
  const productosFiltrados = catFiltro ? productos.filter((p) => p.categoria === catFiltro) : productos
  const toggleMec = (m: string) => setMecanicos((prev) => prev.includes(m) ? prev.filter((x) => x !== m) : [...prev, m])

  const submit = async () => {
    setSaving(true)
    try {
      // Materiales del catálogo -> recursos del conjunto del equipo.
      const materiales = filas
        .filter((m) => !m.solicitar && (m.producto_id || (m.descripcion ?? '').trim()))
        .map((m) => ({ producto_id: m.producto_id || null, descripcion: m.descripcion, cantidad: Number(m.cantidad) || 1, nc_id: m.nc_id ?? null }))
      await asignarRecursosNcEquipo({
        activoId: equipo.activoId,
        grupo: mecanicos.length ? mecanicos.join(', ') : null,
        horas: horas ? Number(horas) : null,
        tiempoDias: dias ? Number(dias) : null,
        materiales,
      })
      // Materiales que NO están en bodega -> solicitud a bodega (queda ligada al equipo vía su NC).
      // Con foto propia si el jefe la adjuntó; si no, la RPC hereda la foto de la NC.
      const ncAncla = ncsAbiertas[0]
      const solicitudes = filas.filter((m) => m.solicitar && (m.descripcion ?? '').trim())
      for (const s of solicitudes) {
        const fotoUrl = s.foto ? await subirFotoNc(s.foto) : null
        await solicitarMaterialBodega({ descripcion: s.descripcion!, cantidad: Number(s.cantidad) || 1, ncId: ncAncla?.id ?? null, fotoUrl })
      }
      toast.success(`Recursos de ${equipo.patente} guardados (${ncsAbiertas.length} NC)${solicitudes.length ? ` · ${solicitudes.length} solicitud(es) enviada(s) a bodega` : ''}`)
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setSaving(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Recursos del equipo · ${equipo.patente}`}>
      <div className="space-y-3">
        <div>
          <p className="text-xs font-medium mb-1">No Conformidades del equipo ({ncsAbiertas.length})</p>
          <div className="max-h-40 space-y-1 overflow-y-auto rounded-lg border border-gray-100 bg-gray-50 p-2">
            {ncsAbiertas.map((nc) => (
              <div key={nc.id} className="flex items-center gap-2 rounded border border-gray-100 bg-white px-2 py-1.5 text-xs">
                {nc.foto_url && (
                  <a href={nc.foto_url} target="_blank" rel="noreferrer" className="shrink-0">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={nc.foto_url} alt="foto" className="h-9 w-9 rounded border object-cover hover:opacity-80" />
                  </a>
                )}
                <span className="flex-1 text-gray-700">{nc.descripcion}</span>
                <Badge variant={nc.severidad as any} className="text-[9px] shrink-0">{nc.severidad}</Badge>
              </div>
            ))}
          </div>
        </div>

        {ncsInsumos.map((nc) => <InsumosOperadorNC key={nc.id} nc={nc} todaOT />)}

        <div>
          <label className="text-xs font-medium">Grupo de trabajo (mano de obra) — para todo el conjunto</label>
          <div className="mt-1 flex flex-wrap gap-1">
            {MECANICOS.map((m) => {
              const on = mecanicos.includes(m)
              return (
                <button key={m} type="button" onClick={() => toggleMec(m)}
                  className={`rounded border px-2 py-1 text-[11px] ${on ? 'border-blue-500 bg-blue-500 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>{m}</button>
              )
            })}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs font-medium">Horas estimadas totales (MO)
            <input type="number" value={horas} onChange={(e) => setHoras(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
          <label className="text-xs font-medium">Tiempo total (días)
            <input type="number" value={dias} onChange={(e) => setDias(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
        </div>
        <div>
          <div className="text-xs font-medium mb-1 flex items-center justify-between">
            <span className="flex items-center gap-1"><Package className="h-3.5 w-3.5" /> Materiales del equipo</span>
            <select value={catFiltro} onChange={(e) => setCatFiltro(e.target.value)} className="rounded border px-1.5 py-0.5 text-[11px] text-gray-600">
              <option value="">Todas las categorías</option>
              {categorias.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}
            </select>
          </div>
          <div className="space-y-1">
            {filas.map((m, i) => (
              <div key={i} className="flex gap-1 items-center">
                {m.solicitar ? (
                  <div className="flex-1 flex items-center gap-1">
                    <input value={m.descripcion ?? ''} placeholder="Material que no está en bodega…"
                      onChange={(e) => setMats((s) => (s ?? []).map((x, j) => j === i ? { ...x, descripcion: e.target.value } : x))}
                      className="flex-1 rounded border border-amber-300 bg-amber-50 px-2 py-1 text-sm" />
                    <label className={`cursor-pointer rounded border px-1.5 py-1 text-[10px] whitespace-nowrap ${m.foto ? 'border-green-400 bg-green-50 text-green-700' : 'border-amber-300 bg-white text-amber-700'}`}
                           title="Foto del material para bodega (opcional)">
                      {m.foto ? '✓ foto' : '📷 foto'}
                      <input type="file" accept="image/*" capture="environment" className="hidden"
                        onChange={(e) => { const f = e.target.files?.[0] ?? null; setMats((s) => (s ?? []).map((x, j) => j === i ? { ...x, foto: f } : x)) }} />
                    </label>
                  </div>
                ) : (
                  <select value={m.producto_id ?? ''}
                    onChange={(e) => {
                      const p = productos.find((x) => x.id === e.target.value)
                      setMats((s) => (s ?? []).map((x, j) => j === i ? { ...x, producto_id: e.target.value, descripcion: p ? `${p.codigo} · ${p.nombre}` : '' } : x))
                    }}
                    className="flex-1 rounded border px-2 py-1 text-sm">
                    <option value="">{m.descripcion ? m.descripcion : '— Repuesto / material —'}</option>
                    {productosFiltrados.map((p) => <option key={p.id} value={p.id}>{p.codigo} · {p.nombre}</option>)}
                  </select>
                )}
                <input type="number" value={m.cantidad} onChange={(e) => setMats((s) => (s ?? []).map((x, j) => j === i ? { ...x, cantidad: Number(e.target.value) } : x))} className="w-14 rounded border px-2 py-1 text-sm" />
                <button type="button" title="No está en bodega (solicitar)"
                  onClick={() => setMats((s) => (s ?? []).map((x, j) => j === i ? { ...x, solicitar: !x.solicitar, producto_id: '', descripcion: '' } : x))}
                  className={`rounded border px-1.5 py-1 text-[10px] ${m.solicitar ? 'border-amber-400 bg-amber-100 text-amber-700' : 'border-gray-200 text-gray-500'}`}>
                  {m.solicitar ? 'a bodega' : 'no hay'}
                </button>
                <button type="button" onClick={() => setMats((s) => (s ?? []).filter((_, j) => j !== i))} className="text-red-500 px-1"><Trash2 className="h-4 w-4" /></button>
              </div>
            ))}
          </div>
          <button type="button" onClick={() => setMats((s) => [...(s ?? []), { producto_id: '', descripcion: '', cantidad: 1 }])} className="text-xs text-blue-600 mt-1">+ Agregar material</button>
          <p className="text-[10px] text-gray-400 mt-1">La lista es del conjunto del equipo. Si un material no está en bodega, pulsa «no hay» → se envía una solicitud a bodega asociada a la patente, con la foto que adjuntes (si no adjuntas, va la foto de la NC).</p>
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
        <Button onClick={submit} disabled={saving || mats === null}>{saving ? 'Guardando…' : `Guardar recursos (${ncsAbiertas.length} NC)`}</Button>
      </ModalFooter>
    </Modal>
  )
}

function GenerarDesdeRecepcionModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const { data: receps = [] } = useQuery({ queryKey: ['recepciones-para-nc'], queryFn: getRecepcionesParaNc })
  const [busy, setBusy] = useState<string | null>(null)
  const generar = async (informeId: string, patente: string) => {
    setBusy(informeId)
    try {
      const r: any = await generarNcDesdeRecepcion(informeId)
      toast.success(`${r?.creadas ?? 0} No Conformidad(es) generada(s) de ${patente}`)
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setBusy(null) }
  }
  return (
    <Modal open onClose={onClose} title="Generar NC desde checklist de recepción">
      <div className="space-y-1 max-h-80 overflow-auto">
        <p className="text-xs text-gray-500 mb-2">Toma los ítems «no OK» del checklist de la recepción y crea una NC por cada uno.</p>
        {receps.length === 0 && <p className="text-sm text-muted-foreground py-4 text-center">Sin recepciones.</p>}
        {receps.map((r: any) => (
          <div key={r.id} className="flex items-center justify-between border rounded p-2 text-sm">
            <div><b>{r.patente ?? r.activo_codigo}</b> <span className="text-xs text-muted-foreground">· {r.folio} · {r.estado}</span></div>
            <Button size="sm" variant="outline" disabled={busy === r.id} onClick={() => generar(r.id, r.patente ?? r.activo_codigo)}>
              {busy === r.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4 mr-1" />} Generar
            </Button>
          </div>
        ))}
      </div>
      <ModalFooter><Button variant="outline" onClick={onClose}>Cerrar</Button></ModalFooter>
    </Modal>
  )
}

function RegistrarNcModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const { data: activos = [] } = useQuery({ queryKey: ['activos-para-nc'], queryFn: getActivosParaNc })
  const [activoId, setActivoId] = useState('')
  const [desc, setDesc] = useState('')
  const [sev, setSev] = useState('media')
  const [foto, setFoto] = useState<File | null>(null)
  const [saving, setSaving] = useState(false)
  const submit = async () => {
    if (!activoId || !desc.trim()) { toast.error('Equipo y descripción obligatorios'); return }
    if (!foto) { toast.error('La foto es obligatoria para la NC del mecánico'); return }
    setSaving(true)
    try {
      const fotoUrl = await subirFotoNc(foto)
      await registrarNcAdhoc({ activoId, descripcion: desc, severidad: sev, fotoUrl })
      toast.success('No Conformidad registrada')
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setSaving(false) }
  }
  return (
    <Modal open onClose={onClose} title="Registrar No Conformidad (ad-hoc)">
      <div className="space-y-3">
        <p className="text-xs text-gray-500">Para las NC que el grupo encuentra y NO estaban en el checklist (mejora continua).</p>
        <label className="text-xs font-medium block">Equipo
          <select value={activoId} onChange={(e) => setActivoId(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm">
            <option value="">—</option>
            {(activos as any[]).map((a) => <option key={a.id} value={a.id}>{a.patente ?? a.codigo}</option>)}
          </select>
        </label>
        <label className="text-xs font-medium block">Descripción
          <textarea value={desc} onChange={(e) => setDesc(e.target.value)} rows={2} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
        </label>
        <label className="text-xs font-medium block">Severidad
          <select value={sev} onChange={(e) => setSev(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm">
            <option value="baja">Baja</option><option value="media">Media</option><option value="alta">Alta</option><option value="critica">Crítica</option>
          </select>
        </label>
        <label className="text-xs font-medium block">Foto <span className="text-red-500">*</span> (obligatoria)
          <input type="file" accept="image/*" capture="environment" onChange={(e) => setFoto(e.target.files?.[0] ?? null)}
            className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          {foto && <span className="text-[10px] text-green-600">✓ {foto.name}</span>}
        </label>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
        <Button onClick={submit} disabled={saving}>{saving ? 'Guardando…' : 'Registrar'}</Button>
      </ModalFooter>
    </Modal>
  )
}
