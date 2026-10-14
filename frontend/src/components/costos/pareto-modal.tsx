'use client'

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { ChevronRight, Target } from 'lucide-react'
import { Modal } from '@/components/ui/modal'
import { Spinner } from '@/components/ui/spinner'
import {
  getPareto, type DimensionPareto, type FiltrosPareto, type ItemPareto,
} from '@/lib/services/costos-operacion'
import { fmtClp, fmtMM, fmtNum, fmtPct } from '@/lib/costos-operacion'

// ============================================================================
// Pareto con bajada (MIG601)
// ----------------------------------------------------------------------------
// Cualquier clic del panel abre esto. Ranking de mayor a menor; en color los
// ítems que hacen el 80 % (los «pocos vitales»: por ahí se ataca), en gris el
// resto. Clic en una barra o fila = bajar un nivel con ese filtro:
//   faena → subfaena → equipo → familia → producto → líneas de bodega.
// Sin doble eje: el % acumulado va en la tabla y en el tooltip.
// ============================================================================

export type PasoPareto = {
  titulo: string            // lo que se muestra en la miga de pan
  filtros: FiltrosPareto
  dimension: DimensionPareto
}

const NOMBRE_DIM: Record<DimensionPareto, string> = {
  faena: 'Faena', subfaena: 'Subfaena', equipo: 'Equipo', familia: 'Familia',
  producto: 'Producto', centro_costo: 'Centro de costo', mes: 'Mes', linea: 'Líneas',
}

// A qué nivel se baja desde cada dimensión.
const SIGUIENTE: Record<DimensionPareto, DimensionPareto> = {
  faena: 'subfaena', subfaena: 'equipo', equipo: 'familia', familia: 'producto',
  producto: 'linea', centro_costo: 'familia', mes: 'faena', linea: 'linea',
}

// Cómo se convierte la clave del ítem en filtro.
function filtroDe(dim: DimensionPareto, clave: string): FiltrosPareto {
  switch (dim) {
    case 'faena': return { faena: clave }
    case 'subfaena': return { subfaena: clave }
    case 'equipo': return clave.startsWith('cc:') ? { codi_cc: clave.slice(3) } : { activo_id: clave }
    case 'familia': return { familia: clave }
    case 'producto': return { cod_prod: clave }
    case 'centro_costo': return { codi_cc: clave }
    case 'mes': return { mes: clave }
    default: return {}
  }
}

const COLOR_VITAL = '#2563EB'
const COLOR_RESTO = '#CBD5E1'
const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
const etiquetaItem = (dim: DimensionPareto, it: ItemPareto) =>
  dim === 'mes' ? `${MESES[Number(it.clave.slice(5, 7)) - 1]} ${it.clave.slice(2, 4)}` : it.etiqueta

