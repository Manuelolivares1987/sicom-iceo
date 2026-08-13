'use client'

import { Fragment, useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, ClipboardList, Wrench, PlusCircle, Trash2, CheckCircle2, Loader2, Package, Ticket, Printer,
  ChevronDown, ChevronRight, StickyNote, ImageOff, Receipt, ExternalLink,
} from 'lucide-react'
import Link from 'next/link'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import {
  getNcRecepcion, planificarNcEquipo, asignarRecursosNcEquipo, getNcMaterialesEquipo,
  registrarNcAdhoc, generarNcDesdeRecepcion, setRecobroNc, armarInformeRecobro,
  guardarManoObraNc, planificarNc, getNcMateriales,
  getRecepcionesParaNc, getActivosParaNc, subirFotoNc, RECOBRO_LABEL, RECOBRO_FUENTE_TXT,
  type NcRecepcion, type NcMaterial, type RecobroValor,
} from '@/lib/services/no-conformidades'
import { getNotasOTs, convertirNotaEnNc, type OTNota } from '@/lib/services/ot-notas'
import {
  getInsumosNc, agregarInsumoNc, quitarInsumoNc, buscarInsumosConStock,
  INSUMO_ESTADO, type ProductoConStock,
} from '@/lib/services/nc-insumos'
import { getTarifasHH } from '@/lib/services/informe-recepcion'
import { getProductos } from '@/lib/services/inventario'
import {
  getRecursosPorHallazgo, getRecursosOT, getRecursosOTs, validarRecurso, agregarRecursoJefe, subirFotoRecurso,
  getSeguimientoRecursos,
  RECURSO_ESTADO_LABEL, type OTRecurso, type OTRecursoSeguimiento,
} from '@/lib/services/ot-recursos'
import { buscarProductos } from '@/lib/services/ot-materiales'
import { subirFirmaTicket, crearTicket, getTicketsOts, anularTicket } from '@/lib/services/bodega-tickets'
import { SignaturePad } from '@/components/ui/signature-pad'
import { getCategoriasProducto } from '@/lib/services/producto-categorias'
import { solicitarMaterialBodega } from '@/lib/services/bodega-solicitudes'
import { MECANICOS } from '@/lib/taller-grupos'
import { getTallerTecnicos } from '@/lib/services/taller-plan-semanal'
import { RepuestosPorAprobar } from '@/components/mantenimiento/repuestos-por-aprobar'
import { NcEquipoCard } from '@/components/mantenimiento/nc-equipo-card'
import { InformesRecobroEnCurso } from '@/components/mantenimiento/informes-recobro-en-curso'
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
// De dónde salió el hallazgo. Lo que reporta el CLIENTE se dice con todas sus
// letras: no es lo mismo que lo encuentre el taller a que lo reclame quien
// está pagando el arriendo.
const ORIGEN_TXT: Record<string, string> = {
  recepcion_adhoc: 'ad-hoc',
  checklist_cliente: 'reportado por el cliente',
  auditoria_calidad: 'auditoría de calidad',
  manual: 'registro manual',
}

const ORDEN_ESTADO = ['registrada', 'con_recursos', 'planificada', 'en_ejecucion', 'resuelta', 'descartada']
const ORDEN_SEV = ['critica', 'alta', 'media', 'baja']
const FILTROS = [['', 'Todas'], ['registrada', 'Sin recursos'], ['con_recursos', 'Con recursos'], ['planificada', 'Planificadas']] as const

// ── El ciclo, dicho como pasos ──────────────────────────────────────────────
// El jefe de taller preguntaba por qué no "le llegaban" las cosas: la bandeja
// mostraba estados ('registrada', 'con_recursos') pero no QUÉ HACER con cada
// equipo ni de quién dependía. Estas son las mismas etapas nombradas por la
// acción que falta, y se pueden clickear para ver solo las que están ahí.
type PasoClave = 'aprobar' | 'recursos' | 'planificar' | 'vale' | 'taller' | 'listo'

const PASOS: { k: PasoClave; label: string; hacer: string; color: string }[] = [
  { k: 'aprobar',    label: 'Insumos por aprobar', hacer: 'El operador pidió repuestos: aprobar o ajustar', color: 'bg-orange-600' },
  { k: 'recursos',   label: 'Falta definir recursos', hacer: 'Asignar grupo, horas y materiales', color: 'bg-amber-500' },
  { k: 'planificar', label: 'Listos para planificar', hacer: 'Crear la OT correctiva del equipo', color: 'bg-sky-600' },
  { k: 'vale',       label: 'Esperando vale', hacer: 'Emitir el vale para que bodega prepare', color: 'bg-violet-600' },
  { k: 'taller',     label: 'En taller', hacer: 'El trabajo está en ejecución', color: 'bg-emerald-600' },
  { k: 'listo',      label: 'Resueltos', hacer: 'Sin nada pendiente', color: 'bg-gray-400' },
]
const PASO_TXT: Record<PasoClave, string> = {
  aprobar: 'Aprobar insumos', recursos: 'Definir recursos', planificar: 'Planificar OT',
  vale: 'Emitir vale', taller: 'En taller', listo: 'Resuelto',
}

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
  otIds: string[]          // OT del equipo (origen + correctiva) para leer sus notas
  nNotas: number           // notas/anexos que dejó el operador
  nRecobrables: number     // NC que se le cobran al cliente
  nNoRecobrables: number   // NC que asume la empresa
  nRecobroPorDefinir: number
  nDelCliente: number      // hallazgos que reclamó el cliente por el QR
  paso: PasoClave          // qué falta hacer con este equipo
}

/**
 * En qué paso del ciclo está parado el equipo. Se mira lo que BLOQUEA primero:
 * un insumo esperando aprobación detiene todo lo demás, aunque el resto del
 * conjunto ya esté planificado.
 */
function pasoDelEquipo(eq: Omit<EquipoNC, 'paso'>, otsConValePendiente: Set<string>): PasoClave {
  if (eq.nInsumosOperador > 0 && ['registrada', 'con_recursos'].includes(eq.estado)) return 'aprobar'
  if (eq.otIds.some((id) => otsConValePendiente.has(id))) return 'vale'
  if (eq.pendientes.length > 0) return eq.estado === 'registrada' ? 'recursos' : 'planificar'
  if (eq.estado === 'en_ejecucion' || eq.estado === 'planificada') return 'taller'
  return 'listo'
}

