'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, Search, Filter, X, AlertTriangle, RefreshCw, Calendar, Truck,
  Camera, Fuel, Download, Building2, DollarSign,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  cargarVentasExternasComercial, nombreClienteVenta,
} from '@/lib/services/combustible-comercial'
import type { TransaccionCombustibleCliente } from '@/lib/services/portal-cliente'

// Patente del despacho: vehiculo externo o activo propio (las ventas a cliente
// manual pueden no tener patente registrada).
function patenteVenta(r: TransaccionCombustibleCliente): string | null {
  return r.externo_patente ?? r.activo_patente ?? null
}

function fmtCLP(n: number | null) {
  if (n == null) return '—'
  return n.toLocaleString('es-CL', { style: 'currency', currency: 'CLP', maximumFractionDigits: 0 })
}
function fmtLt(n: number | null | undefined) {
  if (n == null) return '—'
  return `${n.toLocaleString('es-CL', { maximumFractionDigits: 1 })} L`
}
function todayISO()       { return new Date().toISOString().slice(0, 10) }
function hace30diasISO()  {
  const d = new Date(); d.setDate(d.getDate() - 30); return d.toISOString().slice(0, 10)
}
// Registros antiguos se guardaban como fecha-solo a medianoche UTC (sin hora real);
// para esos mostramos el día calendario en UTC y NO restamos la zona horaria
// (Chile UTC-4 corría el día anterior). Los registros nuevos llevan hora real
// (NOW()): para esos mostramos fecha + hora en horario de Chile.
function fmtFecha(iso: string) {
  const d = new Date(iso)
  const esFechaSolo = d.getUTCHours() === 0 && d.getUTCMinutes() === 0 && d.getUTCSeconds() === 0
  if (esFechaSolo) {
    return d.toLocaleDateString('es-CL', {
      timeZone: 'UTC', day: '2-digit', month: '2-digit', year: 'numeric',
    })
  }
  return d.toLocaleString('es-CL', {
    timeZone: 'America/Santiago',
    day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

export default function ComercialVentasCombustiblePage() {
  useRequireAuth()
  const [rows, setRows]         = useState<TransaccionCombustibleCliente[]>([])
  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState<string | null>(null)

  const [fechaDesde, setFechaDesde] = useState(hace30diasISO())
  const [fechaHasta, setFechaHasta] = useState(todayISO())
  const [patente, setPatente]       = useState('')
  const [empresa, setEmpresa]       = useState('')
  const [seleccion, setSeleccion]   = useState<TransaccionCombustibleCliente | null>(null)

  const cargar = async () => {
    setError(null); setLoading(true)
    try {
      const data = await cargarVentasExternasComercial({ fechaDesde, fechaHasta, patente, empresa })
      setRows(data)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    const t = setTimeout(cargar, 300)
    return () => clearTimeout(t)
    /* eslint-disable-next-line react-hooks/exhaustive-deps */
  }, [fechaDesde, fechaHasta, patente, empresa])

  // Agregados para encabezado: total a cobrar, litros, transacciones, empresas
  const stats = useMemo(() => {
    const empresas = new Set<string>()
    const patentes = new Set<string>()
    let litros = 0, totalVenta = 0, costoCpp = 0, sinPrecio = 0
    for (const r of rows) {
      litros     += Number(r.litros)
      totalVenta += Number(r.total_venta_clp ?? 0)
      costoCpp   += Number(r.costo_total_clp ?? 0)
      if (r.precio_venta_clp_lt == null) sinPrecio++
      empresas.add(nombreClienteVenta(r))
      const pat = patenteVenta(r)
      if (pat) patentes.add(pat)
    }
    return {
      despachos: rows.length,
      litros,
      total_a_cobrar: totalVenta,
      costo_propio:   costoCpp,
      margen:         totalVenta - costoCpp,
      empresas: empresas.size,
      patentes: patentes.size,
      sin_precio: sinPrecio,
    }
  }, [rows])

  // Agregado por empresa para preparar la facturacion
  const porEmpresa = useMemo(() => {
    const m = new Map<string, { despachos: number; litros: number; total: number; sin_precio: number }>()
    for (const r of rows) {
      const e = nombreClienteVenta(r)
      if (!m.has(e)) m.set(e, { despachos: 0, litros: 0, total: 0, sin_precio: 0 })
      const g = m.get(e)!
      g.despachos += 1
      g.litros    += Number(r.litros)
      g.total     += Number(r.total_venta_clp ?? 0)
      if (r.precio_venta_clp_lt == null) g.sin_precio++
    }
    return Array.from(m.entries())
      .map(([empresa, g]) => ({ empresa, ...g }))
      .sort((a, b) => b.total - a.total)
  }, [rows])

  const exportarCSV = () => {
    if (rows.length === 0) return
    const sep = ';'
    const esc = (v: unknown) => {
      if (v == null) return ''
      const s = String(v).replace(/"/g, '""')
      return /[";\n\r]/.test(s) ? `"${s}"` : s
    }
    const fmtNum = (n: number | null | undefined) =>
      n == null ? '' : String(n).replace('.', ',')

    const headers = [
      'Fecha', 'Guia/Folio', 'Documento', 'Cliente', 'Patente', 'Estanque', 'Litros',
      'Lectura inicial', 'Lectura final',
      'Precio venta CLP/lt', 'Total a cobrar CLP', 'Costo CPP CLP', 'Margen CLP',
      'Receptor', 'RUT', 'Kilometraje',
      'Observaciones', 'Foto medidor inicial', 'Foto medidor final',
      'Foto patente', 'Firma receptor',
    ]
    const lines = [
      headers.join(sep),
      ...rows.map((r) => {
        const total = Number(r.total_venta_clp ?? 0)
        const cpp = Number(r.costo_total_clp ?? 0)
        return [
          fmtFecha(r.fecha),
          r.folio_movimiento ?? '',
          r.documento_numero ?? '',
          nombreClienteVenta(r),
          patenteVenta(r) ?? '',
          r.estanque_codigo ?? '',
          fmtNum(Number(r.litros)),
          fmtNum(r.lectura_inicial_lt != null ? Number(r.lectura_inicial_lt) : null),
          fmtNum(r.lectura_final_lt != null ? Number(r.lectura_final_lt) : null),
          fmtNum(r.precio_venta_clp_lt != null ? Number(r.precio_venta_clp_lt) : null),
          fmtNum(total),
          fmtNum(cpp),
          fmtNum(total - cpp),
          r.nombre_receptor ?? '',
          r.rut_receptor ?? '',
          fmtNum(r.kilometraje_vehiculo != null ? Number(r.kilometraje_vehiculo) : null),
          r.observaciones ?? '',
          r.foto_medidor_inicial_url ?? '',
          r.foto_medidor_final_url ?? '',
          r.foto_patente_url ?? '',
          r.firma_receptor_url ?? '',
        ].map(esc).join(sep)
      }),
      '',
      `Resumen${sep}`,
      `Periodo${sep}${fechaDesde} → ${fechaHasta}`,
      `Despachos${sep}${stats.despachos}`,
      `Litros${sep}${fmtNum(Math.round(stats.litros * 100) / 100)}`,
      `Total a cobrar CLP${sep}${Math.round(stats.total_a_cobrar)}`,
      `Costo CPP CLP${sep}${Math.round(stats.costo_propio)}`,
      `Margen CLP${sep}${Math.round(stats.margen)}`,
      `Despachos sin precio${sep}${stats.sin_precio}`,
    ]

    const csv = '﻿' + lines.join('\r\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `comercial_ventas_combustible_${fechaDesde}_${fechaHasta}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/dashboard/comercial">
            <Button variant="ghost" size="sm" className="gap-1">
              <ArrowLeft className="h-4 w-4" /> Comercial
            </Button>
          </Link>
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold">
              <DollarSign className="h-6 w-6 text-pillado-green-600" />
              Ventas combustible a clientes
            </h1>
            <p className="text-sm text-muted-foreground">
              Detalle de cada venta a clientes (vehículos externos autorizados y clientes registrados), con guía/folio y evidencia. Lista para cobrar y exportable a facturación.
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button onClick={cargar} variant="outline" size="sm" className="gap-1" disabled={loading}>
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </Button>
          <Button onClick={exportarCSV} variant="outline" size="sm" className="gap-1" disabled={rows.length === 0}>
            <Download className="h-4 w-4" /> Exportar CSV
          </Button>
        </div>
      </div>

      {/* KPIs principales */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        <Kpi icon={<Truck />}     label="Despachos"      valor={stats.despachos.toString()} />
        <Kpi icon={<Fuel />}      label="Litros vendidos" valor={fmtLt(stats.litros)} />
        <Kpi icon={<DollarSign />} label="Total a cobrar" valor={fmtCLP(stats.total_a_cobrar)} highlight />
        <Kpi icon={<DollarSign />} label="Margen estimado" valor={fmtCLP(stats.margen)} />
        <Kpi icon={<Building2 />} label="Empresas"       valor={stats.empresas.toString()} />
      </div>

      {stats.sin_precio > 0 && (
        <Card className="border-amber-300 bg-amber-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-amber-800">
            <AlertTriangle className="h-4 w-4" />
            <span>
              <strong>{stats.sin_precio} despachos sin precio de venta configurado.</strong>
              {' '}Configura precios en{' '}
              <Link href="/dashboard/comercial/precios-combustible" className="underline">
                Precios combustible
              </Link>
              {' '}para que aparezcan en el total a cobrar.
            </span>
          </CardContent>
        </Card>
      )}

      {/* Filtros */}
      <Card>
        <CardContent className="space-y-3 p-3">
          <div className="flex flex-wrap items-center gap-2">
            <Filter className="h-4 w-4 text-gray-500" />
            <span className="text-sm font-medium">Filtros</span>
            {(patente || empresa) && (
              <Button variant="ghost" size="sm" onClick={() => { setPatente(''); setEmpresa('') }} className="gap-1">
                <X className="h-3 w-3" /> Limpiar
              </Button>
            )}
            <span className="ml-auto text-xs text-muted-foreground">
              <RefreshCw className={`mr-1 inline h-3 w-3 ${loading ? 'animate-spin' : ''}`} />
              {rows.length} despachos
            </span>
          </div>
          <div className="grid gap-2 sm:grid-cols-4">
            <div>
              <label className="text-[10px] font-medium text-gray-500">Desde</label>
              <Input type="date" value={fechaDesde} onChange={(e) => setFechaDesde(e.target.value)} />
            </div>
            <div>
              <label className="text-[10px] font-medium text-gray-500">Hasta</label>
              <Input type="date" value={fechaHasta} onChange={(e) => setFechaHasta(e.target.value)} />
            </div>
            <div className="relative">
              <label className="text-[10px] font-medium text-gray-500">Empresa</label>
              <Search className="absolute left-2 top-7 h-3 w-3 text-gray-400" />
              <Input value={empresa} onChange={(e) => setEmpresa(e.target.value)}
                     placeholder="LISSET, MYG, ..." className="pl-7" />
            </div>
            <div className="relative">
              <label className="text-[10px] font-medium text-gray-500">Patente</label>
              <Search className="absolute left-2 top-7 h-3 w-3 text-gray-400" />
              <Input value={patente} onChange={(e) => setPatente(e.target.value)}
                     placeholder="XX-XX-NN" className="pl-7" />
            </div>
          </div>
        </CardContent>
      </Card>

      {error && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </CardContent>
        </Card>
      )}

      {/* Resumen por empresa */}
      {porEmpresa.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-base">
              <Building2 className="h-4 w-4" /> Por empresa (para facturar)
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <table className="w-full text-sm">
              <thead className="bg-pillado-green-50">
                <tr>
                  <th className="px-3 py-2 text-left">Empresa</th>
                  <th className="px-3 py-2 text-right">Despachos</th>
                  <th className="px-3 py-2 text-right">Litros</th>
                  <th className="px-3 py-2 text-right">Total a cobrar</th>
                  <th className="px-3 py-2 text-right">Sin precio</th>
                </tr>
              </thead>
              <tbody>
                {porEmpresa.map((e) => (
                  <tr key={e.empresa} className="border-t">
                    <td className="px-3 py-2 font-semibold">{e.empresa}</td>
                    <td className="px-3 py-2 text-right">{e.despachos}</td>
                    <td className="px-3 py-2 text-right font-mono">{fmtLt(e.litros)}</td>
                    <td className="px-3 py-2 text-right font-semibold text-pillado-orange-700">
                      {fmtCLP(e.total)}
                    </td>
                    <td className="px-3 py-2 text-right">
                      {e.sin_precio > 0
                        ? <span className="text-amber-700">{e.sin_precio}</span>
                        : <span className="text-gray-400">—</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="bg-pillado-green-50 font-semibold">
                <tr>
                  <td className="px-3 py-2">TOTAL</td>
                  <td className="px-3 py-2 text-right">{stats.despachos}</td>
                  <td className="px-3 py-2 text-right font-mono">{fmtLt(stats.litros)}</td>
                  <td className="px-3 py-2 text-right">{fmtCLP(stats.total_a_cobrar)}</td>
                  <td className="px-3 py-2 text-right">{stats.sin_precio}</td>
                </tr>
              </tfoot>
            </table>
          </CardContent>
        </Card>
      )}

      {/* Detalle por despacho */}
      <Card className="border-pillado-green-200">
        <CardHeader className="border-b border-pillado-green-100 bg-pillado-green-50/40 pb-2">
          <CardTitle className="flex items-center gap-2 text-base text-pillado-green-800">
            <Fuel className="h-4 w-4" /> Detalle por despacho
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {loading && rows.length === 0 ? (
            <div className="flex h-32 items-center justify-center"><Spinner /></div>
          ) : rows.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              Sin despachos a externos para los filtros seleccionados.
            </div>
          ) : (
            <div className="max-h-[70vh] overflow-auto">
              <table className="w-full text-xs">
                <thead className="sticky top-0 bg-gray-50">
                  <tr>
                    <th className="px-2 py-2 text-left">Fecha</th>
                    <th className="px-2 py-2 text-left">Guía / Folio</th>
                    <th className="px-2 py-2 text-left">Cliente</th>
                    <th className="px-2 py-2 text-left">Patente</th>
                    <th className="px-2 py-2 text-right">Litros</th>
                    <th className="px-2 py-2 text-right">Precio/lt</th>
                    <th className="px-2 py-2 text-right">A cobrar</th>
                    <th className="px-2 py-2 text-left">Receptor</th>
                    <th className="px-2 py-2 text-center">Evidencia</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => {
                    const evidencias = [r.foto_medidor_inicial_url, r.foto_medidor_final_url,
                                        r.foto_patente_url, r.firma_receptor_url].filter(Boolean).length
                    return (
                      <tr key={r.id} className="border-t cursor-pointer hover:bg-gray-50"
                          onClick={() => setSeleccion(r)}>
                        <td className="px-2 py-1.5 text-gray-500 whitespace-nowrap">
                          {fmtFecha(r.fecha)}
                        </td>
                        <td className="px-2 py-1.5 font-mono text-gray-600 whitespace-nowrap">
                          {r.folio_movimiento ?? '—'}
                          {r.documento_numero && (
                            <span className="ml-1 text-[10px] text-gray-400">({r.documento_numero})</span>
                          )}
                        </td>
                        <td className="px-2 py-1.5 text-gray-700 font-medium">
                          {nombreClienteVenta(r)}
                        </td>
                        <td className="px-2 py-1.5 font-mono">
                          {patenteVenta(r) ?? '—'}
                        </td>
                        <td className="px-2 py-1.5 text-right font-mono">{fmtLt(r.litros)}</td>
                        <td className="px-2 py-1.5 text-right text-gray-600">
                          {r.precio_venta_clp_lt != null
                            ? fmtCLP(r.precio_venta_clp_lt)
                            : <span className="text-amber-600 text-[10px]">sin precio</span>}
                        </td>
                        <td className="px-2 py-1.5 text-right font-semibold text-pillado-orange-700">
                          {r.total_venta_clp != null && r.total_venta_clp > 0
                            ? fmtCLP(r.total_venta_clp)
                            : '—'}
                        </td>
                        <td className="px-2 py-1.5 text-gray-600 max-w-[160px] truncate">
                          {r.nombre_receptor ?? '—'}
                        </td>
                        <td className="px-2 py-1.5 text-center text-gray-500">
                          {evidencias} <Camera className="inline h-3 w-3" />
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {seleccion && <DetalleModal trx={seleccion} onClose={() => setSeleccion(null)} />}
    </div>
  )
}

function Kpi({ icon, label, valor, highlight }: {
  icon: React.ReactNode; label: string; valor: string; highlight?: boolean
}) {
  return (
    <div className={`rounded-xl border-2 p-4 shadow-sm ${
      highlight
        ? 'border-pillado-green-600 bg-pillado-green-500 text-white'
        : 'border-gray-200 bg-white'
    }`}>
      <div className="flex items-center justify-between">
        <div className="text-xs font-semibold uppercase tracking-wider opacity-80">{label}</div>
        <div className={highlight ? 'text-pillado-orange-300' : 'text-gray-400'}>{icon}</div>
      </div>
      <div className={`mt-2 text-xl font-bold sm:text-2xl ${highlight ? '' : 'text-gray-900'}`}>{valor}</div>
    </div>
  )
}

function DetalleModal({ trx, onClose }: { trx: TransaccionCombustibleCliente; onClose: () => void }) {
  const fotos = [
    { label: 'Medidor inicial', url: trx.foto_medidor_inicial_url, color: 'bg-blue-100 text-blue-700' },
    { label: 'Medidor final',   url: trx.foto_medidor_final_url,   color: 'bg-green-100 text-green-700' },
    { label: 'Patente',         url: trx.foto_patente_url,         color: 'bg-purple-100 text-purple-700' },
    { label: 'Firma receptor',  url: trx.firma_receptor_url,       color: 'bg-emerald-100 text-emerald-700' },
  ].filter((f) => f.url)

  return (
    <Modal open={true} onClose={onClose} title={`Despacho ${fmtFecha(trx.fecha)}`}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-2 text-sm">
          <Field icon={<Building2 className="h-3 w-3" />} label="Cliente"
                 value={nombreClienteVenta(trx)} />
          <Field icon={<Truck className="h-3 w-3" />} label="Patente"
                 value={patenteVenta(trx) ?? '—'} highlight />
          <Field label="Guía / Folio" value={trx.folio_movimiento ?? '—'} />
          {trx.documento_numero && <Field label="Documento" value={trx.documento_numero} />}
          <Field icon={<Calendar className="h-3 w-3" />} label="Fecha"
                 value={fmtFecha(trx.fecha)} />
          <Field icon={<Fuel className="h-3 w-3" />} label="Litros"
                 value={fmtLt(trx.litros)} highlight />
          <Field label="Precio CLP/lt"
                 value={trx.precio_venta_clp_lt != null ? fmtCLP(trx.precio_venta_clp_lt) : 'sin precio'} />
          <Field label="Total a cobrar"
                 value={trx.total_venta_clp != null && trx.total_venta_clp > 0 ? fmtCLP(trx.total_venta_clp) : '—'}
                 highlight />
          <Field label="Lectura inicial" value={fmtLt(trx.lectura_inicial_lt)} />
          <Field label="Lectura final"   value={fmtLt(trx.lectura_final_lt)} />
          <Field label="Estanque"        value={trx.estanque_nombre ?? '—'} />
          <Field label="Kilometraje"     value={trx.kilometraje_vehiculo != null ? `${trx.kilometraje_vehiculo} km` : '—'} />
          {trx.nombre_receptor && <Field label="Receptor" value={trx.nombre_receptor} />}
          {trx.rut_receptor && <Field label="RUT" value={trx.rut_receptor} />}
        </div>

        {fotos.length > 0 && (
          <div>
            <div className="mb-1 flex items-center gap-1 text-xs font-semibold text-gray-700">
              <Camera className="h-3 w-3" /> Evidencias ({fotos.length})
            </div>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {fotos.map((f) => (
                <div key={f.label} className="space-y-1">
                  <div className={`inline-block rounded-full px-2 py-0.5 text-[9px] font-bold ${f.color}`}>
                    {f.label}
                  </div>
                  <a href={f.url!} target="_blank" rel="noopener noreferrer">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={f.url!} alt={f.label}
                         className="h-32 w-full rounded border object-cover hover:opacity-90" />
                  </a>
                </div>
              ))}
            </div>
          </div>
        )}

        {trx.observaciones && (
          <div>
            <div className="text-xs font-semibold text-gray-700">Observaciones</div>
            <div className="text-sm text-gray-600">{trx.observaciones}</div>
          </div>
        )}
      </div>
    </Modal>
  )
}

function Field({ icon, label, value, highlight }: {
  icon?: React.ReactNode; label: string; value: string; highlight?: boolean
}) {
  return (
    <div>
      <div className="flex items-center gap-1 text-[10px] font-medium uppercase text-gray-500">
        {icon}{label}
      </div>
      <div className={`text-sm ${highlight ? 'font-bold text-gray-900' : 'text-gray-700'}`}>{value}</div>
    </div>
  )
}
