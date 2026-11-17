'use client'

import { Fragment, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ChevronDown, ChevronRight, Download } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { fmtClp, fmtNum } from '@/lib/costos-operacion'
import { getCamionesDetallePpto, getParametrosExcelPpto, type CamionDetallePpto } from '@/lib/services/presupuesto'
import { ComposicionEquipo } from '@/components/costos/presupuesto-composicion'

// ============================================================================
// Presupuesto por camión (MIG702): primero los contratos de servicio de Pillado,
// que se mantienen en terreno, y después el resto de la flota por familia. Por
// equipo: real 2023-2025, 2026 a la fecha y proyectado 2027, con su base.
// ============================================================================

type Camion = CamionDetallePpto
type Grupo = { clave: string; titulo: string; nota?: string; filas: Camion[] }

const fmtM = (v: number) => (v / 1e6).toLocaleString('es-CL', { minimumFractionDigits: 1, maximumFractionDigits: 1 })
const total27 = (c: Camion) => c.preventivo + c.correctivo + c.neumaticos + c.mayores + (c.certificaciones ?? 0)
const sumar = (fs: Camion[], f: (c: Camion) => number) => fs.reduce((a, c) => a + f(c), 0)
const ORDEN_CONTRATO = ['Romeral', 'Franke', 'Calama ENEX']
const fmtH = (v: number) => v.toLocaleString('es-CL', { maximumFractionDigits: 1 })
const MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']

/** Regla (MIG703): el mayor entre el promedio de 18 meses y el mejor mes completo de GPS. */
function origenRitmo(b: CamionDetallePpto['base']): string {
  const larga = b.ritmo_18m != null ? `promedio 18 meses ${fmtH(b.ritmo_18m)} h/día` : 'sin lecturas de 18 meses'
  const mes = b.ritmo_mejor_mes != null && b.mejor_mes
    ? `mejor mes GPS ${fmtH(b.ritmo_mejor_mes)} h/día (${MES[Number(b.mejor_mes.slice(5, 7)) - 1]} ${b.mejor_mes.slice(0, 4)})`
    : 'sin mes completo de GPS'
  return `Se toma el mayor entre ${larga} y ${mes}.`
}

const NIVEL_TIPO: Record<string, string> = { pauta: 'Pauta', componente: 'Componente', anual: 'Servicio anual' }