export default function NoConformidadesPage() {
  useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [filtro, setFiltro] = useState('')
  const { data: ncs = [], isLoading } = useQuery({ queryKey: ['nc-recepcion', filtro], queryFn: () => getNcRecepcion(filtro || undefined), staleTime: 20_000 })
  const [recursosEquipo, setRecursosEquipo] = useState<EquipoNC | null>(null)
  const [fichaNc, setFichaNc] = useState<{ nc: NcRecepcion; patente: string } | null>(null)
  const [recobroEquipo, setRecobroEquipo] = useState<EquipoNC | null>(null)
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
        otIds: [], nNotas: 0, nRecobrables: 0, nNoRecobrables: 0, nRecobroPorDefinir: 0,
        nDelCliente: 0, paso: 'listo',
      }
      g.ncs.push(nc)
      if (!nc.plan_ot_id && ['registrada', 'con_recursos'].includes(nc.estado_planificacion)) g.pendientes.push(nc)
      if (ORDEN_SEV.indexOf(nc.severidad) < ORDEN_SEV.indexOf(g.sevMax as any)) g.sevMax = nc.severidad
      if (ORDEN_ESTADO.indexOf(nc.estado_planificacion) < ORDEN_ESTADO.indexOf(g.estado)) g.estado = nc.estado_planificacion
      if (nc.grupo_trabajo && !(g.grupos ?? '').includes(nc.grupo_trabajo)) g.grupos = g.grupos ? `${g.grupos}, ${nc.grupo_trabajo}` : nc.grupo_trabajo
      g.horas += nc.horas_estimadas ?? 0
      g.dias = Math.max(g.dias, nc.tiempo_estimado_dias ?? 0)
      g.nMateriales += nc.n_materiales
      g.nInsumosOperador += nc.n_recursos_operador ?? 0
      // Recobro del conjunto: cuántas se le cobran al cliente y cuántas las paga la empresa
      if (nc.recobro === 'cliente' || nc.recobro === 'compartido') g.nRecobrables += 1
      else if (nc.recobro === 'empresa') g.nNoRecobrables += 1
      else g.nRecobroPorDefinir += 1
      // OT del equipo: de ahí salen las notas/anexos del operador. n_notas_operador
      // ya cuenta las notas de la(s) OT de la NC → max (no sumar: se repetirían).
      for (const ot of [nc.ot_id, nc.plan_ot_id]) if (ot && !g.otIds.includes(ot)) g.otIds.push(ot)
      g.nNotas = Math.max(g.nNotas, nc.n_notas_operador ?? 0)
      if (nc.origen === 'checklist_cliente') g.nDelCliente += 1
      m.set(nc.activo_id, g)
    }
    const otsConVale = new Set(equiposListos.map((e) => e.otId))
    const lista = Array.from(m.values())
    for (const eq of lista) eq.paso = pasoDelEquipo(eq, otsConVale)
    // Primero lo que está trabado esperando al jefe, después lo que ya avanza.
    return lista.sort((a, b) =>
      PASOS.findIndex((p) => p.k === a.paso) - PASOS.findIndex((p) => p.k === b.paso)
      || ORDEN_SEV.indexOf(a.sevMax) - ORDEN_SEV.indexOf(b.sevMax)
      || a.patente.localeCompare(b.patente))
  }, [ncs, equiposListos])

  // Filtro por paso del ciclo: se aplica en pantalla, sin volver a consultar.
  const [paso, setPaso] = useState<PasoClave | null>(null)
  const visibles = useMemo(
    () => (paso ? equipos.filter((e) => e.paso === paso) : equipos), [equipos, paso])
  const conteoPaso = useMemo(() => {
    const c = {} as Record<PasoClave, number>
    for (const p of PASOS) c[p.k] = 0
    for (const e of equipos) c[e.paso] += 1
    return c
  }, [equipos])

  const invalidar = () => qc.invalidateQueries({ queryKey: ['nc-recepcion'] })
  const todoAbierto = equipos.length > 0 && equipos.every((e) => expandido[e.activoId])

  const kpi = useMemo(() => ({
    total: equipos.length,
    recobrables: ncs.filter((n) => n.recobro === 'cliente' || n.recobro === 'compartido').length,
  }), [equipos, ncs])

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
            Despliega un equipo para ver la foto y la observación de cada hallazgo, las notas que dejó el
            operador y si el daño se le recobra al cliente (el chip de recobro se puede corregir con un click).
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
          <Button onClick={() => setValeOpen(true)}
                  className="bg-orange-600 hover:bg-orange-700 text-white font-bold px-5"
                  title="Elegir la patente, revisar/aprobar/agregar los recursos y emitir el vale de bodega (llega a bodega y se imprime para el retiro)">
            <Ticket className="h-5 w-5 mr-1.5" /> Vale para bodega{equiposListos.length > 0 ? ` (${equiposListos.length})` : ''}
          </Button>
        </div>
      </div>

      {/* Lo que espera una decisión del jefe va primero, antes que cualquier
          tablero: es a lo que viene cuando abre esta página desde el taller. */}
      <RepuestosPorAprobar onCambio={invalidar} />

      {/* Un informe armado y olvidado en borrador es plata que no se cobró:
          se queda a la vista hasta que alguien lo termine. */}
      <InformesRecobroEnCurso />

      {/* El ciclo de izquierda a derecha: cada casilla es lo que falta hacer.
          Click para ver solo esos equipos. */}
      <div className="grid gap-2 grid-cols-2 sm:grid-cols-3 lg:grid-cols-6">
        {PASOS.map((p) => {
          const n = conteoPaso[p.k] ?? 0
          const activo = paso === p.k
          return (
            <button key={p.k} onClick={() => setPaso(activo ? null : p.k)} title={p.hacer}
              className={cn('rounded-lg border p-3 text-left transition-colors',
                activo ? 'border-gray-900 bg-gray-50 ring-1 ring-gray-900' : 'hover:bg-muted/50',
                n === 0 && !activo && 'opacity-50')}>
              <div className="flex items-center gap-1.5">
                <span className={cn('h-2 w-2 shrink-0 rounded-full', p.color)} />
                <span className="text-2xl font-bold leading-none">{n}</span>
              </div>
              <p className="mt-1 text-[11px] font-medium leading-tight text-gray-700">{p.label}</p>
            </button>
          )
        })}
      </div>
      {paso && (
        <p className="-mt-3 text-xs text-muted-foreground">
          Mostrando {visibles.length} equipo{visibles.length === 1 ? '' : 's'} en «{PASOS.find((p) => p.k === paso)?.label}»
          — {PASOS.find((p) => p.k === paso)?.hacer}.
          <button onClick={() => setPaso(null)} className="ml-2 underline hover:text-gray-900">Ver todos</button>
        </p>
      )}

      <div className="grid gap-3 grid-cols-2 md:grid-cols-4">
        <Kpi label="Equipos con NC" value={kpi.total} />
        <Kpi label="NC totales" value={ncs.length} />
        <Kpi label="Esperando al jefe" value={conteoPaso.aprobar + conteoPaso.recursos + conteoPaso.planificar}
             warn={(conteoPaso.aprobar + conteoPaso.recursos + conteoPaso.planificar) > 0} />
        <Kpi label="NC recobrables al cliente" value={kpi.recobrables} />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {FILTROS.map(([k, l]) => (
          <button key={k} onClick={() => setFiltro(k)} className={cn('rounded-full border px-3 py-1 text-xs', filtro === k ? 'bg-orange-600 text-white border-orange-600' : 'hover:bg-muted')}>{l}</button>
        ))}
        {/* El detalle (foto, observación, notas) vive dentro de cada equipo: un
            solo click para abrirlos todos y revisar sin ir uno por uno. */}
        <button onClick={() => setExpandido(todoAbierto ? {} : Object.fromEntries(equipos.map((e) => [e.activoId, true])))}
                className="ml-auto inline-flex items-center gap-1 rounded-full border px-3 py-1 text-xs hover:bg-muted">
          {todoAbierto ? <ChevronRight className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
          {todoAbierto ? 'Plegar todo' : 'Ver el detalle de todas'}
        </button>
      </div>

      {/* ── En el teléfono: una tarjeta por equipo ─────────────────────────── */}
      <div className="space-y-2 md:hidden">
        {isLoading && <Spinner className="h-5 w-5" />}
        {visibles.map((eq) => {
          const abierto = expandido[eq.activoId] ?? false
          const pasoEq = PASOS.find((p) => p.k === eq.paso)!
          return (
            <NcEquipoCard
              key={eq.activoId}
              patente={eq.patente} nombre={eq.nombre} nNc={eq.ncs.length} sevMax={eq.sevMax}
              pasoLabel={PASO_TXT[eq.paso]} pasoHacer={pasoEq.hacer} pasoColor={pasoEq.color}
              nPendientes={eq.pendientes.length} nRecobrables={eq.nRecobrables}
              nInsumosOperador={eq.nInsumosOperador} nDelCliente={eq.nDelCliente}
              recursosTxt={eq.grupos || eq.horas > 0 || eq.nMateriales > 0
                ? `${eq.grupos ?? '—'}${eq.horas ? ` · ${eq.horas}h` : ''}${eq.nMateriales ? ` · ${eq.nMateriales} mat.` : ''}`
                : 'Sin recursos asignados'}
              abierto={abierto} ocupado={busyId === eq.activoId}
              onToggle={() => setExpandido((p) => ({ ...p, [eq.activoId]: !abierto }))}
              onRecursos={() => setRecursosEquipo(eq)}
              onPlanificar={() => planificar(eq)}
              onRecobro={() => setRecobroEquipo(eq)}
            >
              {/* Cada hallazgo con su foto: es lo que el jefe va a mirar. */}
              <div className="space-y-1.5">
                {eq.ncs.map((nc) => (
                  <button key={nc.id} onClick={() => setFichaNc({ nc, patente: eq.patente })}
                          className="flex w-full gap-2 rounded border bg-white p-2 text-left">
                    {nc.foto_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={nc.foto_url} alt="Evidencia" className="h-12 w-12 shrink-0 rounded border object-cover" />
                    ) : (
                      <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded border border-dashed border-gray-300 text-gray-300">
                        <ImageOff className="h-4 w-4" />
                      </span>
                    )}
                    <span className="min-w-0 flex-1">
                      <span className="block text-xs font-medium text-gray-800">{nc.descripcion}</span>
                      {nc.observacion_item && (
                        <span className="mt-0.5 block text-[11px] text-gray-600">«{nc.observacion_item}»</span>
                      )}
                      <span className="mt-0.5 block text-[10px] text-muted-foreground">
                        {ESTADO_BADGE[nc.estado_planificacion]?.t ?? nc.estado_planificacion} · {nc.severidad}
                      </span>
                    </span>
                  </button>
                ))}
              </div>
            </NcEquipoCard>
          )
        })}
        {!isLoading && visibles.length === 0 && (
          <p className="rounded-lg border bg-white p-6 text-center text-sm text-muted-foreground">
            {paso ? `Ningún equipo está en «${PASOS.find((p) => p.k === paso)?.label}».` : 'Sin No Conformidades.'}
          </p>
        )}
      </div>

      {/* ── En pantalla grande: la tabla completa ──────────────────────────── */}
      <Card className="hidden md:block">
        <CardContent className="p-0 overflow-x-auto">
          {isLoading && <div className="p-4"><Spinner className="h-5 w-5" /></div>}
          <table className="w-full text-sm">
            <thead><tr className="text-xs text-muted-foreground border-b">
              <th className="text-left p-2">Equipo</th><th className="p-2">NC</th><th className="p-2">Sev.</th>
              <th className="p-2">Recobro</th>
              <th className="text-left p-2">Recursos del conjunto</th>
              <th className="p-2">Estado</th><th className="p-2"></th>
            </tr></thead>
            <tbody>
              {visibles.map((eq) => {
                const abierto = expandido[eq.activoId] ?? false
                const eb = ESTADO_EQUIPO[eq.estado] ?? { v: 'default', t: eq.estado }
                const pasoEq = PASOS.find((p) => p.k === eq.paso)!
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
                      <td className="p-2 text-center whitespace-nowrap" onClick={(e) => e.stopPropagation()}>
                        <RecobroResumenEquipo eq={eq} onDone={invalidar} />
                      </td>
                      <td className="p-2 text-xs text-muted-foreground">
                        {eq.grupos || eq.horas > 0 || eq.nMateriales > 0
                          ? `${eq.grupos ?? '—'}${eq.horas ? ` · ${eq.horas}h` : ''}${eq.dias ? ` · ${eq.dias}d` : ''}${eq.nMateriales ? ` · ${eq.nMateriales} mat.` : ''}`
                          : <span className="text-amber-600">sin asignar</span>}
                        {eq.nInsumosOperador > 0 && (
                          <span className="ml-1.5 rounded bg-orange-100 px-1.5 py-0.5 text-[10px] font-semibold text-orange-700 whitespace-nowrap">
                            {eq.nInsumosOperador} insumo{eq.nInsumosOperador > 1 ? 's' : ''} pedido{eq.nInsumosOperador > 1 ? 's' : ''} por operador
                          </span>
                        )}
                        {eq.nDelCliente > 0 && (
                          <span title="El cliente reportó esto desde el QR del equipo"
                                className="ml-1.5 rounded bg-blue-100 px-1.5 py-0.5 text-[10px] font-semibold text-blue-800 whitespace-nowrap">
                            {eq.nDelCliente} del cliente
                          </span>
                        )}
                        {eq.nNotas > 0 && (
                          <span title="Notas con foto que dejó el operador en la OT — ábrelas desplegando el equipo"
                                className="ml-1.5 inline-flex items-center gap-1 rounded bg-sky-100 px-1.5 py-0.5 text-[10px] font-semibold text-sky-700 whitespace-nowrap">
                            <StickyNote className="h-3 w-3" />
                            {eq.nNotas} nota{eq.nNotas > 1 ? 's' : ''} del operador
                          </span>
                        )}
                      </td>
                      <td className="p-2 text-center">
                        {/* Qué falta hacer, antes que en qué estado está: es lo
                            primero que el jefe necesita saber al mirar la fila. */}
                        <span title={pasoEq.hacer}
                              className={cn('inline-block whitespace-nowrap rounded-full px-2 py-0.5 text-[10px] font-bold text-white', pasoEq.color)}>
                          {PASO_TXT[eq.paso]}
                        </span>
                        <Badge variant={eb.v} className="ml-1 text-[10px]">{eb.t}</Badge>
                      </td>
                      <td className="p-2 whitespace-nowrap text-right" onClick={(e) => e.stopPropagation()}>
                        <Button size="sm" variant="outline" onClick={() => setRecursosEquipo(eq)}>
                          <Package className="h-3.5 w-3.5 mr-1" /> Recursos
                        </Button>
                        {eq.nRecobrables > 0 && (
                          <Button size="sm" variant="outline" className="ml-1 border-violet-300 text-violet-700 hover:bg-violet-50"
                                  title="Pasar las NC recobrables de este equipo a un informe de recobro, valorizadas con los recursos ya cargados"
                                  onClick={() => setRecobroEquipo(eq)}>
                            <Receipt className="h-3.5 w-3.5 mr-1" /> Recobro ({eq.nRecobrables})
                          </Button>
                        )}
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
                      <tr key={nc.id} className="border-b bg-muted/20 text-xs align-top cursor-pointer hover:bg-muted/50"
                          title="Abrir la ficha de esta NC: recursos, recobro e insumos"
                          onClick={() => setFichaNc({ nc, patente: eq.patente })}>
                        <td className="p-2 pl-8" colSpan={2}>
                          <div className="flex gap-2">
                            {/* La evidencia es lo primero que mira el jefe: foto grande y clickeable */}
                            {nc.foto_url ? (
                              <a href={nc.foto_url} target="_blank" rel="noreferrer" title="Ver la foto del hallazgo"
                                 onClick={(e) => e.stopPropagation()} className="shrink-0">
                                {/* eslint-disable-next-line @next/next/no-img-element */}
                                <img src={nc.foto_url} alt="Evidencia de la NC" className="h-14 w-14 rounded border object-cover hover:opacity-80" />
                              </a>
                            ) : (
                              <span title="Esta NC se levantó sin foto"
                                    className="flex h-14 w-14 shrink-0 items-center justify-center rounded border border-dashed border-gray-300 text-gray-300">
                                <ImageOff className="h-5 w-5" />
                              </span>
                            )}
                            <div className="min-w-0">
                              <p className="font-medium text-gray-800">{nc.descripcion}</p>
                              {nc.observacion_item && (
                                <p className="mt-0.5 text-[11px] text-gray-600">«{nc.observacion_item}»</p>
                              )}
                              <p className="mt-0.5 text-[10px] text-muted-foreground">
                                {new Date(nc.created_at).toLocaleDateString('es-CL')}
                                {nc.registrada_por_nombre ? ` · ${nc.registrada_por_nombre}` : ''}
                                {nc.ot_folio ? ` · OT ${nc.ot_folio}` : ''}
                              </p>
                            </div>
                          </div>
                        </td>
                        <td className="p-2 text-center"><Badge variant={nc.severidad as any} className="text-[10px]">{nc.severidad}</Badge></td>
                        <td className="p-2 text-center whitespace-nowrap" onClick={(e) => e.stopPropagation()}>
                          <RecobroMenu ncIds={[nc.id]} actual={nc.recobro} onDone={invalidar}
                                       titulo={`${RECOBRO_FUENTE_TXT[nc.recobro_fuente]}${nc.recobro_nota ? ` — «${nc.recobro_nota}»` : ''}`}>
                            <RecobroChip valor={nc.recobro} fuente={nc.recobro_fuente} />
                          </RecobroMenu>
                        </td>
                        <td className="p-2 text-[11px] text-muted-foreground">
                          {nc.grupo_trabajo || nc.horas_estimadas || nc.n_materiales > 0 ? (
                            <span className="text-gray-700">
                              {nc.grupo_trabajo ?? '—'}
                              {nc.horas_estimadas ? ` · ${nc.horas_estimadas}h` : ''}
                              {nc.n_materiales > 0 ? ` · ${nc.n_materiales} mat.` : ''}
                            </span>
                          ) : <span className="text-amber-600">sin recursos — abrir ficha</span>}
                          <span className="block">
                            {ORIGEN_TXT[nc.origen] ?? 'checklist'}
                            {nc.n_recursos_operador > 0 && ` · ${nc.n_recursos_operador} insumo(s) del operador`}
                          </span>
                          {nc.recobro_informe_folio && (
                            <span className="mt-0.5 inline-flex items-center gap-1 rounded bg-violet-100 px-1.5 py-0.5 text-[10px] font-semibold text-violet-800">
                              <Receipt className="h-3 w-3" /> {nc.recobro_informe_folio}
                            </span>
                          )}
                        </td>
                        <td className="p-2 text-center">
                          <Badge variant={(ESTADO_BADGE[nc.estado_planificacion]?.v) ?? 'default'} className="text-[10px]">
                            {ESTADO_BADGE[nc.estado_planificacion]?.t ?? nc.estado_planificacion}
                          </Badge>
                        </td>
                        <td />
                      </tr>
                    ))}
                    {abierto && eq.otIds.length > 0 && (
                      <tr className="border-b bg-muted/20">
                        <td colSpan={7} className="p-2 pl-8">
                          <NotasOperadorEquipo otIds={eq.otIds} onNcCreada={invalidar} />
                        </td>
                      </tr>
                    )}
                  </Fragment>
                )
              })}
              {!isLoading && visibles.length === 0 && (
                <tr><td colSpan={7} className="p-6 text-center text-muted-foreground">
                  {paso
                    ? `Ningún equipo está en «${PASOS.find((p) => p.k === paso)?.label}».`
                    : 'Sin No Conformidades. Genera desde un checklist de recepción o registra una ad-hoc.'}
                </td></tr>
              )}
            </tbody>
          </table>
        </CardContent>
      </Card>

      {fichaNc && (
        <NcFichaModal nc={fichaNc.nc} patente={fichaNc.patente}
                      onClose={() => setFichaNc(null)}
                      onDone={() => { setFichaNc(null); invalidar() }} />
      )}
      {recobroEquipo && (
        <InformeRecobroModal equipo={recobroEquipo}
                             onClose={() => setRecobroEquipo(null)}
                             onDone={() => { setRecobroEquipo(null); invalidar() }} />
      )}
      {recursosEquipo && <RecursosEquipoModal equipo={recursosEquipo} onClose={() => setRecursosEquipo(null)} onDone={() => { setRecursosEquipo(null); invalidar() }} />}
      {genOpen && <GenerarDesdeRecepcionModal onClose={() => setGenOpen(false)} onDone={() => { setGenOpen(false); invalidar() }} />}
      {adhocOpen && <RegistrarNcModal onClose={() => setAdhocOpen(false)} onDone={() => { setAdhocOpen(false); invalidar() }} />}
      {valeOpen && (
        <ValeBodegaModal grupos={equipos} listos={equiposListos}
                         onClose={() => {
                           setValeOpen(false)
                           qc.invalidateQueries({ queryKey: ['vale-equipos-listos'] })
                           qc.invalidateQueries({ queryKey: ['nc-insumos-operador'] })
                           invalidar()
                         }} />
      )}
    </div>
  )
}

