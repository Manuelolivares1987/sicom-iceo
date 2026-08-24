'use client'

// ============================================================================
// Lo que revisó el mecánico en faena — vista de oficina (MIG357-359)
// ----------------------------------------------------------------------------
// No es un tablero para mirar: es el capítulo 4 («Desviaciones de los equipos»)
// y el 12 («Disponibilidad») de la entrega de turno, armados solos. Lo que hoy
// alguien redacta el día 7 desde la memoria.
//
// Se ordena por lo que hay que hacer, no por lo que hay que informar: primero
// lo vencido, después lo que no se revisó hoy, y al final lo que está al día.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  Wrench, AlertTriangle, CheckCircle2, Ban, ClipboardList, Truck, ExternalLink,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { cn } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import {
  FAENA_FRANKE, getFaenaId, getAgenda, textoSenal, type PautaAgenda,
} from '@/lib/services/faena-pauta'

type Hallazgo = {
  id: string
  descripcion: string
  fecha_evento: string
  severidad: string
  estado_planificacion: string
  foto_url: string | null
  resuelto: boolean
  patente: string | null
  codigo: string | null
}

async function getHallazgos(): Promise<Hallazgo[]> {
  const { data, error } = await supabase
    .from('no_conformidades')
    .select('id, descripcion, fecha_evento, severidad, estado_planificacion, foto_url, resuelto, activos!inner(patente, codigo)')
    .eq('origen', 'pauta_faena')
    .order('fecha_evento', { ascending: false })
    .limit(100)
  if (error) throw error
  type Row = Omit<Hallazgo, 'patente' | 'codigo'> & { activos: { patente: string | null; codigo: string | null } }
  return ((data ?? []) as unknown as Row[]).map((r) => ({
    ...r, patente: r.activos?.patente ?? null, codigo: r.activos?.codigo ?? null,
  }))
}

const SEV: Record<string, string> = {
  critica: 'bg-red-100 text-red-800',
  alta:    'bg-red-50 text-red-700',
  media:   'bg-amber-50 text-amber-800',
  baja:    'bg-gray-100 text-gray-700',
}

