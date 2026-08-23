'use client'

// ============================================================================
// Lo que se le pidió a la faena, y qué hizo cada turno (MIG344/345)
// ----------------------------------------------------------------------------
// La queja del mandante: se le dice algo al turno de día, el de noche no lo
// hace, y nadie se entera hasta que el mandante vuelve a preguntar.
//
// Un campo de observaciones no arregla eso, porque una nota no obliga a nadie:
// no tiene dueño, no tiene cierre y nadie está obligado a leerla. Acá el
// pendiente es un objeto con estado — nace abierto y sigue abierto hasta que un
// turno lo cierra diciendo qué hizo — y vive dentro del cierre del turno, que
// es el único ritual que el turno ya está obligado a completar.
//
// Lo que esta pantalla muestra no es «¿lo anotaron?» sino la pregunta que de
// verdad importa: cuántos turnos lleva dando vueltas y quién lo dejó pasar cada
// vez.
// ============================================================================

import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ClipboardList, Plus, ChevronDown, ChevronRight } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import {
  getPendientesAbiertos, crearPendiente, type Pendiente,
} from '@/lib/services/combustible-cierre'
import { supabase } from '@/lib/supabase'

const SENAL: Record<string, { label: string; cls: string }> = {
  nuevo:       { label: 'Todavía no lo ve ningún turno', cls: 'bg-blue-100 text-blue-800' },
  arrastrando: { label: 'Viene arrastrando',             cls: 'bg-amber-100 text-amber-800' },
  // Tres turnos o más ya no es «se les pasó»: es que nadie se hizo cargo.
  atascado:    { label: 'Atascado',                      cls: 'bg-red-100 text-red-800' },
}

type FilaHistoria = {
  fecha: string | null
  turno: string | null
  respuesta: string | null
  comentario: string | null
  respondido_por: string | null
}

async function getHistoria(pendienteId: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_pendiente_historia')
    .select('fecha, turno, respuesta, comentario, respondido_por')
    .eq('pendiente_id', pendienteId)
    .not('fecha', 'is', null)
    .order('respondido_at')
  if (error) throw error
  return (data ?? []) as FilaHistoria[]
}

