'use client'

// ============================================================================
// Copiloto Técnico — panel de jefatura (MIG543)
// ----------------------------------------------------------------------------
// La función del copiloto es MEJORAR la capacidad de diagnóstico del taller,
// y eso se demuestra con números, no con sensaciones: qué se pregunta, si
// las respuestas sirven (👍/👎), qué casos se resolvieron y quedaron como
// conocimiento, dónde el corpus está cojo (consultas sin fuentes) y cuánto
// cuesta. Todo sale de copiloto_consultas + copiloto_diagnosticos.
// ============================================================================

import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Bot, ThumbsUp, Camera, FileQuestion, DollarSign, Stethoscope, Repeat,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { supabase } from '@/lib/supabase'

// Tarifa claude-opus-5: US$5/M entrada + US$25/M salida
const USD_IN = 5 / 1_000_000
const USD_OUT = 25 / 1_000_000

type Consulta = {
  id: string; usuario_id: string; pregunta: string; con_foto: boolean
  feedback: 'util' | 'no_util' | null; fuentes: unknown[]
  input_tokens: number | null; output_tokens: number | null
  created_at: string; diagnostico_id: string | null
  activo: { codigo: string | null; patente: string | null } | null
}

type Dx = {
  id: string; sintoma: string; sistema: string | null; estado: string
  causa_raiz: string | null; reparacion: string | null
  comprobaciones: unknown[]; created_at: string; resuelto_at: string | null
  activo: { codigo: string | null; patente: string | null; modelo_id: string | null } | null
  activo_id: string
}

async function getDatos() {
  const desde = new Date(Date.now() - 30 * 86400_000).toISOString()
  const [consultas, dxs, perfiles] = await Promise.all([
    supabase.from('copiloto_consultas')
      .select('id, usuario_id, pregunta, con_foto, feedback, fuentes, input_tokens, output_tokens, created_at, diagnostico_id, activo:activos(codigo, patente)')
      .gte('created_at', desde).order('created_at', { ascending: false }).limit(300),
    supabase.from('copiloto_diagnosticos')
      .select('id, sintoma, sistema, estado, causa_raiz, reparacion, comprobaciones, created_at, resuelto_at, activo_id, activo:activos(codigo, patente, modelo_id)')
      .order('created_at', { ascending: false }).limit(300),
    supabase.from('usuarios_perfil').select('id, nombre_completo'),
  ])
  if (consultas.error) throw consultas.error
  if (dxs.error) throw dxs.error
  const nombres = new Map((perfiles.data ?? []).map((p) => [p.id as string, p.nombre_completo as string]))
  return {
    consultas: (consultas.data ?? []) as unknown as Consulta[],
    dxs: (dxs.data ?? []) as unknown as Dx[],
    nombres,
  }
}

function Kpi({ icon: Icon, titulo, valor, detalle, tono }: {
  icon: React.ComponentType<{ className?: string }>
  titulo: string; valor: string; detalle?: string; tono?: 'ok' | 'warn'
}) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-3">
      <div className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-gray-500">
        <Icon className="h-3.5 w-3.5" /> {titulo}
      </div>
      <div className={`mt-1 text-2xl font-bold tabular-nums ${
        tono === 'ok' ? 'text-green-700' : tono === 'warn' ? 'text-amber-700' : 'text-gray-900'}`}>{valor}</div>
      {detalle && <div className="mt-0.5 text-[11px] text-gray-500">{detalle}</div>}
    </div>
  )
}

const equipoLabel = (a: { codigo: string | null; patente: string | null } | null) =>
  a?.patente ?? a?.codigo ?? '—'