export default function PautaFaenaPage() {
  useRequireAuth()
  const [tab, setTab] = useState<'equipos' | 'hallazgos'>('equipos')

  const { data: faenaId } = useQuery({
    queryKey: ['faena', FAENA_FRANKE],
    queryFn: () => getFaenaId(FAENA_FRANKE),
  })
  const { data: agenda = [], isLoading } = useQuery({
    queryKey: ['pauta-agenda', faenaId],
    queryFn: () => getAgenda(faenaId as string),
    enabled: !!faenaId,
  })
  const { data: hallazgos = [] } = useQuery({
    queryKey: ['pauta-hallazgos'],
    queryFn: getHallazgos,
  })

  const equipos = useMemo(() => {
    const m = new Map<string, { cab: PautaAgenda; filas: PautaAgenda[] }>()
    for (const a of agenda) {
      const e = m.get(a.activo_id) ?? { cab: a, filas: [] }
      e.filas.push(a)
      m.set(a.activo_id, e)
    }
    return Array.from(m.values())
  }, [agenda])

  const revisadosHoy = agenda.filter(
    (a) => a.pauta_tipo === 'diaria' && (a.ejecucion_hoy_estado === 'cerrada' || a.ejecucion_hoy_estado === 'no_aplica'),
  ).length
  const diarias = agenda.filter((a) => a.pauta_tipo === 'diaria').length
  const vencidas = agenda.filter((a) => a.senal === 'vencida').length
  const abiertos = hallazgos.filter((h) => !h.resuelto).length

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Revisión de equipos en faena</h1>
        <p className="mt-1 text-sm text-gray-600">
          Faena Franke · lo que el mecánico marcó en terreno. Reemplaza los capítulos de
          desviaciones y disponibilidad de la entrega de turno.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Kpi titulo="Revisados hoy" valor={`${revisadosHoy}/${diarias}`} icono={ClipboardList}
             tono={revisadosHoy === diarias && diarias > 0 ? 'ok' : 'aviso'} />
        <Kpi titulo="Mantenciones vencidas" valor={String(vencidas)} icono={Wrench}
             tono={vencidas > 0 ? 'malo' : 'ok'} />
        <Kpi titulo="Hallazgos abiertos" valor={String(abiertos)} icono={AlertTriangle}
             tono={abiertos > 0 ? 'aviso' : 'ok'} />
        <Kpi titulo="Equipos con pauta" valor={String(equipos.length)} icono={Truck} tono="neutro" />
      </div>

      <div className="flex gap-2 border-b border-gray-200">
        {([['equipos', 'Equipos'], ['hallazgos', 'Hallazgos']] as const).map(([k, l]) => (
          <button key={k} onClick={() => setTab(k)}
                  className={cn('-mb-px border-b-2 px-4 py-2 text-sm font-semibold transition',
                                tab === k
                                  ? 'border-gray-900 text-gray-900'
                                  : 'border-transparent text-gray-500 hover:text-gray-700')}>
            {l}
          </button>
        ))}
      </div>

      {isLoading && <div className="flex justify-center py-10"><Spinner /></div>}

      {tab === 'equipos' && !isLoading && (
        <div className="grid gap-4 lg:grid-cols-2">
          {equipos.map(({ cab, filas }) => {
            const diaria = filas.find((f) => f.pauta_tipo === 'diaria')
            const prog = filas.filter((f) => f.pauta_tipo === 'programada')
            return (
              <Card key={cab.activo_id}>
                <CardHeader className="flex-row items-center justify-between gap-3">
                  <div className="min-w-0">
                    <CardTitle className="truncate text-base">
                      {cab.patente ?? cab.activo_codigo}
                    </CardTitle>
                    <p className="truncate text-xs text-gray-500">{cab.modelo ?? cab.activo_nombre}</p>
                  </div>
                  <EstadoDia a={diaria} />
                </CardHeader>
                <CardContent className="space-y-2.5">
                  <div className="grid grid-cols-2 gap-3 text-sm">
                    <Dato k="Horómetro" v={cab.horas_uso_actual} u="h" />
                    <Dato k="Kilometraje" v={cab.kilometraje_actual} u="km" />
                  </div>
                  {prog.map((p) => (
                    <div key={p.pauta_id}
                         className="flex items-center gap-2 rounded-lg border border-gray-200 px-3 py-2">
                      <Wrench className="h-4 w-4 shrink-0 text-gray-400" />
                      <span className="min-w-0 flex-1 truncate text-sm text-gray-700">{p.pauta_nombre}</span>
                      <span className={cn('shrink-0 rounded px-1.5 py-0.5 font-mono text-xs font-semibold tabular-nums',
                                          p.senal === 'vencida' ? 'bg-red-100 text-red-800'
                                          : p.senal === 'por_vencer' ? 'bg-amber-100 text-amber-800'
                                          : 'bg-emerald-50 text-emerald-800')}>
                        {textoSenal(p)}
                      </span>
                    </div>
                  ))}
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      {tab === 'hallazgos' && (
        <Card>
          <CardContent className="p-0">
            {hallazgos.length === 0 ? (
              <p className="p-8 text-center text-sm text-gray-500">
                Todavía no hay hallazgos registrados desde la pauta de faena.
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="border-b border-gray-200 bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
                    <tr>
                      <th className="px-4 py-2.5">Equipo</th>
                      <th className="px-4 py-2.5">Hallazgo</th>
                      <th className="px-4 py-2.5">Fecha</th>
                      <th className="px-4 py-2.5">Severidad</th>
                      <th className="px-4 py-2.5">Estado</th>
                      <th className="px-4 py-2.5">Foto</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {hallazgos.map((h) => (
                      <tr key={h.id} className={cn(h.resuelto && 'opacity-50')}>
                        <td className="whitespace-nowrap px-4 py-2.5 font-semibold text-gray-900">
                          {h.patente ?? h.codigo}
                        </td>
                        <td className="max-w-md px-4 py-2.5 text-gray-700">{h.descripcion}</td>
                        <td className="whitespace-nowrap px-4 py-2.5 tabular-nums text-gray-600">
                          {h.fecha_evento}
                        </td>
                        <td className="px-4 py-2.5">
                          <span className={cn('rounded px-1.5 py-0.5 text-xs font-semibold',
                                              SEV[h.severidad] ?? SEV.baja)}>
                            {h.severidad}
                          </span>
                        </td>
                        <td className="whitespace-nowrap px-4 py-2.5 text-gray-600">
                          {h.resuelto ? 'Resuelto' : h.estado_planificacion}
                        </td>
                        <td className="px-4 py-2.5">
                          {h.foto_url ? (
                            <a href={h.foto_url} target="_blank" rel="noreferrer"
                               className="inline-flex items-center gap-1 text-blue-600 hover:underline">
                              Ver <ExternalLink className="h-3.5 w-3.5" />
                            </a>
                          ) : <span className="text-gray-400">—</span>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      <p className="text-xs text-gray-500">
        Los hallazgos entran a la bandeja de{' '}
        <Link href="/dashboard/mantenimiento/no-conformidades" className="text-blue-600 hover:underline">
          No Conformidades
        </Link>{' '}
        con dueño, igual que los de recepción. El mecánico los registra desde{' '}
        <code className="rounded bg-gray-100 px-1">/m/franke/pauta</code>.
      </p>
    </div>
  )
}

function Kpi({ titulo, valor, icono: Icono, tono }: {
  titulo: string; valor: string
  icono: typeof Wrench
  tono: 'ok' | 'aviso' | 'malo' | 'neutro'
}) {
  const color = {
    ok: 'text-emerald-700', aviso: 'text-amber-700', malo: 'text-red-700', neutro: 'text-gray-900',
  }[tono]
  return (
    <Card>
      <CardContent className="flex items-center gap-3 p-4">
        <Icono className={cn('h-5 w-5 shrink-0', color)} />
        <div className="min-w-0">
          <p className={cn('text-2xl font-bold tabular-nums', color)}>{valor}</p>
          <p className="truncate text-xs text-gray-500">{titulo}</p>
        </div>
      </CardContent>
    </Card>
  )
}

function Dato({ k, v, u }: { k: string; v: number | null; u: string }) {
  return (
    <div>
      <p className="text-xs text-gray-500">{k}</p>
      <p className="font-mono font-semibold tabular-nums text-gray-900">
        {v == null ? '—' : `${Number(v).toLocaleString('es-CL', { maximumFractionDigits: 0 })} ${u}`}
      </p>
    </div>
  )
}

function EstadoDia({ a }: { a: PautaAgenda | undefined }) {
  if (!a) return null
  if (a.ejecucion_hoy_estado === 'cerrada') {
    return (
      <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-800">
        <CheckCircle2 className="h-3.5 w-3.5" /> Revisado hoy
      </span>
    )
  }
  if (a.ejecucion_hoy_estado === 'no_aplica') {
    return (
      <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-gray-100 px-2.5 py-1 text-xs font-semibold text-gray-600">
        <Ban className="h-3.5 w-3.5" /> No está en faena
      </span>
    )
  }
  return (
    <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-800">
      <AlertTriangle className="h-3.5 w-3.5" /> Sin revisar hoy
    </span>
  )
}
