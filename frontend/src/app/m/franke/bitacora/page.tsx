'use client'

// ============================================================================
// Bitácora del turno — Franke (MIG696), funciona sin señal
// ----------------------------------------------------------------------------
// El canal DIARIO entre supervisores que faltaba. La entrega de turno (MIG362)
// es una vez por rotación y se usó una sola vez; acá escribir una novedad toma
// diez segundos y no necesita señal.
//
//   Para leer   → lo importante/crítico que YO no he leído. «Leído y entendido»
//                 deja nombre y hora: el otro supervisor sabe que llegó.
//   Novedades   → qué pasó en el turno, con severidad, equipo y foto.
//   Pendientes  → con dueño (turno A/B), vencimiento y «si pasa X, hacer Y».
//                 Se arrastran hasta que alguien los cierra diciendo cómo.
//   Resumen 7 d → el «archivo de lectura» para el que vuelve del descanso.
// Investigación: reports/Cambio de turno faena Franke.md
// ============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import {
  AlertOctagon, AlertTriangle, Camera, Check, CheckCheck, ChevronLeft, CloudOff, Download, ListTodo, MessageSquarePlus, Plus, XCircle,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import { getFaenaId } from '@/lib/services/faena-pauta'
import {
  colaBitacora, conCola, descartar, getBitacora, guardarFotoLocal, registrar,
  type Bitacora, type Categoria, type Novedad, type OpBitacora, type Pendiente, type Severidad,
} from '@/lib/offline/faena-bitacora-offline'

