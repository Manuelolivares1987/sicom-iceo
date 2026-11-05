'use client'

// ============================================================================
// Gantt del taller (MIG668)
// ----------------------------------------------------------------------------
// El planificador pone aquí lo que le toca a cada camión (lavado, RT y otros
// papeles) y lo mismo aparece en el televisor y en el teléfono del responsable.
// Las barras de OT salen del Plan semanal: acá se ven, pero se mueven allá.
// ============================================================================

import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, CalendarRange, Check, ChevronLeft, ChevronRight, Copy, ExternalLink, FileText, Monitor, Plus, X,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Spinner } from '@/components/ui/spinner'
import { usePermissions } from '@/hooks/use-permissions'
import { useToast } from '@/contexts/toast-context'
import { isoToday } from '@/lib/semana'
import { errorMessage } from '@/lib/utils'
import { getTecnicosTaller } from '@/lib/services/certificados-activo'
import {
  aprobarActividad, cancelarActividad, crearActividad, crearPantallaTaller, getCamionesPlanificables, getGanttTaller,
  getPantallasTaller, getTiposActividad, rechazarActividad, reprogramarActividad, revocarPantallaTaller,
  type BarraGantt, type CamionGantt,
} from '@/lib/services/taller-actividades'
import {
  carrilesDe, colocarBarras, diasEntre, diasVisibles, etiquetaEstadoBarra, lunesDe, papelCorto, sumarDias, textoPapel,
  type VistaBarra,
} from '@/lib/taller-gantt'

const COLOR_BARRA: Record<VistaBarra, string> = {
  ok: 'bg-green-700 text-white',
  hoy: 'bg-blue-700 text-white',
  atraso: 'bg-red-700 text-white',
  falta: 'bg-amber-300 text-gray-900 border border-amber-500',
  por_aprobar: 'bg-amber-400 text-gray-900',
  plan: 'bg-white text-gray-900 border-2 border-gray-500',
}
const LEYENDA: { v: VistaBarra; t: string }[] = [
  { v: 'ok', t: 'Cerrada con evidencia' }, { v: 'hoy', t: 'En curso' }, { v: 'falta', t: 'Falta evidencia' },
  { v: 'por_aprobar', t: 'Por aprobar' }, { v: 'atraso', t: 'Atrasada' }, { v: 'plan', t: 'Programada' },
]
const DIAS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']
const etiquetaDia = (iso: string) => {
  const d = new Date(`${iso}T12:00:00`)
  return `${DIAS[d.getDay()]} ${d.getDate()}`
}
const fechaCorta = (iso?: string | null) => (iso ? iso.slice(0, 10).split('-').reverse().join('-') : '—')
const ROLES_PLANIFICA = ['jefe_mantenimiento', 'administrador', 'subgerente_operaciones', 'jefe_operaciones', 'planificador', 'supervisor']
const ROLES_APRUEBA = ['jefe_mantenimiento', 'jefe_operaciones', 'administrador', 'subgerente_operaciones']

type Prefijo = { activoId?: string; tipo?: string; inicio?: string }
type Mover = { barra: BarraGantt; patente: string; inicio: string; fin: string }

