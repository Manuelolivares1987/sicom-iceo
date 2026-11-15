'use client'

// ============================================================================
// Comunicación de turno Franke — indicadores para jefatura (MIG696)
// ----------------------------------------------------------------------------
// La herramienta sola no arregla la comunicación: la investigación
// (reports/Cambio de turno faena Franke.md) dice que sin seguimiento de
// jefatura los registros se abandonan. Acá se ve, por persona, si escribe,
// si lee lo crítico y cuánto tarda, y si los pendientes se cierran o se pudren.
// Las primeras semanas son la línea base: no hay benchmark publicado.
// ============================================================================

import { useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2, MessagesSquare } from 'lucide-react'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { supabase } from '@/lib/supabase'
import { cn } from '@/lib/utils'
import { getFaenaId } from '@/lib/services/faena-pauta'
import type { Bitacora } from '@/lib/offline/faena-bitacora-offline'

type Indicadores = {
  dias: number
  por_persona: { nombre: string; cargo: string | null; turno: string | null; novedades: number; dias_con_novedad: number;
                 pendientes_creados: number; pendientes_cerrados: number; criticas_sin_leer: number;
                 horas_promedio_acuse: number | null; entregas_firmadas: number; entregas_recibidas: number }[]
  pendientes: { abiertos: number; vencidos: number; dias_promedio_cierre: number | null; mas_antiguo_dias: number | null }
  dias_sin_novedad: number
}

const fh = (s: string) => new Date(s).toLocaleString('es-CL', { weekday: 'short', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })

export default function ComunicacionFrankePage() {
  const { loading } = useRequireAuth()
  const [dias, setDias] = useState(30)
  const { data: faenaId } = useQuery({ queryKey: ['faena-franke-id'], queryFn: () => getFaenaId() })
  const { data: ind } = useQuery({
    queryKey: ['faena-com-ind', faenaId, dias], enabled: !!faenaId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('rpc_faena_comunicacion_indicadores', { p_faena_id: faenaId, p_dias: dias })
      if (error) throw error
      return data as Indicadores
    },
  })
  const { data: bit } = useQuery({
    queryKey: ['faena-com-bit', faenaId], enabled: !!faenaId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('rpc_faena_comunicacion', { p_faena_id: faenaId, p_dias: 7 })
      if (error) throw error
      return data as Bitacora
    },
  })

  if (loading) return null
  const sup = (ind?.por_persona ?? []).filter((p) => p.turno)
  const otros = (ind?.por_persona ?? []).filter((p) => !p.turno)

  return (
    <div className="mx-auto max-w-6xl space-y-5 p-4 md:p-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-emerald-800">Faena Franke · comunicación de turno</p>
          <h1 className="text-2xl font-bold text-gray-900">¿Se están comunicando los supervisores?</h1>
          <p className="text-sm text-gray-500">Bitácora diaria, «leído y entendido», pendientes y entregas de turno. Las primeras semanas son la línea base.</p>
        </div>
        <div className="flex gap-1">
          {[7, 30, 90].map((d) => (
            <button key={d} onClick={() => setDias(d)} className={cn('rounded-lg border px-3 py-1.5 text-sm', dias === d ? 'border-gray-900 bg-gray-900 text-white' : 'bg-white')}>{d} días</button>
          ))}
        </div>
      </header>

      {ind && (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi titulo="Días sin ninguna novedad" valor={`${ind.dias_sin_novedad} de ${dias + 1}`} malo={ind.dias_sin_novedad > dias / 3} />
          <Kpi titulo="Pendientes abiertos" valor={String(ind.pendientes.abiertos)} sub={ind.pendientes.mas_antiguo_dias != null ? `el más antiguo: ${ind.pendientes.mas_antiguo_dias} d` : undefined} />
          <Kpi titulo="Pendientes vencidos" valor={String(ind.pendientes.vencidos)} malo={ind.pendientes.vencidos > 0} />
          <Kpi titulo="Días promedio para cerrar" valor={ind.pendientes.dias_promedio_cierre != null ? String(ind.pendientes.dias_promedio_cierre) : '—'} />
        </div>
      )}

      <section className="overflow-x-auto rounded-xl border bg-white">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
            <tr><th className="px-3 py-2">Supervisor</th><th className="px-3 py-2">Turno</th><th className="px-3 py-2 text-right">Novedades</th>
              <th className="px-3 py-2 text-right">Días con novedad</th><th className="px-3 py-2 text-right">Críticas sin leer</th>
              <th className="px-3 py-2 text-right">Horas en leer</th><th className="px-3 py-2 text-right">Pendientes creados / cerrados</th>
              <th className="px-3 py-2 text-right">Entregas firmadas / recibidas</th></tr>
          </thead>
          <tbody className="divide-y">
            {sup.map((p) => (
              <tr key={p.nombre}>
                <td className="px-3 py-2 font-medium">{p.nombre}</td>
                <td className="px-3 py-2">{p.turno}</td>
                <td className="px-3 py-2 text-right tabular-nums">{p.novedades}</td>
                <td className="px-3 py-2 text-right tabular-nums">{p.dias_con_novedad}</td>
                <td className={cn('px-3 py-2 text-right tabular-nums', p.criticas_sin_leer > 0 && 'font-semibold text-red-700')}>{p.criticas_sin_leer}</td>
                <td className="px-3 py-2 text-right tabular-nums">{p.horas_promedio_acuse ?? '—'}</td>
                <td className="px-3 py-2 text-right tabular-nums">{p.pendientes_creados} / {p.pendientes_cerrados}</td>
                <td className="px-3 py-2 text-right tabular-nums">{p.entregas_firmadas} / {p.entregas_recibidas}</td>
              </tr>
            ))}
            {sup.length === 0 && <tr><td colSpan={8} className="px-3 py-6 text-center text-gray-500">Cargando…</td></tr>}
          </tbody>
        </table>
        {otros.length > 0 && <p className="border-t px-3 py-2 text-xs text-gray-500">Mecánicos y conductores: {otros.filter((o) => o.novedades > 0).length} de {otros.length} han escrito novedades (por ahora la bitácora es de supervisores).</p>}
      </section>

      {bit && (
        <section className="grid gap-4 lg:grid-cols-2">
          <div className="rounded-xl border bg-white p-4">
            <p className="mb-2 flex items-center gap-2 text-sm font-semibold"><MessagesSquare className="h-4 w-4" /> Últimas novedades (7 días)</p>
            {bit.novedades.length === 0 && <p className="text-sm text-gray-500">Nadie ha escrito en la bitácora esta semana.</p>}
            <ul className="space-y-2">
              {bit.novedades.slice(0, 20).map((n) => (
                <li key={n.id} className="text-sm">
                  <span className={cn('mr-1 text-xs font-bold', n.severidad === 'critica' ? 'text-red-700' : n.severidad === 'importante' ? 'text-amber-700' : 'text-gray-500')}>{n.severidad.toUpperCase()}</span>
                  {n.texto}
                  <span className="block text-xs text-gray-500">{n.autor} · {fh(n.fecha_hora)}{n.acuses.length ? ` · leído por ${n.acuses.map((a) => a.nombre.split(' ')[0]).join(', ')}` : n.severidad !== 'normal' ? ' · nadie lo ha leído' : ''}</span>
                </li>
              ))}
            </ul>
          </div>
          <div className="rounded-xl border bg-white p-4">
            <p className="mb-2 text-sm font-semibold">Pendientes abiertos</p>
            {bit.pendientes.filter((p) => p.estado === 'abierto').length === 0 && <p className="text-sm text-gray-500">No hay pendientes abiertos.</p>}
            <ul className="space-y-1.5">
              {bit.pendientes.filter((p) => p.estado === 'abierto').map((p) => (
                <li key={p.id} className="text-sm">
                  {p.vencido ? <AlertTriangle className="mr-1 inline h-4 w-4 text-red-600" /> : <CheckCircle2 className="mr-1 inline h-4 w-4 text-gray-300" />}
                  {p.titulo}
                  <span className="block pl-5 text-xs text-gray-500">{p.responsable_turno === 'ambos' ? 'cualquier turno' : `turno ${p.responsable_turno}`} · {p.prioridad}{p.vence ? ` · para el ${p.vence.split('-').reverse().join('-')}` : ''} · creó {p.creado_nombre}</span>
                </li>
              ))}
            </ul>
          </div>
        </section>
      )}
      <p className="text-xs text-gray-500">
        Los supervisores escriben en <Link href="/m/franke/bitacora" className="underline">/m/franke/bitacora</Link> (funciona sin señal). Todos los días a las 07:00 les llega el resumen por correo, con copia a usted.
      </p>
    </div>
  )
}

function Kpi({ titulo, valor, sub, malo }: { titulo: string; valor: string; sub?: string; malo?: boolean }) {
  return (
    <div className="rounded-xl border bg-white p-4">
      <p className="flex items-center justify-between text-xs font-medium uppercase tracking-wide text-gray-500">
        {titulo}{malo !== undefined && (malo ? <AlertTriangle className="h-4 w-4 text-amber-600" aria-label="atención" /> : <CheckCircle2 className="h-4 w-4 text-emerald-600" aria-label="bien" />)}
      </p>
      <p className="mt-1 text-2xl font-bold tabular-nums">{valor}</p>
      {sub && <p className="text-xs text-gray-500">{sub}</p>}
    </div>
  )
}