type Pestana = 'leer' | 'novedades' | 'pendientes' | 'resumen'
const CATEGORIAS: { id: Categoria; texto: string }[] = [
  { id: 'seguridad', texto: 'Seguridad' }, { id: 'equipo', texto: 'Equipo' }, { id: 'operacion', texto: 'Operación' },
  { id: 'combustible', texto: 'Combustible' }, { id: 'bodega', texto: 'Bodega' }, { id: 'personal', texto: 'Personal' },
  { id: 'mandante', texto: 'Mandante' }, { id: 'otro', texto: 'Otro' },
]
const SEV: Record<Severidad, { texto: string; cls: string; activo: string }> = {
  normal: { texto: 'Normal', cls: 'border-gray-200 text-gray-700', activo: 'bg-gray-800 text-white border-gray-800' },
  importante: { texto: 'Importante', cls: 'border-amber-300 text-amber-800', activo: 'bg-amber-500 text-white border-amber-500' },
  critica: { texto: 'Crítica', cls: 'border-red-300 text-red-700', activo: 'bg-red-700 text-white border-red-700' },
}
const fh = (s: string) => new Date(s).toLocaleString('es-CL', { weekday: 'short', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
const hace = (iso: string | null) => {
  if (!iso) return 'nunca'
  const m = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
  return m < 1 ? 'recién' : m < 60 ? `hace ${m} min` : m < 1440 ? `hace ${Math.round(m / 60)} h` : `hace ${Math.round(m / 1440)} d`
}

export default function BitacoraFrankePage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const online = useNetworkStatus()
  const toast = useToast()
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [base, setBase] = useState<Bitacora | null>(null)
  const [guardada, setGuardada] = useState<string | null>(null)
  const [cola, setCola] = useState<OpBitacora[]>([])
  const [cargando, setCargando] = useState(true)
  const [pestana, setPestana] = useState<Pestana | null>(null)

  const cargar = useCallback(async (forzar = false) => {
    try {
      let f = faenaId
      if (!f) {
        try { f = await getFaenaId(); if (f) localStorage.setItem('sicom-franke-faena-id', f) }
        catch { f = localStorage.getItem('sicom-franke-faena-id') }
        setFaenaId(f)
      }
      if (!f) return
      const r = await getBitacora(f, forzar)
      setBase(r.data); setGuardada(r.guardada_at)
    } catch (e) { toast.error(errorMessage(e)) } finally { setCargando(false) }
  }, [faenaId, toast])
  const refrescarCola = useCallback(async () => { try { setCola(await colaBitacora()) } catch { /* sin IndexedDB */ } }, [])

  useEffect(() => { void cargar(); void refrescarCola() }, [cargar, refrescarCola])
  useEffect(() => { if (online) void cargar() }, [online, cargar])
  useEffect(() => { const t = setInterval(() => { void refrescarCola() }, 8000); return () => clearInterval(t) }, [refrescarCola])
  // Cuando la cola se vacía (subió), se vuelve a bajar para ver acuses de los demás.
  const enCola = cola.filter((c) => c.sync_status === 'pending').length
  const prevCola = useRef(enCola)
  useEffect(() => { if (prevCola.current > 0 && enCola === 0 && online) void cargar(true); prevCola.current = enCola }, [enCola, online, cargar])

  const b = useMemo(() => (base ? conCola(base, cola) : null), [base, cola])
  const porLeer = useMemo(() => (b ? b.novedades.filter((n) => b.por_leer.includes(n.id)) : []), [b])
  const tab: Pestana = pestana ?? (porLeer.length ? 'leer' : 'novedades')
  const rechazadas = cola.filter((c) => c.sync_status === 'rechazada')

  async function hacer(op: Parameters<typeof registrar>[0], ok: string) {
    try {
      const r = await registrar({ ...op, autor: perfil?.nombre_completo ?? null })
      if (r.rechazo) toast.error(`No se guardó: ${r.rechazo}`)
      else toast.success(r.enviado ? ok : `${ok} (guardado en el teléfono, sube solo con señal)`)
      await refrescarCola()
      if (r.enviado) void cargar(true)
      return !r.rechazo
    } catch (e) { toast.error(errorMessage(e)); return false }
  }

  if (verificando) return <div className="flex min-h-screen items-center justify-center"><Spinner className="h-8 w-8" /></div>
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      <header className="border-b bg-white px-4 pb-3 pt-[max(1rem,env(safe-area-inset-top))]">
        <Link href="/m/franke" className="mb-1 inline-flex items-center gap-1 text-xs text-gray-500"><ChevronLeft className="h-3.5 w-3.5" /> Franke</Link>
        <div className="flex items-start justify-between gap-2">
          <div>
            <p className="text-lg font-bold text-gray-900">Bitácora del turno</p>
            <p className="text-xs text-gray-500">
              {b?.ciclo ? `${b.ciclo.turno} en faena` : 'Novedades y pendientes entre supervisores'}{b?.mi_turno ? ` · usted es turno ${b.mi_turno}` : ''}
            </p>
          </div>
          {!online && <span className="flex items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-xs font-semibold text-amber-900"><CloudOff className="h-3.5 w-3.5" /> Sin señal</span>}
        </div>
        <div className="mt-2 flex items-center justify-between text-[11px] text-gray-500">
          <span>Actualizada {hace(guardada)}{enCola ? ` · ${enCola} por subir` : ''}</span>
          <button onClick={() => void cargar(true)} disabled={!online} className="flex items-center gap-1 font-medium text-gray-700 disabled:opacity-40"><Download className="h-3.5 w-3.5" /> Actualizar</button>
        </div>
      </header>

      {cargando && <div className="flex justify-center py-10"><Spinner className="h-7 w-7" /></div>}
      {!cargando && !b && (
        <p className="m-4 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">Este teléfono todavía no tiene la bitácora. Ábrala una vez con señal para descargarla.</p>
      )}

      {rechazadas.map((r) => (
        <div key={r.local_id} className="mx-4 mt-3 rounded-xl border border-red-300 bg-red-50 p-3 text-sm text-red-900">
          <p className="flex items-center gap-1.5 font-semibold"><XCircle className="h-4 w-4" /> No se pudo subir ({r.tipo})</p>
          <p className="mt-0.5 text-xs">{r.ultimo_error}</p>
          <button onClick={async () => { await descartar(r.local_id); await refrescarCola() }} className="mt-2 rounded-lg border border-red-300 bg-white px-3 py-1 text-xs">Descartar</button>
        </div>
      ))}

      {b && faenaId && (<>
        <nav className="sticky top-0 z-10 mt-3 flex gap-1 overflow-x-auto bg-gray-50 px-4 pb-2">
          {([['leer', `Para leer${porLeer.length ? ` (${porLeer.length})` : ''}`], ['novedades', 'Novedades'],
             ['pendientes', `Pendientes (${b.pendientes.filter((p) => p.estado === 'abierto').length})`], ['resumen', 'Resumen 7 días']] as [Pestana, string][]).map(([id, t]) => (
            <button key={id} onClick={() => setPestana(id)}
                    className={cn('shrink-0 rounded-full border px-3 py-1.5 text-sm font-medium',
                      tab === id ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-200 bg-white text-gray-700',
                      id === 'leer' && porLeer.length > 0 && tab !== id && 'border-red-300 text-red-700')}>
              {t}
            </button>
          ))}
        </nav>

        {tab === 'leer' && (
          <section className="space-y-2 px-4">
            {porLeer.length === 0 ? (
              <p className="rounded-xl border bg-white p-6 text-center text-sm text-gray-600"><CheckCheck className="mx-auto mb-2 h-6 w-6 text-emerald-600" />Está al día: leyó todo lo importante.</p>
            ) : (<>
              <p className="text-xs text-gray-500">Lo importante y crítico que usted no ha leído. Al marcarlo, el autor ve su nombre y la hora.</p>
              {porLeer.map((n) => <TarjetaNovedad key={n.id} n={n} onLeer={() => hacer({ tipo: 'acuse', ids: [n.id], faena_id: faenaId }, 'Leído y entendido')} />)}
              {porLeer.length > 1 && (
                <button onClick={() => hacer({ tipo: 'acuse', ids: porLeer.map((n) => n.id), faena_id: faenaId }, 'Todo marcado como leído')}
                        className="w-full rounded-xl bg-gray-900 py-3 text-sm font-bold text-white">Leí y entendí las {porLeer.length}</button>
              )}
            </>)}
          </section>
        )}

        {tab === 'novedades' && (
          <section className="space-y-2 px-4">
            <NuevaNovedad equipos={b.equipos} onGuardar={(d) => hacer({ tipo: 'novedad', ...d, faena_id: faenaId }, 'Novedad registrada')} />
            {b.novedades.length === 0 && <p className="rounded-xl border border-dashed bg-white p-6 text-center text-sm text-gray-500">Sin novedades en los últimos 7 días.</p>}
            {b.novedades.map((n) => <TarjetaNovedad key={n.id} n={n}
              onLeer={!n.leida_por_mi ? () => hacer({ tipo: 'acuse', ids: [n.id], faena_id: faenaId }, 'Leído y entendido') : undefined} />)}
          </section>
        )}

        {tab === 'pendientes' && (
          <section className="space-y-2 px-4">
            <NuevoPendiente equipos={b.equipos} miTurno={b.mi_turno}
                            onGuardar={(d) => hacer({ tipo: 'pendiente', ...d, faena_id: faenaId }, 'Pendiente creado')} />
            {b.pendientes.length === 0 && <p className="rounded-xl border border-dashed bg-white p-6 text-center text-sm text-gray-500">No hay pendientes.</p>}
            {b.pendientes.map((p) => <TarjetaPendiente key={p.id} p={p}
              onNota={(texto, cerrar) => hacer({ tipo: 'nota', pendiente_id: p.id, texto, cerrar, faena_id: faenaId }, cerrar ? 'Pendiente cerrado' : 'Nota agregada')} />)}
          </section>
        )}

        {tab === 'resumen' && <Resumen b={b} />}
      </>)}
    </div>
  )
}