export default function CopilotoPanelPage() {
  const { loading: authLoading } = useRequireAuth()
  const { data, isLoading, error } = useQuery({ queryKey: ['copiloto-panel'], queryFn: getDatos })

  const stats = useMemo(() => {
    if (!data) return null
    const cs = data.consultas
    const conFb = cs.filter((c) => c.feedback)
    const utiles = conFb.filter((c) => c.feedback === 'util').length
    const sinFuentes = cs.filter((c) => Array.isArray(c.fuentes) && c.fuentes.length === 0)
    const costo = cs.reduce((s, c) => s + (c.input_tokens ?? 0) * USD_IN + (c.output_tokens ?? 0) * USD_OUT, 0)
    const mecanicos = new Set(cs.map((c) => c.usuario_id)).size
    const resueltos = data.dxs.filter((d) => d.estado === 'resuelto')
    const abiertos = data.dxs.filter((d) => d.estado === 'abierto')

    // Recurrencia: el mismo equipo con más de un diagnóstico del mismo sistema
    // = la falla que "vuelve al taller". Es LA métrica que el copiloto debe bajar.
    const porEquipoSistema = new Map<string, { equipo: string; sistema: string; n: number }>()
    for (const d of data.dxs) {
      const k = `${d.activo_id}|${d.sistema ?? '?'}`
      const prev = porEquipoSistema.get(k)
      if (prev) prev.n += 1
      else porEquipoSistema.set(k, { equipo: equipoLabel(d.activo), sistema: d.sistema ?? 'sin sistema', n: 1 })
    }
    const recurrentes = Array.from(porEquipoSistema.values()).filter((x) => x.n > 1).sort((a, b) => b.n - a.n)

    return { cs, conFb, utiles, sinFuentes, costo, mecanicos, resueltos, abiertos, recurrentes }
  }, [data])

  if (authLoading || isLoading) {
    return <div className="flex h-64 items-center justify-center"><Spinner size="lg" /></div>
  }
  if (error || !stats || !data) {
    return <div className="p-6 text-sm text-red-600">No se pudo cargar el panel. {String((error as Error)?.message ?? '')}</div>
  }

  return (
    <div className="space-y-5 p-4 md:p-6">
      <div>
        <h1 className="flex items-center gap-2 text-xl font-bold text-gray-900">
          <Bot className="h-5 w-5 text-indigo-600" /> Copiloto Técnico
        </h1>
        <p className="text-sm text-gray-500">
          Qué pregunta el taller, si las respuestas sirven y qué casos quedaron como conocimiento. Últimos 30 días.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
        <Kpi icon={Bot} titulo="Consultas" valor={String(stats.cs.length)}
             detalle={`${stats.mecanicos} mecánico(s) · ${stats.cs.filter((c) => c.con_foto).length} con foto`} />
        <Kpi icon={ThumbsUp} titulo="¿Sirvió?" tono={stats.conFb.length && stats.utiles / stats.conFb.length >= 0.7 ? 'ok' : undefined}
             valor={stats.conFb.length ? `${Math.round(100 * stats.utiles / stats.conFb.length)}%` : '—'}
             detalle={stats.conFb.length ? `${stats.utiles} 👍 de ${stats.conFb.length} evaluadas` : 'sin evaluaciones aún'} />
        <Kpi icon={Stethoscope} titulo="Casos resueltos" tono="ok" valor={String(stats.resueltos.length)}
             detalle={`${stats.abiertos.length} diagnóstico(s) abiertos`} />
        <Kpi icon={FileQuestion} titulo="Sin fuentes" tono={stats.sinFuentes.length > 0 ? 'warn' : undefined}
             valor={String(stats.sinFuentes.length)} detalle="vacíos del corpus a revisar" />
        <Kpi icon={Repeat} titulo="Fallas recurrentes" tono={stats.recurrentes.length ? 'warn' : 'ok'}
             valor={String(stats.recurrentes.length)} detalle="mismo equipo, mismo sistema" />
        <Kpi icon={DollarSign} titulo="Costo IA 30d" valor={`US$${stats.costo.toFixed(2)}`}
             detalle={`~US$${stats.cs.length ? (stats.costo / stats.cs.length).toFixed(3) : '0'} por consulta`} />
      </div>

      {/* Casos técnicos: el conocimiento que el taller acumuló */}
      <div className="rounded-lg border border-gray-200 bg-white">
        <div className="border-b px-4 py-2.5 text-sm font-semibold text-gray-800">
          Casos técnicos resueltos <span className="font-normal text-gray-400">— lo que el copiloto cita como experiencia interna</span>
        </div>
        {stats.resueltos.length === 0 ? (
          <p className="px-4 py-6 text-center text-sm text-gray-400">
            Aún no hay casos. Nacen cuando un mecánico marca «Encontré la causa» en un diagnóstico.
          </p>
        ) : (
          <div className="divide-y">
            {stats.resueltos.slice(0, 12).map((d) => (
              <div key={d.id} className="px-4 py-2.5 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-mono text-xs font-bold text-gray-700">{equipoLabel(d.activo)}</span>
                  {d.sistema && <span className="rounded-full bg-indigo-50 px-2 py-0.5 text-[10px] font-semibold text-indigo-700">{d.sistema}</span>}
                  <span className="text-[11px] text-gray-400">{(d.resuelto_at ?? '').slice(0, 10)}</span>
                  <span className="text-[11px] text-gray-400">· {(d.comprobaciones ?? []).length} comprobaciones</span>
                </div>
                <div className="mt-0.5 text-gray-700"><b>Síntoma:</b> {d.sintoma}</div>
                <div className="text-green-800"><b>Causa:</b> {d.causa_raiz}{d.reparacion ? ` — ${d.reparacion}` : ''}</div>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        {/* Últimas consultas */}
        <div className="rounded-lg border border-gray-200 bg-white">
          <div className="border-b px-4 py-2.5 text-sm font-semibold text-gray-800">Últimas consultas</div>
          <div className="divide-y">
            {stats.cs.slice(0, 15).map((c) => (
              <div key={c.id} className="px-4 py-2 text-sm">
                <div className="flex items-center gap-2 text-[11px] text-gray-400">
                  <span className="font-mono font-semibold text-gray-600">{equipoLabel(c.activo)}</span>
                  <span>{data.nombres.get(c.usuario_id) ?? '—'}</span>
                  <span>{c.created_at.slice(5, 16).replace('T', ' ')}</span>
                  {c.con_foto && <Camera className="h-3 w-3" />}
                  {c.feedback === 'util' && <ThumbsUp className="h-3 w-3 text-green-500" />}
                  {c.feedback === 'no_util' && <ThumbsUp className="h-3 w-3 rotate-180 text-red-500" />}
                </div>
                <div className="truncate text-gray-700">{c.pregunta}</div>
              </div>
            ))}
            {stats.cs.length === 0 && <p className="px-4 py-6 text-center text-sm text-gray-400">Sin consultas en 30 días.</p>}
          </div>
        </div>

        {/* Vacíos del corpus + recurrencia */}
        <div className="space-y-4">
          <div className="rounded-lg border border-amber-200 bg-white">
            <div className="border-b border-amber-100 bg-amber-50 px-4 py-2.5 text-sm font-semibold text-amber-800">
              Consultas sin fuentes — dónde faltan manuales
            </div>
            <div className="divide-y">
              {stats.sinFuentes.slice(0, 8).map((c) => (
                <div key={c.id} className="truncate px-4 py-2 text-sm text-gray-700">
                  <span className="mr-2 font-mono text-xs font-semibold text-gray-500">{equipoLabel(c.activo)}</span>
                  {c.pregunta}
                </div>
              ))}
              {stats.sinFuentes.length === 0 && (
                <p className="px-4 py-4 text-center text-sm text-gray-400">Todas las consultas encontraron fuentes. 💪</p>
              )}
            </div>
          </div>

          <div className="rounded-lg border border-gray-200 bg-white">
            <div className="border-b px-4 py-2.5 text-sm font-semibold text-gray-800">
              Fallas recurrentes <span className="font-normal text-gray-400">— la métrica que hay que bajar</span>
            </div>
            <div className="divide-y">
              {stats.recurrentes.slice(0, 8).map((r, i) => (
                <div key={i} className="flex items-center gap-2 px-4 py-2 text-sm">
                  <span className="font-mono text-xs font-bold text-gray-700">{r.equipo}</span>
                  <span className="text-gray-600">{r.sistema}</span>
                  <span className="ml-auto rounded-full bg-red-100 px-2 py-0.5 text-xs font-bold text-red-700">{r.n}×</span>
                </div>
              ))}
              {stats.recurrentes.length === 0 && (
                <p className="px-4 py-4 text-center text-sm text-gray-400">Ningún equipo con la misma falla repetida.</p>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