function Kpi({ label, value, warn }: { label: string; value: number; warn?: boolean }) {
  return <Card><CardContent className="p-3"><div className="text-xs text-muted-foreground">{label}</div><div className={cn('text-2xl font-bold', warn && 'text-amber-600')}>{value}</div></CardContent></Card>
}

// ── Recobro (MIG250) ────────────────────────────────────────────────────────
// ¿El daño se le cobra al cliente o lo asume la empresa? La sugerencia viene de
// la pauta / de lo que marcó terreno; el jefe de taller la confirma o corrige y
// esa decisión manda (queda registrada con su nombre y fecha).
const RECOBRO_OPCIONES: Array<{ v: RecobroValor; ayuda: string }> = [
  { v: 'cliente',    ayuda: 'Daño del arrendatario — se le cobra' },
  { v: 'compartido', ayuda: 'Se reparte entre cliente y empresa' },
  { v: 'empresa',    ayuda: 'Desgaste normal / es nuestro — no se cobra' },
  { v: 'evaluar',    ayuda: 'Falta información para decidir' },
  { v: 'na',         ayuda: 'No corresponde recobro' },
]

function RecobroChip({ valor, fuente }: { valor: RecobroValor | null; fuente?: NcRecepcion['recobro_fuente'] }) {
  if (!valor) {
    return (
      <span className="inline-flex items-center rounded-full border border-dashed border-gray-300 px-2 py-0.5 text-[10px] font-semibold text-gray-400">
        definir
      </span>
    )
  }
  const l = RECOBRO_LABEL[valor]
  return (
    <span className={cn('inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-semibold', l.cls)}>
      {l.corto}
      {/* Punto hueco = todavía es una sugerencia, el jefe no la ha confirmado */}
      {fuente && fuente !== 'jefe' && <span className="opacity-50">◦</span>}
    </span>
  )
}

