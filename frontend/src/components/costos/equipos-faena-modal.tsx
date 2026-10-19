'use client'

import { useQuery } from '@tanstack/react-query'
import { Modal } from '@/components/ui/modal'
import { Spinner } from '@/components/ui/spinner'
import { rpcCostos } from '@/lib/services/costos-operacion'
import { fmtClp, fmtMM, fmtNum } from '@/lib/costos-operacion'
import { fmtFecha, nombreTipo } from '@/components/costos/comunes'
import type { PasoPareto } from '@/components/costos/pareto-modal'

// ============================================================================
// Qué equipos cuenta una faena y por qué (MIG605)
// ----------------------------------------------------------------------------
// «7 equipos en Franke» eran 4 permanentes y 3 de paso. Aquí se ve cada uno:
// días en la faena, desde/hasta, de dónde sale el dato (GPS, estado diario o
// arrastre de la última ubicación conocida), su ficha y cuánto gastó ahí.
// ============================================================================

type EquipoFaena = {
  activo_id: string
  patente: string | null
  tipo: string | null
  faena_ficha: string | null
  dias: number
  desde: string | null
  hasta: string | null
  dias_gps: number
  dias_estado: number
  dias_arrastre: number
  subfaenas: string | null
  costo: number
}

async function getEquiposFaena(desde: string, hasta: string, faena: string, subfaena?: string) {
  const { data, error } = await rpcCostos('rpc_costos_faena_equipos', {
    p_desde: desde, p_hasta: hasta, p_faena: faena, p_subfaena: subfaena ?? null,
  })
  if (error) throw new Error(error.message)
  return data as { dias_periodo: number; equipos: EquipoFaena[] }
}

/** Un equipo «permanente» estuvo al menos la mitad del período en la faena. */
const esPermanente = (e: EquipoFaena, diasPeriodo: number) => e.dias >= diasPeriodo / 2

export function EquiposFaenaModal({ faena, subfaena, desde, hasta, onClose, onPareto }: {
  faena: string; subfaena?: string; desde: string; hasta: string
  onClose: () => void; onPareto: (p: PasoPareto) => void
}) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['costos-faena-equipos', desde, hasta, faena, subfaena ?? null],
    queryFn: () => getEquiposFaena(desde, hasta, faena, subfaena),
    staleTime: 5 * 60_000,
  })
  const dp = data?.dias_periodo ?? 1
  const eq = data?.equipos ?? []
  const perm = eq.filter((e) => esPermanente(e, dp)).length
  const diasEq = eq.reduce((s, e) => s + e.dias, 0)

  return (
    <Modal open onClose={onClose} title={`Equipos en ${subfaena ?? faena}`} className="sm:max-w-5xl"
           description="Todos los equipos que estuvieron en la faena al menos un día del período. Clic en uno: Pareto de su gasto ahí.">
      {isLoading && <div className="flex justify-center py-10"><Spinner /></div>}
      {error && <div className="text-sm text-red-700">{(error as Error).message}</div>}
      {data && (
        <>
          <div className="mb-3 flex flex-wrap gap-x-6 gap-y-1 text-sm">
            <span><b>{eq.length}</b> equipos distintos</span>
            <span><b>{perm}</b> permanentes (≥ la mitad del período) · <b>{eq.length - perm}</b> de paso</span>
            <span><b>{(diasEq / dp).toLocaleString('es-CL', { maximumFractionDigits: 1 })}</b> en promedio
              ({fmtNum(diasEq)} días-equipo ÷ {fmtNum(dp)} días)</span>
          </div>
          <div className="max-h-[60vh] overflow-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-gray-50 text-xs text-gray-600">
                <tr>
                  <th className="px-2 py-1.5 text-left">Equipo</th>
                  <th className="px-2 py-1.5 text-left">Ficha SICOM</th>
                  <th className="px-2 py-1.5 text-right">Días en la faena</th>
                  <th className="px-2 py-1.5 text-left">Desde – hasta</th>
                  <th className="px-2 py-1.5 text-left">De dónde sale el dato</th>
                  <th className="px-2 py-1.5 text-right">Gasto ahí</th>
                  <th className="px-2 py-1.5 text-right">$/día</th>
                </tr>
              </thead>
              <tbody>
                {eq.map((e) => {
                  const perma = esPermanente(e, dp)
                  return (
                    <tr key={e.activo_id} className="cursor-pointer border-t hover:bg-gray-50"
                        onClick={() => onPareto({
                          titulo: `${e.patente ?? '—'} en ${subfaena ?? faena}`,
                          filtros: { faena, ...(subfaena ? { subfaena } : {}), activo_id: e.activo_id },
                          dimension: 'familia',
                        })}>
                      <td className="px-2 py-1.5">
                        <div className="font-medium">{e.patente ?? '—'}
                          <span className={`ml-2 rounded px-1.5 py-0.5 text-[10px] font-medium ${perma ? 'bg-blue-100 text-blue-800' : 'bg-amber-100 text-amber-800'}`}>
                            {perma ? 'permanente' : 'de paso'}
                          </span>
                        </div>
                        <div className="text-xs text-gray-500">{nombreTipo(e.tipo)}</div>
                      </td>
                      <td className="px-2 py-1.5 text-xs">{e.faena_ficha ?? '—'}</td>
                      <td className="px-2 py-1.5 text-right">{fmtNum(e.dias)}</td>
                      <td className="px-2 py-1.5 text-xs">{fmtFecha(e.desde)} – {fmtFecha(e.hasta)}</td>
                      <td className="px-2 py-1.5 text-xs">
                        <Fuente n={e.dias_gps} label="GPS" clase="bg-green-100 text-green-800" />
                        <Fuente n={e.dias_estado} label="estado diario" clase="bg-blue-100 text-blue-800" />
                        <Fuente n={e.dias_arrastre} label="arrastre" clase="bg-gray-100 text-gray-700" />
                      </td>
                      <td className="px-2 py-1.5 text-right font-medium">{fmtMM(e.costo)}</td>
                      <td className="px-2 py-1.5 text-right">{e.dias ? fmtClp(e.costo / e.dias) : '—'}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-xs text-gray-400">
            «GPS»: ese día el GPS lo ubicó en la geocerca de la faena. «Estado diario»: lo dice el estado diario de flota.
            «Arrastre»: ese día no hubo dato y se usó la última ubicación conocida. Un equipo de paso con pocos días suele
            ser una visita (traslado, apoyo) y no cambia el costo de la faena.
          </p>
        </>
      )}
    </Modal>
  )
}

function Fuente({ n, label, clase }: { n: number; label: string; clase: string }) {
  if (!n) return null
  return <span className={`mr-1 inline-block rounded px-1.5 py-0.5 ${clase}`}>{n} {label}</span>
}
