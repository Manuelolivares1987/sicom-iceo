'use client'

import { useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, ClipboardList, Wrench, PlusCircle, Trash2, CheckCircle2, Loader2, Package,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getNcRecepcion, asignarRecursosNc, planificarNc, registrarNcAdhoc, generarNcDesdeRecepcion,
  getRecepcionesParaNc, getActivosParaNc, subirFotoNc, type NcRecepcion, type NcMaterial,
} from '@/lib/services/no-conformidades'
import { getProductos } from '@/lib/services/inventario'
import {
  getRecursosPorHallazgo, getRecursosOT, validarRecurso, agregarRecursoJefe,
  RECURSO_ESTADO_LABEL, type OTRecurso,
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
const FILTROS = [['', 'Todas'], ['registrada', 'Sin recursos'], ['con_recursos', 'Con recursos'], ['planificada', 'Planificadas']] as const

export default function NoConformidadesPage() {
  useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [filtro, setFiltro] = useState('')
  const { data: ncs = [], isLoading } = useQuery({ queryKey: ['nc-recepcion', filtro], queryFn: () => getNcRecepcion(filtro || undefined), staleTime: 20_000 })
  const [recursosNc, setRecursosNc] = useState<NcRecepcion | null>(null)
  const [genOpen, setGenOpen] = useState(false)
  const [adhocOpen, setAdhocOpen] = useState(false)
  const [busyId, setBusyId] = useState<string | null>(null)

  const invalidar = () => qc.invalidateQueries({ queryKey: ['nc-recepcion'] })

  const kpi = useMemo(() => ({
    total: ncs.length,
    sin: ncs.filter((n) => n.estado_planificacion === 'registrada').length,
    con: ncs.filter((n) => n.estado_planificacion === 'con_recursos').length,
    plan: ncs.filter((n) => n.estado_planificacion === 'planificada').length,
  }), [ncs])

  const planificar = async (nc: NcRecepcion) => {
    setBusyId(nc.id)
    try {
      await planificarNc(nc.id)
      toast.success('NC planificada: se creó la OT correctiva')
      invalidar(); qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al planificar') } finally { setBusyId(null) }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2"><AlertTriangle className="h-6 w-6 text-orange-600" /> No Conformidades (Recepción)</h1>
          <p className="text-sm text-muted-foreground">Nacen del checklist de recepción (y ad-hoc). Asigna recursos y planifícalas como trabajo correctivo.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setGenOpen(true)}><ClipboardList className="h-4 w-4 mr-1" /> Generar del checklist</Button>
          <Button variant="outline" onClick={() => setAdhocOpen(true)}><PlusCircle className="h-4 w-4 mr-1" /> Registrar NC ad-hoc</Button>
        </div>
      </div>

      <div className="grid gap-3 grid-cols-2 md:grid-cols-4">
        <Kpi label="Total" value={kpi.total} />
        <Kpi label="Sin recursos" value={kpi.sin} warn={kpi.sin > 0} />
        <Kpi label="Con recursos" value={kpi.con} />
        <Kpi label="Planificadas" value={kpi.plan} />
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
              <th className="text-left p-2">Equipo</th><th className="text-left p-2">No Conformidad</th>
              <th className="p-2">Sev.</th><th className="p-2">Origen</th><th className="text-left p-2">Recursos</th>
              <th className="p-2">Estado</th><th className="p-2"></th>
            </tr></thead>
            <tbody>
              {ncs.map((nc) => (
                <tr key={nc.id} className="border-b hover:bg-muted/40">
                  <td className="p-2 font-medium whitespace-nowrap">{nc.patente ?? nc.codigo}</td>
                  <td className="p-2">{nc.descripcion}</td>
                  <td className="p-2 text-center"><Badge variant={nc.severidad as any} className="text-[10px]">{nc.severidad}</Badge></td>
                  <td className="p-2 text-center text-[11px] text-muted-foreground">{nc.origen === 'recepcion_adhoc' ? 'ad-hoc' : 'checklist'}</td>
                  <td className="p-2 text-xs text-muted-foreground">
                    {nc.grupo_trabajo || nc.horas_estimadas || nc.n_materiales > 0
                      ? `${nc.grupo_trabajo ?? '—'}${nc.horas_estimadas ? ` · ${nc.horas_estimadas}h` : ''}${nc.tiempo_estimado_dias ? ` · ${nc.tiempo_estimado_dias}d` : ''}${nc.n_materiales ? ` · ${nc.n_materiales} mat.` : ''}`
                      : <span className="text-amber-600">sin asignar</span>}
                    {nc.n_recursos_operador > 0 && (
                      <span className="ml-1.5 rounded bg-orange-100 px-1.5 py-0.5 text-[10px] font-semibold text-orange-700 whitespace-nowrap">
                        {nc.n_recursos_operador} insumo{nc.n_recursos_operador > 1 ? 's' : ''} pedido{nc.n_recursos_operador > 1 ? 's' : ''} por operador
                      </span>
                    )}
                  </td>
                  <td className="p-2 text-center"><Badge variant={(ESTADO_BADGE[nc.estado_planificacion]?.v) ?? 'default'} className="text-[10px]">{ESTADO_BADGE[nc.estado_planificacion]?.t ?? nc.estado_planificacion}</Badge></td>
                  <td className="p-2 whitespace-nowrap text-right">
                    <Button size="sm" variant="outline" onClick={() => setRecursosNc(nc)}><Package className="h-3.5 w-3.5 mr-1" /> Recursos</Button>
                    {!nc.plan_ot_id && (
                      <Button size="sm" className="ml-1" disabled={busyId === nc.id} onClick={() => planificar(nc)}>
                        {busyId === nc.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Wrench className="h-3.5 w-3.5 mr-1" />} Planificar
                      </Button>
                    )}
                    {nc.plan_ot_id && <Badge variant="en_ejecucion" className="ml-1 text-[10px]">OT creada</Badge>}
                  </td>
                </tr>
              ))}
              {!isLoading && ncs.length === 0 && <tr><td colSpan={7} className="p-6 text-center text-muted-foreground">Sin No Conformidades. Genera desde un checklist de recepción o registra una ad-hoc.</td></tr>}
            </tbody>
          </table>
        </CardContent>
      </Card>

      {recursosNc && <AsignarRecursosModal nc={recursosNc} onClose={() => setRecursosNc(null)} onDone={() => { setRecursosNc(null); invalidar() }} />}
      {genOpen && <GenerarDesdeRecepcionModal onClose={() => setGenOpen(false)} onDone={() => { setGenOpen(false); invalidar() }} />}
      {adhocOpen && <RegistrarNcModal onClose={() => setAdhocOpen(false)} onDone={() => { setAdhocOpen(false); invalidar() }} />}
    </div>
  )
}

function Kpi({ label, value, warn }: { label: string; value: number; warn?: boolean }) {
  return <Card><CardContent className="p-3"><div className="text-xs text-muted-foreground">{label}</div><div className={cn('text-2xl font-bold', warn && 'text-amber-600')}>{value}</div></CardContent></Card>
}

// Gestión COMPLETA de los insumos del taller desde la NC (MIG204): aprobar /
// rechazar / ajustar cantidad / agregar ítems y emitir el vale de bodega, sin
// tener que ir al Plan Taller.
type ProductoLiteNC = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }

