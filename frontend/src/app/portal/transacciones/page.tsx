'use client'

import { useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  Search, Filter, X, AlertTriangle, RefreshCw, Calendar, Truck,
  Camera, FileSignature, Fuel, Download,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { supabase } from '@/lib/supabase'
import {
  cargarTransaccionesCliente, esUsuarioPortal,
  type TransaccionCombustibleCliente,
} from '@/lib/services/portal-cliente'

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

export default function PortalTransaccionesPage() {
  const router = useRouter()
  const [rows, setRows]         = useState<TransaccionCombustibleCliente[]>([])
  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState<string | null>(null)

  const [fechaDesde, setFechaDesde] = useState(hace30diasISO())
  const [fechaHasta, setFechaHasta] = useState(todayISO())
  const [patente, setPatente]       = useState('')
  const [empresa, setEmpresa]       = useState('')
  const [seleccion, setSeleccion]   = useState<TransaccionCombustibleCliente | null>(null)

  // Guard: si no es usuario portal, redirige al login
  useEffect(() => {
    (async () => {
      const { data } = await supabase.auth.getUser()
      if (!data.user) { router.push('/portal/login'); return }
      const esPortal = await esUsuarioPortal()
      if (!esPortal) { router.push('/portal/login'); return }
      cargar()
    })()
    /* eslint-disable-next-line react-hooks/exhaustive-deps */
  }, [])

  const cargar = async () => {
    setError(null); setLoading(true)
    try {
      const data = await cargarTransaccionesCliente({ fechaDesde, fechaHasta, patente, empresa })
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

  const stats = useMemo(() => {
    const litros = rows.reduce((s, r) => s + Number(r.litros), 0)
    const costo  = rows.reduce((s, r) => s + Number(r.costo_total_clp ?? 0), 0)
    return { transacciones: rows.length, litros, costo }
  }, [rows])

  const exportarCSV = () => {
    if (rows.length === 0) return
    // Excel-ES interpreta `;` como separador. UTF-8 BOM para que respete tildes.
    const sep = ';'
    const headers = [
      'Fecha', 'Patente', 'Empresa / Cliente', 'Estanque', 'Litros',
      'Lectura inicial', 'Lectura final', 'Costo CLP', 'Receptor', 'RUT',
      'Observaciones', 'Foto medidor inicial', 'Foto medidor final',
      'Foto patente', 'Firma receptor',
    ]
    const esc = (v: unknown) => {
      if (v == null) return ''
      const s = String(v).replace(/"/g, '""')
      return /[";\n\r]/.test(s) ? `"${s}"` : s
    }
    const fmtNum = (n: number | null | undefined) =>
      n == null ? '' : String(n).replace('.', ',') // coma decimal para Excel-ES

    const lines = [
      headers.join(sep),
      ...rows.map((r) => [
        new Date(r.fecha).toLocaleString('es-CL'),
        r.activo_patente ?? r.externo_patente ?? '',
        r.activo_cliente ?? r.externo_empresa ?? '',
        r.estanque_codigo ?? '',
        fmtNum(Number(r.litros)),
        fmtNum(r.lectura_inicial_lt != null ? Number(r.lectura_inicial_lt) : null),
        fmtNum(r.lectura_final_lt != null ? Number(r.lectura_final_lt) : null),
        fmtNum(r.costo_total_clp != null ? Number(r.costo_total_clp) : null),
        r.nombre_receptor ?? '',
        r.rut_receptor ?? '',
        r.observaciones ?? '',
        r.foto_medidor_inicial_url ?? '',
        r.foto_medidor_final_url ?? '',
        r.foto_patente_url ?? '',
        r.firma_receptor_url ?? '',
      ].map(esc).join(sep)),
      '',
      // Resumen al pie
      `Resumen${sep}`,
      `Periodo desde${sep}${fechaDesde}`,
      `Periodo hasta${sep}${fechaHasta}`,
      `Filtro patente${sep}${patente || '(todas)'}`,
      `Filtro empresa${sep}${empresa || '(todas)'}`,
      `Total despachos${sep}${stats.transacciones}`,
      `Litros totales${sep}${fmtNum(Math.round(stats.litros * 100) / 100)}`,
      `Costo total CLP${sep}${Math.round(stats.costo)}`,
    ]

    const csv = '﻿' + lines.join('\r\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `pillado_combustible_${fechaDesde}_${fechaHasta}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4 p-4">
      {/* Stats */}
      <div className="grid grid-cols-3 gap-2">
        <StatBox label="Despachos" valor={stats.transacciones.toString()}
                 color="border-pillado-green-300 bg-white text-pillado-green-700" />
        <StatBox label="Litros totales" valor={fmtLt(stats.litros)}
                 color="border-pillado-orange-300 bg-white text-pillado-orange-700" />
        <StatBox label="Costo total" valor={fmtCLP(stats.costo)}
                 color="border-pillado-green-500 bg-pillado-green-500 text-white" />
      </div>

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
              {rows.length} resultados
            </span>
            <Button variant="outline" size="sm" onClick={exportarCSV}
                    disabled={rows.length === 0}
                    className="gap-1 border-pillado-green-300 text-pillado-green-700 hover:bg-pillado-green-50">
              <Download className="h-3 w-3" /> Exportar CSV
            </Button>
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
              <label className="text-[10px] font-medium text-gray-500">Patente</label>
              <Search className="absolute left-2 top-7 h-3 w-3 text-gray-400" />
              <Input value={patente} onChange={(e) => setPatente(e.target.value)}
                     placeholder="XXXX-NN" className="pl-7" />
            </div>
            <div className="relative">
              <label className="text-[10px] font-medium text-gray-500">Empresa / Cliente</label>
              <Search className="absolute left-2 top-7 h-3 w-3 text-gray-400" />
              <Input value={empresa} onChange={(e) => setEmpresa(e.target.value)}
                     placeholder="Buscar..." className="pl-7" />
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

      <Card className="border-pillado-green-200">
        <CardHeader className="border-b border-pillado-green-100 bg-pillado-green-50/40 pb-2">
          <CardTitle className="flex items-center gap-2 text-base text-pillado-green-800">
            <Fuel className="h-4 w-4" /> Despachos de combustible
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {loading && rows.length === 0 ? (
            <div className="flex h-32 items-center justify-center"><Spinner /></div>
          ) : rows.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              Sin transacciones para los filtros seleccionados.
            </div>
          ) : (
            <div className="max-h-[70vh] overflow-auto">
              <table className="w-full text-xs">
                <thead className="sticky top-0 bg-gray-50">
                  <tr>
                    <th className="px-2 py-2 text-left">Fecha</th>
                    <th className="px-2 py-2 text-left">Patente</th>
                    <th className="px-2 py-2 text-left">Empresa / Cliente</th>
                    <th className="px-2 py-2 text-left">Estanque</th>
                    <th className="px-2 py-2 text-right">Litros</th>
                    <th className="px-2 py-2 text-right">Costo</th>
                    <th className="px-2 py-2 text-center">Evidencia</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.id} className="border-t cursor-pointer hover:bg-gray-50"
                        onClick={() => setSeleccion(r)}>
                      <td className="px-2 py-1.5 text-gray-500 whitespace-nowrap">
                        {new Date(r.fecha).toLocaleString('es-CL')}
                      </td>
                      <td className="px-2 py-1.5 font-medium">
                        {r.activo_patente ?? r.externo_patente ?? '—'}
                      </td>
                      <td className="px-2 py-1.5 text-gray-600">
                        {r.activo_cliente ?? r.externo_empresa ?? '—'}
                      </td>
                      <td className="px-2 py-1.5 text-gray-500">{r.estanque_codigo ?? '—'}</td>
                      <td className="px-2 py-1.5 text-right font-mono">{fmtLt(r.litros)}</td>
                      <td className="px-2 py-1.5 text-right">{fmtCLP(r.costo_total_clp)}</td>
                      <td className="px-2 py-1.5 text-center">
                        {[r.foto_medidor_inicial_url, r.foto_medidor_final_url, r.foto_patente_url, r.firma_receptor_url]
                          .filter(Boolean).length} 📷
                      </td>
                    </tr>
                  ))}
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

function StatBox({ label, valor, color }: { label: string; valor: string; color: string }) {
  return (
    <div className={`rounded-xl border-2 px-3 py-2.5 shadow-sm ${color}`}>
      <div className="text-[10px] font-semibold uppercase tracking-wider opacity-80">{label}</div>
      <div className="mt-1 text-lg font-bold sm:text-xl">{valor}</div>
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
    <Modal open={true} onClose={onClose} title={`Despacho ${new Date(trx.fecha).toLocaleString('es-CL')}`}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-2 text-sm">
          <Field icon={<Truck className="h-3 w-3" />} label="Patente"
                 value={trx.activo_patente ?? trx.externo_patente ?? '—'} />
          <Field icon={<Calendar className="h-3 w-3" />} label="Fecha"
                 value={new Date(trx.fecha).toLocaleString('es-CL')} />
          <Field icon={<Fuel className="h-3 w-3" />} label="Litros"
                 value={fmtLt(trx.litros)} highlight />
          <Field label="Costo" value={fmtCLP(trx.costo_total_clp)} highlight />
          <Field label="Lectura inicial" value={fmtLt(trx.lectura_inicial_lt)} />
          <Field label="Lectura final" value={fmtLt(trx.lectura_final_lt)} />
          <Field label="Estanque" value={trx.estanque_nombre ?? '—'} />
          <Field label="Empresa / Cliente"
                 value={trx.activo_cliente ?? trx.externo_empresa ?? '—'} />
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

function Field({ icon, label, value, highlight }: { icon?: React.ReactNode; label: string; value: string; highlight?: boolean }) {
  return (
    <div>
      <div className="flex items-center gap-1 text-[10px] font-medium uppercase text-gray-500">
        {icon}{label}
      </div>
      <div className={`text-sm ${highlight ? 'font-bold text-gray-900' : 'text-gray-700'}`}>{value}</div>
    </div>
  )
}