function TarjetaNovedad({ n, onLeer }: { n: Novedad; onLeer?: () => void }) {
  const I = n.severidad === 'critica' ? AlertOctagon : n.severidad === 'importante' ? AlertTriangle : null
  return (
    <article className={cn('rounded-xl border bg-white p-3', n.severidad === 'critica' && 'border-red-300', n.severidad === 'importante' && 'border-amber-300')}>
      <div className="flex items-center justify-between gap-2 text-xs text-gray-500">
        <span className="flex items-center gap-1">
          {I && <I className={cn('h-3.5 w-3.5', n.severidad === 'critica' ? 'text-red-700' : 'text-amber-600')} />}
          <b className={cn(n.severidad === 'critica' ? 'text-red-700' : n.severidad === 'importante' ? 'text-amber-700' : 'text-gray-700')}>{SEV[n.severidad].texto}</b>
          · {CATEGORIAS.find((c) => c.id === n.categoria)?.texto}{n.equipo ? ` · ${n.equipo}` : ''}
        </span>
        <span>{fh(n.fecha_hora)}</span>
      </div>
      <p className="mt-1.5 whitespace-pre-wrap text-sm text-gray-900">{n.texto}</p>
      {n.foto_url && <a href={n.foto_url} target="_blank" rel="noreferrer"><img src={n.foto_url} alt="Foto de la novedad" className="mt-2 max-h-48 rounded-lg object-cover" /></a>}
      <p className="mt-1.5 text-xs text-gray-500">
        {n.autor ?? '—'}{n.turno ? ` (turno ${n.turno})` : ''}{n.local ? ' · en el teléfono, por subir' : ''}
        {n.acuses.length > 0 && <> · <span className="text-emerald-700">leído por {n.acuses.map((a) => a.nombre.split(' ')[0]).join(', ')}</span></>}
      </p>
      {onLeer && (
        <button onClick={onLeer} className="mt-2 flex w-full items-center justify-center gap-1.5 rounded-lg border-2 border-gray-900 py-2 text-sm font-bold text-gray-900">
          <Check className="h-4 w-4" /> Leído y entendido
        </button>
      )}
    </article>
  )
}

