'use client'

/**
 * [MIG668] Actividades del camión en el teléfono: lavado, revisión técnica, etc.
 *
 * El planificador las pone en el Gantt y le aparecen acá a quien las tiene
 * asignadas. No hay nada que cerrar sin evidencia: el lavado se cierra con la foto
 * y un certificado queda esperando la aprobación del jefe de taller.
 *
 * Subir evidencia necesita señal. A diferencia del checklist, no pasa por la cola
 * sin conexión: si no hay red lo dice, en vez de mostrar como subido algo que
 * sigue en el teléfono (eso pasó con las fotos de la OT-202609-00037).
 */

import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, Camera, CheckCircle2, ChevronDown, ChevronRight, ClipboardCheck, FileUp, WifiOff } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { errorMessage } from '@/lib/utils'
import { isoToday } from '@/lib/semana'
import {
  getMisActividades, marcarActividadHecha, subirCertificadoActividad, subirFotosActividad, type MiActividad,
} from '@/lib/services/taller-actividades'

const fechaCorta = (iso: string) => {
  const [, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}`
}

function Tarjeta({ a, online }: { a: MiActividad; online: boolean }) {
  const qc = useQueryClient()
  const [abierta, setAbierta] = useState(false)
  const [archivo, setArchivo] = useState<File | null>(null)
  const [emision, setEmision] = useState('')
  const [vencimiento, setVencimiento] = useState('')
  const [numero, setNumero] = useState('')
  const [error, setError] = useState<string | null>(null)
  const refrescar = () => qc.invalidateQueries({ queryKey: ['mis-actividades'] })
  const atrasada = a.estado === 'programada' && a.fecha_fin.slice(0, 10) < isoToday()

  const hecha = useMutation({
    mutationFn: () => marcarActividadHecha(a.id),
    onSuccess: refrescar,
    onError: (e) => setError(errorMessage(e)),
  })
  const fotos = useMutation({
    mutationFn: (lista: File[]) => subirFotosActividad(a.id, lista),
    onSuccess: refrescar,
    onError: (e) => setError(errorMessage(e, 'No se pudo subir la foto. Revisa la señal e inténtalo de nuevo.')),
  })
  const certificado = useMutation({
    mutationFn: () => subirCertificadoActividad({
      actividad: a, archivo: archivo as File, emision, vencimiento, numero: numero || null,
    }),
    onSuccess: refrescar,
    onError: (e) => setError(errorMessage(e, 'No se pudo subir el certificado. Revisa la señal e inténtalo de nuevo.')),
  })
  const ocupado = hecha.isPending || fotos.isPending || certificado.isPending

  return (
    <div className={`rounded-lg border bg-white p-3 ${atrasada ? 'border-red-300' : a.estado === 'hecha' ? 'border-amber-300' : 'border-gray-200'}`}>
      <button type="button" onClick={() => setAbierta(!abierta)} className="flex w-full items-center justify-between gap-2 text-left">
        <div className="min-w-0">
          <p className="text-sm font-bold text-gray-900">{a.patente} · {a.nombre}</p>
          <p className="text-xs text-gray-500">
            {fechaCorta(a.fecha_inicio)}{a.fecha_fin !== a.fecha_inicio ? ` al ${fechaCorta(a.fecha_fin)}` : ''} · {a.responsable}
          </p>
          {atrasada && <p className="text-xs font-semibold text-red-700">Atrasada</p>}
          {a.estado === 'hecha' && !a.rechazo_motivo && <p className="text-xs font-semibold text-amber-700">Falta la evidencia</p>}
        </div>
        {abierta ? <ChevronDown className="h-4 w-4 shrink-0 text-gray-400" /> : <ChevronRight className="h-4 w-4 shrink-0 text-gray-400" />}
      </button>

      {a.rechazo_motivo && (
        <p className="mt-2 flex items-start gap-1.5 rounded bg-red-50 p-2 text-xs text-red-800">
          <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />Rechazada: {a.rechazo_motivo}
        </p>
      )}

      {abierta && (
        <div className="mt-3 space-y-2 border-t border-gray-100 pt-3">
          {a.notas && <p className="text-xs text-gray-600">{a.notas}</p>}
          {!online && (
            <p className="flex items-center gap-1.5 rounded bg-amber-50 p-2 text-xs text-amber-800">
              <WifiOff className="h-3.5 w-3.5" />Sin señal: la evidencia se sube cuando vuelva la conexión.
            </p>
          )}
          {error && <p className="rounded bg-red-50 p-2 text-xs text-red-800">{error}</p>}

          {a.evidencia === 'foto' ? (
            <label className={`flex min-h-11 cursor-pointer items-center justify-center gap-2 rounded-lg bg-orange-600 px-3 text-sm font-semibold text-white ${!online || ocupado ? 'pointer-events-none opacity-50' : ''}`}>
              {fotos.isPending ? <Spinner size="sm" /> : <Camera className="h-4 w-4" />}
              Subir foto y cerrar
              <input
                type="file" accept="image/*" multiple className="sr-only" disabled={!online || ocupado}
                onChange={(e) => {
                  const lista = Array.from(e.target.files ?? [])
                  e.target.value = ''
                  setError(null)
                  if (lista.length) fotos.mutate(lista)
                }}
              />
            </label>
          ) : (
            <div className="space-y-2">
              <label className="block text-xs font-medium text-gray-700">
                Certificado (foto o PDF)
                <input type="file" accept="image/*,application/pdf" className="mt-1 block w-full text-xs" onChange={(e) => setArchivo(e.target.files?.[0] ?? null)} />
              </label>
              <div className="grid grid-cols-2 gap-2">
                <label className="block text-xs font-medium text-gray-700">
                  Emisión
                  <input type="date" value={emision} onChange={(e) => setEmision(e.target.value)} className="mt-1 h-11 w-full rounded border border-gray-300 px-2 text-sm" />
                </label>
                <label className="block text-xs font-medium text-gray-700">
                  Vence
                  <input type="date" value={vencimiento} onChange={(e) => setVencimiento(e.target.value)} className="mt-1 h-11 w-full rounded border border-gray-300 px-2 text-sm" />
                </label>
              </div>
              <label className="block text-xs font-medium text-gray-700">
                N° de certificado (opcional)
                <input value={numero} onChange={(e) => setNumero(e.target.value)} className="mt-1 h-11 w-full rounded border border-gray-300 px-2 text-sm" />
              </label>
              <button
                type="button" disabled={!online || ocupado || !archivo || !emision || !vencimiento}
                onClick={() => { setError(null); certificado.mutate() }}
                className="flex min-h-11 w-full items-center justify-center gap-2 rounded-lg bg-orange-600 px-3 text-sm font-semibold text-white disabled:opacity-50"
              >
                {certificado.isPending ? <Spinner size="sm" /> : <FileUp className="h-4 w-4" />}
                Enviar al jefe de taller
              </button>
            </div>
          )}

          {a.estado === 'programada' && (
            <button
              type="button" disabled={!online || ocupado}
              onClick={() => { setError(null); hecha.mutate() }}
              className="flex min-h-11 w-full items-center justify-center gap-2 rounded-lg border border-gray-300 px-3 text-sm font-medium text-gray-700 disabled:opacity-50"
            >
              <CheckCircle2 className="h-4 w-4" />Ya la hice, subo la evidencia después
            </button>
          )}
        </div>
      )}
    </div>
  )
}

export function MisActividades({ online }: { online: boolean }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['mis-actividades'],
    queryFn: getMisActividades,
    enabled: online,
    staleTime: 60_000,
  })
  if (isLoading) return null
  if (error) return <p className="rounded bg-red-50 p-2 text-xs text-red-800">No se pudieron cargar las actividades del camión.</p>
  const lista = data ?? []
  if (lista.length === 0) return null
  return (
    <section className="space-y-2">
      <h2 className="flex items-center gap-1.5 text-sm font-bold text-gray-900">
        <ClipboardCheck className="h-4 w-4 text-orange-600" />Actividades del camión ({lista.length})
      </h2>
      {lista.map((a) => <Tarjeta key={a.id} a={a} online={online} />)}
    </section>
  )
}
