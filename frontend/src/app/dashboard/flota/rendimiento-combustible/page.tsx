'use client'

// [MIG659] Rendimiento de combustible: km/L y $/km por vehículo y mes.
// Camionetas y furgones: litros de la tarjeta Aramco + km del GPS.
// Renault: litros que informa su propio computador (rFMS); el $ es estimado con
// el precio del diésel pagado ese mes con la tarjeta.

import { Fragment, useMemo, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, ChevronDown, ChevronLeft, ChevronRight, ChevronUp, Fuel, Loader2, Upload } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import {
  ALERTA_TXT, getCargasTarjeta, getImportaciones, getRendimientoMes, importarTarjeta, leerAramco,
  type Alerta, type FilaTarjeta, type ResultadoImportacion,
} from '@/lib/services/combustible-tarjeta'

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
const n0 = (n: number | null | undefined) => (n == null ? '—' : Math.round(Number(n)).toLocaleString('es-CL'))
const n1 = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 }))
const pesos = (n: number | null | undefined) => (n == null ? '—' : '$' + n0(n))
const mesIso = (y: number, m: number) => `${y}-${String(m).padStart(2, '0')}-01`
const sumarMes = (iso: string, d: number) => {
  const [y, m] = iso.split('-').map(Number)
  const t = new Date(y, m - 1 + d, 1)
  return mesIso(t.getFullYear(), t.getMonth() + 1)
}
const fechaHora = (s: string) => {
  const [d, t] = s.split('T')
  const [, m, dd] = d.split('-')
  return `${dd}-${m} ${t?.slice(0, 5) ?? ''}`
}
// Lo que no es sospecha sino falta de dato no se pinta como alerta.
const INFORMATIVAS: Alerta[] = ['sin_gps', 'sin_ficha']

type Leido = { archivo: string; filas: FilaTarjeta[]; descartadas: number }