function NuevaNovedad({ equipos, onGuardar }: {
  equipos: { id: string; patente: string }[]
  onGuardar: (d: { categoria: Categoria; severidad: Severidad; texto: string; activo_id: string | null; equipo: string | null; foto_blob: string | null; fecha_hora: string }) => Promise<boolean>
}) {
  const [abierto, setAbierto] = useState(false)
  const [categoria, setCategoria] = useState<Categoria>('operacion')
  const [severidad, setSeveridad] = useState<Severidad>('normal')
  const [texto, setTexto] = useState('')
  const [equipo, setEquipo] = useState('')
  const [foto, setFoto] = useState<string | null>(null)
  const [guardando, setGuardando] = useState(false)
  const toast = useToast()
  if (!abierto) {
    return (
      <button onClick={() => setAbierto(true)} className="flex w-full items-center justify-center gap-2 rounded-xl bg-gray-900 py-3.5 text-sm font-bold text-white">
        <MessageSquarePlus className="h-5 w-5" /> Escribir novedad del turno
      </button>
    )
  }
  return (
    <div className="space-y-2 rounded-xl border-2 border-gray-900 bg-white p-3">
      <div className="flex flex-wrap gap-1.5">
        {CATEGORIAS.map((c) => (
          <button key={c.id} onClick={() => setCategoria(c.id)}
                  className={cn('rounded-full border px-2.5 py-1 text-xs font-medium', categoria === c.id ? 'border-gray-900 bg-gray-900 text-white' : 'bg-white text-gray-700')}>
            {c.texto}
          </button>
        ))}
      </div>
      <div className="grid grid-cols-3 gap-1.5">
        {(Object.keys(SEV) as Severidad[]).map((s) => (
          <button key={s} onClick={() => setSeveridad(s)} className={cn('rounded-lg border-2 py-2 text-xs font-bold', severidad === s ? SEV[s].activo : SEV[s].cls)}>{SEV[s].texto}</button>
        ))}
      </div>
      <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} autoFocus
                placeholder="Qué pasó. Ej.: HHWB-44 pierde aceite por el retén trasero; no salir a ruta larga."
                className="w-full rounded-lg border px-3 py-2 text-sm" />
      <div className="flex gap-2">
        <select value={equipo} onChange={(e) => setEquipo(e.target.value)} className="flex-1 rounded-lg border px-2 py-2 text-sm">
          <option value="">Sin equipo</option>
          {equipos.map((e) => <option key={e.id} value={e.id}>{e.patente}</option>)}
        </select>
        <label className={cn('flex cursor-pointer items-center gap-1 rounded-lg border px-3 py-2 text-sm', foto && 'border-emerald-600 text-emerald-700')}>
          <Camera className="h-4 w-4" />{foto ? 'Foto lista' : 'Foto'}
          <input type="file" accept="image/*" capture="environment" className="hidden"
                 onChange={async (e) => { const f = e.target.files?.[0]; if (f) { try { setFoto(await guardarFotoLocal(f)) } catch (er) { toast.error(errorMessage(er)) } } }} />
        </label>
      </div>
      {severidad === 'critica' && <p className="text-xs text-red-700">Crítica: los demás supervisores deben marcarla «leído y entendido». Si en 12 h no lo hacen, se avisa a jefatura.</p>}
      <div className="flex gap-2">
        <button disabled={guardando || texto.trim().length < 3} onClick={async () => {
          setGuardando(true)
          const ok = await onGuardar({ categoria, severidad, texto: texto.trim(), activo_id: equipo || null,
            equipo: equipos.find((e) => e.id === equipo)?.patente ?? null, foto_blob: foto, fecha_hora: new Date().toISOString() })
          setGuardando(false)
          if (ok) { setTexto(''); setFoto(null); setEquipo(''); setSeveridad('normal'); setAbierto(false) }
        }} className="flex-1 rounded-lg bg-gray-900 py-2.5 text-sm font-bold text-white disabled:opacity-40">{guardando ? 'Guardando…' : 'Guardar'}</button>
        <button onClick={() => setAbierto(false)} className="rounded-lg border px-3 text-sm">Cancelar</button>
      </div>
    </div>
  )
}