export function ParetoModal({ inicio, desde, hasta, conAdmin, onClose }: {
  inicio: PasoPareto; desde: string; hasta: string; conAdmin?: boolean; onClose: () => void
}) {
  const [pasos, setPasos] = useState<PasoPareto[]>([inicio])
  const paso = pasos[pasos.length - 1]
  const [dim, setDim] = useState<DimensionPareto>(inicio.dimension)

  const { data, isLoading, error } = useQuery({
    queryKey: ['costos-pareto', desde, hasta, conAdmin ?? false, paso.filtros, dim],
    queryFn: () => getPareto({ desde, hasta, filtros: paso.filtros, dimension: dim, conAdmin }),
    staleTime: 5 * 60_000,
  })

  const bajar = (it: ItemPareto) => {
    if (dim === 'linea') return
    const sig = SIGUIENTE[dim]
    setPasos([...pasos, {
      titulo: etiquetaItem(dim, it),
      filtros: { ...paso.filtros, ...filtroDe(dim, it.clave) },
      dimension: sig,
    }])
    setDim(sig)
  }
  const volverA = (i: number) => {
    const p = pasos.slice(0, i + 1)
    setPasos(p)
    setDim(p[p.length - 1].dimension)
  }

  const serie = (data?.items ?? []).map((it, i) => ({
    nombre: etiquetaItem(dim, it), total: Math.round(it.total), it, vital: i < (data?.vitales ?? 0),
  }))

  return (
    <Modal open onClose={onClose} title="Pareto de costos" className="sm:max-w-6xl"
           description="En azul, lo que suma el 80 % del gasto: por ahí conviene atacar. Clic en una barra o fila para bajar un nivel.">
      {/* Miga de pan */}
      <div className="mb-3 flex flex-wrap items-center gap-1 text-sm">
        {pasos.map((p, i) => (
          <span key={i} className="flex items-center gap-1">
            {i > 0 && <ChevronRight className="h-3.5 w-3.5 text-gray-400" />}
            <button onClick={() => volverA(i)}
                    className={`rounded px-2 py-0.5 ${i === pasos.length - 1 ? 'bg-pillado-green-100 font-semibold text-pillado-green-800' : 'text-gray-600 hover:bg-gray-100'}`}>
              {p.titulo}
            </button>
          </span>
        ))}
      </div>

      {/* Cambiar el corte sin bajar */}
      <div className="mb-3 flex flex-wrap gap-1">
        {(['subfaena', 'equipo', 'familia', 'producto', 'centro_costo', 'mes', 'linea'] as DimensionPareto[]).map((d) => (
          <button key={d} onClick={() => setDim(d)}
                  className={`rounded-full px-3 py-1 text-xs font-medium ${dim === d ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'}`}>
            Por {NOMBRE_DIM[d].toLowerCase()}
          </button>
        ))}
      </div>

      {isLoading && <div className="flex justify-center py-12"><Spinner /></div>}
      {error && <div className="text-sm text-red-700">{(error as Error).message}</div>}

      {data && dim === 'linea' && <TablaLineas lineas={data.lineas ?? []} total={data.total} />}

      {data && dim !== 'linea' && (
        <>
          <div className="mb-2 flex flex-wrap items-center gap-x-6 gap-y-1 text-sm">
            <span className="flex items-center gap-1.5 font-medium text-gray-900">
              <Target className="h-4 w-4 text-pillado-green-600" />
              {data.vitales} de {data.n} {NOMBRE_DIM[dim].toLowerCase()}s hacen el 80 % del gasto
            </span>
            <span className="text-gray-500">Total {fmtClp(data.total)}</span>
          </div>

          <div style={{ width: '100%', height: 260 }}>
            <ResponsiveContainer>
              <BarChart data={serie} margin={{ top: 5, right: 5, left: 10, bottom: 60 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                <XAxis dataKey="nombre" tick={{ fontSize: 10 }} interval={0} angle={-40} textAnchor="end" height={70} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `${(v / 1e6).toLocaleString('es-CL', { maximumFractionDigits: 1 })} M`} />
                <Tooltip cursor={{ fill: '#F3F4F6' }}
                         formatter={(v: number, _n, p) => [
                           `${fmtClp(v)} · ${fmtPct((p?.payload as { it: ItemPareto }).it.pct)} · acumulado ${fmtPct((p?.payload as { it: ItemPareto }).it.pct_acum)}`,
                           'Gasto']} />
                <Bar dataKey="total" radius={[4, 4, 0, 0]} className="cursor-pointer"
                     onClick={(d: { it?: ItemPareto }) => d?.it && bajar(d.it)}>
                  {serie.map((s, i) => <Cell key={i} fill={s.vital ? COLOR_VITAL : COLOR_RESTO} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>

          <div className="max-h-[38vh] overflow-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-gray-50 text-xs text-gray-600">
                <tr>
                  <th className="px-2 py-1.5 text-left">#</th>
                  <th className="px-2 py-1.5 text-left">{NOMBRE_DIM[dim]}</th>
                  <th className="px-2 py-1.5 text-right">Gasto</th>
                  <th className="px-2 py-1.5 text-right">%</th>
                  <th className="px-2 py-1.5 text-right">% acumulado</th>
                  <th className="px-2 py-1.5 text-right">Líneas</th>
                  <th className="px-2 py-1.5" />
                </tr>
              </thead>
              <tbody>
                {data.items.map((it, i) => {
                  const vital = i < data.vitales
                  return (
                    <tr key={it.clave} onClick={() => bajar(it)}
                        className={`cursor-pointer border-t hover:bg-gray-50 ${vital ? '' : 'text-gray-500'}`}>
                      <td className="px-2 py-1">{i + 1}</td>
                      <td className="px-2 py-1">
                        <span className="flex items-center gap-2">
                          <i className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: vital ? COLOR_VITAL : COLOR_RESTO }} />
                          {etiquetaItem(dim, it)}
                        </span>
                      </td>
                      <td className="px-2 py-1 text-right font-medium">{fmtMM(it.total)}</td>
                      <td className="px-2 py-1 text-right">{fmtPct(it.pct)}</td>
                      <td className="px-2 py-1 text-right">{fmtPct(it.pct_acum)}</td>
                      <td className="px-2 py-1 text-right">{fmtNum(it.lineas)}</td>
                      <td className="px-2 py-1 text-right text-xs text-pillado-green-700">
                        ver {NOMBRE_DIM[SIGUIENTE[dim]].toLowerCase()} ›
                      </td>
                    </tr>
                  )
                })}
                {data.resto.n > 0 && (
                  <tr className="border-t text-gray-400">
                    <td />
                    <td className="px-2 py-1">{data.resto.n} más</td>
                    <td className="px-2 py-1 text-right">{fmtMM(data.resto.total)}</td>
                    <td colSpan={4} />
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </>
      )}
    </Modal>
  )
}

function TablaLineas({ lineas, total }: {
  lineas: NonNullable<Awaited<ReturnType<typeof getPareto>>['lineas']>; total: number
}) {
  return (
    <>
      <div className="mb-2 text-sm text-gray-600">
        Salidas de bodega Softland, de mayor a menor (máx. 300) · total {fmtClp(total)}
      </div>
      <div className="max-h-[60vh] overflow-auto">
        <table className="w-full text-xs">
          <thead className="sticky top-0 bg-gray-50 text-gray-600">
            <tr>
              <th className="px-2 py-1.5 text-left">Fecha</th>
              <th className="px-2 py-1.5 text-left">Folio</th>
              <th className="px-2 py-1.5 text-left">Equipo / CC</th>
              <th className="px-2 py-1.5 text-left">Subfaena</th>
              <th className="px-2 py-1.5 text-left">Producto</th>
              <th className="px-2 py-1.5 text-right">Cant.</th>
              <th className="px-2 py-1.5 text-right">Precio</th>
              <th className="px-2 py-1.5 text-right">Total</th>
              <th className="px-2 py-1.5 text-left">Glosa</th>
            </tr>
          </thead>
          <tbody>
            {lineas.map((l, i) => (
              <tr key={i} className={`border-t ${l.total === 0 ? 'bg-amber-50' : ''}`}>
                <td className="px-2 py-1">{l.fecha}</td>
                <td className="px-2 py-1">{l.folio}{l.concepto === '08' ? ' (EPP)' : ''}</td>
                <td className="px-2 py-1">{l.patente ?? l.codi_cc ?? '—'}</td>
                <td className="px-2 py-1">{l.subfaena ?? '—'}</td>
                <td className="px-2 py-1">{l.des_prod} <span className="text-gray-400">{l.cod_prod}</span></td>
                <td className="px-2 py-1 text-right">{fmtNum(l.cantidad)}</td>
                <td className="px-2 py-1 text-right">{fmtClp(l.precio_unit)}</td>
                <td className="px-2 py-1 text-right font-medium">{fmtClp(l.total)}</td>
                <td className="px-2 py-1 text-gray-500">{l.glosa}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}
