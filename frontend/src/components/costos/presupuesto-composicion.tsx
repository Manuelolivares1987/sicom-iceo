'use client'

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { fmtClp } from '@/lib/costos-operacion'
import { getComposicionEquipoPpto, type ComposicionEquipoPpto } from '@/lib/services/presupuesto'

// ============================================================================
// Composición de un equipo (MIG706): real por componente año a año y qué compras
// forman su correctivo y su overhaul, para entender la diferencia con años
// anteriores y con Comercial.
// ============================================================================

const COMPONENTES: { k: 'A1' | 'A2' | 'A3' | 'A4' | 'B4'; nombre: string }[] = [
  { k: 'A1', nombre: 'Preventivo' }, { k: 'A2', nombre: 'Correctivo' }, { k: 'A3', nombre: 'Neumáticos' },
  { k: 'A4', nombre: 'Overhaul / mayores' }, { k: 'B4', nombre: 'TC8 y certificaciones' },
]
const fmtM = (v: number) => (v / 1e6).toLocaleString('es-CL', { minimumFractionDigits: 1, maximumFractionDigits: 1 })
const fechaCorta = (iso: string) => `${iso.slice(8, 10)}-${iso.slice(5, 7)}-${iso.slice(2, 4)}`

export function ComposicionEquipo({ patente }: { patente: string }) {
  const { data, isLoading } = useQuery({ queryKey: ['ppto-composicion', patente], queryFn: () => getComposicionEquipoPpto(patente) })
  const [verCompras, setVerCompras] = useState(false)
  const [verNeu, setVerNeu] = useState(false)
  if (isLoading) return <p className="text-xs text-gray-500">Cargando composición…</p>
  if (!data) return null
  const d: ComposicionEquipoPpto = data
  const v = (x: number | null | undefined) => (x ? fmtM(Number(x)) : '—')
  const incluidas = d.correctivo_categorias.filter((x) => !x.excluida)
  const excluidas = d.correctivo_categorias.filter((x) => x.excluida)
  const baseAnual = incluidas.reduce((s, x) => s + Number(x.monto_2026), 0) / 2
  const th = 'px-2 py-1.5 text-right font-medium'

  return (
    <div className="grid gap-4 text-xs text-gray-700 xl:grid-cols-2">
      <div>
        <p className="mb-1 font-semibold text-gray-900">Real contra presupuesto, en millones</p>
        <table className="w-full border text-xs">
          <thead className="bg-gray-50 text-gray-500">
            <tr>
              <th className="px-2 py-1.5 text-left font-medium">Componente</th>
              <th className={th}>2023</th><th className={th}>2024</th><th className={th}>2025</th>
              <th className={th}>2026 a {fechaCorta(d.corte).slice(3)}</th>
              <th className={`${th} bg-pillado-green-50 text-pillado-green-800`}>PPTO 2027</th>
              <th className={th}>2028</th><th className={th}>2029</th>
            </tr>
          </thead>
          <tbody>
            {COMPONENTES.map((x) => (
              <tr key={x.k} className="border-t">
                <td className="px-2 py-1">{x.nombre}</td>
                {['2023', '2024', '2025', '2026'].map((y) => <td key={y} className="px-2 py-1 text-right text-gray-600">{v(d.real[x.k]?.[y])}</td>)}
                <td className="bg-pillado-green-50 px-2 py-1 text-right font-semibold">{v(d.ppto?.[x.k]?.['2027'])}</td>
                <td className="px-2 py-1 text-right">{v(d.ppto?.[x.k]?.['2028'])}</td>
                <td className="px-2 py-1 text-right">{v(d.ppto?.[x.k]?.['2029'])}</td>
              </tr>
            ))}
          </tbody>
        </table>

        <p className="mb-1 mt-4 font-semibold text-gray-900">¿Qué se toma como overhaul / reparación mayor?</p>
        {d.overhaul_2027.length ? (
          <ul className="list-disc pl-4">
            {d.overhaul_2027.map((o, i) => (
              <li key={i}>
                {o.anio} · {o.descripcion}: <b>{fmtClp(o.monto)}</b>
                {o.gatillo && <span className="text-gray-500"> — condición: {o.gatillo}</span>}
              </li>
            ))}
          </ul>
        ) : <p>Nada programado para este equipo en 2027-2029.</p>}
        <p className="mt-1 text-gray-500">
          Se programa por equipo (lista editable en «Supuestos y programas») o por horómetro (componentes de la pauta, como DPF o C9000).
          {d.overhaul_historia.length > 0
            ? ` Historial de reparaciones de $2,5 MM o más: ${d.overhaul_historia.map((h) => `${fechaCorta(h.fecha)} ${h.descripcion ?? ''} ${fmtClp(h.monto)}`).join(' · ')}.`
            : ' Sin reparaciones de $2,5 MM o más desde 2023.'}
        </p>
      </div>

      <div>
        <p className="mb-1 font-semibold text-gray-900">¿Qué se toma como correctivo?</p>
        <p className="mb-1">
          Compras cargadas al equipo entre el {fechaCorta(d.ventana_desde)} y el {fechaCorta(d.corte)} (24 meses), de menos de $2,5 MM cada una,
          sin filtros, lubricantes ni neumáticos. Base anual: <b>{fmtClp(baseAnual)}</b> (pesos 2026, antes del ajuste por edad e IPC).
        </p>
        <table className="w-full border text-xs">
          <tbody>
            {incluidas.map((x) => (
              <tr key={x.categoria} className="border-t">
                <td className="px-2 py-1">{x.categoria} <span className="text-gray-400">({x.n})</span></td>
                <td className="px-2 py-1 text-right">{fmtClp(x.monto)}</td>
              </tr>
            ))}
            {excluidas.map((x) => (
              <tr key={x.categoria} className="border-t text-gray-400 line-through">
                <td className="px-2 py-1">{x.categoria} ({x.n})</td>
                <td className="px-2 py-1 text-right">{fmtClp(x.monto)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {excluidas.length > 0 && (
          <p className="mt-1 text-gray-500">Tachado: mantención preventiva en taller o concesionario; no entra al correctivo porque el preventivo por pauta ya la cuenta.</p>
        )}
        <button type="button" className="mt-1 text-pillado-green-700 underline" onClick={() => setVerCompras(!verCompras)}>
          {verCompras ? 'Ocultar compras' : `Ver las ${d.correctivo_compras.length} compras`}
        </button>
        <button type="button" className="ml-3 mt-1 text-pillado-green-700 underline" onClick={() => setVerNeu(!verNeu)}>
          {verNeu ? 'Ocultar neumáticos' : `Ver neumáticos de 36 meses (${d.neumaticos_compras.length})`}
        </button>
        {verCompras && (
          <div className="mt-1 max-h-64 overflow-auto rounded border">
            <table className="w-full text-xs">
              <thead className="sticky top-0 bg-gray-50 text-gray-500">
                <tr>
                  <th className="px-2 py-1 text-left">Fecha</th><th className="px-2 py-1 text-left">Proveedor</th>
                  <th className="px-2 py-1 text-left">Descripción</th><th className="px-2 py-1 text-left">Categoría</th>
                  <th className="px-2 py-1 text-right">Monto</th>
                </tr>
              </thead>
              <tbody>
                {d.correctivo_compras.map((x, i) => (
                  <tr key={i} className={`border-t ${x.excluida ? 'text-gray-400 line-through' : ''}`}>
                    <td className="whitespace-nowrap px-2 py-1">{fechaCorta(x.fecha)}</td>
                    <td className="px-2 py-1">{x.proveedor}</td>
                    <td className="px-2 py-1">{x.descripcion}</td>
                    <td className="px-2 py-1 text-gray-500">{x.categoria}</td>
                    <td className="whitespace-nowrap px-2 py-1 text-right">{fmtClp(x.monto)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {verNeu && (
          <ul className="mt-1 max-h-40 list-disc overflow-auto pl-4">
            {d.neumaticos_compras.map((x, i) => <li key={i}>{fechaCorta(x.fecha)} · {x.proveedor} · {x.descripcion}: {fmtClp(x.monto)}</li>)}
          </ul>
        )}
      </div>
    </div>
  )
}