function RecobroMenu({ ncIds, actual, titulo, bulk, onDone, children }: {
  ncIds: string[]; actual: RecobroValor | null; titulo?: string; bulk?: number
  onDone: () => void; children: React.ReactNode
}) {
  const toast = useToast()
  const { canEdit, canCreate } = usePermissions()
  const puedeDefinir = canEdit('mantenimiento') || canCreate('mantenimiento')
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)

  if (!puedeDefinir) return <span title={titulo}>{children}</span>

  const aplicar = async (v: RecobroValor | null) => {
    setBusy(true)
    try {
      const r = await setRecobroNc(ncIds, v)
      toast.success(v
        ? `${r.actualizadas} NC marcada(s) como «${RECOBRO_LABEL[v].txt}»`
        : `${r.actualizadas} NC vuelven a lo que sugiere la pauta`)
      setOpen(false)
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al definir el recobro') } finally { setBusy(false) }
  }

  return (
    <span className="relative inline-block">
      <button type="button" title={titulo} disabled={busy} onClick={() => setOpen((o) => !o)}
              className="inline-flex items-center rounded hover:opacity-75 disabled:opacity-50">
        {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : children}
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 z-50 mt-1 w-60 rounded-lg border border-gray-200 bg-white p-1 text-left shadow-lg">
            <p className="px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-gray-400">
              {bulk && bulk > 1 ? `Recobro de las ${bulk} NC del equipo` : '¿Quién paga esta NC?'}
            </p>
            {RECOBRO_OPCIONES.map((o) => (
              <button key={o.v} type="button" onClick={() => aplicar(o.v)}
                      className={cn('flex w-full flex-col rounded px-2 py-1.5 text-left hover:bg-gray-50',
                                    actual === o.v && 'bg-gray-100')}>
                <span className="text-xs font-semibold text-gray-800">{RECOBRO_LABEL[o.v].txt}</span>
                <span className="text-[10px] text-gray-500">{o.ayuda}</span>
              </button>
            ))}
            <button type="button" onClick={() => aplicar(null)}
                    className="mt-0.5 w-full rounded border-t border-gray-100 px-2 py-1.5 text-left text-[10px] text-gray-500 hover:bg-gray-50">
              Volver a lo que sugiere la pauta
            </button>
          </div>
        </>
      )}
    </span>
  )
}

/** Recobro del CONJUNTO del equipo: un chip si todas coinciden, si no el conteo. */
function RecobroResumenEquipo({ eq, onDone }: { eq: EquipoNC; onDone: () => void }) {
  const ids = eq.ncs.map((n) => n.id)
  const primero = eq.ncs[0]?.recobro ?? null
  const unico = eq.ncs.every((n) => n.recobro === primero) ? primero : null
  const titulo = `${eq.nRecobrables} se le cobra(n) al cliente · ${eq.nNoRecobrables} las asume la empresa · ${eq.nRecobroPorDefinir} sin definir. Click para marcar las ${eq.ncs.length} NC del equipo.`
  return (
    <RecobroMenu ncIds={ids} actual={unico} titulo={titulo} bulk={eq.ncs.length} onDone={onDone}>
      {unico ? <RecobroChip valor={unico} /> : (
        <span className="inline-flex items-center gap-1 text-[10px] font-semibold">
          {eq.nRecobrables > 0 && <span className="rounded-full bg-green-100 px-1.5 py-0.5 text-green-800" title="Recobrables al cliente">{eq.nRecobrables}</span>}
          {eq.nNoRecobrables > 0 && <span className="rounded-full bg-rose-100 px-1.5 py-0.5 text-rose-800" title="Las asume la empresa">{eq.nNoRecobrables}</span>}
          {eq.nRecobroPorDefinir > 0 && <span className="rounded-full bg-gray-100 px-1.5 py-0.5 text-gray-500" title="Sin definir">{eq.nRecobroPorDefinir}?</span>}
        </span>
      )}
    </RecobroMenu>
  )
}