function NuevaActividad({ operacion, prefijo, onClose, onDone }: {
  operacion: string; prefijo: Prefijo; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const hoy = isoToday()
  const [activoId, setActivoId] = useState(prefijo.activoId ?? '')
  const [tipo, setTipo] = useState(prefijo.tipo ?? '')
  const [inicio, setInicio] = useState(prefijo.inicio ?? hoy)
  const [fin, setFin] = useState(prefijo.inicio ?? hoy)
  const [tecnicoId, setTecnicoId] = useState('')
  const [notas, setNotas] = useState('')
  const [motivo, setMotivo] = useState('')
  const camiones = useQuery({ queryKey: ['gantt-camiones', operacion], queryFn: () => getCamionesPlanificables(operacion), staleTime: 300_000 })
  const tipos = useQuery({ queryKey: ['gantt-tipos'], queryFn: getTiposActividad, staleTime: 300_000 })
  const tecnicos = useQuery({ queryKey: ['gantt-tecnicos'], queryFn: getTecnicosTaller, staleTime: 300_000 })
  const crear = useMutation({
    mutationFn: () => crearActividad({ activoId, tipo, inicio, fin, tecnicoId, notas: notas || null, motivo: motivo || null }),
    onSuccess: () => { toast.success('Actividad planificada'); onDone() },
    onError: (e) => toast.error(errorMessage(e)),
  })
  const pasada = inicio < hoy
  const campo = 'mt-1 h-10 w-full rounded-md border border-gray-300 bg-white px-2 text-sm'
  return (
    <Modal open onClose={onClose} title="Planificar actividad" description="Aparece en el televisor y en el teléfono del responsable.">
      <div className="space-y-3">
        <label className="block text-sm font-medium text-gray-700">Camión
          <select value={activoId} onChange={(e) => setActivoId(e.target.value)} className={campo}>
            <option value="">Elegir…</option>
            {(camiones.data ?? []).map((c) => <option key={c.id} value={c.id}>{c.patente}</option>)}
          </select>
        </label>
        <label className="block text-sm font-medium text-gray-700">Actividad
          <select value={tipo} onChange={(e) => setTipo(e.target.value)} className={campo}>
            <option value="">Elegir…</option>
            {(tipos.data ?? []).map((t) => (
              <option key={t.codigo} value={t.codigo}>
                {t.nombre} · {t.evidencia === 'foto' ? 'se cierra con foto' : 'se cierra con certificado, aprueba el jefe'}
              </option>
            ))}
          </select>
        </label>
        <div className="grid grid-cols-2 gap-3">
          <label className="block text-sm font-medium text-gray-700">Desde
            <input type="date" value={inicio} className={campo} onChange={(e) => { setInicio(e.target.value); if (fin < e.target.value) setFin(e.target.value) }} />
          </label>
          <label className="block text-sm font-medium text-gray-700">Hasta
            <input type="date" value={fin} min={inicio} className={campo} onChange={(e) => setFin(e.target.value)} />
          </label>
        </div>
        <label className="block text-sm font-medium text-gray-700">Responsable
          <select value={tecnicoId} onChange={(e) => setTecnicoId(e.target.value)} className={campo}>
            <option value="">Elegir…</option>
            {(tecnicos.data ?? []).map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}
          </select>
        </label>
        <label className="block text-sm font-medium text-gray-700">Notas (opcional)
          <input value={notas} onChange={(e) => setNotas(e.target.value)} className={campo} />
        </label>
        {pasada && (
          <label className="block text-sm font-medium text-red-700">¿Por qué se planifica en una fecha pasada?
            <input value={motivo} onChange={(e) => setMotivo(e.target.value)} className={campo} />
          </label>
        )}
      </div>
      <ModalFooter>
        <Button variant="secondary" onClick={onClose}>Cancelar</Button>
        <Button onClick={() => crear.mutate()} disabled={crear.isPending || !activoId || !tipo || !tecnicoId || (pasada && motivo.trim().length < 5)}>
          {crear.isPending ? 'Guardando…' : 'Planificar'}
        </Button>
      </ModalFooter>
    </Modal>
  )
}

function DetalleBarra({ barra, patente, puedePlanificar, puedeAprobar, onClose, onDone, onMover }: {
  barra: BarraGantt; patente: string; puedePlanificar: boolean; puedeAprobar: boolean
  onClose: () => void; onDone: () => void; onMover: () => void
}) {
  const toast = useToast()
  const [motivo, setMotivo] = useState('')
  const ok = (m: string) => () => { toast.success(m); onDone() }
  const err = (e: unknown) => toast.error(errorMessage(e))
  const aprobar = useMutation({ mutationFn: () => aprobarActividad(barra.id), onSuccess: ok('Aprobada: el papel quedó renovado'), onError: err })
  const rechazar = useMutation({ mutationFn: () => rechazarActividad(barra.id, motivo), onSuccess: ok('Rechazada: vuelve al responsable'), onError: err })
  const cancelar = useMutation({ mutationFn: () => cancelarActividad(barra.id, motivo), onSuccess: ok('Actividad cancelada'), onError: err })
  const esActividad = barra.origen === 'actividad'
  const abierta = ['programada', 'hecha', 'por_aprobar'].includes(barra.estado)
  const motivoOk = motivo.trim().length >= 5
  return (
    <Modal open onClose={onClose} title={`${patente} · ${barra.titulo}`} description={`${fechaCorta(barra.inicio)}${barra.fin !== barra.inicio ? ` al ${fechaCorta(barra.fin)}` : ''} · ${barra.responsable ?? 'Sin responsable'}`}>
      <div className="space-y-3 text-sm">
        <p className="font-medium text-gray-900">{LEYENDA.find((l) => l.v === barra.vista)?.t}</p>
        {barra.folio && <p className="text-gray-600">{barra.folio}. Esta barra viene del Plan semanal y se mueve allá.</p>}
        {barra.notas && <p className="text-gray-600">{barra.notas}</p>}
        {barra.rechazo_motivo && <p className="rounded bg-red-50 p-2 text-red-800">Rechazada: {barra.rechazo_motivo}</p>}
        {(barra.fotos?.length ?? 0) > 0 && (
          <div className="grid grid-cols-3 gap-2">
            {barra.fotos!.map((f) => (
              <a key={f.url} href={f.url} target="_blank" rel="noreferrer">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={f.url} alt={`Evidencia de ${barra.titulo}`} className="h-24 w-full rounded object-cover" />
              </a>
            ))}
          </div>
        )}
        {barra.cert_archivo_url && (
          <a href={barra.cert_archivo_url} target="_blank" rel="noreferrer" className="flex items-center gap-2 rounded border border-gray-200 p-2 text-blue-700 hover:bg-gray-50">
            <FileText className="h-4 w-4" />
            Ver certificado · emisión {fechaCorta(barra.cert_emision)} · vence {fechaCorta(barra.cert_vencimiento)}
            {barra.cert_numero ? ` · N° ${barra.cert_numero}` : ''}
            <ExternalLink className="ml-auto h-3.5 w-3.5" />
          </a>
        )}
        {esActividad && abierta && (puedePlanificar || (puedeAprobar && barra.estado === 'por_aprobar')) && (
          <label className="block font-medium text-gray-700">Motivo (para rechazar o cancelar)
            <input value={motivo} onChange={(e) => setMotivo(e.target.value)} className="mt-1 h-10 w-full rounded-md border border-gray-300 px-2" />
          </label>
        )}
      </div>
      <ModalFooter>
        {esActividad && abierta && puedePlanificar && (
          <Button variant="secondary" disabled={!motivoOk || cancelar.isPending} onClick={() => cancelar.mutate()}>Cancelar actividad</Button>
        )}
        {esActividad && barra.estado === 'programada' && puedePlanificar && (
          <Button variant="secondary" onClick={onMover}>Reprogramar</Button>
        )}
        {barra.estado === 'por_aprobar' && puedeAprobar && (
          <>
            <Button variant="secondary" disabled={!motivoOk || rechazar.isPending} onClick={() => rechazar.mutate()}>Rechazar</Button>
            <Button disabled={aprobar.isPending} onClick={() => aprobar.mutate()}>Aprobar</Button>
          </>
        )}
        <Button variant="secondary" onClick={onClose}>Cerrar</Button>
      </ModalFooter>
    </Modal>
  )
}

function ReprogramarModal({ mover, onClose, onDone }: { mover: Mover; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const hoy = isoToday()
  const [inicio, setInicio] = useState(mover.inicio)
  const [fin, setFin] = useState(mover.fin)
  const [motivo, setMotivo] = useState('')
  const exigeMotivo = mover.barra.inicio.slice(0, 10) <= hoy
  const guardar = useMutation({
    mutationFn: () => reprogramarActividad({ id: mover.barra.id, inicio, fin, motivo: motivo || null }),
    onSuccess: () => { toast.success('Reprogramada'); onDone() },
    onError: (e) => toast.error(errorMessage(e)),
  })
  const campo = 'mt-1 h-10 w-full rounded-md border border-gray-300 px-2 text-sm'
  return (
    <Modal open onClose={onClose} title={`Reprogramar ${mover.barra.titulo}`} description={mover.patente}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <label className="block text-sm font-medium text-gray-700">Desde
            <input type="date" value={inicio} className={campo} onChange={(e) => { setInicio(e.target.value); if (fin < e.target.value) setFin(e.target.value) }} />
          </label>
          <label className="block text-sm font-medium text-gray-700">Hasta
            <input type="date" value={fin} min={inicio} className={campo} onChange={(e) => setFin(e.target.value)} />
          </label>
        </div>
        {exigeMotivo && (
          <label className="block text-sm font-medium text-gray-700">Motivo: ya partió o está atrasada
            <input value={motivo} onChange={(e) => setMotivo(e.target.value)} className={campo} />
          </label>
        )}
      </div>
      <ModalFooter>
        <Button variant="secondary" onClick={onClose}>Cancelar</Button>
        <Button disabled={guardar.isPending || (exigeMotivo && motivo.trim().length < 5)} onClick={() => guardar.mutate()}>Guardar</Button>
      </ModalFooter>
    </Modal>
  )
}

function Pantallas({ operacion }: { operacion: string }) {
  const toast = useToast()
  const qc = useQueryClient()
  const lista = useQuery({ queryKey: ['pantallas-taller'], queryFn: getPantallasTaller })
  const refrescar = () => qc.invalidateQueries({ queryKey: ['pantallas-taller'] })
  const crear = useMutation({ mutationFn: () => crearPantallaTaller(`Taller ${operacion}`, operacion), onSuccess: refrescar, onError: (e) => toast.error(errorMessage(e)) })
  const revocar = useMutation({ mutationFn: revocarPantallaTaller, onSuccess: refrescar, onError: (e) => toast.error(errorMessage(e)) })
  const url = (token: string) => `${window.location.origin}/pantalla-taller/${token}`
  return (
    <section className="rounded-lg border border-gray-200 bg-white p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-gray-900"><Monitor className="h-4 w-4" />Televisores</h2>
        <Button size="sm" variant="secondary" disabled={crear.isPending} onClick={() => crear.mutate()}>Crear enlace para {operacion}</Button>
      </div>
      <p className="mt-1 text-xs text-gray-500">El enlace abre la pantalla sin usuario ni contraseña. Revócalo si se filtra o el PC cambia de lugar.</p>
      <ul className="mt-2 space-y-1">
        {(lista.data ?? []).map((p) => (
          <li key={p.id} className="flex flex-wrap items-center gap-2 text-sm">
            <span className="font-medium">{p.nombre}</span>
            <a href={url(p.token)} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-blue-700 hover:underline">Abrir <ExternalLink className="h-3.5 w-3.5" /></a>
            <button type="button" className="inline-flex items-center gap-1 text-gray-700 hover:underline" onClick={async () => { await navigator.clipboard.writeText(url(p.token)); toast.success('Enlace copiado') }}>Copiar <Copy className="h-3.5 w-3.5" /></button>
            <button type="button" className="inline-flex items-center gap-1 text-red-700 hover:underline" onClick={() => revocar.mutate(p.id)}>Revocar <X className="h-3.5 w-3.5" /></button>
          </li>
        ))}
      </ul>
    </section>
  )
}

function FilaCamion({ c, dias, hoy, puedePlanificar, onBarra, onCelda, onSoltar }: {
  c: CamionGantt; dias: string[]; hoy: string; puedePlanificar: boolean
  onBarra: (b: BarraGantt, patente: string) => void
  onCelda: (activoId: string, dia: string) => void
  onSoltar: (b: BarraGantt, patente: string, dia: string) => void
}) {
  const colocadas = useMemo(() => colocarBarras(c.barras, dias), [c.barras, dias])
  const carriles = carrilesDe(colocadas)
  const [encima, setEncima] = useState<string | null>(null)
  const detenido = c.estado_codigo === 'F'
  return (
    <div className="flex border-t border-gray-200" style={{ minWidth: 1040 }}>
      <div className="sticky left-0 z-10 w-52 shrink-0 border-r border-gray-200 bg-white p-2">
        <p className="text-base font-bold text-gray-900">{c.patente}</p>
        <p className="text-xs text-gray-500">{c.en_taller ? `En taller · ${c.dias ?? 0} días` : `Estado ${c.estado_codigo ?? '—'}`}</p>
        <div className="mt-1 flex flex-col gap-0.5">
          {c.papeles.map((p) => (
            <span key={p.tipo} className={`rounded px-1.5 py-0.5 text-xs font-semibold ${detenido && c.barras.length === 0 ? 'bg-gray-200 text-gray-700' : p.estado === 'vencido' ? 'bg-red-700 text-white' : 'bg-amber-300 text-gray-900'}`}>
              {textoPapel(papelCorto(p.tipo, p.etiqueta), p.estado, p.dias)}
            </span>
          ))}
        </div>
      </div>
      <div className="relative flex-1" style={{ minHeight: Math.max(76, carriles * 52 + 8) }}>
        <div className="absolute inset-0 grid" style={{ gridTemplateColumns: `repeat(${dias.length},minmax(0,1fr))` }}>
          {dias.map((d) => (
            <button
              type="button" key={d} disabled={!puedePlanificar}
              aria-label={`Planificar en ${c.patente}, ${etiquetaDia(d)}`}
              onClick={() => onCelda(c.activo_id, d)}
              onDragOver={(e) => { e.preventDefault(); setEncima(d) }}
              onDragLeave={() => setEncima(null)}
              onDrop={(e) => {
                e.preventDefault(); setEncima(null)
                const b = c.barras.find((x) => x.id === e.dataTransfer.getData('text/plain'))
                if (b) onSoltar(b, c.patente, d)
              }}
              className={`border-l border-gray-100 ${d === hoy ? 'bg-orange-50' : ''} ${encima === d ? 'bg-blue-100' : ''} ${puedePlanificar ? 'hover:bg-gray-50' : ''}`}
            />
          ))}
        </div>
        <div className="pointer-events-none absolute inset-0 grid gap-1 p-1" style={{ gridTemplateColumns: `repeat(${dias.length},minmax(0,1fr))`, gridTemplateRows: `repeat(${carriles},minmax(0,1fr))` }}>
          {colocadas.map(({ barra, col, largo, carril, cortadaInicio }) => {
            const movible = puedePlanificar && barra.origen === 'actividad' && barra.estado === 'programada'
            const txt = etiquetaEstadoBarra(barra.vista, barra.evidencia, barra.origen)
            return (
              <button
                type="button" key={`${barra.origen}-${barra.id}`} draggable={movible}
                onDragStart={(e) => e.dataTransfer.setData('text/plain', barra.id)}
                onClick={() => onBarra(barra, c.patente)}
                className={`pointer-events-auto min-w-0 overflow-hidden rounded px-1 text-center text-xs leading-tight ${COLOR_BARRA[barra.vista]} ${movible ? 'cursor-grab' : ''}`}
                style={{ gridColumn: `${col + 1} / span ${largo}`, gridRow: carril + 1 }}
                title={`${barra.titulo} · ${barra.responsable ?? 'Sin responsable'}`}
              >
                <span className="block truncate font-bold">{cortadaInicio ? '◄ ' : ''}{largo > 1 ? barra.titulo : barra.corto}</span>
                {txt && <span className="block truncate">{txt}</span>}
              </button>
            )
          })}
        </div>
      </div>
    </div>
  )
}

export default function GanttTallerPage() {
  const qc = useQueryClient()
  const { rol } = usePermissions()
  const hoy = isoToday()
  const [operacion, setOperacion] = useState('Coquimbo')
  const [semanas, setSemanas] = useState(0)
  const [nueva, setNueva] = useState<Prefijo | null>(null)
  const [detalle, setDetalle] = useState<{ barra: BarraGantt; patente: string } | null>(null)
  const [mover, setMover] = useState<Mover | null>(null)
  const puedePlanificar = ROLES_PLANIFICA.includes(rol ?? '')
  const puedeAprobar = ROLES_APRUEBA.includes(rol ?? '')
  const desde = lunesDe(hoy, semanas)
  const hasta = sumarDias(desde, 12)
  const dias = useMemo(() => diasVisibles(desde, hasta), [desde, hasta])
  const { data, isLoading, error } = useQuery({
    queryKey: ['gantt-taller', desde, hasta, operacion],
    queryFn: () => getGanttTaller(desde, hasta, operacion),
    refetchInterval: 120_000,
  })
  const refrescar = () => {
    qc.invalidateQueries({ queryKey: ['gantt-taller'] })
    setNueva(null); setDetalle(null); setMover(null)
  }
  const soltar = (barra: BarraGantt, patente: string, dia: string) => {
    if (barra.origen !== 'actividad' || barra.estado !== 'programada') return
    const largo = diasEntre(barra.inicio, barra.fin)
    setMover({ barra, patente, inicio: dia, fin: sumarDias(dia, largo) })
  }
  const porAprobar = (data?.camiones ?? []).flatMap((c) => c.barras).filter((b) => b.estado === 'por_aprobar').length

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-xl font-bold text-gray-900"><CalendarRange className="h-5 w-5 text-orange-600" />Gantt del taller</h1>
          <p className="text-sm text-gray-500">Lo que le toca a cada camión. Toca un día para planificar; arrastra una barra para moverla.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label="Operación" value={operacion} onChange={(e) => setOperacion(e.target.value)} className="h-10 rounded-md border border-gray-300 bg-white px-2 text-sm">
            <option>Coquimbo</option><option>Calama</option>
          </select>
          <Button variant="secondary" size="sm" aria-label="Semana anterior" onClick={() => setSemanas(semanas - 1)}><ChevronLeft className="h-4 w-4" /></Button>
          <Button variant="secondary" size="sm" onClick={() => setSemanas(0)}>Hoy</Button>
          <Button variant="secondary" size="sm" aria-label="Semana siguiente" onClick={() => setSemanas(semanas + 1)}><ChevronRight className="h-4 w-4" /></Button>
          {puedePlanificar && <Button onClick={() => setNueva({})}><Plus className="mr-1 h-4 w-4" />Actividad</Button>}
        </div>
      </div>

      {puedeAprobar && porAprobar > 0 && (
        <p className="flex items-center gap-2 rounded-lg bg-amber-50 p-3 text-sm font-medium text-amber-900">
          <Check className="h-4 w-4" />{porAprobar === 1 ? 'Hay 1 evidencia' : `Hay ${porAprobar} evidencias`} por aprobar: abre la barra amarilla.
        </p>
      )}

      {(data?.sin_agendar?.length ?? 0) > 0 && (
        <section className="rounded-lg border border-red-200 bg-red-50 p-3">
          <h2 className="flex items-center gap-2 text-sm font-semibold text-red-900"><AlertTriangle className="h-4 w-4" />Revisión técnica sin agendar</h2>
          <div className="mt-2 flex flex-wrap gap-2">
            {data!.sin_agendar.map((s) => (
              <button type="button" key={s.activo_id} disabled={!puedePlanificar} onClick={() => setNueva({ activoId: s.activo_id, tipo: 'revision_tecnica' })} className="min-h-9 rounded-md border border-red-300 bg-white px-2 text-sm text-red-900 hover:bg-red-100 disabled:cursor-default">
                <b>{s.patente}</b> · {s.dias < 0 ? `vencida hace ${-s.dias} d` : s.dias === 0 ? 'vence hoy' : `vence en ${s.dias} d`}
              </button>
            ))}
          </div>
        </section>
      )}

      {isLoading && <div className="flex justify-center p-8"><Spinner /></div>}
      {error && <p className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{errorMessage(error)}</p>}
      {data && (
        <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
          <div className="flex" style={{ minWidth: 1040 }}>
            <div className="sticky left-0 z-10 w-52 shrink-0 border-r border-gray-200 bg-white p-2 text-xs font-semibold text-gray-500">Camión y papeles</div>
            <div className="grid flex-1" style={{ gridTemplateColumns: `repeat(${dias.length},minmax(0,1fr))` }}>
              {dias.map((d) => (
                <div key={d} className={`p-2 text-center text-xs font-semibold ${d === data.hoy ? 'bg-orange-600 text-white' : 'text-gray-600'}`}>{etiquetaDia(d)}</div>
              ))}
            </div>
          </div>
          {data.camiones.map((c) => (
            <FilaCamion
              key={c.activo_id} c={c} dias={dias} hoy={data.hoy} puedePlanificar={puedePlanificar}
              onBarra={(barra, patente) => setDetalle({ barra, patente })}
              onCelda={(activoId, dia) => setNueva({ activoId, inicio: dia })}
              onSoltar={soltar}
            />
          ))}
          {data.camiones.length === 0 && <p className="p-6 text-center text-sm text-gray-500">No hay camiones en taller ni actividades en estas semanas.</p>}
        </div>
      )}

      <div className="flex flex-wrap gap-3 text-xs text-gray-600">
        {LEYENDA.map((l) => <span key={l.v} className="flex items-center gap-1"><i className={`block h-3 w-5 rounded ${COLOR_BARRA[l.v]}`} />{l.t}</span>)}
      </div>

      {puedeAprobar && <Pantallas operacion={operacion} />}

      {nueva && <NuevaActividad operacion={operacion} prefijo={nueva} onClose={() => setNueva(null)} onDone={refrescar} />}
      {detalle && (
        <DetalleBarra
          barra={detalle.barra} patente={detalle.patente} puedePlanificar={puedePlanificar} puedeAprobar={puedeAprobar}
          onClose={() => setDetalle(null)} onDone={refrescar}
          onMover={() => { setMover({ barra: detalle.barra, patente: detalle.patente, inicio: detalle.barra.inicio.slice(0, 10), fin: detalle.barra.fin.slice(0, 10) }); setDetalle(null) }}
        />
      )}
      {mover && <ReprogramarModal mover={mover} onClose={() => setMover(null)} onDone={refrescar} />}
    </div>
  )
}