function InsumosOperadorNC({ nc }: { nc: NcRecepcion }) {
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
  // Agregar ítem
  const [agregarOpen, setAgregarOpen] = useState(false)
  const [q, setQ] = useState('')
  const [resultados, setResultados] = useState<ProductoLiteNC[]>([])
  const [prod, setProd] = useState<ProductoLiteNC | null>(null)
  const [cant, setCant] = useState('')
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

  const valeables = recursos.filter((r) => r.estado === 'aprobado' || r.estado === 'recibido').length
  const pendientes = recursos.filter((r) => r.estado === 'solicitado').length

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
      await agregarRecursoJefe({
        otId: nc.ot_id, cantidad: n,
        productoId: prod?.id ?? null, descripcion: prod ? null : q.trim(),
        unidad: prod?.unidad_medida ?? null,
        instanceItemId: nc.checklist_item_ref ?? null,
      })
      setQ(''); setProd(null); setCant(''); setAgregarOpen(false)
      invalidar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }
  async function emitirVale() {
    if (!firma || !nc.ot_id) return
    setBusy(true)
    try {
      const url = await subirFirmaTicket(firma, 'vale-nc')
      const r = await crearTicket({ otId: nc.ot_id, firmaJefeUrl: url })
      toast.success(`Vale ${r.folio} emitido (${r.items} ítems) — bodega lo despacha con el QR`)
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

      {recursos.length === 0 ? (
        <p className="text-[11px] text-gray-400">Sin insumos pedidos para esta OT todavía.</p>
      ) : (
        <div className="space-y-1.5">
          {recursos.map((r) => {
            const chip = RECURSO_ESTADO_LABEL[r.estado]
            const deEsteHallazgo = !!nc.checklist_item_ref && r.instance_item_id === nc.checklist_item_ref
            return (
              <div key={r.id} className="rounded border border-orange-100 bg-white px-2 py-1.5">
                <div className="flex flex-wrap items-center gap-2 text-xs">
                  <span className="flex-1 font-medium text-gray-800">
                    {r.producto_nombre ?? r.descripcion}
                    {deEsteHallazgo && (
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
        </div>
      )}

      <p className="mt-1.5 text-[10px] text-gray-500">
        Aprueba/ajusta y emite el vale aquí mismo. Si un insumo aprobado no tiene stock, sigue en
        Bodega → Seguimiento repuestos (solicitud de OC) y vuelve como «Recibido» para el vale.
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

function AsignarRecursosModal({ nc, onClose, onDone }: { nc: NcRecepcion; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const { data: prodRes } = useQuery({ queryKey: ['productos-nc'], queryFn: () => getProductos(), staleTime: 300_000 })
  const productos = (prodRes?.data ?? []) as Array<{ id: string; codigo: string; nombre: string; categoria: string }>
  const { data: categorias = [] } = useQuery({ queryKey: ['producto-categorias-activas'], queryFn: () => getCategoriasProducto(true), staleTime: 300_000 })

  type MatRow = NcMaterial & { solicitar?: boolean }
  const [mecanicos, setMecanicos] = useState<string[]>(() =>
    (nc.grupo_trabajo ?? '').split(',').map((s) => s.trim()).filter((s) => (MECANICOS as readonly string[]).includes(s)))
  const [horas, setHoras] = useState(nc.horas_estimadas?.toString() ?? '')
  const [dias, setDias] = useState(nc.tiempo_estimado_dias?.toString() ?? '')
  const [catFiltro, setCatFiltro] = useState('')
  const [mats, setMats] = useState<MatRow[]>([{ producto_id: '', descripcion: '', cantidad: 1 }])
  const [saving, setSaving] = useState(false)

  const productosFiltrados = catFiltro ? productos.filter((p) => p.categoria === catFiltro) : productos
  const toggleMec = (m: string) => setMecanicos((prev) => prev.includes(m) ? prev.filter((x) => x !== m) : [...prev, m])

  const submit = async () => {
    setSaving(true)
    try {
      // Materiales del catálogo -> recursos de la NC.
      const materiales = mats
        .filter((m) => !m.solicitar && (m.producto_id || (m.descripcion ?? '').trim()))
        .map((m) => ({ producto_id: m.producto_id || null, descripcion: m.descripcion, cantidad: Number(m.cantidad) || 1 }))
      await asignarRecursosNc({
        ncId: nc.id,
        grupo: mecanicos.length ? mecanicos.join(', ') : null,
        horas: horas ? Number(horas) : null,
        tiempoDias: dias ? Number(dias) : null,
        materiales,
      })
      // Materiales que NO están en bodega -> solicitud a bodega (con foto+obs de la NC).
      const solicitudes = mats.filter((m) => m.solicitar && (m.descripcion ?? '').trim())
      for (const s of solicitudes) {
        await solicitarMaterialBodega({ descripcion: s.descripcion!, cantidad: Number(s.cantidad) || 1, ncId: nc.id })
      }
      toast.success(`Recursos asignados${solicitudes.length ? ` · ${solicitudes.length} solicitud(es) enviada(s) a bodega` : ''}`)
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setSaving(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Recursos · ${nc.patente ?? nc.codigo}`}>
      <div className="space-y-3">
        <div className="flex items-start gap-3">
          {nc.foto_url && (
            <a href={nc.foto_url} target="_blank" rel="noreferrer" className="shrink-0">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={nc.foto_url} alt="foto del hallazgo" className="h-20 w-20 rounded-lg border object-cover hover:opacity-80" />
            </a>
          )}
          <p className="text-xs text-gray-600">{nc.descripcion}</p>
        </div>
        <InsumosOperadorNC nc={nc} />
        <div>
          <label className="text-xs font-medium">Grupo de trabajo (mano de obra)</label>
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
          <label className="text-xs font-medium">Horas estimadas (MO)
            <input type="number" value={horas} onChange={(e) => setHoras(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
          <label className="text-xs font-medium">Tiempo (días)
            <input type="number" value={dias} onChange={(e) => setDias(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
        </div>
        <div>
          <div className="text-xs font-medium mb-1 flex items-center justify-between">
            <span className="flex items-center gap-1"><Package className="h-3.5 w-3.5" /> Materiales</span>
            <select value={catFiltro} onChange={(e) => setCatFiltro(e.target.value)} className="rounded border px-1.5 py-0.5 text-[11px] text-gray-600">
              <option value="">Todas las categorías</option>
              {categorias.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}
            </select>
          </div>
          <div className="space-y-1">
            {mats.map((m, i) => (
              <div key={i} className="flex gap-1 items-center">
                {m.solicitar ? (
                  <input value={m.descripcion ?? ''} placeholder="Material que no está en bodega…"
                    onChange={(e) => setMats((s) => s.map((x, j) => j === i ? { ...x, descripcion: e.target.value } : x))}
                    className="flex-1 rounded border border-amber-300 bg-amber-50 px-2 py-1 text-sm" />
                ) : (
                  <select value={m.producto_id ?? ''}
                    onChange={(e) => {
                      const p = productos.find((x) => x.id === e.target.value)
                      setMats((s) => s.map((x, j) => j === i ? { ...x, producto_id: e.target.value, descripcion: p ? `${p.codigo} · ${p.nombre}` : '' } : x))
                    }}
                    className="flex-1 rounded border px-2 py-1 text-sm">
                    <option value="">— Repuesto / material —</option>
                    {productosFiltrados.map((p) => <option key={p.id} value={p.id}>{p.codigo} · {p.nombre}</option>)}
                  </select>
                )}
                <input type="number" value={m.cantidad} onChange={(e) => setMats((s) => s.map((x, j) => j === i ? { ...x, cantidad: Number(e.target.value) } : x))} className="w-14 rounded border px-2 py-1 text-sm" />
                <button type="button" title="No está en bodega (solicitar)"
                  onClick={() => setMats((s) => s.map((x, j) => j === i ? { ...x, solicitar: !x.solicitar, producto_id: '', descripcion: '' } : x))}
                  className={`rounded border px-1.5 py-1 text-[10px] ${m.solicitar ? 'border-amber-400 bg-amber-100 text-amber-700' : 'border-gray-200 text-gray-500'}`}>
                  {m.solicitar ? 'a bodega' : 'no hay'}
                </button>
                <button type="button" onClick={() => setMats((s) => s.filter((_, j) => j !== i))} className="text-red-500 px-1"><Trash2 className="h-4 w-4" /></button>
              </div>
            ))}
          </div>
          <button type="button" onClick={() => setMats((s) => [...s, { producto_id: '', descripcion: '', cantidad: 1 }])} className="text-xs text-blue-600 mt-1">+ Agregar material</button>
          <p className="text-[10px] text-gray-400 mt-1">Si un material no está en bodega, pulsa «no hay» → se envía una solicitud a bodega con la foto y observación de la NC.</p>
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
        <Button onClick={submit} disabled={saving}>{saving ? 'Guardando…' : 'Guardar recursos'}</Button>
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