// ── Ficha de UNA No Conformidad (MIG251) ────────────────────────────────────
// Todo el análisis de la NC en un solo lugar: la evidencia, quién paga, los
// recursos que necesita (grupo, horas, materiales), lo que pidió el operador y
// las notas — y de ahí sale planificada o al informe de recobro.
function NcFichaModal({ nc, patente, onClose, onDone }: {
  nc: NcRecepcion; patente: string; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const { canEdit, canCreate } = usePermissions()
  const puedeGestionar = canEdit('mantenimiento') || canCreate('mantenimiento')

  const { data: prodRes } = useQuery({ queryKey: ['productos-nc'], queryFn: () => getProductos(), staleTime: 300_000 })
  const productos = (prodRes?.data ?? []) as Array<{ id: string; codigo: string; nombre: string; categoria: string }>
  const { data: categorias = [] } = useQuery({ queryKey: ['producto-categorias-activas'], queryFn: () => getCategoriasProducto(true), staleTime: 300_000 })
  const { data: tecnicosCat = [] } = useQuery({ queryKey: ['taller-tecnicos-activos'], queryFn: () => getTallerTecnicos(), staleTime: 300_000 })
  const { data: matsGuardados, isLoading: cargandoMats } = useQuery({
    queryKey: ['nc-materiales', nc.id], queryFn: () => getNcMateriales(nc.id),
  })

  type MatRow = NcMaterial & { solicitar?: boolean; foto?: File | null }
  const [mecanicos, setMecanicos] = useState<string[]>(() =>
    (nc.grupo_trabajo ?? '').split(',').map((s) => s.trim()).filter(Boolean))
  const [horas, setHoras] = useState(nc.horas_estimadas ? String(nc.horas_estimadas) : '')
  const [dias, setDias] = useState(nc.tiempo_estimado_dias ? String(nc.tiempo_estimado_dias) : '')
  const [recobro, setRecobro] = useState<RecobroValor | null>(nc.recobro)
  const [recobroNota, setRecobroNota] = useState(nc.recobro_nota ?? '')
  const [saving, setSaving] = useState(false)
  const [planificando, setPlanificando] = useState(false)

  const opcionesTecnicos = useMemo(() => {
    const base = tecnicosCat.length > 0
      ? tecnicosCat.map((t) => ({ nombre: t.nombre, especialidad: t.especialidad }))
      : (MECANICOS as readonly string[]).map((m) => ({ nombre: m, especialidad: '' }))
    const extra = mecanicos.filter((m) => !base.some((b) => b.nombre === m)).map((m) => ({ nombre: m, especialidad: '' }))
    return [...base, ...extra]
  }, [tecnicosCat, mecanicos])

  const guardar = async () => {
    setSaving(true)
    try {
      // Solo mano de obra: los insumos se piden uno a uno en su propio panel, y
      // guardarlos aquí los borraría (fn_asignar_recursos_nc reescribe la lista).
      await guardarManoObraNc({
        ncId: nc.id,
        grupo: mecanicos.length ? mecanicos.join(', ') : null,
        horas: horas ? Number(horas) : null,
        tiempoDias: dias ? Number(dias) : null,
      })
      // La clasificación de recobro solo se toca si el jefe la cambió
      if (recobro !== nc.recobro || (recobroNota.trim() || null) !== nc.recobro_nota) {
        await setRecobroNc([nc.id], recobro, recobroNota.trim() || null)
      }
      toast.success('Análisis de la NC guardado')
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al guardar') } finally { setSaving(false) }
  }

  const planificar = async () => {
    setPlanificando(true)
    try {
      const r: any = await planificarNc(nc.id)
      toast.success(r?.mensaje === 'Ya tenía OT' ? 'Esta NC ya estaba en una OT correctiva' : 'OT correctiva creada para esta NC')
      qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
      qc.invalidateQueries({ queryKey: ['nc-ot-por-agendar'] })
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al planificar') } finally { setPlanificando(false) }
  }

  const yaPlanificada = !!nc.plan_ot_id
  const otIds = [nc.ot_id, nc.plan_ot_id].filter(Boolean) as string[]

  return (
    // Más ancho que el modal por defecto: aquí conviven evidencia, recobro,
    // recursos, insumos y notas.
    <Modal open onClose={onClose} title={`NC de ${patente}`} className="sm:max-w-2xl">
      <div className="space-y-3">
        {/* ── Evidencia ── */}
        <div className="flex gap-3 rounded-lg border border-gray-200 bg-gray-50 p-2.5">
          {nc.foto_url ? (
            <a href={nc.foto_url} target="_blank" rel="noreferrer" title="Abrir la foto en grande" className="shrink-0">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={nc.foto_url} alt="Evidencia de la NC" className="h-24 w-24 rounded border object-cover hover:opacity-80" />
            </a>
          ) : (
            <span className="flex h-24 w-24 shrink-0 items-center justify-center rounded border border-dashed border-gray-300 text-gray-300">
              <ImageOff className="h-6 w-6" />
            </span>
          )}
          <div className="min-w-0 flex-1">
            <p className="text-sm font-semibold text-gray-800">{nc.descripcion}</p>
            {nc.observacion_item && <p className="mt-0.5 text-xs text-gray-600">«{nc.observacion_item}»</p>}
            <p className="mt-1 text-[11px] text-gray-500">
              {new Date(nc.created_at).toLocaleDateString('es-CL')}
              {nc.registrada_por_nombre ? ` · ${nc.registrada_por_nombre}` : ''}
              {nc.ot_folio ? ` · OT ${nc.ot_folio}` : ''}
            </p>
            <div className="mt-1 flex flex-wrap items-center gap-1">
              <Badge variant={nc.severidad as any} className="text-[10px]">{nc.severidad}</Badge>
              <Badge variant={(ESTADO_BADGE[nc.estado_planificacion]?.v) ?? 'default'} className="text-[10px]">
                {ESTADO_BADGE[nc.estado_planificacion]?.t ?? nc.estado_planificacion}
              </Badge>
              {nc.recobro_informe_folio && (
                <Link href={`/dashboard/flota/recepcion/${nc.recobro_informe_id}/emitir`} target="_blank"
                      className="inline-flex items-center gap-1 rounded bg-violet-100 px-1.5 py-0.5 text-[10px] font-semibold text-violet-800 hover:underline">
                  <Receipt className="h-3 w-3" /> En el informe {nc.recobro_informe_folio}
                  <ExternalLink className="h-3 w-3" />
                </Link>
              )}
            </div>
          </div>
        </div>

        {/* ── ¿Quién paga? ── */}
        <div className="rounded-lg border border-gray-200 p-2.5">
          <p className="text-xs font-semibold text-gray-700">¿Se le recobra al cliente?</p>
          <div className="mt-1.5 flex flex-wrap gap-1">
            {RECOBRO_OPCIONES.map((o) => {
              const on = recobro === o.v
              return (
                <button key={o.v} type="button" disabled={!puedeGestionar} onClick={() => setRecobro(o.v)} title={o.ayuda}
                        className={cn('rounded border px-2 py-1 text-[11px] font-medium disabled:opacity-50',
                                      on ? RECOBRO_LABEL[o.v].cls : 'border-gray-200 bg-white text-gray-600')}>
                  {RECOBRO_LABEL[o.v].corto}
                </button>
              )
            })}
          </div>
          <p className="mt-1 text-[10px] text-gray-500">
            Sugerencia actual: <b>{nc.recobro ? RECOBRO_LABEL[nc.recobro].txt : 'ninguna'}</b> ({RECOBRO_FUENTE_TXT[nc.recobro_fuente]}).
          </p>
          <input value={recobroNota} onChange={(e) => setRecobroNota(e.target.value)} disabled={!puedeGestionar}
                 placeholder="Justificación del recobro (la lee el encargado de cobros)…"
                 className="mt-1.5 w-full rounded border border-gray-300 px-2 py-1.5 text-xs" />
        </div>

        {/* ── Recursos de ESTA NC ── */}
        <div>
          <label className="text-xs font-medium">Grupo de trabajo (mano de obra)</label>
          <div className="mt-1 flex flex-wrap gap-1">
            {opcionesTecnicos.map((t) => {
              const on = mecanicos.includes(t.nombre)
              return (
                <button key={t.nombre} type="button" disabled={!puedeGestionar} title={t.especialidad || undefined}
                        onClick={() => setMecanicos((p) => p.includes(t.nombre) ? p.filter((x) => x !== t.nombre) : [...p, t.nombre])}
                        className={`rounded border px-2 py-1 text-[11px] disabled:opacity-50 ${on ? 'border-blue-500 bg-blue-500 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>
                  {t.nombre}
                  {t.especialidad && <span className={`ml-1 text-[9px] ${on ? 'text-blue-100' : 'text-gray-400'}`}>{t.especialidad}</span>}
                </button>
              )
            })}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs font-medium">Horas estimadas (HH)
            <input type="number" value={horas} onChange={(e) => setHoras(e.target.value)} disabled={!puedeGestionar}
                   className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
          <label className="text-xs font-medium">Tiempo (días)
            <input type="number" value={dias} onChange={(e) => setDias(e.target.value)} disabled={!puedeGestionar}
                   className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
        </div>

        {/* ── UN solo lugar para pedir a bodega (MIG254) ── */}
        <InsumosNC ncId={nc.id} puedeGestionar={puedeGestionar} otId={nc.plan_ot_id ?? nc.ot_id} />

        {/* ── Notas del operador ── */}
        {otIds.length > 0 && <NotasOperadorEquipo otIds={otIds} />}
      </div>

      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cerrar</Button>
        {puedeGestionar && !yaPlanificada && (
          <Button variant="outline" onClick={planificar} disabled={planificando || saving}
                  title="Crea la OT correctiva solo de esta NC (para el resto del equipo usa «Planificar equipo»)">
            {planificando ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Wrench className="h-4 w-4 mr-1" />}
            Planificar solo esta NC
          </Button>
        )}
        {puedeGestionar && (
          <Button onClick={guardar} disabled={saving}>
            {saving ? 'Guardando…' : 'Guardar análisis'}
          </Button>
        )}
      </ModalFooter>
    </Modal>
  )
}

// ── Insumos de la NC: UNA lista, UN botón (MIG254) ──────────────────────────
// Antes había tres caminos para pedirle algo a bodega desde una NC y el jefe
// tenía que adivinar cuál usar (dos de ellos nunca se usaron en producción).
// Ahora: una lista con el estado real de cada insumo y un solo «+ Agregar»,
// que muestra el stock al elegir. El sistema decide el circuito por dentro.
function InsumosNC({ ncId, puedeGestionar, otId }: {
  ncId: string; puedeGestionar: boolean; otId: string | null
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: insumos = [], isLoading } = useQuery({
    queryKey: ['nc-insumos', ncId], queryFn: () => getInsumosNc(ncId), staleTime: 10_000,
  })
  const refrescar = () => {
    qc.invalidateQueries({ queryKey: ['nc-insumos', ncId] })
    qc.invalidateQueries({ queryKey: ['nc-recepcion'] })
    qc.invalidateQueries({ queryKey: ['vale-equipos-listos'] })
  }

  const [abierto, setAbierto] = useState(false)
  const [q, setQ] = useState('')
  const [resultados, setResultados] = useState<ProductoConStock[]>([])
  const [prod, setProd] = useState<ProductoConStock | null>(null)
  const [cant, setCant] = useState('1')
  const [foto, setFoto] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [cantidades, setCantidades] = useState<Record<string, string>>({})

  useEffect(() => {
    if (prod || q.trim().length < 2) { setResultados([]); return }
    const t = setTimeout(async () => {
      try { setResultados(await buscarInsumosConStock(q)) } catch { setResultados([]) }
    }, 300)
    return () => clearTimeout(t)
  }, [q, prod])

  const porAprobar = insumos.filter((i) => i.estado === 'solicitado').length
  const paraVale = insumos.filter((i) => i.estado === 'aprobado').length

  const agregar = async () => {
    const n = Number(cant)
    if (!n || n <= 0 || (!prod && q.trim().length < 3)) return
    setBusy(true)
    try {
      const fotos = foto && otId ? [await subirFotoRecurso(otId, foto)] : null
      const r = await agregarInsumoNc({
        ncId, cantidad: n,
        productoId: prod?.id ?? null,
        descripcion: prod ? null : q.trim(),
        unidad: prod?.unidad_medida ?? null,
        fotos,
      })
      toast.success(r.sin_stock
        ? 'Agregado — OJO: no hay stock, bodega tendrá que comprarlo'
        : 'Insumo agregado: va en el próximo vale de bodega')
      setQ(''); setProd(null); setCant('1'); setFoto(null); setAbierto(false)
      refrescar()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al agregar') } finally { setBusy(false) }
  }

  const validar = async (id: string, accion: 'aprobar' | 'rechazar', cantOriginal: number) => {
    setBusy(true)
    try {
      const txt = cantidades[id]
      const nota = accion === 'rechazar' ? (window.prompt('Motivo del rechazo (lo verá quien lo pidió):') ?? undefined) : undefined
      await validarRecurso({
        recursoId: id, accion,
        cantidadAprobada: accion === 'aprobar' ? (txt ? Number(txt) : cantOriginal) : null,
        nota: nota?.trim() || null,
      })
      refrescar()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setBusy(false) }
  }

  const quitar = async (i: (typeof insumos)[number]) => {
    if (!window.confirm(`¿Quitar «${i.descripcion}» de esta NC?`)) return
    setBusy(true)
    try { await quitarInsumoNc(i.id, i.fuente); refrescar() }
    catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setBusy(false) }
  }

  return (
    <div className="rounded-lg border border-orange-200 bg-orange-50/50 p-2.5">
      <div className="mb-1.5 flex flex-wrap items-center justify-between gap-2">
        <p className="flex items-center gap-1 text-xs font-semibold text-orange-800">
          <Package className="h-3.5 w-3.5" /> Insumos que necesita esta NC
          {porAprobar > 0 && (
            <span className="rounded-full bg-amber-200 px-1.5 py-0.5 text-[10px] font-bold text-amber-900">
              {porAprobar} por aprobar
            </span>
          )}
        </p>
        {puedeGestionar && (
          <button type="button" onClick={() => setAbierto((v) => !v)}
                  className="rounded bg-orange-600 px-2.5 py-1 text-[11px] font-semibold text-white">
            {abierto ? 'Cancelar' : '+ Agregar insumo'}
          </button>
        )}
      </div>

      {isLoading ? <Spinner className="h-4 w-4" /> : insumos.length === 0 ? (
        <p className="text-[11px] text-gray-500">
          Sin insumos todavía. Agrega lo que se necesita y viajará solo al vale de bodega del equipo.
        </p>
      ) : (
        <div className="space-y-1.5">
          {insumos.map((i) => {
            const chip = INSUMO_ESTADO[i.estado] ?? { txt: i.estado, cls: 'bg-gray-100 text-gray-600' }
            const enVale = i.estado === 'en_vale' || i.estado === 'entregado'
            return (
              <div key={`${i.fuente}-${i.id}`} className="rounded border border-orange-100 bg-white px-2 py-1.5">
                <div className="flex flex-wrap items-center gap-2 text-xs">
                  <span className="min-w-0 flex-1 font-medium text-gray-800">{i.descripcion}</span>
                  <span className="whitespace-nowrap text-gray-600">{i.cantidad} {i.unidad ?? 'un'}</span>
                  {enVale && i.ticket_id ? (
                    <a href={`/vale/${i.ticket_id}`} target="_blank" rel="noreferrer"
                       title="Ver / volver a imprimir el vale"
                       className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium underline decoration-dotted ${chip.cls}`}>
                      <Printer className="h-3 w-3" /> {chip.txt}{i.ticket_folio ? ` · ${i.ticket_folio}` : ''}
                    </a>
                  ) : (
                    <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${chip.cls}`}>{chip.txt}</span>
                  )}
                  {puedeGestionar && !enVale && i.estado !== 'solicitado' && (
                    <button type="button" onClick={() => quitar(i)} disabled={busy}
                            title="Quitar de esta NC" className="text-red-500 disabled:opacity-50">
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  )}
                </div>
                {(i.solicitado_nombre || i.comentario) && (
                  <p className="mt-0.5 text-[10px] text-gray-500">
                    {i.lo_agrego_el_jefe ? 'Agregado por jefatura' : `Lo pidió ${i.solicitado_nombre ?? 'el operador'}`}
                    {i.comentario ? ` · «${i.comentario}»` : ''}
                  </p>
                )}
                {(i.fotos?.length ?? 0) > 0 && (
                  <div className="mt-1 flex gap-1">
                    {(i.fotos ?? []).map((url, k) => (
                      <a key={k} href={url} target="_blank" rel="noreferrer">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={url} alt="foto del insumo" className="h-12 w-12 rounded border object-cover hover:opacity-80" />
                      </a>
                    ))}
                  </div>
                )}
                {puedeGestionar && i.estado === 'solicitado' && (
                  <div className="mt-1 flex items-center gap-1.5">
                    <input type="number" min="0" step="any"
                           value={cantidades[i.id] ?? String(i.cantidad_pedida)}
                           onChange={(e) => setCantidades((p) => ({ ...p, [i.id]: e.target.value }))}
                           className="w-16 rounded border border-gray-300 px-1.5 py-0.5 text-xs" />
                    <button type="button" onClick={() => validar(i.id, 'aprobar', i.cantidad_pedida)} disabled={busy}
                            className="rounded bg-green-600 px-2 py-1 text-[11px] font-semibold text-white disabled:opacity-50">
                      Aprobar
                    </button>
                    <button type="button" onClick={() => validar(i.id, 'rechazar', i.cantidad_pedida)} disabled={busy}
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

      {abierto && (
        <div className="mt-2 space-y-1.5 rounded border border-orange-200 bg-white p-2">
          {prod ? (
            <div className="flex items-center gap-2 rounded border border-green-200 bg-green-50 px-2 py-1 text-xs">
              <span className="min-w-0 flex-1 font-medium text-green-800">{prod.nombre}</span>
              <span className={`whitespace-nowrap rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                prod.stock > 0 ? 'bg-green-200 text-green-900' : 'bg-red-100 text-red-700'}`}>
                {prod.stock > 0 ? `${prod.stock} en bodega` : 'sin stock'}
              </span>
              <button type="button" onClick={() => { setProd(null); setQ('') }} className="text-[11px] text-green-700">cambiar</button>
            </div>
          ) : (
            <div>
              <input value={q} onChange={(e) => setQ(e.target.value)} autoFocus
                     placeholder="Busca en bodega o describe el material…"
                     className="w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
              {resultados.length > 0 && (
                <div className="mt-1 overflow-hidden rounded border border-gray-200 bg-white">
                  {resultados.map((r) => (
                    <button key={r.id} type="button" onClick={() => { setProd(r); setResultados([]) }}
                            className="flex w-full items-center gap-2 border-b border-gray-100 px-2 py-1.5 text-left text-xs last:border-0 hover:bg-gray-50">
                      <span className="min-w-0 flex-1 truncate">{r.nombre}</span>
                      {/* El stock a la vista: el jefe ya no adivina si hay */}
                      <span className={`whitespace-nowrap rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                        r.stock > 0 ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-700'}`}>
                        {r.stock > 0 ? `${r.stock} disp.` : 'sin stock'}
                      </span>
                    </button>
                  ))}
                </div>
              )}
              {q.trim().length >= 3 && resultados.length === 0 && (
                <p className="mt-1 text-[10px] text-gray-500">
                  No está en el catálogo: se pedirá tal como lo escribiste y bodega lo comprará.
                </p>
              )}
            </div>
          )}
          <div className="flex items-center gap-1.5">
            <input type="number" min="0" value={cant} onChange={(e) => setCant(e.target.value)}
                   placeholder="Cantidad" className="w-24 rounded border border-gray-300 px-2 py-1.5 text-sm" />
            {otId && (
              <label className={`cursor-pointer rounded border px-2 py-1.5 text-[11px] whitespace-nowrap ${
                foto ? 'border-green-400 bg-green-50 text-green-700' : 'border-gray-300 text-gray-600'}`}>
                {foto ? '✓ foto' : '📷 foto'}
                <input type="file" accept="image/*" capture="environment" className="hidden"
                       onChange={(e) => setFoto(e.target.files?.[0] ?? null)} />
              </label>
            )}
            <button type="button" disabled={busy || !Number(cant) || (!prod && q.trim().length < 3)} onClick={agregar}
                    className="rounded bg-orange-600 px-2.5 py-1.5 text-[11px] font-semibold text-white disabled:opacity-50">
              {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : 'Agregar'}
            </button>
          </div>
        </div>
      )}

      <p className="mt-1.5 text-[10px] text-gray-500">
        {paraVale > 0
          ? `${paraVale} insumo(s) esperando el vale. `
          : ''}
        Todo lo aprobado sale junto en el vale de bodega del equipo («Vale para bodega», arriba).
        Si algo no tiene stock, bodega lo compra y vuelve como recibido para el vale.
      </p>
    </div>
  )
}