function NuevoPendiente({ equipos, miTurno, onGuardar }: {
  equipos: { id: string; patente: string }[]; miTurno: 'A' | 'B' | null
  onGuardar: (d: { titulo: string; detalle: string; prioridad: Pendiente['prioridad']; responsable_turno: 'A' | 'B' | 'ambos'; vence: string | null; contingencia: string; activo_id: string | null; equipo: string | null }) => Promise<boolean>
}) {
  const [abierto, setAbierto] = useState(false)
  const [titulo, setTitulo] = useState('')
  const [detalle, setDetalle] = useState('')
  const [prioridad, setPrioridad] = useState<Pendiente['prioridad']>('media')
  const [resp, setResp] = useState<'A' | 'B' | 'ambos'>(miTurno === 'A' ? 'B' : miTurno === 'B' ? 'A' : 'ambos')
  const [vence, setVence] = useState('')
  const [contingencia, setContingencia] = useState('')
  const [equipo, setEquipo] = useState('')
  if (!abierto) {
    return <button onClick={() => setAbierto(true)} className="flex w-full items-center justify-center gap-2 rounded-xl bg-gray-900 py-3.5 text-sm font-bold text-white"><Plus className="h-5 w-5" /> Nuevo pendiente</button>
  }
  return (
    <div className="space-y-2 rounded-xl border-2 border-gray-900 bg-white p-3 text-sm">
      <input value={titulo} onChange={(e) => setTitulo(e.target.value)} placeholder="Qué hay que hacer" autoFocus className="w-full rounded-lg border px-3 py-2" />
      <textarea value={detalle} onChange={(e) => setDetalle(e.target.value)} rows={2} placeholder="Detalle (opcional)" className="w-full rounded-lg border px-3 py-2" />
      <div className="grid grid-cols-3 gap-1.5">
        {(['alta', 'media', 'baja'] as const).map((p) => (
          <button key={p} onClick={() => setPrioridad(p)} className={cn('rounded-lg border-2 py-1.5 text-xs font-bold capitalize', prioridad === p ? 'border-gray-900 bg-gray-900 text-white' : 'text-gray-700')}>{p}</button>
        ))}
      </div>
      <div className="grid grid-cols-2 gap-2">
        <label className="text-xs text-gray-600">Lo resuelve
          <select value={resp} onChange={(e) => setResp(e.target.value as 'A' | 'B' | 'ambos')} className="mt-0.5 w-full rounded-lg border px-2 py-2 text-sm">
            <option value="A">Turno A</option><option value="B">Turno B</option><option value="ambos">Cualquiera</option>
          </select>
        </label>
        <label className="text-xs text-gray-600">Para cuándo
          <input type="date" value={vence} onChange={(e) => setVence(e.target.value)} className="mt-0.5 w-full rounded-lg border px-2 py-1.5 text-sm" />
        </label>
      </div>
      <select value={equipo} onChange={(e) => setEquipo(e.target.value)} className="w-full rounded-lg border px-2 py-2">
        <option value="">Sin equipo</option>
        {equipos.map((e) => <option key={e.id} value={e.id}>{e.patente}</option>)}
      </select>
      <input value={contingencia} onChange={(e) => setContingencia(e.target.value)} placeholder="Si pasa X, hacer Y (opcional)" className="w-full rounded-lg border px-3 py-2" />
      <div className="flex gap-2">
        <button disabled={titulo.trim().length < 3} onClick={async () => {
          const ok = await onGuardar({ titulo: titulo.trim(), detalle, prioridad, responsable_turno: resp, vence: vence || null, contingencia,
            activo_id: equipo || null, equipo: equipos.find((e) => e.id === equipo)?.patente ?? null })
          if (ok) { setTitulo(''); setDetalle(''); setVence(''); setContingencia(''); setEquipo(''); setAbierto(false) }
        }} className="flex-1 rounded-lg bg-gray-900 py-2.5 font-bold text-white disabled:opacity-40">Guardar</button>
        <button onClick={() => setAbierto(false)} className="rounded-lg border px-3">Cancelar</button>
      </div>
    </div>
  )
}