export default function RendimientoCombustiblePage() {
  const { loading: authLoading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const input = useRef<HTMLInputElement>(null)

  const hoy = new Date()
  const [mes, setMes] = useState(mesIso(hoy.getFullYear(), hoy.getMonth() + 1))
  const [abierto, setAbierto] = useState<string | null>(null)
  const [leyendo, setLeyendo] = useState(false)
  const [subiendo, setSubiendo] = useState(false)
  const [leido, setLeido] = useState<Leido | null>(null)
  const [resultado, setResultado] = useState<ResultadoImportacion | null>(null)

  const mesAnt = sumarMes(mes, -1)
  const { data: rend = [], isLoading } = useQuery({
    queryKey: ['comb-rendimiento-mes', mesAnt],
    queryFn: () => getRendimientoMes(mesAnt),
  })
  const { data: cargas = [] } = useQuery({
    queryKey: ['comb-tarjeta-cargas', mes],
    queryFn: () => getCargasTarjeta(mes, sumarMes(mes, 1)),
  })
  const { data: importaciones = [] } = useQuery({ queryKey: ['comb-tarjeta-importaciones'], queryFn: getImportaciones })

  const filas = useMemo(() => {
    const ant = new Map(rend.filter((r) => r.mes.slice(0, 10) === mesAnt).map((r) => [r.fuente + r.patente, r.km_l]))
    return rend.filter((r) => r.mes.slice(0, 10) === mes)
      .map((r) => ({
        ...r, km_l_ant: ant.get(r.fuente + r.patente) ?? null,
        alertas: cargas.filter((c) => c.patente_ver === r.patente && c.alertas.some((a) => !INFORMATIVAS.includes(a))).length,
      }))
      .sort((a, b) => (b.monto ?? 0) - (a.monto ?? 0))
  }, [rend, cargas, mes, mesAnt])

  const tot = useMemo(() => {
    const t = filas.filter((f) => f.fuente === 'tarjeta' && f.grupo === 'flota')
    const ab = filas.filter((f) => f.grupo === 'abastecimiento')
    return {
      monto: t.reduce((s, f) => s + (f.monto ?? 0), 0),
      litros: t.reduce((s, f) => s + (f.litros ?? 0), 0),
      cargas: t.reduce((s, f) => s + (f.cargas ?? 0), 0),
      abMonto: ab.reduce((s, f) => s + (f.monto ?? 0), 0),
      abLitros: ab.reduce((s, f) => s + (f.litros ?? 0), 0),
      renault: filas.filter((f) => f.fuente === 'computador').reduce((s, f) => s + (f.monto ?? 0), 0),
    }
  }, [filas])
  const flota = filas.filter((f) => f.grupo === 'flota')
  const abastecimiento = filas.filter((f) => f.grupo === 'abastecimiento')
  const sospechosas = cargas.filter((c) => c.alertas.some((a) => !INFORMATIVAS.includes(a)))

  async function alElegirArchivo(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setResultado(null)
    setLeyendo(true)
    try {
      const { default: ExcelJS } = await import('exceljs')
      const wb = new ExcelJS.Workbook()
      await wb.xlsx.load(await file.arrayBuffer())
      const r = leerAramco(wb)
      if (!r.filas.length) { toast.error('El archivo no trae ninguna carga legible.'); setLeido(null); return }
      setLeido({ archivo: file.name, ...r })
    } catch (err) {
      toast.error(errorMessage(err))
      setLeido(null)
    } finally {
      setLeyendo(false)
      if (input.current) input.current.value = ''
    }
  }

  async function confirmar() {
    if (!leido) return
    setSubiendo(true)
    try {
      const r = await importarTarjeta(leido.archivo, leido.filas)
      setResultado(r)
      setLeido(null)
      qc.invalidateQueries({ queryKey: ['comb-rendimiento-mes'] })
      qc.invalidateQueries({ queryKey: ['comb-tarjeta-cargas'] })
      qc.invalidateQueries({ queryKey: ['comb-tarjeta-importaciones'] })
      toast.success(r.nuevas > 0 ? `${r.nuevas} cargas nuevas.` : 'Ese archivo ya estaba cargado. No se duplicó nada.')
    } catch (err) {
      toast.error(errorMessage(err))
    } finally {
      setSubiendo(false)
    }
  }

  if (authLoading) return null
  const [y, m] = mes.split('-').map(Number)
  const leidoLitros = leido?.filas.reduce((s, f) => s + f.litros, 0) ?? 0
  const leidoPago = leido?.filas.reduce((s, f) => s + (f.total_pago ?? 0), 0) ?? 0
  const leidoFechas = leido ? leido.filas.map((f) => f.fecha_hora).sort() : []

  return (
    <div className="mx-auto max-w-6xl space-y-5 p-4">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-xl font-bold text-gray-900"><Fuel className="h-5 w-5 text-blue-600" /> Rendimiento de combustible</h1>
          <p className="mt-1 max-w-3xl text-sm text-gray-600">
            Camionetas y furgones: litros y $ de la tarjeta Aramco, km del GPS. Renault: litros que informa su computador
            ($ estimado con el diésel del mes). El km/L cuenta solo los tramos entre cargas que tienen GPS en las dos puntas.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => setMes(sumarMes(mes, -1))} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Mes anterior"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[130px] text-center text-sm font-semibold capitalize">{MESES[m - 1]} {y}</span>
          <button onClick={() => setMes(sumarMes(mes, 1))} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Mes siguiente"><ChevronRight className="h-4 w-4" /></button>
        </div>
      </header>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi t="Flota con tarjeta" v={pesos(tot.monto)} s={`${n0(tot.litros)} L · ${tot.cargas} cargas`} />
        <Kpi t="Abastecimiento (aljibes)" v={pesos(tot.abMonto)} s={`${n0(tot.abLitros)} L para llenar aljibes`} />
        <Kpi t="Renault (estimado)" v={pesos(tot.renault)} s="litros del computador × $/L diésel" />
        <Kpi t="Cargas para revisar" v={String(sospechosas.length)} s="ver abajo" alerta={sospechosas.length > 0} />
      </div>

      <Card>
        <CardHeader><CardTitle className="text-base">Flota por vehículo</CardTitle></CardHeader>
        <CardContent className="overflow-x-auto p-0">
          {isLoading ? <div className="flex justify-center p-8"><Loader2 className="h-6 w-6 animate-spin text-blue-600" /></div>
            : flota.length === 0 ? <p className="p-6 text-sm text-gray-500">Sin cargas ni datos del computador este mes. Suba el Excel de Aramco más abajo.</p>
            : <TablaVehiculos filas={flota} cargas={cargas} abierto={abierto} setAbierto={setAbierto} />}
          <p className="border-t p-2 text-xs text-gray-500">
            Km/L en blanco: el mes tiene menos de 100 km medidos entre cargas con GPS. El GPS manda el odómetro una vez al día,
            así que una carga suelta puede dar un km/L raro; el del mes es el confiable.
          </p>
        </CardContent>
      </Card>

      {abastecimiento.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Abastecimiento · aljibes de combustible</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto p-0">
            <TablaVehiculos filas={abastecimiento} cargas={cargas} abierto={abierto} setAbierto={setAbierto} abastecimiento />
            <p className="border-t p-2 text-xs text-gray-500">
              Cargan con la tarjeta para llenar su estanque y abastecer a otros equipos: no se mide km/L.
            </p>
          </CardContent>
        </Card>
      )}

      {sospechosas.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2 text-base"><AlertTriangle className="h-4 w-4 text-amber-600" /> Cargas para revisar</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto p-0"><TablaCargas cargas={sospechosas} conPatente /></CardContent>
        </Card>
      )}

      <Card>
        <CardHeader><CardTitle className="text-base">Cargar el Excel de Aramco Fleet</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-gray-600">
            En portaltarjetas.cl: <b>Transacciones</b> → ícono de exportar → <b>Excel</b> → clip de arriba → descargar
            «transacciones.xlsx». Se puede subir el mismo archivo varias veces: las cargas ya subidas no se duplican.
          </p>
          <input ref={input} type="file" accept=".xlsx" className="hidden" onChange={alElegirArchivo} />
          {!leido && (
            <button onClick={() => input.current?.click()} disabled={leyendo || subiendo}
                    className="flex w-full flex-col items-center gap-2 rounded-lg border-2 border-dashed border-gray-300 py-8 text-gray-600 transition hover:border-blue-400 hover:bg-blue-50 disabled:opacity-50">
              {leyendo ? <><Loader2 className="h-7 w-7 animate-spin text-blue-600" /><span>Leyendo…</span></>
                : <><Upload className="h-7 w-7" /><span className="font-medium">Elegir transacciones.xlsx</span></>}
            </button>
          )}
          {leido && (
            <div className="rounded-lg border border-blue-200 bg-blue-50 p-4 text-sm">
              <p><b>{leido.archivo}</b>: {leido.filas.length} cargas del {fechaHora(leidoFechas[0])} al {fechaHora(leidoFechas[leidoFechas.length - 1])} ·
                {' '}{n0(leidoLitros)} L · {pesos(leidoPago)}{leido.descartadas > 0 && ` · ${leido.descartadas} filas sin datos se ignoran`}</p>
              <div className="mt-3 flex gap-2">
                <button onClick={confirmar} disabled={subiendo}
                        className="rounded-lg bg-blue-600 px-4 py-2 font-medium text-white hover:bg-blue-700 disabled:opacity-50">
                  {subiendo ? 'Guardando…' : 'Guardar en SICOM'}
                </button>
                <button onClick={() => setLeido(null)} disabled={subiendo} className="rounded-lg border bg-white px-4 py-2 hover:bg-gray-50">Cancelar</button>
              </div>
            </div>
          )}
          {resultado && (
            <p className="rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-800">
              {resultado.nuevas} nuevas, {resultado.repetidas} ya estaban. {resultado.con_posicion_gps} con posición GPS a la hora de la carga.
              {resultado.patentes_sin_ficha.length > 0 && <> Patentes que no están en SICOM: {resultado.patentes_sin_ficha.join(', ')}.</>}
            </p>
          )}
          {importaciones.length > 0 && (
            <div className="text-xs text-gray-500">
              <p className="font-semibold text-gray-600">Últimas cargas de archivo</p>
              {importaciones.map((i) => (
                <p key={i.id}>{new Date(i.created_at).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' })} · {i.archivo} · {i.nuevas} nuevas de {i.filas}</p>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

type FilaVista = Awaited<ReturnType<typeof getRendimientoMes>>[number] & { km_l_ant: number | null; alertas: number }

function TablaVehiculos({ filas, cargas, abierto, setAbierto, abastecimiento }: {
  filas: FilaVista[]; cargas: Awaited<ReturnType<typeof getCargasTarjeta>>
  abierto: string | null; setAbierto: (k: string | null) => void; abastecimiento?: boolean
}) {
  return (
    <table className="w-full text-sm">
      <thead className="bg-gray-50 text-xs text-gray-600">
        <tr>
          <th className="p-2 text-left">Patente</th><th className="p-2 text-left">Fuente</th>
          <th className="p-2 text-right">Cargas</th><th className="p-2 text-right">Litros</th><th className="p-2 text-right">$</th>
          {!abastecimiento && <><th className="p-2 text-right">Km GPS</th><th className="p-2 text-right">Km/L</th><th className="p-2 text-right">Mes ant.</th>
            <th className="p-2 text-right">$/km</th></>}
          <th className="p-2 text-right">Alertas</th><th />
        </tr>
      </thead>
      <tbody>
        {filas.map((f) => {
          const k = f.fuente + f.patente
          const detalle = cargas.filter((c) => c.patente_ver === f.patente)
          return (
            <Fragment key={k}>
              <tr className={cn('border-t', f.fuente === 'tarjeta' && 'cursor-pointer hover:bg-gray-50')}
                  onClick={() => f.fuente === 'tarjeta' && setAbierto(abierto === k ? null : k)}>
                <td className="p-2 font-medium">{f.patente}<div className="text-xs font-normal text-gray-500">{f.tipo ?? ''}</div></td>
                <td className="p-2 text-xs">{f.fuente === 'tarjeta' ? (abastecimiento ? 'Tarjeta' : 'Tarjeta + GPS') : 'Computador Renault'}</td>
                <td className="p-2 text-right tabular-nums">{f.cargas ?? '—'}</td>
                <td className="p-2 text-right tabular-nums">{n1(f.litros)}</td>
                <td className="p-2 text-right tabular-nums">{f.monto_real ? pesos(f.monto) : <span className="text-gray-500">≈ {pesos(f.monto)}</span>}</td>
                {!abastecimiento && <>
                  <td className="p-2 text-right tabular-nums">{f.km_gps == null ? <span className="text-xs text-gray-400">sin GPS</span> : n0(f.km_gps)}</td>
                  <td className="p-2 text-right font-semibold tabular-nums">{n1(f.km_l)}</td>
                  <td className="p-2 text-right tabular-nums text-gray-500">{n1(f.km_l_ant)}</td>
                  <td className="p-2 text-right tabular-nums">{f.costo_km == null ? '—' : pesos(f.costo_km)}</td>
                </>}
                <td className="p-2 text-right">{f.alertas > 0 ? <span className="rounded bg-amber-100 px-1.5 py-0.5 text-xs font-semibold text-amber-800">{f.alertas}</span> : ''}</td>
                <td className="p-2 text-gray-400">{f.fuente === 'tarjeta' && (abierto === k ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />)}</td>
              </tr>
              {abierto === k && (
                <tr className="bg-gray-50/60"><td colSpan={abastecimiento ? 7 : 11} className="p-2"><TablaCargas cargas={detalle} /></td></tr>
              )}
            </Fragment>
          )
        })}
      </tbody>
    </table>
  )
}

function Kpi({ t, v, s, alerta }: { t: string; v: string; s: string; alerta?: boolean }) {
  return (
    <div className={cn('rounded-xl border bg-white p-3', alerta && 'border-amber-300 bg-amber-50')}>
      <p className="text-xs text-gray-500">{t}</p>
      <p className="text-lg font-bold tabular-nums text-gray-900">{v}</p>
      <p className="text-xs text-gray-500">{s}</p>
    </div>
  )
}

function TablaCargas({ cargas, conPatente }: { cargas: Awaited<ReturnType<typeof getCargasTarjeta>>; conPatente?: boolean }) {
  if (cargas.length === 0) return <p className="p-2 text-xs text-gray-500">Sin cargas este mes.</p>
  return (
    <table className="w-full text-xs">
      <thead className="text-gray-500">
        <tr>
          <th className="p-1.5 text-left">Fecha</th>{conPatente && <th className="p-1.5 text-left">Patente</th>}
          <th className="p-1.5 text-left">Estación</th><th className="p-1.5 text-right">Litros</th><th className="p-1.5 text-right">$</th>
          <th className="p-1.5 text-right">Km desde anterior</th><th className="p-1.5 text-right">Km/L tramo</th>
          <th className="p-1.5 text-right" title="Distancia entre donde estaba el GPS y la estación">GPS vs estación</th><th className="p-1.5 text-left">Alertas</th>
        </tr>
      </thead>
      <tbody>
        {cargas.map((c) => (
          <tr key={c.id} className="border-t border-gray-200">
            <td className="p-1.5 whitespace-nowrap">{fechaHora(c.fecha_hora)}</td>
            {conPatente && <td className="p-1.5 font-medium">{c.patente_ver}</td>}
            <td className="p-1.5">{c.estacion}</td>
            <td className="p-1.5 text-right tabular-nums">{n1(c.litros)}</td>
            <td className="p-1.5 text-right tabular-nums">{pesos(c.total_pago)}</td>
            <td className="p-1.5 text-right tabular-nums">{n0(c.km_tramo)}</td>
            <td className="p-1.5 text-right tabular-nums">{n1(c.km_l_tramo)}{c.km_l_mediana != null && <span className="text-gray-400"> / {n1(c.km_l_mediana)}</span>}</td>
            <td className="p-1.5 text-right tabular-nums">
              {c.gps_lat != null
                ? <a href={`https://www.google.com/maps?q=${c.gps_lat},${c.gps_lng}`} target="_blank" rel="noreferrer" className="text-blue-600 hover:underline"
                     title={`Lectura GPS a ${c.gps_dif_min} min de la carga`}>{c.dist_estacion_km != null ? `${n1(c.dist_estacion_km)} km` : 'ver'}</a>
                : '—'}
            </td>
            <td className="p-1.5">
              {c.alertas.map((a) => (
                <span key={a} className={cn('mr-1 inline-block rounded px-1.5 py-0.5',
                  INFORMATIVAS.includes(a) ? 'bg-gray-100 text-gray-600' : 'bg-amber-100 text-amber-800')}>{ALERTA_TXT[a]}</span>
              ))}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