// ── Informe de recobros del equipo (MIG251) ─────────────────────────────────
// Cierra el ciclo: lo que el jefe clasificó como recobrable pasa a un informe
// IR valorizado con los recursos que ya cargó, y el encargado de cobros lo
// emite con firma y PDF en /dashboard/flota/recepcion.
function InformeRecobroModal({ equipo, onClose, onDone }: {
  equipo: EquipoNC; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [tarifaId, setTarifaId] = useState('')
  const [resultado, setResultado] = useState<{ informe_id: string; folio: string; informe_nuevo: boolean; hallazgos_creados: number; ya_estaban: number; costos_creados: number; total_cobrable: number } | null>(null)
  const { data: tarifasRes } = useQuery({ queryKey: ['tarifas-hh'], queryFn: getTarifasHH, staleTime: 300_000 })
  const tarifas = tarifasRes?.data ?? []

  const recobrables = equipo.ncs.filter((n) => n.recobro === 'cliente' || n.recobro === 'compartido')
  const sinRecursos = recobrables.filter((n) => !n.grupo_trabajo && !n.horas_estimadas && n.n_materiales === 0)
  const nMateriales = recobrables.reduce((s, n) => s + Number(n.n_materiales ?? 0), 0)
  const horas = recobrables.reduce((s, n) => s + Number(n.horas_estimadas ?? 0), 0)

  const armar = async () => {
    setBusy(true)
    try {
      const r = await armarInformeRecobro({
        activoId: equipo.activoId, ncIds: recobrables.map((n) => n.id), tarifaHhId: tarifaId || null,
      })
      setResultado(r)
      toast.success(r.informe_nuevo
        ? `Informe de recobro ${r.folio} creado con ${r.hallazgos_creados} hallazgo(s)`
        : `${r.hallazgos_creados} hallazgo(s) agregados al informe ${r.folio}`)
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al armar el informe') } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Informe de recobro · ${equipo.patente}`}>
      <div className="space-y-3">
        <p className="text-xs text-gray-600">
          Pasan al informe las NC que clasificaste como <b>recobrables al cliente</b> (o compartidas), con
          su foto, su observación y el detalle de lo que hay que cobrar: qué material, cuánta cantidad y
          cuántas horas. <b>Va sin valores</b> — los precios los carga el planificador en el informe, que
          queda editable hasta que se emite.
        </p>

        <div className="grid grid-cols-3 gap-2 text-center">
          <div className="rounded-lg border p-2"><div className="text-[10px] text-gray-500">NC recobrables</div><div className="text-xl font-bold">{recobrables.length}</div></div>
          <div className="rounded-lg border p-2"><div className="text-[10px] text-gray-500">Ítems de material</div><div className="text-xl font-bold">{nMateriales}</div></div>
          <div className="rounded-lg border p-2"><div className="text-[10px] text-gray-500">Mano de obra</div><div className="text-xl font-bold">{horas} HH</div></div>
        </div>

        {horas > 0 && (
          <label className="block text-xs font-medium">
            Especialidad de la mano de obra (opcional)
            <select value={tarifaId} onChange={(e) => setTarifaId(e.target.value)}
                    className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm">
              <option value="">— Sin especificar —</option>
              {tarifas.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}
            </select>
            <span className="mt-0.5 block text-[10px] text-gray-500">
              Solo nombra la línea de las {horas} HH para que el planificador sepa qué tarifa aplicar.
              El valor lo pone él.
            </span>
          </label>
        )}

        {sinRecursos.length > 0 && (
          <p className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-[11px] text-amber-800">
            <b>{sinRecursos.length}</b> de estas NC no tienen recursos cargados: entrarán al informe como
            hallazgo <b>sin valorizar</b>. Si quieres cobrarlas, ábrelas primero y asígnales materiales/horas.
          </p>
        )}

        <div className="max-h-56 space-y-1 overflow-y-auto rounded-lg border border-gray-100 bg-gray-50 p-2">
          {recobrables.map((n) => (
            <div key={n.id} className="flex items-center gap-2 rounded border border-gray-100 bg-white px-2 py-1.5 text-xs">
              {n.foto_url && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={n.foto_url} alt="foto" className="h-8 w-8 shrink-0 rounded border object-cover" />
              )}
              <span className="min-w-0 flex-1 truncate text-gray-700" title={n.descripcion}>{n.descripcion}</span>
              <RecobroChip valor={n.recobro} />
              <span className="w-24 text-right text-[11px] text-gray-500">
                {[n.n_materiales ? `${n.n_materiales} mat.` : null,
                  n.horas_estimadas ? `${n.horas_estimadas}h` : null].filter(Boolean).join(' · ') || '—'}
              </span>
              {n.recobro_informe_folio && <Receipt className="h-3.5 w-3.5 text-violet-600" />}
            </div>
          ))}
        </div>

        {resultado && (
          <div className="rounded-lg border border-green-200 bg-green-50 p-2.5 text-xs text-green-900">
            <p className="font-semibold">Informe {resultado.folio} listo</p>
            <p className="mt-0.5">
              {resultado.hallazgos_creados} hallazgo(s) nuevos
              {resultado.ya_estaban > 0 && ` · ${resultado.ya_estaban} ya estaban`}
              {' · '}{resultado.costos_creados} ítem(s) por valorizar
            </p>
            <Link href={`/dashboard/flota/recepcion/${resultado.informe_id}/emitir`} target="_blank"
                  className="mt-1 inline-flex items-center gap-1 font-semibold text-green-800 underline">
              Abrir el informe para valorizar y emitir <ExternalLink className="h-3 w-3" />
            </Link>
          </div>
        )}
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
        <Button onClick={armar} disabled={busy || recobrables.length === 0}>
          {busy ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Receipt className="h-4 w-4 mr-1" />}
          {resultado ? 'Volver a sincronizar' : `Pasar ${recobrables.length} NC al informe`}
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// ── Notas / anexos del operador (MIG249) ────────────────────────────────────
// Lo que el operador escribió en la OT y que no cabía en el checklist. El jefe
// las tenía solo en la ficha de la OT; aquí las ve junto a las NC del equipo.
function NotasOperadorEquipo({ otIds, onNcCreada }: { otIds: string[]; onNcCreada?: () => void }) {
  const { data: notas = [], isLoading } = useQuery({
    queryKey: ['nc-notas-operador', ...otIds],
    queryFn: () => getNotasOTs(otIds),
    staleTime: 30_000,
  })
  if (isLoading) return <Spinner className="h-4 w-4" />
  if (notas.length === 0) {
    return <p className="text-[11px] text-gray-400">Sin notas del operador en las OT de este equipo.</p>
  }
  return (
    <div className="rounded-lg border border-sky-200 bg-sky-50/60 p-2">
      <p className="mb-1.5 flex items-center gap-1 text-xs font-semibold text-sky-900">
        <StickyNote className="h-3.5 w-3.5" /> Notas del operador ({notas.length})
        <span className="font-normal text-[10px] text-sky-700">— si de una sale trabajo, conviértela en NC</span>
      </p>
      <div className="space-y-1.5">
        {notas.map((n) => (
          <div key={n.id} className="rounded border border-sky-100 bg-white px-2 py-1.5">
            <p className="whitespace-pre-wrap text-xs text-gray-800">{n.texto}</p>
            <p className="mt-0.5 text-[10px] text-gray-500">
              {n.autor ?? 'Operador'} · {new Date(n.created_at).toLocaleString('es-CL')}
            </p>
            {n.fotos.length > 0 && (
              <div className="mt-1 flex flex-wrap gap-1">
                {n.fotos.map((url, i) => (
                  <a key={i} href={url} target="_blank" rel="noreferrer" title="Abrir la foto de la nota">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={url} alt="Foto de la nota" className="h-14 w-14 rounded border object-cover hover:opacity-80" />
                  </a>
                ))}
              </div>
            )}
            <NotaAccionNc nota={n} onDone={onNcCreada} />
          </div>
        ))}
      </div>
    </div>
  )
}

// Nota → NC (MIG252): la NC nace con la foto y el autor de la nota, y entra al
// mismo circuito (recursos → planificar → recobro).
function NotaAccionNc({ nota, onDone }: { nota: OTNota; onDone?: () => void }) {
  const toast = useToast()
  const qc = useQueryClient()
  const { canEdit, canCreate } = usePermissions()
  const [sev, setSev] = useState<'baja' | 'media' | 'alta' | 'critica'>('media')
  const [busy, setBusy] = useState(false)

  if (!(canEdit('mantenimiento') || canCreate('mantenimiento'))) return null
  if (nota.nc_id) {
    return (
      <p className="mt-1 inline-flex items-center gap-1 rounded bg-green-100 px-1.5 py-0.5 text-[10px] font-semibold text-green-800">
        <CheckCircle2 className="h-3 w-3" /> Ya levantada como No Conformidad
      </p>
    )
  }

  const convertir = async () => {
    setBusy(true)
    try {
      const r = await convertirNotaEnNc({ evidenciaId: nota.id, severidad: sev })
      toast.success(r.ya_existia
        ? 'Esta nota ya tenía su NC'
        : 'NC levantada desde la nota — ya puedes asignarle recursos y clasificar el recobro')
      qc.invalidateQueries({ queryKey: ['nc-notas-operador'] })
      qc.invalidateQueries({ queryKey: ['nc-recepcion'] })
      onDone?.()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al convertir la nota') } finally { setBusy(false) }
  }

  return (
    <div className="mt-1.5 flex items-center gap-1.5">
      <select value={sev} onChange={(e) => setSev(e.target.value as typeof sev)}
              className="rounded border border-gray-300 px-1.5 py-0.5 text-[11px]">
        <option value="baja">Baja</option><option value="media">Media</option>
        <option value="alta">Alta</option><option value="critica">Crítica</option>
      </select>
      <button type="button" onClick={convertir} disabled={busy}
              title="Crea una NC con esta foto y este texto, a nombre del operador que la escribió"
              className="inline-flex items-center gap-1 rounded border border-sky-300 bg-white px-2 py-1 text-[11px] font-semibold text-sky-700 hover:bg-sky-50 disabled:opacity-50">
        {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : <AlertTriangle className="h-3 w-3" />}
        Convertir en NC
      </button>
    </div>
  )
}

// Botón grande "Vale para bodega": SIEMPRE habilitado. Elegir la patente,
// revisar/aprobar/agregar los recursos del equipo (con foto) y emitir el vale
// aquí mismo — aunque todavía no haya nada aprobado. Bodega recibe campanita
// y el vale queda imprimible para el retiro.
type EquipoVale = { otId: string; otFolio: string; patente: string; nombre: string | null; items: OTRecursoSeguimiento[] }

function ValeBodegaModal({ grupos, listos, onClose }: {
  grupos: EquipoNC[]; listos: EquipoVale[]; onClose: () => void
}) {
  type Opcion = { key: string; patente: string; nombre: string | null; otIds: string[]; nc: NcRecepcion; nListos: number }

  // UNA entrada por patente. Por dentro junta TODAS las OT del equipo (la de
  // origen de los hallazgos y la correctiva donde el operador pide durante la
  // ejecución) — MIG213: el vale también se arma por equipo.
  const opciones = useMemo<Opcion[]>(() => {
    const out: Opcion[] = []
    const vistos = new Set<string>()
    const fakeNc = (key: string, otId: string) =>
      ({ id: `eq-${key}`, ot_id: otId, checklist_item_ref: null } as unknown as NcRecepcion)
    for (const g of grupos) {
      const otIds: string[] = []
      let mainOt: string | null = null
      for (const n of g.ncs) {
        if (n.ot_id && !otIds.includes(n.ot_id)) otIds.push(n.ot_id)
        if (n.plan_ot_id && !otIds.includes(n.plan_ot_id)) otIds.push(n.plan_ot_id)
        if (n.plan_ot_id) mainOt = n.plan_ot_id  // la correctiva manda para + Ítem / emitir
        else if (!mainOt && n.ot_id) mainOt = n.ot_id
      }
      if (otIds.length === 0 || !mainOt) continue
      otIds.forEach((o) => vistos.add(o))
      out.push({
        key: g.activoId, patente: g.patente, nombre: g.nombre, otIds,
        nc: fakeNc(g.activoId, mainOt),
        nListos: listos.filter((l) => otIds.includes(l.otId)).reduce((s, l) => s + l.items.length, 0),
      })
    }
    // Equipos con insumos listos que no están en la bandeja
    for (const l of listos) {
      if (vistos.has(l.otId)) continue
      out.push({
        key: l.otId, patente: l.patente, nombre: l.nombre, otIds: [l.otId],
        nListos: l.items.length, nc: fakeNc(l.otId, l.otId),
      })
    }
    return out.sort((a, b) => b.nListos - a.nListos || a.patente.localeCompare(b.patente))
  }, [grupos, listos])

  const [sel, setSel] = useState<Opcion | null>(opciones.length === 1 ? opciones[0] : null)

  return (
    <Modal open onClose={onClose} title="Vale para bodega">
      <div className="space-y-3">
        {opciones.length === 0 ? (
          <p className="py-4 text-center text-sm text-gray-500">
            No hay equipos con OT de taller para emitir vale. Los insumos nacen de los hallazgos
            de la OT o se agregan con «+ Ítem» una vez que el equipo tiene OT.
          </p>
        ) : (
          <>
            <div>
              <label className="text-xs font-medium">1. Elige la patente / equipo</label>
              <div className="mt-1 grid max-h-52 gap-1.5 overflow-y-auto">
                {opciones.map((o) => (
                  <button key={o.key} type="button" onClick={() => setSel(o)}
                          className={`flex items-center gap-3 rounded-lg border px-3 py-2 text-left ${
                            sel?.key === o.key ? 'border-orange-500 bg-orange-50' : 'border-gray-200 bg-white hover:bg-gray-50'}`}>
                    <span className="text-base font-bold text-gray-800">{o.patente}</span>
                    <span className="flex-1 text-xs text-gray-500">{o.nombre}</span>
                    {o.nListos > 0 ? (
                      <span className="rounded-full bg-green-100 px-2 py-0.5 text-[11px] font-semibold text-green-700">
                        {o.nListos} listo{o.nListos !== 1 ? 's' : ''} para vale
                      </span>
                    ) : (
                      <span className="rounded-full bg-gray-100 px-2 py-0.5 text-[11px] text-gray-500">revisar / agregar</span>
                    )}
                  </button>
                ))}
              </div>
            </div>

            {sel && (
              <>
                <ValesDelEquipo key={`vales-${sel.key}`} otIds={sel.otIds} />
                <div>
                  <label className="text-xs font-medium">2. Revisa, aprueba o agrega ítems — y emite el vale con tu firma</label>
                  <div className="mt-1">
                    <InsumosOperadorNC key={sel.key} nc={sel.nc} todaOT otIds={sel.otIds} />
                  </div>
                  <p className="mt-1 text-[10px] text-gray-500">
                    Cada vale nuevo sale solo con lo que no estaba en un vale anterior. Para re-emitir
                    TODO en un solo vale, anula el vale abierto (arriba) y genera de nuevo.
                  </p>
                </div>
              </>
            )}
          </>
        )}
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
      </ModalFooter>
    </Modal>
  )
}

// Vales ya emitidos del equipo: volver a imprimir en un click, o anular el
// abierto para re-emitir todo junto.
const TICKET_ESTADO_CHIP: Record<string, string> = {
  emitido: 'bg-blue-100 text-blue-800',
  parcial: 'bg-amber-100 text-amber-800',
  entregado: 'bg-green-100 text-green-700',
  anulado: 'bg-gray-200 text-gray-500',
}

function ValesDelEquipo({ otIds }: { otIds: string[] }) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: vales = [] } = useQuery({
    queryKey: ['vales-equipo', ...otIds],
    queryFn: () => getTicketsOts(otIds),
    staleTime: 10_000,
  })
  const [busy, setBusy] = useState<string | null>(null)

  const anular = async (id: string, folio: string) => {
    if (!window.confirm(`¿Anular el vale ${folio}? Sus insumos vuelven a "aprobado" para re-emitirlos junto a lo nuevo.`)) return
    setBusy(id)
    try {
      await anularTicket(id, 'Re-emisión desde bandeja NC')
      toast.success(`Vale ${folio} anulado — genera el vale de nuevo con todo incluido`)
      qc.invalidateQueries({ queryKey: ['vales-equipo'] })
      qc.invalidateQueries({ queryKey: ['nc-insumos-operador'] })
      qc.invalidateQueries({ queryKey: ['vale-equipos-listos'] })
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(null) }
  }

  if (vales.length === 0) return null
  return (
    <div>
      <label className="text-xs font-medium">Vales ya emitidos de este equipo</label>
      <div className="mt-1 space-y-1">
        {vales.map((t) => (
          <div key={t.id} className="flex items-center gap-2 rounded-lg border border-gray-200 bg-white px-2.5 py-1.5 text-xs">
            <span className="font-mono font-bold">{t.folio}</span>
            <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-medium ${TICKET_ESTADO_CHIP[t.estado] ?? 'bg-gray-100'}`}>{t.estado}</span>
            <span className="flex-1 text-gray-500">
              {t.n_items} ítem{t.n_items !== 1 ? 's' : ''} · {new Date(t.created_at).toLocaleDateString('es-CL')}
            </span>
            <button type="button" onClick={() => window.open(`/vale/${t.id}`, '_blank')}
                    className="inline-flex items-center gap-1 rounded border border-gray-300 px-2 py-1 font-semibold text-gray-700 hover:bg-gray-50">
              <Printer className="h-3 w-3" /> Imprimir
            </button>
            {(t.estado === 'emitido' || t.estado === 'parcial') && (
              <button type="button" disabled={busy === t.id} onClick={() => anular(t.id, t.folio)}
                      title="Anular para re-emitir TODO junto (los insumos vuelven a aprobado)"
                      className="rounded border border-red-200 px-2 py-1 text-red-600 hover:bg-red-50 disabled:opacity-50">
                {busy === t.id ? <Loader2 className="h-3 w-3 animate-spin" /> : 'Anular'}
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}

// Gestión COMPLETA de los insumos del taller desde la NC (MIG204): aprobar /
// rechazar / ajustar cantidad / agregar ítems y emitir el vale de bodega, sin
// tener que ir al Plan Taller. En el modal por equipo se muestra TODO lo de la
// OT de una vez (todaOT).
type ProductoLiteNC = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }

function InsumosOperadorNC({ nc, todaOT, otIds }: { nc: NcRecepcion; todaOT?: boolean; otIds?: string[] }) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: recursos = [] } = useQuery({
    queryKey: ['nc-insumos-operador', nc.id, ...(otIds ?? [])],
    // Con otIds (modo equipo): insumos de TODAS las OT del equipo. Con OT: los
    // de esa OT. Sin OT: los del hallazgo.
    queryFn: () => (otIds && otIds.length > 0)
      ? getRecursosOTs(otIds)
      : nc.ot_id ? getRecursosOT(nc.ot_id) : getRecursosPorHallazgo(nc.checklist_item_ref!),
    enabled: (otIds?.length ?? 0) > 0 || !!nc.ot_id || !!nc.checklist_item_ref,
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
      qc.invalidateQueries({ queryKey: ['vales-equipo'] })
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  if (!nc.ot_id && !nc.checklist_item_ref && (otIds?.length ?? 0) === 0) return null

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
                  {r.estado === 'en_vale' && r.ticket_id ? (
                    <a href={`/vale/${r.ticket_id}`} target="_blank" rel="noreferrer"
                       title="Ver / volver a imprimir el vale"
                       className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium underline decoration-dotted hover:opacity-75 ${chip.cls}`}>
                      <Printer className="h-3 w-3" />
                      {chip.label}{r.ticket_folio ? ` · ${r.ticket_folio}` : ''}
                    </a>
                  ) : (
                    <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${chip.cls}`}>
                      {chip.label}
                    </span>
                  )}
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
        (solicitud de OC) y vuelve como «Recibido» para el vale. Los vales emitidos quedan con el
        folio clickeable (🖨) para volver a imprimir; bodega los recibe por campanita y los despacha
        en Bodega → Tickets.
      </p>

      {valeOpen && (
        <Modal open onClose={() => setValeOpen(false)} title="Vale de bodega — firma del jefe">
          <div className="space-y-3">
            <p className="text-sm text-gray-600">
              Se emite un ticket QR con los {valeables} insumos aprobados/recibidos del equipo (más los
              materiales de NC pendientes que no estén en otro vale). Bodega lo despacha escaneándolo.
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
    (equipo.grupos ?? '').split(',').map((s) => s.trim()).filter(Boolean))

  // Mismos técnicos que en Planificación (catálogo taller_tecnicos, MIG195);
  // MECANICOS queda solo de respaldo si el catálogo está vacío.
  const { data: tecnicosCat = [] } = useQuery({
    queryKey: ['taller-tecnicos-activos'], queryFn: () => getTallerTecnicos(), staleTime: 300_000,
  })
  const opcionesTecnicos = useMemo(() => {
    const base = tecnicosCat.length > 0
      ? tecnicosCat.map((t) => ({ nombre: t.nombre, especialidad: t.especialidad }))
      : (MECANICOS as readonly string[]).map((m) => ({ nombre: m, especialidad: '' }))
    // Nombres ya guardados que no están en el catálogo siguen visibles para poder quitarlos
    const extra = mecanicos.filter((m) => !base.some((b) => b.nombre === m))
      .map((m) => ({ nombre: m, especialidad: '' }))
    return [...base, ...extra]
  }, [tecnicosCat, mecanicos])
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
            {opcionesTecnicos.map((t) => {
              const on = mecanicos.includes(t.nombre)
              return (
                <button key={t.nombre} type="button" onClick={() => toggleMec(t.nombre)} title={t.especialidad || undefined}
                  className={`rounded border px-2 py-1 text-[11px] ${on ? 'border-blue-500 bg-blue-500 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>
                  {t.nombre}
                  {t.especialidad && <span className={`ml-1 text-[9px] ${on ? 'text-blue-100' : 'text-gray-400'}`}>{t.especialidad}</span>}
                </button>
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
              <div key={i} className="flex min-w-0 gap-1 items-center">
                {m.solicitar ? (
                  <div className="flex-1 min-w-0 flex items-center gap-1">
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
                    className="flex-1 min-w-0 rounded border px-2 py-1 text-sm">
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
