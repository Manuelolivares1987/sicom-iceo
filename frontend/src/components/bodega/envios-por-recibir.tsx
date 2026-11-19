'use client'

// [MIG712] En la faena, «Recibir» parte por lo que mandó Coquimbo: el supervisor
// abre el envío, anota lo que llegó de verdad (viene lleno con lo enviado) y
// confirma. Entra con el costo del envío. Requiere señal (es una sola vez por
// envío y el folio lo amarra a Coquimbo).

import { useCallback, useEffect, useState } from 'react'
import { ChevronDown, ChevronUp, PackageCheck, Truck } from 'lucide-react'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import { nuevoUuid } from '@/lib/services/bodega-faena'
import { getEnvios, recibirEnvio, type Envio } from '@/lib/services/bodega-envios'

const fmt = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 2 }))
const fecha = (s: string) => new Date(s).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' })

export function EnviosPorRecibir({ bodegaId, online, onRecibido }: { bodegaId: string; online: boolean; onRecibido: () => void }) {
  const toast = useToast()
  const [envios, setEnvios] = useState<Envio[] | null>(null)
  const [abierto, setAbierto] = useState<string | null>(null)
  const [cant, setCant] = useState<Record<string, string>>({})
  const [obs, setObs] = useState('')
  const [uuid, setUuid] = useState(nuevoUuid)
  const [guardando, setGuardando] = useState(false)

  const cargar = useCallback(async () => {
    if (!online) return
    try { setEnvios((await getEnvios(bodegaId, true)).filter((e) => e.destino.id === bodegaId && e.estado === 'en_camino')) }
    catch { setEnvios([]) }
  }, [bodegaId, online])
  useEffect(() => { void cargar() }, [cargar])

  function abrir(e: Envio) {
    if (abierto === e.id) { setAbierto(null); return }
    setAbierto(e.id); setObs(''); setUuid(nuevoUuid())
    setCant(Object.fromEntries(e.items.map((i) => [i.producto_id, String(i.enviada)])))
  }

  async function confirmar(e: Envio) {
    const items = e.items.map((i) => ({ producto_id: i.producto_id, cantidad: Number(cant[i.producto_id] ?? i.enviada) }))
    if (items.some((i) => !Number.isFinite(i.cantidad) || i.cantidad < 0)) { toast.error('Hay cantidades inválidas.'); return }
    const mal = e.items.find((i) => Number(cant[i.producto_id]) > i.enviada)
    if (mal) { toast.error(`${mal.nombre}: no puede recibir más de lo enviado (${fmt(mal.enviada)}). Lo que sobre, regístrelo con el lector.`); return }
    const faltan = e.items.filter((i) => Number(cant[i.producto_id]) < i.enviada)
    if (faltan.length && obs.trim().length < 3) { toast.error('Llegó menos de lo enviado: anote qué pasó en la observación.'); return }
    setGuardando(true)
    try {
      const r = await recibirEnvio(e.id, items, obs, uuid)
      toast.success(r.con_diferencia ? `${r.folio} recibido con ${r.con_diferencia} diferencia(s): Coquimbo queda avisado.` : `${r.folio} recibido completo.`)
      setAbierto(null); await cargar(); onRecibido()
    } catch (err) { toast.error(errorMessage(err)) } finally { setGuardando(false) }
  }

  if (!online) return <p className="mx-4 mt-3 rounded-xl border border-gray-200 bg-white p-3 text-xs text-gray-500">Los envíos de Coquimbo se confirman con señal.</p>
  if (!envios || envios.length === 0) return null

  return (
    <section className="mx-4 mt-3 space-y-2">
      <p className="flex items-center gap-1.5 text-sm font-semibold text-blue-900"><Truck className="h-4 w-4" /> {envios.length} envío{envios.length === 1 ? '' : 's'} en camino desde Coquimbo</p>
      {envios.map((e) => (
        <div key={e.id} className="overflow-hidden rounded-xl border border-blue-200 bg-white">
          <button onClick={() => abrir(e)} className="flex w-full items-center justify-between gap-2 px-3 py-3 text-left">
            <span>
              <b className="text-sm">{e.folio}</b> <span className="text-xs text-gray-500">· {e.items.length} productos · {fecha(e.created_at)}</span>
              <span className="block text-xs text-gray-500">{e.creado_por ?? 'Bodega Coquimbo'}{e.guia ? ` · guía ${e.guia}` : ''}</span>
            </span>
            {abierto === e.id ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
          </button>
          {abierto === e.id && (
            <div className="space-y-2 border-t bg-blue-50/40 p-3">
              <p className="text-xs text-gray-600">Revise lo que llegó y corrija si falta algo.</p>
              {e.items.map((i) => {
                const v = cant[i.producto_id] ?? ''
                const menos = Number(v) < i.enviada
                return (
                  <div key={i.producto_id} className={cn('flex items-center justify-between gap-2 rounded-lg border bg-white p-2', menos && 'border-amber-400')}>
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium">{i.nombre}</p>
                      <p className="text-xs text-gray-500">{i.codigo} · enviado {fmt(i.enviada)} {i.unidad}</p>
                    </div>
                    <input type="number" inputMode="decimal" min={0} step="any" value={v} aria-label={`Recibido de ${i.nombre}`}
                           onChange={(ev) => setCant((c) => ({ ...c, [i.producto_id]: ev.target.value }))}
                           className="h-10 w-20 shrink-0 rounded-lg border text-center text-base font-semibold" />
                  </div>
                )
              })}
              <input value={obs} onChange={(ev) => setObs(ev.target.value)} placeholder="Observación (obligatoria si llegó menos)" className="w-full rounded-lg border px-3 py-2.5 text-sm" />
              <button onClick={() => void confirmar(e)} disabled={guardando}
                      className="flex w-full items-center justify-center gap-2 rounded-xl bg-emerald-700 py-3 text-base font-bold text-white disabled:opacity-50">
                <PackageCheck className="h-5 w-5" /> {guardando ? 'Confirmando…' : 'Confirmar recepción'}
              </button>
            </div>
          )}
        </div>
      ))}
      <p className="text-xs text-gray-500">¿Llegó algo que no viene en un envío (compra local)? Escanéelo abajo.</p>
    </section>
  )
}