export function PendientesTurno({ faenaId }: { faenaId: string }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [abriendo, setAbriendo] = useState(false)
  const [texto, setTexto] = useState('')
  const [quien, setQuien] = useState('')
  const [delMandante, setDelMandante] = useState(true)
  const [alta, setAlta] = useState(false)
  const [verHistoria, setVerHistoria] = useState<string | null>(null)

  const { data: lista } = useQuery({
    queryKey: ['comb-pendientes', faenaId],
    queryFn: () => getPendientesAbiertos(faenaId),
    enabled: !!faenaId,
  })

  const { data: historia } = useQuery({
    queryKey: ['comb-pendiente-historia', verHistoria],
    queryFn: () => getHistoria(verHistoria!),
    enabled: !!verHistoria,
  })

  async function anotar() {
    try {
      await crearPendiente({
        faenaId,
        texto,
        origen: delMandante ? 'mandante' : 'oficina',
        pedidoPor: quien || null,
        prioridad: alta ? 'alta' : 'normal',
      })
      setTexto(''); setQuien(''); setAbriendo(false)
      qc.invalidateQueries({ queryKey: ['comb-pendientes'] })
      toast.success('Anotado. El turno lo va a ver al empezar y al firmar.')
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo anotar'))
    }
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base text-gray-700">
          <ClipboardList className="h-4 w-4 text-amber-600" />
          Lo que quedó pendiente
          {!!lista?.length && <span className="text-xs font-normal text-gray-400">({lista.length})</span>}
        </CardTitle>
        <p className="text-xs text-gray-500">
          El turno lo ve al empezar y no puede firmar sin decir qué pasó con cada uno.
        </p>
      </CardHeader>

      <CardContent className="space-y-3">
        {!lista?.length && !abriendo && (
          <p className="py-3 text-center text-sm text-gray-400">
            No hay nada pendiente.
          </p>
        )}

        {lista?.map((p: Pendiente) => {
          const s = SENAL[p.senal] ?? SENAL.nuevo
          const abierto = verHistoria === p.id
          return (
            <div key={p.id} className="rounded-lg border border-gray-200 p-3">
              <div className="flex flex-wrap items-center gap-2">
                {p.origen === 'mandante' && (
                  <span className="rounded bg-gray-900 px-1.5 py-0.5 text-[10px] font-bold uppercase text-white">
                    Mandante
                  </span>
                )}
                {p.prioridad === 'alta' && (
                  <span className="rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-bold uppercase text-red-800">
                    Prioridad
                  </span>
                )}
                <span className={cn('rounded px-1.5 py-0.5 text-[10px] font-bold uppercase', s.cls)}>
                  {s.label}
                </span>
                {p.turnos_sin_hacer > 0 && (
                  <span className="text-xs tabular-nums text-gray-500">
                    {p.turnos_sin_hacer} turno{p.turnos_sin_hacer > 1 ? 's' : ''} · {p.dias_abierto} día
                    {p.dias_abierto === 1 ? '' : 's'}
                  </span>
                )}
              </div>

              <p className="mt-1.5 font-medium text-gray-900">{p.texto}</p>
              {p.pedido_por && <p className="text-xs text-gray-500">Lo pidió {p.pedido_por}</p>}

              {p.ultimo_comentario && (
                <p className="mt-1.5 border-l-2 border-gray-200 pl-2 text-sm text-gray-600">
                  Último turno: «{p.ultimo_comentario}»
                  {p.ultimo_turno_por && <> — {p.ultimo_turno_por}</>}
                </p>
              )}

              {p.turnos_sin_hacer > 0 && (
                <button
                  onClick={() => setVerHistoria(abierto ? null : p.id)}
                  className="mt-2 flex items-center gap-1 text-xs font-medium text-blue-700 hover:underline"
                >
                  {abierto ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                  Ver qué dijo cada turno
                </button>
              )}

              {abierto && !!historia?.length && (
                <div className="mt-2 space-y-1.5 border-l-2 border-amber-300 pl-3">
                  {historia.map((h, i) => (
                    <div key={i} className="text-sm">
                      <span className="tabular-nums text-gray-500">
                        {h.fecha?.slice(5)} {h.turno}
                      </span>{' '}
                      <span className={cn('font-medium',
                        h.respuesta === 'hecho' ? 'text-emerald-700' : 'text-amber-800')}>
                        {h.respuesta === 'hecho' ? 'lo hizo' : 'no alcanzó'}
                      </span>
                      {h.comentario && <span className="text-gray-600"> — {h.comentario}</span>}
                      {h.respondido_por && <span className="text-gray-400"> ({h.respondido_por})</span>}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )
        })}

        {abriendo ? (
          <div className="space-y-2 rounded-lg border border-blue-200 bg-blue-50/50 p-3">
            <textarea
              value={texto} onChange={(e) => setTexto(e.target.value)} rows={2}
              placeholder="Qué hay que hacer"
              className="w-full rounded border border-gray-300 p-2 text-sm"
            />
            <input
              value={quien} onChange={(e) => setQuien(e.target.value)}
              placeholder="Quién lo pidió"
              className="w-full rounded border border-gray-300 p-2 text-sm"
            />
            <div className="flex flex-wrap gap-3 text-sm">
              <label className="flex items-center gap-1.5">
                <input type="checkbox" checked={delMandante}
                       onChange={(e) => setDelMandante(e.target.checked)} />
                Lo pide el mandante
              </label>
              <label className="flex items-center gap-1.5">
                <input type="checkbox" checked={alta} onChange={(e) => setAlta(e.target.checked)} />
                Es prioritario
              </label>
            </div>
            <div className="flex gap-2">
              <button onClick={anotar} disabled={texto.trim().length < 5}
                      className="flex-1 rounded bg-blue-600 py-2 text-sm font-medium text-white
                                 hover:bg-blue-700 disabled:opacity-40">
                Anotar
              </button>
              <button onClick={() => setAbriendo(false)}
                      className="rounded border border-gray-300 px-3 py-2 text-sm text-gray-700">
                Cancelar
              </button>
            </div>
          </div>
        ) : (
          <button
            onClick={() => setAbriendo(true)}
            className="flex w-full items-center justify-center gap-2 rounded-lg border border-dashed
                       border-gray-300 py-2.5 text-sm font-medium text-gray-600
                       transition hover:border-blue-400 hover:bg-blue-50"
          >
            <Plus className="h-4 w-4" /> Anotar algo para el turno
          </button>
        )}
      </CardContent>
    </Card>
  )
}
