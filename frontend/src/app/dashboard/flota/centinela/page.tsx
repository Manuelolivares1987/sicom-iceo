'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, ShieldAlert, MapPin, RefreshCw, CheckCircle2, Hand } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { errorMessage } from '@/lib/utils'
import { supabase } from '@/lib/supabase'

// ============================================================================
// Centinela de flota (MIG571)
// ----------------------------------------------------------------------------
// Los camiones cuyo GPS dejó de reportar, un incidente por camión. Crítico =
// se cortó andando y no vuelve en 48 h, o está en arriendo y lleva 7 días
// mudo. Se cierra solo si el tracker vuelve; a mano, solo diciendo qué se
// verificó. Nace de KVWD-27: 110 días sin GPS y nadie se enteró.
// ============================================================================

type Incidente = {
  id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  cliente: string | null
  operacion: string | null
  estado_comercial: string | null
  regla: 'corte_en_marcha' | 'sin_senal'
  severidad: 'vigilar' | 'alto' | 'critico'
  estado: 'abierto' | 'acusado' | 'cerrado'
  abierto_en: string
  ultimo_contacto: string | null
  horas_sin_contacto: number | null
  latitud: number | null
  longitud: number | null
  velocidad_kmh: number | null
  ignicion: boolean | null
  bateria_pct: number | null
  notificado_en: string | null
  acusado_en: string | null
  acusado_por_nombre: string | null
  nota_acuse: string | null
  cerrado_en: string | null
  cerrado_por_nombre: string | null
  motivo_cierre: string | null
  detalle_cierre: string | null
  cortes_recuperados_60d: number
}

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
  ...Object.fromEntries(MOTIVOS.map((m) => [m.v, m.label.split(':')[0]])),
}

const SEV = {
  critico: { label: 'Crítico', cls: 'bg-red-100 text-red-800 border-red-200' },
  alto: { label: 'Alto', cls: 'bg-amber-100 text-amber-800 border-amber-200' },
  vigilar: { label: 'Vigilar', cls: 'bg-emerald-50 text-emerald-800 border-emerald-200' },
} as const

const fmtFecha = (s: string | null) =>
  s ? new Date(s).toLocaleString('es-CL', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—'

const fmtSilencio = (h: number | null) =>
  h == null ? '—' : h < 48 ? `${Math.round(h)} h` : `${Math.round(h / 24)} días`

function alCortarse(i: Incidente) {
  const partes: string[] = []
  if (i.regla === 'corte_en_marcha') {
    partes.push(i.velocidad_kmh && i.velocidad_kmh > 0 ? `Se cortó andando a ${Math.round(i.velocidad_kmh)} km/h` : 'Se cortó con el motor encendido')
  } else {
    partes.push('Se calló detenido')
  }
  if (i.bateria_pct != null) partes.push(`batería ${Math.round(i.bateria_pct)}%`)
  return partes.join(' · ')
}

export default function CentinelaPage() {
  useRequireAuth()
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
    <div className="space-y-6 p-4 md:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <Link href="/dashboard/flota" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
            <ArrowLeft className="h-4 w-4" /> Flota
          </Link>
          <h1 className="mt-1 flex items-center gap-2 text-2xl font-bold text-gray-900">
            <ShieldAlert className="h-7 w-7 text-red-600" /> Centinela de flota
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-gray-500">
            Camiones cuyo GPS dejó de reportar. <b>Crítico</b>: el GPS se cortó andando y no vuelve en 48 h,
            o el equipo está en arriendo y lleva 7 días sin contacto. Te llega un correo apenas algo pasa a crítico.
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={() => refetch()} disabled={isFetching}>
          <RefreshCw className={`mr-1 h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} /> Actualizar
        </Button>
      </div>

      <div className="grid grid-cols-3 gap-3 sm:max-w-xl">
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
          Todos los camiones con GPS están reportando.
        </CardContent></Card>
      ) : (
        <div className="space-y-3">
          {abiertos.map((i) => (
            <Card key={i.id} className={i.severidad === 'critico' && i.estado === 'abierto' ? 'border-red-300' : ''}>
              <CardContent className="flex flex-col gap-3 p-4 md:flex-row md:items-center">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-lg font-bold text-gray-900">{i.patente ?? i.codigo}</span>
                    <span className={`rounded-full border px-2 py-0.5 text-xs font-bold ${SEV[i.severidad].cls}`}>
                      {SEV[i.severidad].label}
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
                    <b className="text-red-700">Mudo hace {fmtSilencio(i.horas_sin_contacto)}</b>
                    <span className="text-gray-500"> (desde {fmtFecha(i.ultimo_contacto)}) · {alCortarse(i)}</span>
                  </div>
                  {i.cortes_recuperados_60d > 0 && (
                    <div className="mt-1 text-xs text-gray-500">
                      Se cortó {i.cortes_recuperados_60d} vez/veces en 60 días y volvió solo: puede ser zona sin cobertura.
                    </div>
                  )}
                </div>
                <div className="flex flex-wrap gap-2">
                  {i.latitud != null && i.longitud != null && (
                    <a href={`https://maps.google.com/?q=${i.latitud},${i.longitud}`} target="_blank" rel="noreferrer"
                       className="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm hover:bg-gray-50">
                      <MapPin className="h-4 w-4" /> Último punto
                    </a>
                  )}
                  {i.estado === 'abierto' && (
                    <Button size="sm" variant="secondary" onClick={() => acusar.mutate(i.id)} disabled={acusar.isPending}>
                      <Hand className="mr-1 h-4 w-4" /> Lo tomo
                    </Button>
                  )}
                  <Button size="sm" variant="primary" onClick={() => { setCerrando(i); setMotivo(''); setDetalle('') }}>
                    Cerrar
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
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
                <span className="text-gray-500"> · {fmtFecha(i.cerrado_en)} · {MOTIVO_LABEL[i.motivo_cierre ?? ''] ?? i.motivo_cierre}</span>
                {i.cerrado_por_nombre && <span className="text-gray-500"> · {i.cerrado_por_nombre}</span>}
                {i.detalle_cierre && <div className="text-gray-600">{i.detalle_cierre}</div>}
              </div>
            ))}
          </div>
        )}
      </div>

      <Modal open={!!cerrando} onClose={() => setCerrando(null)}
             title={`Cerrar incidente · ${cerrando?.patente ?? ''}`}
             description="Si el GPS vuelve a reportar, el incidente se cierra solo. Para cerrarlo a mano hay que decir qué se verificó.">
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