function TarjetaPendiente({ p, onNota }: { p: Pendiente; onNota: (texto: string, cerrar: boolean) => Promise<boolean> }) {
  const [texto, setTexto] = useState('')
  const [abierto, setAbierto] = useState(false)
  const cerrado = p.estado === 'cerrado'
  return (
    <article className={cn('rounded-xl border bg-white p-3', cerrado && 'opacity-60', p.vencido && 'border-red-300', !cerrado && p.prioridad === 'alta' && !p.vencido && 'border-amber-300')}>
      <button onClick={() => setAbierto(!abierto)} className="w-full text-left">
        <div className="flex items-start justify-between gap-2">
          <p className={cn('text-sm font-semibold text-gray-900', cerrado && 'line-through')}><ListTodo className="mr-1 inline h-4 w-4 text-gray-500" />{p.titulo}</p>
          <span className={cn('shrink-0 rounded px-1.5 py-0.5 text-[10px] font-bold uppercase',
            cerrado ? 'bg-emerald-50 text-emerald-700' : p.vencido ? 'bg-red-100 text-red-700' : p.prioridad === 'alta' ? 'bg-amber-100 text-amber-800' : 'bg-gray-100 text-gray-600')}>
            {cerrado ? 'Cerrado' : p.vencido ? 'Vencido' : p.prioridad}
          </span>
        </div>
        <p className="mt-0.5 text-xs text-gray-500">
          {p.responsable_turno === 'ambos' ? 'Cualquier turno' : `Turno ${p.responsable_turno}`}{p.vence ? ` · para el ${p.vence.split('-').reverse().join('-')}` : ''}{p.equipo ? ` · ${p.equipo}` : ''} · creó {p.creado_nombre?.split(' ')[0] ?? '—'}{p.local ? ' · por subir' : ''}
        </p>
      </button>
      {abierto && (
        <div className="mt-2 space-y-2 border-t pt-2 text-sm">
          {p.detalle && <p className="text-gray-700">{p.detalle}</p>}
          {p.contingencia && <p className="rounded bg-amber-50 p-2 text-xs text-amber-900"><b>Si pasa:</b> {p.contingencia}</p>}
          {p.notas.map((n, i) => <p key={i} className="text-xs text-gray-600"><b>{n.autor?.split(' ')[0] ?? '—'}</b> · {fh(n.at)}: {n.texto}</p>)}
          {cerrado && p.cierre_nota && <p className="text-xs text-emerald-800"><b>Cerró {p.cerrado_nombre}:</b> {p.cierre_nota}</p>}
          {!cerrado && (<>
            <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Avance, o cómo se resolvió" className="w-full rounded-lg border px-3 py-2" />
            <div className="flex gap-2">
              <button disabled={texto.trim().length < 2} onClick={async () => { if (await onNota(texto.trim(), false)) setTexto('') }} className="flex-1 rounded-lg border py-2 text-xs font-semibold disabled:opacity-40">Agregar nota</button>
              <button disabled={texto.trim().length < 5} onClick={async () => { if (await onNota(texto.trim(), true)) setTexto('') }} className="flex-1 rounded-lg bg-emerald-700 py-2 text-xs font-bold text-white disabled:opacity-40">Cerrar pendiente</button>
            </div>
          </>)}
        </div>
      )}
    </article>
  )
}

