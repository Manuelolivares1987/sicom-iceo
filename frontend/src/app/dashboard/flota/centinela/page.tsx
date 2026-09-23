'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import dynamic from 'next/dynamic'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft, ShieldAlert, MapPin, RefreshCw, CheckCircle2, Hand, Route, Map as MapIcon, Sparkles, Clock,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { errorMessage } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import type { ZonaCirculo } from '@/components/flota/mapa-zonas'

const MapaZonas = dynamic(
  () => import('@/components/flota/mapa-zonas').then((m) => m.MapaZonas),
  { ssr: false, loading: () => <div className="flex h-[360px] items-center justify-center"><Spinner /></div> },
)

// ============================================================================
// Centinela de flota (MIG571-573)
// ----------------------------------------------------------------------------
// Nace de KVWD-27: 110 días sin GPS, «arrendado» todos los días, y nadie se
// enteró. Tres pestañas:
//  · Incidentes: un incidente por camión (mudo, fuera de zona, fuera de
//    horario). Crítico = correo inmediato. Se toma, se escala, se cierra con
//    motivo y lo que se verificó.
//  · Zonas: la zona de cada contrato. Solo una zona VERIFICADA por una
//    persona puede disparar crítico por salida; SICOM sugiere desde el GPS.
//  · Traslados: ventanas autorizadas en que el Centinela no abre incidentes.
// ============================================================================

type Incidente = {
  id: string
  activo_id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  cliente: string | null
  operacion: string | null
  estado_comercial: string | null
  regla: 'corte_en_marcha' | 'sin_senal' | 'fuera_de_zona' | 'fuera_de_horario'
  severidad: 'vigilar' | 'alto' | 'critico'
  estado: 'abierto' | 'acusado' | 'cerrado'
  abierto_en: string
  ultimo_contacto: string | null
  horas_sin_contacto: number | null
  horas_fuera: number | null
  detalle: string | null
  latitud: number | null
  longitud: number | null
  velocidad_kmh: number | null
  ignicion: boolean | null
  bateria_pct: number | null
  acusado_en: string | null
  acusado_por_nombre: string | null
  cerrado_en: string | null
  cerrado_por_nombre: string | null
  motivo_cierre: string | null
  detalle_cierre: string | null
  cortes_recuperados_60d: number
}

type Zona = {
  id: string; nombre: string; lat: number; lng: number; radio_m: number
  verificada_en: string | null; verificada_por: string | null
}
type Horario = { hora_desde: string; hora_hasta: string; dias: number[]; activo: boolean } | null
type Contrato = {
  contrato_id: string; codigo: string; cliente: string | null
  equipos: string[] | null; verificada: boolean; zonas: Zona[]; horario: Horario
}
type Permiso = {
  id: string; patente: string; desde: string; hasta: string; motivo: string
  revocado_en: string | null; vigente: boolean; creado_por: string | null
}
type PanelZonas = {
  contratos: Contrato[]
  sin_contrato: { activo_id: string; patente: string; codigo: string; cliente: string | null }[]
  permisos: Permiso[]
}
type Sugerida = { lat: number; lng: number; radio_m: number; pct: number }

const MOTIVOS: { v: string; label: string }[] = [
  { v: 'ubicado_con_evidencia', label: 'Ubicado: se vio el camión (foto, horómetro, persona)' },
  { v: 'falla_gps', label: 'Falla del GPS: el camión está bien, el tracker no (OT/Radicom)' },
  { v: 'traslado_autorizado', label: 'Traslado o faena sin cobertura autorizada' },
  { v: 'denuncia', label: 'Denuncia presentada' },
  { v: 'falso_positivo', label: 'Falso positivo' },
  { v: 'otro', label: 'Otro' },
]
const MOTIVO_LABEL: Record<string, string> = {
  senal_recuperada: 'El GPS volvió a reportar',
  normalizado: 'Se normalizó solo',
  permiso_transito: 'Cubierto por traslado autorizado',
  ...Object.fromEntries(MOTIVOS.map((m) => [m.v, m.label.split(':')[0]])),
}
const REGLA_LABEL: Record<Incidente['regla'], string> = {
  corte_en_marcha: 'GPS cortado andando',
  sin_senal: 'GPS mudo',
  fuera_de_zona: 'Fuera de su zona',
  fuera_de_horario: 'Fuera de horario',
}
const SEV = {
  critico: { label: 'Crítico', cls: 'bg-red-100 text-red-800 border-red-200' },
  alto: { label: 'Alto', cls: 'bg-amber-100 text-amber-800 border-amber-200' },
  vigilar: { label: 'Vigilar', cls: 'bg-emerald-50 text-emerald-800 border-emerald-200' },
} as const
const DIAS = ['L', 'M', 'X', 'J', 'V', 'S', 'D']

