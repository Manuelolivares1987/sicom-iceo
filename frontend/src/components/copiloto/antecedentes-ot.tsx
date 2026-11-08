'use client'

// [MIG677] El Copiloto dentro de la OT, sin gastar IA.
// ----------------------------------------------------------------------------
// Lo que hace el mercado (Snap-on «Real Fixes», Penske, ServiceMax): antes de
// que el mecánico pregunte, mostrarle lo que esta flota ya hizo con un síntoma
// parecido. Son consultas a la base (casos confirmados + historial del equipo):
// cero llamadas a la IA. «Diagnosticar con IA» abre el chat con la pregunta
// armada, pero NO la envía: cada consulta cuesta y la decide el mecánico.
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { Bot, BadgeCheck, History } from 'lucide-react'
import { getAntecedentesOT } from '@/lib/services/copiloto'

export function AntecedentesOT({ otId, activoId, equipo, online }: {
  otId: string; activoId: string; equipo: string; online: boolean
}) {
  const { data } = useQuery({
    queryKey: ['copiloto-antecedentes', otId],
    queryFn: () => getAntecedentesOT(otId),
    enabled: online,
    staleTime: 5 * 60_000,
  })
  if (!data) return null
  const hay = data.casos.length > 0 || data.historial.length > 0
  const pregunta = data.sintoma
    ? `Diagnostica ${equipo}: ${data.sintoma.slice(0, 300)}. Dame las 3 causas más probables, cuán grave es seguir operando y la prueba más barata para confirmar cada una.`
    : ''
  const urlIA = `/m/taller/copiloto?ot=${otId}&activo=${activoId}&equipo=${encodeURIComponent(equipo)}`
    + (pregunta ? `&q=${encodeURIComponent(pregunta)}` : '')

  if (!hay && !pregunta) return null
  return (
    <div className="rounded-xl border border-indigo-200 bg-indigo-50/60 p-3">
      <p className="flex items-center gap-1.5 text-xs font-bold text-indigo-900">
        <History className="h-3.5 w-3.5" /> Lo que ya se hizo con algo parecido
      </p>
      {!hay && (
        <p className="mt-1 text-[11px] text-indigo-800">
          Todavía no hay casos parecidos en la flota. Al finalizar, anota la causa: así el próximo lo encuentra acá.
        </p>
      )}
      {data.casos.map((c, i) => (
        <div key={i} className="mt-2 rounded-lg bg-white px-2.5 py-2 text-[12px]">
          <div className="flex flex-wrap items-center gap-1.5 text-[10px] text-gray-500">
            <span className="font-semibold text-gray-700">{c.equipo}</span>
            {c.mismo_equipo ? <span className="rounded bg-indigo-100 px-1 text-indigo-800">este equipo</span>
              : c.mismo_modelo ? <span className="rounded bg-indigo-100 px-1 text-indigo-800">mismo modelo</span> : null}
            {c.validado && <span className="inline-flex items-center gap-0.5 rounded bg-green-100 px-1 text-green-800"><BadgeCheck className="h-3 w-3" /> verificado por el jefe</span>}
            {c.fecha && <span>{new Date(`${c.fecha}T12:00:00`).toLocaleDateString('es-CL')}</span>}
          </div>
          <p className="mt-0.5 text-gray-600">{c.sintoma}</p>
          {c.causa && <p className="mt-0.5"><b>Causa:</b> {c.causa}</p>}
          {c.reparacion && <p><b>Se hizo:</b> {c.reparacion}</p>}
        </div>
      ))}
      {data.historial.map((h, i) => (
        <div key={`h${i}`} className="mt-2 rounded-lg bg-white px-2.5 py-1.5 text-[11px] text-gray-700">
          <span className="font-mono text-[10px] text-gray-400">{h.folio} · {h.fecha ? new Date(`${h.fecha}T12:00:00`).toLocaleDateString('es-CL') : ''}</span>
          <p>{h.trabajo}</p>
        </div>
      ))}
      {pregunta && (
        <Link href={urlIA}
              className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-indigo-600 px-3 py-1.5 text-xs font-semibold text-white">
          <Bot className="h-3.5 w-3.5" /> Diagnosticar con IA
        </Link>
      )}
    </div>
  )
}