function Resumen({ b }: { b: Bitacora }) {
  const r = b.resumen
  const criticas = b.novedades.filter((n) => n.severidad !== 'normal')
  const abiertos = b.pendientes.filter((p) => p.estado === 'abierto')
  return (
    <section className="space-y-3 px-4">
      <p className="text-xs text-gray-500">Lo que pasó en los últimos 7 días, para el supervisor que vuelve del descanso. Lea primero los registros; después converse con el que se va.</p>
      <div className="grid grid-cols-2 gap-2">
        {[['Novedades', r.novedades], ['Críticas', r.criticas], ['Pendientes abiertos', r.pendientes_abiertos], ['Cerrados en la semana', r.pendientes_cerrados],
          ['Bodega bajo mínimo', r.bodega_bajo_minimo], ['Combustible en camiones', r.combustible_lt != null ? `${Math.round(r.combustible_lt).toLocaleString('es-CL')} L` : '—']].map(([t, v]) => (
          <div key={String(t)} className="rounded-xl border bg-white p-3">
            <p className="text-[11px] uppercase tracking-wide text-gray-500">{t}</p>
            <p className="text-xl font-bold text-gray-900">{v}</p>
          </div>
        ))}
      </div>
      {criticas.length > 0 && (
        <div className="space-y-1 rounded-xl border bg-white p-3">
          <p className="text-sm font-semibold">Importantes y críticas</p>
          {criticas.map((n) => <p key={n.id} className="text-xs text-gray-700"><b className={n.severidad === 'critica' ? 'text-red-700' : 'text-amber-700'}>{fh(n.fecha_hora)}</b> · {n.texto}</p>)}
        </div>
      )}
      {abiertos.length > 0 && (
        <div className="space-y-1 rounded-xl border bg-white p-3">
          <p className="text-sm font-semibold">Pendientes que recibe</p>
          {abiertos.map((p) => <p key={p.id} className="text-xs text-gray-700">• {p.titulo}{p.vence ? ` (para el ${p.vence.split('-').reverse().join('-')})` : ''}{p.vencido ? ' — VENCIDO' : ''}</p>)}
        </div>
      )}
      <Link href="/m/franke/entrega" className="block rounded-xl border-2 border-gray-900 bg-white p-3 text-center text-sm font-bold">Ir a la entrega de turno (firmas)</Link>
    </section>
  )
}