const fmtFecha = (s: string | null) =>
  s ? new Date(s).toLocaleString('es-CL', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—'
const fmtHoras = (h: number | null) =>
  h == null ? '—' : h < 48 ? `${Math.round(h)} h` : `${Math.round(h / 24)} días`

function situacion(i: Incidente) {
  if (i.regla === 'fuera_de_zona' || i.regla === 'fuera_de_horario') return i.detalle ?? REGLA_LABEL[i.regla]
  const partes: string[] = []
  if (i.regla === 'corte_en_marcha') {
    partes.push(i.velocidad_kmh && i.velocidad_kmh > 0 ? `Se cortó andando a ${Math.round(i.velocidad_kmh)} km/h` : 'Se cortó con el motor encendido')
  } else {
    partes.push('Se calló detenido')
  }
  if (i.bateria_pct != null) partes.push(`batería ${Math.round(i.bateria_pct)}%`)
  return partes.join(' · ')
}

const enDias = (d: number) => {
  const x = new Date(Date.now() + d * 86400000)
  x.setMinutes(x.getMinutes() - x.getTimezoneOffset())
  return x.toISOString().slice(0, 16)
}

export default function CentinelaPage() {
  useRequireAuth()
  const [tab, setTab] = useState<'incidentes' | 'zonas' | 'traslados'>('incidentes')
  const [trasladoPara, setTrasladoPara] = useState<{ activo_id: string; patente: string } | null>(null)

  const tabs = [
    { k: 'incidentes' as const, label: 'Incidentes', icon: ShieldAlert },
    { k: 'zonas' as const, label: 'Zonas por contrato', icon: MapIcon },
    { k: 'traslados' as const, label: 'Traslados autorizados', icon: Route },
  ]

  return (
    <div className="space-y-5 p-4 md:p-6">
      <div>
        <Link href="/dashboard/flota" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
          <ArrowLeft className="h-4 w-4" /> Flota
        </Link>
        <h1 className="mt-1 flex items-center gap-2 text-2xl font-bold text-gray-900">
          <ShieldAlert className="h-7 w-7 text-red-600" /> Centinela de flota
        </h1>
        <p className="mt-1 max-w-3xl text-sm text-gray-500">
          Camiones que dejaron de reportar GPS, que salieron de la zona de su contrato o que andan fuera de horario.
          <b> Crítico</b> = correo inmediato: GPS cortado andando por 48 h, equipo en arriendo 7 días sin contacto, o 12 h
          fuera de una zona verificada.
        </p>
      </div>

      <div className="flex flex-wrap gap-1 border-b">
        {tabs.map((t) => (
          <button key={t.k} onClick={() => setTab(t.k)}
                  className={`-mb-px inline-flex items-center gap-1.5 border-b-2 px-3 py-2 text-sm font-medium ${
                    tab === t.k ? 'border-red-600 text-red-700' : 'border-transparent text-gray-500 hover:text-gray-800'}`}>
            <t.icon className="h-4 w-4" /> {t.label}
          </button>
        ))}
      </div>

      {tab === 'incidentes' && <IncidentesTab onTraslado={(a) => { setTrasladoPara(a); setTab('traslados') }} />}
      {tab === 'zonas' && <ZonasTab />}
      {tab === 'traslados' && <TrasladosTab preseleccion={trasladoPara} onUsada={() => setTrasladoPara(null)} />}
    </div>
  )
}

// ── Incidentes ──────────────────────────────────────────────────────────────

function IncidentesTab({ onTraslado }: { onTraslado: (a: { activo_id: string; patente: string }) => void }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [verCerrados, setVerCerrados] = useState(false)
  const [cerrando, setCerrando] = useState<Incidente | null>(null)
  const [motivo, setMotivo] = useState('')
  const [detalle, setDetalle] = useState('')

  const { data = [], isLoading, refetch, isFetching } = useQuery({
    queryKey: ['centinela-incidentes'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('rpc_centinela_listar', { p_dias_cerrados: 14 })
      if (error) throw error
      return (data ?? []) as Incidente[]
    },
    staleTime: 60_000,
  })

  const acusar = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('rpc_centinela_acusar', { p_id: id, p_nota: null })
      if (error) throw error
    },
    onSuccess: () => { toast.success('Quedó registrado que lo tomaste'); qc.invalidateQueries({ queryKey: ['centinela-incidentes'] }) },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const cerrar = useMutation({
    mutationFn: async () => {
      if (!cerrando) return
      const { error } = await supabase.rpc('rpc_centinela_cerrar', { p_id: cerrando.id, p_motivo: motivo, p_detalle: detalle })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Incidente cerrado')
      setCerrando(null); setMotivo(''); setDetalle('')
      qc.invalidateQueries({ queryKey: ['centinela-incidentes'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const abiertos = data.filter((i) => i.estado !== 'cerrado')
  const cerrados = data.filter((i) => i.estado === 'cerrado')
  const criticos = abiertos.filter((i) => i.severidad === 'critico')
  const sinTomar = criticos.filter((i) => i.estado === 'abierto')

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="grid grid-cols-3 gap-3 sm:w-[32rem]">
          <Card><CardContent className="p-4">
            <div className="text-3xl font-extrabold text-red-700">{criticos.length}</div>
            <div className="text-xs font-semibold uppercase text-red-700">Críticos</div>
          </CardContent></Card>
          <Card><CardContent className="p-4">
            <div className="text-3xl font-extrabold text-amber-700">{sinTomar.length}</div>
            <div className="text-xs font-semibold uppercase text-amber-700">Sin acuse</div>
          </CardContent></Card>
          <Card><CardContent className="p-4">
            <div className="text-3xl font-extrabold text-gray-800">{abiertos.length}</div>
            <div className="text-xs font-semibold uppercase text-gray-500">Abiertos</div>
          </CardContent></Card>
        </div>
        <Button variant="outline" size="sm" onClick={() => refetch()} disabled={isFetching}>
          <RefreshCw className={`mr-1 h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} /> Actualizar
        </Button>
      </div>

      {criticos.length > 0 && (
        <div className="rounded-lg border-l-4 border-red-600 bg-red-50 p-4 text-sm text-gray-700">
          <b>Qué hacer con cada crítico</b>
          <ol className="ml-5 mt-1 list-decimal space-y-0.5">
            <li>Llamar al cliente o a la faena y pedir <b>foto del camión con el horómetro visible</b>.</li>
            <li>Pedir a Radicom el historial del tracker: ¿registró corte de alimentación antes de apagarse?</li>
            <li>Marcar <b>«Lo tomo»</b> aquí. Si nadie lo toma en 4 h, el aviso se escala.</li>
            <li>Si en 24–48 h nadie confirma dónde está: evaluar la denuncia con la patente y el último punto.</li>
          </ol>
        </div>
      )}

      {isLoading ? (
        <div className="flex justify-center py-12"><Spinner /></div>
      ) : abiertos.length === 0 ? (
        <Card><CardContent className="p-8 text-center text-gray-500">
          <CheckCircle2 className="mx-auto mb-2 h-10 w-10 text-emerald-500" />
          Todos los camiones con GPS están reportando y dentro de su zona.
        </CardContent></Card>
      ) : (
        <div className="space-y-3">
          {abiertos.map((i) => {
            const zona = i.regla === 'fuera_de_zona' || i.regla === 'fuera_de_horario'
            return (
              <Card key={i.id} className={i.severidad === 'critico' && i.estado === 'abierto' ? 'border-red-300' : ''}>
                <CardContent className="flex flex-col gap-3 p-4 md:flex-row md:items-center">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-lg font-bold text-gray-900">{i.patente ?? i.codigo}</span>
                      <span className={`rounded-full border px-2 py-0.5 text-xs font-bold ${SEV[i.severidad].cls}`}>
                        {SEV[i.severidad].label}
                      </span>
                      <span className="rounded-full border border-gray-200 bg-gray-50 px-2 py-0.5 text-xs text-gray-600">
                        {REGLA_LABEL[i.regla]}
                      </span>
                      {i.estado === 'acusado' && (
                        <span className="rounded-full border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs font-semibold text-blue-800">
                          Lo tomó {i.acusado_por_nombre ?? '—'} · {fmtFecha(i.acusado_en)}
                        </span>
                      )}
                    </div>
                    <div className="text-sm text-gray-500">
                      {i.nombre} · {i.cliente ?? 'sin cliente'} · {i.estado_comercial}{i.operacion ? ` · ${i.operacion}` : ''}
                    </div>
                    <div className="mt-1 text-sm">
                      {zona ? (
                        <b className="text-red-700">
                          {i.regla === 'fuera_de_zona' ? `Fuera hace ${fmtHoras(i.horas_fuera)}` : `Detectado ${fmtFecha(i.abierto_en)}`}
                        </b>
                      ) : (
                        <>
                          <b className="text-red-700">Mudo hace {fmtHoras(i.horas_sin_contacto)}</b>
                          <span className="text-gray-500"> (desde {fmtFecha(i.ultimo_contacto)})</span>
                        </>
                      )}
                      <span className="text-gray-500"> · {situacion(i)}</span>
                    </div>
                    {i.cortes_recuperados_60d > 0 && !zona && (
                      <div className="mt-1 text-xs text-gray-500">
                        Se cortó {i.cortes_recuperados_60d} vez/veces en 60 días y volvió solo: puede ser zona sin cobertura.
                      </div>
                    )}
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {i.latitud != null && i.longitud != null && (
                      <a href={`https://maps.google.com/?q=${i.latitud},${i.longitud}`} target="_blank" rel="noreferrer"
                         className="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm hover:bg-gray-50">
                        <MapPin className="h-4 w-4" /> {zona ? 'Dónde está' : 'Último punto'}
                      </a>
                    )}
                    {i.estado === 'abierto' && (
                      <Button size="sm" variant="secondary" onClick={() => acusar.mutate(i.id)} disabled={acusar.isPending}>
                        <Hand className="mr-1 h-4 w-4" /> Lo tomo
                      </Button>
                    )}
                    {i.regla === 'fuera_de_zona' && (
                      <Button size="sm" variant="outline" onClick={() => onTraslado({ activo_id: i.activo_id, patente: i.patente ?? '' })}>
                        <Route className="mr-1 h-4 w-4" /> Autorizar traslado
                      </Button>
                    )}
                    <Button size="sm" variant="primary" onClick={() => { setCerrando(i); setMotivo(''); setDetalle('') }}>
                      Cerrar
                    </Button>
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      <div>
        <button className="text-sm font-medium text-gray-600 hover:text-gray-900" onClick={() => setVerCerrados((v) => !v)}>
          {verCerrados ? '▾' : '▸'} Cerrados en los últimos 14 días ({cerrados.length})
        </button>
        {verCerrados && (
          <div className="mt-2 divide-y rounded-lg border bg-white">
            {cerrados.length === 0 && <div className="p-4 text-sm text-gray-500">Ninguno.</div>}
            {cerrados.map((i) => (
              <div key={i.id} className="p-3 text-sm">
                <b>{i.patente ?? i.codigo}</b>
                <span className="text-gray-500"> · {REGLA_LABEL[i.regla]} · {fmtFecha(i.cerrado_en)} · {MOTIVO_LABEL[i.motivo_cierre ?? ''] ?? i.motivo_cierre}</span>
                {i.cerrado_por_nombre && <span className="text-gray-500"> · {i.cerrado_por_nombre}</span>}
                {i.detalle_cierre && <div className="text-gray-600">{i.detalle_cierre}</div>}
              </div>
            ))}
          </div>
        )}
      </div>

      <Modal open={!!cerrando} onClose={() => setCerrando(null)}
             title={`Cerrar incidente · ${cerrando?.patente ?? ''}`}
             description="Si el GPS vuelve o el camión vuelve a su zona, el incidente se cierra solo. Para cerrarlo a mano hay que decir qué se verificó.">
        <div className="space-y-3">
          <div className="space-y-1">
            {MOTIVOS.map((m) => (
              <label key={m.v} className="flex cursor-pointer items-start gap-2 text-sm">
                <input type="radio" name="motivo" className="mt-1" checked={motivo === m.v} onChange={() => setMotivo(m.v)} />
                {m.label}
              </label>
            ))}
          </div>
          <textarea
            className="w-full rounded-md border border-gray-300 p-2 text-sm" rows={3}
            placeholder="Qué se verificó: quién vio el camión, foto con horómetro, N° de OT, N° de denuncia…"
            value={detalle} onChange={(e) => setDetalle(e.target.value)}
          />
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setCerrando(null)}>Cancelar</Button>
          <Button variant="primary" onClick={() => cerrar.mutate()}
                  disabled={!motivo || detalle.trim().length < 10 || cerrar.isPending}>
            Cerrar incidente
          </Button>
        </ModalFooter>
      </Modal>
    </div>
  )
}

// ── Zonas por contrato ──────────────────────────────────────────────────────

function usePanelZonas() {
  return useQuery({
    queryKey: ['centinela-zonas'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('rpc_centinela_zonas')
      if (error) throw error
      return data as PanelZonas
    },
    staleTime: 60_000,
  })
}

function ZonasTab() {
  const { data, isLoading } = usePanelZonas()
  const [abierto, setAbierto] = useState<string | null>(null)

  if (isLoading || !data) return <div className="flex justify-center py-12"><Spinner /></div>
  const porVerificar = data.contratos.filter((c) => !c.verificada).length

  return (
    <div className="space-y-4">
      <div className="rounded-lg border bg-white p-4 text-sm text-gray-600">
        Cada contrato necesita la zona donde trabajan sus camiones. <b>Una zona solo dispara alertas críticas si una
        persona la verificó</b>: hoy <b className={porVerificar ? 'text-red-700' : 'text-emerald-700'}>{porVerificar}</b> de{' '}
        {data.contratos.length} contratos con equipos arrendados tienen su zona sin verificar. SICOM sugiere zonas con los
        puntos reales del GPS de los últimos 30 días. Los talleres y bodegas de Pillado siempre cuentan como zona permitida.
      </div>

      {data.sin_contrato.length > 0 && (
        <div className="rounded-lg border-l-4 border-amber-500 bg-amber-50 p-3 text-sm">
          <b>Arrendados sin contrato asignado:</b> {data.sin_contrato.map((a) => a.patente).join(', ')}. Sin contrato no hay
          zona que vigilar. Asígnalo desde{' '}
          <Link href="/dashboard/flota/sugerencias" className="font-semibold underline">Sugerencias estado (GPS) → Contrato</Link>.
        </div>
      )}

      <div className="space-y-3">
        {data.contratos.map((c) => (
          <ContratoZona key={c.contrato_id} c={c} abierto={abierto === c.contrato_id}
                        onToggle={() => setAbierto(abierto === c.contrato_id ? null : c.contrato_id)} />
        ))}
      </div>
    </div>
  )
}

function ContratoZona({ c, abierto, onToggle }: { c: Contrato; abierto: boolean; onToggle: () => void }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [sugeridas, setSugeridas] = useState<Sugerida[] | null>(null)
  const [cargandoSug, setCargandoSug] = useState(false)
  const [ed, setEd] = useState<{ id: string | null; nombre: string; lat: string; lng: string; radioKm: string } | null>(null)
  const [hor, setHor] = useState<{ activo: boolean; desde: string; hasta: string; dias: number[] }>({
    activo: c.horario?.activo ?? false,
    desde: c.horario?.hora_desde?.slice(0, 5) ?? '07:00',
    hasta: c.horario?.hora_hasta?.slice(0, 5) ?? '20:00',
    dias: c.horario?.dias ?? [1, 2, 3, 4, 5, 6],
  })

  const refrescar = () => {
    qc.invalidateQueries({ queryKey: ['centinela-zonas'] })
    qc.invalidateQueries({ queryKey: ['centinela-incidentes'] })
  }

  const guardar = useMutation({
    mutationFn: async (z: { id: string | null; nombre: string; lat: number; lng: number; radio_m: number }) => {
      const { error } = await supabase.rpc('rpc_centinela_guardar_zona', {
        p_contrato_id: c.contrato_id, p_geocerca_id: z.id, p_nombre: z.nombre,
        p_lat: z.lat, p_lng: z.lng, p_radio_m: z.radio_m,
      })
      if (error) throw error
    },
    onSuccess: () => { toast.success('Zona guardada y verificada'); setEd(null); refrescar() },
    onError: (e) => toast.error(errorMessage(e)),
  })
  const desactivar = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('rpc_centinela_desactivar_zona', { p_geocerca_id: id })
      if (error) throw error
    },
    onSuccess: () => { toast.success('Zona desactivada'); refrescar() },
    onError: (e) => toast.error(errorMessage(e)),
  })
  const guardarHorario = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('rpc_centinela_guardar_horario', {
        p_contrato_id: c.contrato_id, p_desde: hor.desde, p_hasta: hor.hasta, p_dias: hor.dias, p_activo: hor.activo,
      })
      if (error) throw error
    },
    onSuccess: () => { toast.success(hor.activo ? 'Horario guardado' : 'Control de horario apagado'); refrescar() },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const sugerir = async () => {
    setCargandoSug(true)
    try {
      const { data, error } = await supabase.rpc('rpc_centinela_sugerir_zonas', { p_contrato_id: c.contrato_id })
      if (error) throw error
      setSugeridas((data ?? []) as Sugerida[])
      if (!data || (data as Sugerida[]).length === 0) toast.error('No hay puntos GPS suficientes de este contrato en 30 días')
    } catch (e) { toast.error(errorMessage(e)) } finally { setCargandoSug(false) }
  }

  const circulos: ZonaCirculo[] = useMemo(() => {
    const out: ZonaCirculo[] = c.zonas
      .filter((z) => z.id !== ed?.id)
      .map((z) => ({ key: z.id, lat: Number(z.lat), lng: Number(z.lng), radio_m: Number(z.radio_m), etiqueta: z.nombre,
                     tipo: z.verificada_en ? 'guardada' : 'guardada_sin_verificar' }))
    ;(sugeridas ?? []).forEach((s, n) => {
      out.push({ key: `s${n}`, lat: s.lat, lng: s.lng, radio_m: s.radio_m, etiqueta: `Sugerida ${n + 1} (${s.pct}% del tiempo)`, tipo: 'sugerida' })
    })
    const lat = Number(ed?.lat), lng = Number(ed?.lng), r = Number(ed?.radioKm) * 1000
    if (ed && Number.isFinite(lat) && Number.isFinite(lng) && r > 0) {
      out.push({ key: 'ed', lat, lng, radio_m: r, etiqueta: ed.nombre || 'Zona en edición', tipo: 'edicion' })
    }
    return out
  }, [c.zonas, sugeridas, ed])

  const estado = c.zonas.length === 0
    ? { txt: 'Sin zona', cls: 'bg-red-100 text-red-800' }
    : c.verificada ? { txt: 'Verificada', cls: 'bg-emerald-100 text-emerald-800' }
    : { txt: 'Por verificar', cls: 'bg-amber-100 text-amber-800' }

  return (
    <Card>
      <CardContent className="p-0">
        <button onClick={onToggle} className="flex w-full flex-wrap items-center gap-2 p-4 text-left hover:bg-gray-50">
          <span className="font-semibold text-gray-900">{c.codigo}</span>
          <span className="text-sm text-gray-500">{c.cliente}</span>
          <span className={`rounded-full px-2 py-0.5 text-xs font-bold ${estado.cls}`}>{estado.txt}</span>
          {c.horario?.activo && (
            <span className="inline-flex items-center gap-1 rounded-full bg-blue-50 px-2 py-0.5 text-xs text-blue-800">
              <Clock className="h-3 w-3" /> {c.horario.hora_desde.slice(0, 5)}–{c.horario.hora_hasta.slice(0, 5)}
            </span>
          )}
          <span className="ml-auto text-xs text-gray-500">{(c.equipos ?? []).join(', ')}</span>
        </button>

        {abierto && (
          <div className="space-y-4 border-t p-4">
            <MapaZonas zonas={circulos}
                       onClic={ed ? (lat, lng) => setEd({ ...ed, lat: lat.toFixed(5), lng: lng.toFixed(5) }) : undefined} />
            <p className="text-xs text-gray-500">
              Verde = zona guardada (punteada si falta verificar) · naranjo = sugerida por el GPS · azul = en edición
              {ed ? ' · haz clic en el mapa para mover el centro' : ''}.
            </p>

            <div className="space-y-2">
              {c.zonas.map((z) => (
                <div key={z.id} className="flex flex-wrap items-center gap-2 rounded border p-2 text-sm">
                  <b>{z.nombre}</b>
                  <span className="text-gray-500">radio {(Number(z.radio_m) / 1000).toFixed(1)} km</span>
                  {z.verificada_en
                    ? <span className="text-xs text-emerald-700">✓ verificada por {z.verificada_por ?? '—'} · {fmtFecha(z.verificada_en)}</span>
                    : <span className="text-xs font-semibold text-amber-700">sin verificar</span>}
                  <div className="ml-auto flex gap-1">
                    {!z.verificada_en && (
                      <Button size="sm" variant="secondary" disabled={guardar.isPending}
                              onClick={() => guardar.mutate({ id: z.id, nombre: z.nombre, lat: Number(z.lat), lng: Number(z.lng), radio_m: Number(z.radio_m) })}>
                        Verificar así
                      </Button>
                    )}
                    <Button size="sm" variant="outline"
                            onClick={() => setEd({ id: z.id, nombre: z.nombre, lat: String(z.lat), lng: String(z.lng), radioKm: (Number(z.radio_m) / 1000).toFixed(1) })}>
                      Editar
                    </Button>
                    <Button size="sm" variant="ghost" disabled={desactivar.isPending} onClick={() => desactivar.mutate(z.id)}>
                      Desactivar
                    </Button>
                  </div>
                </div>
              ))}
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" onClick={sugerir} disabled={cargandoSug}>
                  <Sparkles className="mr-1 h-4 w-4" /> {cargandoSug ? 'Calculando…' : 'Sugerir desde el GPS'}
                </Button>
                <Button size="sm" variant="outline"
                        onClick={() => setEd({ id: null, nombre: c.cliente ?? c.codigo, lat: '', lng: '', radioKm: '5' })}>
                  + Zona manual
                </Button>
              </div>
              {sugeridas && sugeridas.length > 0 && (
                <div className="space-y-1">
                  {sugeridas.map((s, n) => (
                    <div key={n} className="flex flex-wrap items-center gap-2 rounded border border-orange-200 bg-orange-50 p-2 text-sm">
                      <b>Sugerida {n + 1}</b>
                      <span className="text-gray-600">{s.pct}% del tiempo · radio {(s.radio_m / 1000).toFixed(1)} km</span>
                      <a href={`https://maps.google.com/?q=${s.lat},${s.lng}`} target="_blank" rel="noreferrer" className="text-xs underline">ver</a>
                      <Button size="sm" variant="outline" className="ml-auto"
                              onClick={() => setEd({ id: null, nombre: `${c.cliente ?? c.codigo}${sugeridas.length > 1 ? ` ${n + 1}` : ''}`,
                                                     lat: String(s.lat), lng: String(s.lng), radioKm: (s.radio_m / 1000).toFixed(1) })}>
                        Usar
                      </Button>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {ed && (
              <div className="grid gap-2 rounded-lg border border-blue-200 bg-blue-50 p-3 sm:grid-cols-5">
                <input className="h-9 rounded border px-2 text-sm sm:col-span-2" placeholder="Nombre de la zona"
                       value={ed.nombre} onChange={(e) => setEd({ ...ed, nombre: e.target.value })} />
                <input className="h-9 rounded border px-2 text-sm" placeholder="Latitud (-29.97)"
                       value={ed.lat} onChange={(e) => setEd({ ...ed, lat: e.target.value })} />
                <input className="h-9 rounded border px-2 text-sm" placeholder="Longitud (-71.27)"
                       value={ed.lng} onChange={(e) => setEd({ ...ed, lng: e.target.value })} />
                <div className="flex items-center gap-1">
                  <input className="h-9 w-20 rounded border px-2 text-sm" value={ed.radioKm}
                         onChange={(e) => setEd({ ...ed, radioKm: e.target.value })} />
                  <span className="text-sm text-gray-600">km</span>
                </div>
                <div className="flex gap-2 sm:col-span-5">
                  <Button size="sm" variant="primary" disabled={guardar.isPending}
                          onClick={() => guardar.mutate({ id: ed.id, nombre: ed.nombre, lat: Number(ed.lat), lng: Number(ed.lng), radio_m: Number(ed.radioKm) * 1000 })}>
                    Guardar y verificar
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => setEd(null)}>Cancelar</Button>
                  <span className="self-center text-xs text-gray-600">Al guardar respondes por la zona: queda con tu nombre.</span>
                </div>
              </div>
            )}

            <div className="rounded-lg border p-3">
              <label className="flex items-center gap-2 text-sm font-medium">
                <input type="checkbox" checked={hor.activo} onChange={(e) => setHor({ ...hor, activo: e.target.checked })} />
                Avisar si los camiones de este contrato andan fuera de horario
              </label>
              {hor.activo && (
                <div className="mt-2 flex flex-wrap items-center gap-2 text-sm">
                  <input type="time" className="h-9 rounded border px-2" value={hor.desde} onChange={(e) => setHor({ ...hor, desde: e.target.value })} />
                  a
                  <input type="time" className="h-9 rounded border px-2" value={hor.hasta} onChange={(e) => setHor({ ...hor, hasta: e.target.value })} />
                  <div className="flex gap-1">
                    {DIAS.map((d, n) => {
                      const on = hor.dias.includes(n + 1)
                      return (
                        <button key={d} type="button"
                                onClick={() => setHor({ ...hor, dias: on ? hor.dias.filter((x) => x !== n + 1) : [...hor.dias, n + 1].sort() })}
                                className={`h-8 w-8 rounded border text-xs font-bold ${on ? 'border-blue-600 bg-blue-600 text-white' : 'bg-white text-gray-500'}`}>
                          {d}
                        </button>
                      )
                    })}
                  </div>
                </div>
              )}
              <Button size="sm" variant="outline" className="mt-2" disabled={guardarHorario.isPending}
                      onClick={() => guardarHorario.mutate()}>
                Guardar horario
              </Button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ── Traslados autorizados ───────────────────────────────────────────────────

function TrasladosTab({ preseleccion, onUsada }: {
  preseleccion: { activo_id: string; patente: string } | null
  onUsada: () => void
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data, isLoading } = usePanelZonas()
  const [activoId, setActivoId] = useState(preseleccion?.activo_id ?? '')
  const [hasta, setHasta] = useState(enDias(3))
  const [motivo, setMotivo] = useState('')

  const { data: equipos = [] } = useQuery({
    queryKey: ['centinela-equipos-gps'],
    queryFn: async () => {
      const { data, error } = await supabase.from('activos').select('id, patente, codigo')
        .is('fecha_baja', null).not('patente', 'is', null).order('patente')
      if (error) throw error
      return (data ?? []) as { id: string; patente: string; codigo: string }[]
    },
    staleTime: 5 * 60_000,
  })

  const autorizar = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('rpc_centinela_autorizar_traslado', {
        p_activo_id: activoId, p_hasta: new Date(hasta).toISOString(), p_motivo: motivo,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Traslado autorizado: el Centinela no abrirá incidentes para ese camión hasta la fecha indicada')
      setMotivo(''); onUsada()
      qc.invalidateQueries({ queryKey: ['centinela-zonas'] })
      qc.invalidateQueries({ queryKey: ['centinela-incidentes'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })
  const revocar = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('rpc_centinela_revocar_traslado', { p_id: id })
      if (error) throw error
    },
    onSuccess: () => { toast.success('Traslado revocado'); qc.invalidateQueries({ queryKey: ['centinela-zonas'] }) },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <div className="space-y-4">
      <Card><CardContent className="space-y-3 p-4">
        <div className="text-sm text-gray-600">
          Un camión que va al taller, cambia de faena o trabaja unos días donde no hay cobertura: se autoriza por un plazo
          (máximo 15 días) y el Centinela no abre incidentes para él mientras dure. Si ya tenía uno abierto, se cierra en la
          siguiente revisión (cada hora).
        </div>
        <div className="grid gap-2 sm:grid-cols-4">
          <select className="h-9 rounded border px-2 text-sm" value={activoId} onChange={(e) => setActivoId(e.target.value)}>
            <option value="">Camión…</option>
            {equipos.map((a) => <option key={a.id} value={a.id}>{a.patente} · {a.codigo}</option>)}
          </select>
          <input type="datetime-local" className="h-9 rounded border px-2 text-sm" value={hasta} onChange={(e) => setHasta(e.target.value)} />
          <input className="h-9 rounded border px-2 text-sm sm:col-span-2" placeholder="Motivo: destino y quién lo pidió"
                 value={motivo} onChange={(e) => setMotivo(e.target.value)} />
        </div>
        <Button size="sm" variant="primary" disabled={!activoId || motivo.trim().length < 10 || autorizar.isPending}
                onClick={() => autorizar.mutate()}>
          <Route className="mr-1 h-4 w-4" /> Autorizar traslado
        </Button>
      </CardContent></Card>

      {isLoading || !data ? <div className="flex justify-center py-8"><Spinner /></div> : (
        <div className="divide-y rounded-lg border bg-white">
          {data.permisos.length === 0 && <div className="p-4 text-sm text-gray-500">No hay traslados en los últimos 14 días.</div>}
          {data.permisos.map((p) => (
            <div key={p.id} className="flex flex-wrap items-center gap-2 p-3 text-sm">
              <b>{p.patente}</b>
              <span className={`rounded-full px-2 py-0.5 text-xs font-bold ${
                p.vigente ? 'bg-blue-100 text-blue-800' : p.revocado_en ? 'bg-gray-100 text-gray-600' : 'bg-gray-100 text-gray-500'}`}>
                {p.vigente ? 'Vigente' : p.revocado_en ? 'Revocado' : 'Vencido'}
              </span>
              <span className="text-gray-500">{fmtFecha(p.desde)} → {fmtFecha(p.hasta)}</span>
              <span className="text-gray-700">{p.motivo}</span>
              {p.creado_por && <span className="text-xs text-gray-500">· {p.creado_por}</span>}
              {p.vigente && (
                <Button size="sm" variant="ghost" className="ml-auto" disabled={revocar.isPending} onClick={() => revocar.mutate(p.id)}>
                  Revocar
                </Button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