export function PresupuestoPorCamion() {
  const { data, isLoading, error } = useQuery({ queryKey: ['ppto-camiones-detalle'], queryFn: getCamionesDetallePpto })
  const [abierto, setAbierto] = useState<string | null>(null)
  const [cerrados, setCerrados] = useState<Set<string>>(new Set())
  const [bajando, setBajando] = useState(false)
  const [errorExcel, setErrorExcel] = useState<string | null>(null)

  async function descargarExcel() {
    if (!data) return
    setBajando(true); setErrorExcel(null)
    try {
      const [{ exportarPresupuestoExcel }, parametros] = await Promise.all([import('@/lib/export/presupuesto-excel'), getParametrosExcelPpto()])
      const blob = await exportarPresupuestoExcel(parametros, data)
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `Presupuesto mantencion 2027 por equipo (${new Date().toISOString().slice(0, 10)}).xlsx`
      a.click()
      URL.revokeObjectURL(url)
    } catch (e) {
      setErrorExcel((e as Error).message)
    } finally {
      setBajando(false)
    }
  }

  const secciones = useMemo(() => {
    const fs = data ?? []
    const porTotal = (a: Camion, b: Camion) => total27(b) - total27(a)
    const contratos: Grupo[] = ORDEN_CONTRATO
      .concat(Array.from(new Set(fs.map((c) => c.contrato).filter((x): x is string => !!x && !ORDEN_CONTRATO.includes(x)))))
      .map((k) => ({ clave: `c:${k}`, titulo: k, nota: 'Contrato de servicio: mantención en terreno', filas: fs.filter((c) => c.contrato === k).sort(porTotal) }))
      .filter((g) => g.filas.length)
    const flota = fs.filter((c) => !c.contrato)
    const familias: Grupo[] = Array.from(new Set(flota.map((c) => c.familia)))
      .map((k) => ({ clave: `f:${k}`, titulo: k, filas: flota.filter((c) => c.familia === k).sort(porTotal) }))
      .sort((a, b) => sumar(b.filas, total27) - sumar(a.filas, total27))
    return [
      { titulo: 'Contratos de servicio Pillado', grupos: contratos },
      { titulo: 'Flota por familia', grupos: familias },
    ]
  }, [data])

  if (isLoading) return <p className="text-sm text-gray-500">Cargando…</p>
  if (error || !data) return <p className="text-sm text-red-600">No se pudo cargar: {(error as Error)?.message}</p>

  const todos = data
  const alternar = (k: string) => setCerrados((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n })
  const th = 'px-2 py-2 text-right'
  const celdas = (fs: Camion[], fuerte = false) => {
    const cls = `px-2 py-1.5 text-right ${fuerte ? 'font-semibold text-gray-900' : 'text-gray-600'}`
    return (
      <>
        {(['2023', '2024', '2025', '2026'] as const).map((y) => <td key={y} className={cls}>{fmtM(sumar(fs, (c) => c.real[y]))}</td>)}
        <td className={`border-l bg-pillado-green-50 px-2 py-1.5 text-right font-semibold text-pillado-green-800`}>{fmtM(sumar(fs, total27))}</td>
        <td className={cls}>{fmtM(sumar(fs, (c) => c.preventivo))}</td>
        <td className={cls}>{fmtM(sumar(fs, (c) => c.correctivo))}</td>
        <td className={cls}>{fmtM(sumar(fs, (c) => c.neumaticos))}</td>
        <td className={cls}>{fmtM(sumar(fs, (c) => c.mayores))}</td>
        <td className={cls}>{fmtM(sumar(fs, (c) => c.certificaciones ?? 0))}</td>
      </>
    )
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <CardTitle className="text-base">Mantención por equipo, en millones de pesos</CardTitle>
          <Button variant="outline" size="sm" disabled={bajando} onClick={descargarExcel}>
            <Download className="mr-1.5 h-4 w-4" />{bajando ? 'Armando Excel…' : 'Descargar Excel con fórmulas'}
          </Button>
        </div>
        {errorExcel && <p className="text-xs text-red-600">No se pudo armar el Excel: {errorExcel}</p>}
        <p className="text-xs text-gray-500">
          Real: lo cargado directo al equipo en Softland (2026 hasta hoy). Proyectado 2027 = preventivo por pauta + correctivo + neumáticos + reparaciones mayores + certificaciones por vencimiento (TC8 y pluma).
          Toca un equipo para ver en qué se basa su proyectado. No incluye los repuestos y talleres sin patente.
        </p>
      </CardHeader>
      <CardContent className="max-h-[720px] overflow-auto p-0">
        <table className="w-full min-w-[1080px] text-sm">
          <thead className="sticky top-0 z-10 bg-gray-50 text-xs text-gray-500">
            <tr>
              <th className="px-3 py-2 text-left">Equipo</th>
              <th className={th}>2023</th><th className={th}>2024</th><th className={th}>2025</th><th className={th}>2026 a hoy</th>
              <th className="border-l bg-pillado-green-50 px-2 py-2 text-right text-pillado-green-800">Proyectado 2027</th>
              <th className={th}>Preventivo</th><th className={th}>Correctivo</th><th className={th}>Neumáticos</th><th className={th}>Overhaul / mayores</th><th className={th} title="TC8 y certificación de pluma">TC8 y cert.</th>
              <th className="px-3 py-2 text-left">Base del proyectado</th>
            </tr>
          </thead>
          <tbody>
            {secciones.map((s) => (
              <Fragment key={s.titulo}>
                <tr className="border-t-2 border-gray-300 bg-gray-100 text-gray-900">
                  <td className="px-3 py-2 font-bold">{s.titulo} <span className="font-normal text-gray-500">({sumar(s.grupos.flatMap((g) => g.filas), () => 1)})</span></td>
                  {celdas(s.grupos.flatMap((g) => g.filas), true)}
                  <td />
                </tr>
                {s.grupos.map((g) => {
                  const cerrado = cerrados.has(g.clave)
                  return (
                    <Fragment key={g.clave}>
                      <tr className="cursor-pointer border-t bg-gray-50 hover:bg-gray-100" onClick={() => alternar(g.clave)}>
                        <td className="px-3 py-1.5 font-semibold text-gray-800">
                          <span className="inline-flex items-center gap-1">
                            {cerrado ? <ChevronRight className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                            {g.titulo} <span className="font-normal text-gray-500">({g.filas.length})</span>
                          </span>
                          {g.nota && <span className="block pl-5 text-xs font-normal text-gray-500">{g.nota}</span>}
                        </td>
                        {celdas(g.filas, true)}
                        <td />
                      </tr>
                      {!cerrado && g.filas.map((c) => (
                        <Fragment key={c.patente}>
                          <tr className="cursor-pointer border-t hover:bg-gray-50" onClick={() => setAbierto(abierto === c.patente ? null : c.patente)}>
                            <td className="whitespace-nowrap py-1.5 pl-9 pr-3">
                              <span className="font-medium text-gray-900">{c.patente}</span>
                              <span className="ml-1.5 text-xs text-gray-500">{[c.codigo, c.modelo, c.anio_fab].filter(Boolean).join(' · ')}</span>
                              {c.faena && <span className="block text-xs text-gray-400">{c.faena}</span>}
                            </td>
                            {celdas([c])}
                            <td className="px-3 py-1.5 text-xs text-gray-600">{resumenBase(c)}</td>
                          </tr>
                          {abierto === c.patente && (
                            <tr className="border-t bg-pillado-green-50/40">
                              <td colSpan={12} className="space-y-4 px-9 py-3"><DetalleBase c={c} /><ComposicionEquipo patente={c.patente} /></td>
                            </tr>
                          )}
                        </Fragment>
                      ))}
                    </Fragment>
                  )
                })}
              </Fragment>
            ))}
            <tr className="border-t-2 border-gray-400 font-bold text-gray-900">
              <td className="px-3 py-2">Total equipos ({todos.length})</td>
              {celdas(todos, true)}
              <td />
            </tr>
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}

function resumenBase(c: Camion): string {
  const b = c.base
  const pautas = b.visitas.filter((v) => v.tipo === 'pauta').reduce((a, v) => a + v.n, 0)
  const partes = [
    b.con_pauta ? `Pauta cada ${fmtNum(b.intervalo_horas ?? 0)} h · ${pautas} visita${pautas === 1 ? '' : 's'} en 2027` : 'Sin pauta: gasto real',
    `${b.ritmo.toLocaleString('es-CL', { maximumFractionDigits: 1 })} h/día`,
  ]
  if (b.factor_edad != null && b.factor_edad !== 1) partes.push(`edad ×${b.factor_edad.toLocaleString('es-CL')}`)
  if (b.mayores.length) partes.push(`${b.mayores.length} reparación${b.mayores.length === 1 ? '' : 'es'} mayor${b.mayores.length === 1 ? '' : 'es'}`)
  return partes.join(' · ')
}

function DetalleBase({ c }: { c: Camion }) {
  const b = c.base
  const pautas = b.visitas.filter((v) => v.tipo !== 'componente')
  return (
    <div className="grid gap-4 text-xs text-gray-700 md:grid-cols-2 xl:grid-cols-4">
      <div>
        <p className="mb-1 font-semibold text-gray-900">Preventivo 2027: {fmtClp(c.preventivo)}</p>
        {b.con_pauta ? (
          <>
            <p>Pauta del fabricante ({b.grupo_kit}) cada {fmtNum(b.intervalo_horas ?? 0)} h.</p>
            <p>Horómetro {fmtNum(b.horometro)} h, ritmo {fmtH(b.ritmo)} h/día ({b.ritmo_fuente}): unas {fmtNum(b.horas_2027)} h en 2027.</p>
            <p className="text-gray-500">{origenRitmo(b)}</p>
            <ul className="mt-1 list-disc pl-4">
              {pautas.map((v) => (
                <li key={`${v.tipo}${v.nivel}`}>{NIVEL_TIPO[v.tipo]} {v.tipo === 'anual' ? '' : v.nivel} × {v.n}: {fmtClp(v.costo)} <span className="text-gray-500">(kit completo {fmtClp(v.kit)})</span></li>
              ))}
              {pautas.length === 0 && <li>Sin visitas en 2027 con este ritmo.</li>}
            </ul>
            <p className="mt-1 text-gray-500">Entra solo filtros y lubricantes del kit; el resto del kit ya está en el correctivo real.</p>
          </>
        ) : (
          <p>Sin pauta cargada en SICOM: su mantención va dentro del correctivo, según su gasto real.</p>
        )}
      </div>
      <div>
        <p className="mb-1 font-semibold text-gray-900">Correctivo 2027: {fmtClp(c.correctivo)}</p>
        <p>Promedio real de los últimos 24 meses: {fmtClp(b.correctivo_base)} al año.</p>
        {b.factor_edad != null ? (
          <p>Ajuste por edad: ×{b.factor_edad.toLocaleString('es-CL')} (edad equivalente {b.edad_equivalente?.toLocaleString('es-CL')} años: la mayor entre años de fabricación y horas ÷ 2.500).</p>
        ) : (
          <p>Sin ajuste por edad: la curva se midió en camiones pesados.</p>
        )}
        {b.piso_correctivo != null && <p>Piso de camión joven: al menos {fmtClp(b.piso_correctivo)}.</p>}
        {(b.partidas_correctivo ?? []).map((x, i) => <p key={i}>+ {x.descripcion}: {fmtClp(x.monto)} (proveedores de la grúa, 2026 llevado a 12 meses, sobre lo que ya trae el promedio).</p>)}
        <p className="text-gray-500">Más IPC 2027.</p>
      </div>
      <div>
        <p className="mb-1 font-semibold text-gray-900">Neumáticos 2027: {fmtClp(c.neumaticos)}</p>
        <p>Promedio real de los últimos 36 meses: {fmtClp(b.neumatico_base)} al año.</p>
        {b.neumatico_piso != null && <p>Con uso y 2 o más años de edad equivalente lleva al menos {fmtClp(b.neumatico_piso)} (gasto típico de la flota).</p>}
        <p className="text-gray-500">Más IPC 2027.</p>
      </div>
      <div>
        <p className="mb-1 font-semibold text-gray-900">Reparaciones mayores 2027: {fmtClp(c.mayores)}</p>
        {b.mayores.length ? (
          <ul className="list-disc pl-4">{b.mayores.map((m, i) => <li key={i}>{m.descripcion}: {fmtClp(m.monto)}</li>)}</ul>
        ) : (
          <p>Ninguna en 2027 para este equipo.</p>
        )}
        {(b.certificaciones ?? []).length > 0 && (
          <>
            <p className="mb-1 mt-3 font-semibold text-gray-900">Certificaciones por vencimiento</p>
            <ul className="list-disc pl-4">{b.certificaciones.map((x, i) => <li key={i}>{x.anio} · {x.descripcion}: {fmtClp(x.monto)}</li>)}</ul>
          </>
        )}
        <p className="mt-2 text-gray-500">Mantención proyectada 2028: {fmtClp(c.total_2028)} · 2029: {fmtClp(c.total_2029)}</p>
      </div>
    </div>
  )
}
