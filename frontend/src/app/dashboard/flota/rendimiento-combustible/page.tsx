'use client'

// [MIG659] Rendimiento de combustible: km/L y $/km por vehículo y mes.
// Camionetas y furgones: litros de la tarjeta Aramco + km del GPS.
// Renault: litros que informa su propio computador (rFMS); el $ es estimado con
// el precio del diésel pagado ese mes con la tarjeta.
// Tendencia de 12 meses, mapa de calor y revisión por vehículo: lib/combustible-tendencia.

import { Fragment, useMemo, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertOctagon, AlertTriangle, ArrowDown, ArrowUp, ChevronDown, ChevronLeft, ChevronRight, ChevronUp, Fuel, Info, Loader2, Upload,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import {
  ALERTA_TXT, getCargasTarjeta, getImportaciones, getPrimeraCarga, getRendimientoMes, importarTarjeta, leerAramco,
  type Alerta, type FilaTarjeta, type RendimientoMes, type ResultadoImportacion,
} from '@/lib/services/combustible-tarjeta'
import {
  filaFlota, mapaCalor, mesIso, paraRevisar, rangoMeses, revisarVehiculos, serieFlota, sumarMes, valorBase, variacion,
  type Base, type Revision,
} from '@/lib/combustible-tendencia'
import { GraficoKmL, GraficoLitros, MapaCalor, nombreMes } from './graficos'

const n0 = (n: number | null | undefined) => (n == null ? '—' : Math.round(Number(n)).toLocaleString('es-CL'))
const n1 = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 }))
const pesos = (n: number | null | undefined) => (n == null ? '—' : '$' + n0(n))
const pct = (x: number) => `${x > 0 ? '+' : ''}${Math.round(x * 100)} %`
const fechaHora = (s: string) => {
  const [d, t] = s.split('T')
  const [, m, dd] = d.split('-')
  return `${dd}-${m} ${t?.slice(0, 5) ?? ''}`
}
// Lo que no es sospecha sino falta de dato no se pinta como alerta.
const INFORMATIVAS: Alerta[] = ['sin_gps', 'sin_ficha']
const MESES_VISTA = 12

type Leido = { archivo: string; filas: FilaTarjeta[]; descartadas: number }

export default function RendimientoCombustiblePage() {
  const { loading: authLoading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const input = useRef<HTMLInputElement>(null)

  const hoy = new Date()
  const [mes, setMes] = useState(mesIso(hoy.getFullYear(), hoy.getMonth() + 1))
  const [base, setBase] = useState<Base>('prom3')
  const [abierto, setAbierto] = useState<string | null>(null)
  const [leyendo, setLeyendo] = useState(false)
  const [subiendo, setSubiendo] = useState(false)
  const [leido, setLeido] = useState<Leido | null>(null)
  const [resultado, setResultado] = useState<ResultadoImportacion | null>(null)

  const meses = useMemo(() => rangoMeses(mes, MESES_VISTA), [mes])
  // 6 meses más atrás de la ventana: el «normal» de un vehículo mira hasta 6 meses previos.
  const desde = sumarMes(meses[0], -6)
  const { data: rend = [], isLoading } = useQuery({
    queryKey: ['comb-rendimiento-mes', desde],
    queryFn: () => getRendimientoMes(desde),
  })
  const { data: cargas = [] } = useQuery({
    queryKey: ['comb-tarjeta-cargas', mes],
    queryFn: () => getCargasTarjeta(mes, sumarMes(mes, 1)),
  })
  const { data: importaciones = [] } = useQuery({ queryKey: ['comb-tarjeta-importaciones'], queryFn: getImportaciones })
  const { data: inicio = null } = useQuery({ queryKey: ['comb-tarjeta-importaciones', 'inicio'], queryFn: getPrimeraCarga })

  // Hasta qué día hay cargas subidas: el mes de ese día está a medias y se proyecta al cierre.
  const corte = useMemo(() => {
    const h = importaciones.map((i) => i.hasta?.slice(0, 10)).filter(Boolean).sort() as string[]
    return h.length ? h[h.length - 1] : null
  }, [importaciones])

  const alertasPorPatente = useMemo(() => {
    const m = new Map<string, number>()
    for (const c of cargas) if (c.alertas.some((a) => !INFORMATIVAS.includes(a))) m.set(c.patente_ver, (m.get(c.patente_ver) ?? 0) + 1)
    return m
  }, [cargas])

  const serie = useMemo(() => serieFlota(rend, meses, corte, inicio), [rend, meses, corte, inicio])
  const calor = useMemo(() => mapaCalor(rend, meses, corte, inicio), [rend, meses, corte, inicio])
  const revisiones = useMemo(() => revisarVehiculos(rend, mes, corte, alertasPorPatente, inicio),
    [rend, mes, corte, alertasPorPatente, inicio])
  const aRevisar = useMemo(() => paraRevisar(revisiones), [revisiones])
  const revPorPatente = useMemo(() => new Map(revisiones.map((r) => [r.patente, r])), [revisiones])

  const delMes = useMemo(() => rend.filter((r) => r.mes.slice(0, 10) === mes)
    .sort((a, b) => (b.monto ?? 0) - (a.monto ?? 0)), [rend, mes])
  const flota = delMes.filter((f) => f.fuente === 'tarjeta' && f.grupo === 'flota')
  const abastecimiento = delMes.filter((f) => f.grupo === 'abastecimiento')
  const renault = delMes.filter((f) => f.fuente === 'computador')
  const sospechosas = cargas.filter((c) => c.alertas.some((a) => !INFORMATIVAS.includes(a)))

  const punto = serie.find((p) => p.mes === mes)
  const kpi = (clave: 'litrosProy' | 'montoProy' | 'kmL' | 'costoKm') => {
    const v = punto?.[clave] || null
    return { v, d: variacion(v, valorBase(serie, mes, base, clave)) }
  }
  const kL = kpi('litrosProy'), kKm = kpi('kmL'), kM = kpi('montoProy'), kCk = kpi('costoKm')
  const txtBase = base === 'ant' ? 'vs mes anterior' : 'vs prom. 3 meses'

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
  const leidoLitros = leido?.filas.reduce((s, f) => s + f.litros, 0) ?? 0
  const leidoPago = leido?.filas.reduce((s, f) => s + (f.total_pago ?? 0), 0) ?? 0
  const leidoFechas = leido ? leido.filas.map((f) => f.fecha_hora).sort() : []
  const parcial = punto?.parcial ?? false
  const corteTxt = corte ? `${corte.slice(8, 10)}-${corte.slice(5, 7)}` : ''

  return (
    <div className="mx-auto max-w-6xl space-y-5 p-4">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-xl font-bold text-gray-900"><Fuel className="h-5 w-5 text-blue-600" /> Rendimiento de combustible</h1>
          <p className="mt-1 max-w-3xl text-sm text-gray-600">
            Camionetas y furgones con tarjeta Aramco: litros y $ de la tarjeta, km del GPS. Se compara en litros y no en $,
            porque el precio del diésel cambió mucho durante el año.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex rounded-lg border p-0.5 text-xs" role="group" aria-label="Comparar contra">
            {(['ant', 'prom3'] as Base[]).map((b) => (
              <button key={b} onClick={() => setBase(b)}
                      className={cn('rounded-md px-2.5 py-1', base === b ? 'bg-gray-900 text-white' : 'text-gray-600 hover:bg-gray-100')}>
                {b === 'ant' ? 'vs mes anterior' : 'vs prom. 3 meses'}
              </button>
            ))}
          </div>
          <button onClick={() => setMes(sumarMes(mes, -1))} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Mes anterior"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[130px] text-center text-sm font-semibold capitalize">{nombreMes(mes)}</span>
          <button onClick={() => setMes(sumarMes(mes, 1))} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Mes siguiente"><ChevronRight className="h-4 w-4" /></button>
        </div>
      </header>

      {parcial && (
        <p className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs text-blue-900">
          Mes en curso: hay cargas hasta el {corteTxt}. Litros y $ se muestran <b>proyectados al cierre del mes</b> (≈) para compararlos con meses completos.
        </p>
      )}

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi t="Litros flota" v={`${parcial ? '≈ ' : ''}${n0(kL.v)} L`} s={parcial ? `${n0(punto?.litros)} L al ${corteTxt}` : `${punto?.cargas ?? 0} cargas`}
             d={kL.d} txtBase={txtBase} subirEsMalo />
        <Kpi t="Km/L flota" v={n1(kKm.v)} s={kCk.v == null ? 'sin km del GPS' : `${pesos(kCk.v)}/km`} d={kKm.d} txtBase={txtBase} />
        <Kpi t="$ flota" v={`${parcial ? '≈ ' : ''}${pesos(kM.v)}`} s={punto?.precioL ? `${pesos(punto.precioL)}/L` : '—'}
             d={kM.d} txtBase={txtBase} subirEsMalo />
        <Kpi t="Vehículos para revisar" v={String(aRevisar.length)} s={`${sospechosas.length} cargas con alerta`} alerta={aRevisar.length > 0} />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader><CardTitle className="text-base">Litros de la flota, mes a mes</CardTitle></CardHeader>
          <CardContent>{isLoading ? <Cargando /> : <GraficoLitros serie={serie} mes={mes} onElegir={setMes} />}</CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-base">Km/L de la flota, mes a mes</CardTitle></CardHeader>
          <CardContent>{isLoading ? <Cargando /> : <GraficoKmL serie={serie} mes={mes} />}</CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Cada vehículo contra su normal</CardTitle>
          <p className="text-xs text-gray-500">
            Litros de cada mes. El color dice cuánto se aleja de lo que ese vehículo carga normalmente (la mediana de sus otros meses).
            Rojo = cargó más de lo normal. Si además anduvo más, el km/L lo aclara en la lista de abajo.
          </p>
        </CardHeader>
        <CardContent>
          {isLoading ? <Cargando /> : calor.length === 0
            ? <p className="text-sm text-gray-500">Sin cargas en estos meses.</p>
            : <MapaCalor filas={calor} flota={filaFlota(serie)} meses={meses} mes={mes} onElegir={setMes} />}
        </CardContent>
      </Card>

      <Card className={cn(aRevisar.length > 0 && 'border-amber-300')}>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <AlertTriangle className="h-4 w-4 text-amber-600" /> Para revisar en <span className="capitalize">{nombreMes(mes)}</span>
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {aRevisar.length === 0
            ? <p className="px-4 pb-4 text-sm text-gray-500">Ningún vehículo se sale de su normal este mes.</p>
            : <ListaRevision filas={aRevisar} />}
          <Explicados filas={revisiones.filter((r) => r.motivos.length > 0 && r.motivos.every((m) => m.nivel === 'info'))} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-base">Flota por vehículo · <span className="capitalize">{nombreMes(mes)}</span></CardTitle></CardHeader>
        <CardContent className="overflow-x-auto p-0">
          {isLoading ? <Cargando />
            : flota.length === 0 ? <p className="p-6 text-sm text-gray-500">Sin cargas este mes. Suba el Excel de Aramco más abajo.</p>
            : <TablaVehiculos filas={flota} cargas={cargas} rev={revPorPatente} alertas={alertasPorPatente} abierto={abierto} setAbierto={setAbierto} />}
          <p className="border-t p-2 text-xs text-gray-500">
            Km/L en blanco: el mes tiene menos de 100 km medidos entre cargas con GPS. Clic en una fila para ver sus cargas.
          </p>
        </CardContent>
      </Card>

      {renault.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Renault · litros de su computador</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto p-0"><TablaRenault filas={renault} /></CardContent>
        </Card>
      )}

      {abastecimiento.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Abastecimiento · aljibes de combustible</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto p-0">
            <TablaVehiculos filas={abastecimiento} cargas={cargas} alertas={alertasPorPatente} abierto={abierto} setAbierto={setAbierto} abastecimiento />
            <p className="border-t p-2 text-xs text-gray-500">
              Cargan con la tarjeta para llenar su estanque y abastecer a otros equipos: no se mide km/L.
            </p>
          </CardContent>
        </Card>
      )}

      {sospechosas.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2 text-base"><AlertTriangle className="h-4 w-4 text-amber-600" /> Cargas con alerta</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto p-0"><TablaCargas cargas={sospechosas} conPatente /></CardContent>
        </Card>
      )}

      <ComoSeCalcula />

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

const Cargando = () => <div className="flex justify-center p-8"><Loader2 className="h-6 w-6 animate-spin text-blue-600" /></div>

function ListaRevision({ filas }: { filas: Revision[] }) {
  return (
    <ul className="divide-y">
      {filas.map((r) => {
        const alto = r.motivos.some((m) => m.nivel === 'alto')
        const I = alto ? AlertOctagon : AlertTriangle
        return (
          <li key={r.patente} className="flex flex-wrap items-start gap-x-4 gap-y-1 px-4 py-3">
            <div className="flex w-36 shrink-0 items-start gap-2">
              <I className={cn('mt-0.5 h-4 w-4 shrink-0', alto ? 'text-red-600' : 'text-amber-600')} aria-hidden />
              <div>
                <p className="font-semibold text-gray-900">{r.patente}</p>
                <p className="text-xs text-gray-500">{alto ? 'Revisar' : 'Mirar'} · {r.tipo ?? ''}</p>
              </div>
            </div>
            <ul className="min-w-0 flex-1 space-y-0.5 text-sm text-gray-700">
              {r.motivos.filter((m) => m.nivel !== 'info').map((m) => <li key={m.texto}>{m.texto}</li>)}
            </ul>
            <div className="text-right text-xs tabular-nums text-gray-600">
              <p>{r.parcial ? '≈ ' : ''}{n0(r.litrosProy)} L{r.normalLitros != null && <> · normal {n0(r.normalLitros)}</>}</p>
              <p>{r.kmL != null ? `${n1(r.kmL)} km/L` : 'sin km/L'}{r.kmGps != null && ` · ${n0(r.kmGps)} km`}</p>
            </div>
          </li>
        )
      })}
    </ul>
  )
}

// Cargaron más de lo normal pero el km/L confirma que anduvieron más: se muestran para que no parezca que se ignoraron.
function Explicados({ filas }: { filas: Revision[] }) {
  if (!filas.length) return null
  return (
    <div className="border-t bg-gray-50/60 px-4 py-2 text-xs text-gray-600">
      <p className="mb-1 flex items-center gap-1 font-semibold text-gray-700"><Info className="h-3.5 w-3.5" /> Cargaron más, pero está explicado</p>
      {filas.map((r) => <p key={r.patente}><b>{r.patente}</b>: {r.motivos[0].texto}</p>)}
    </div>
  )
}

function TablaVehiculos({ filas, cargas, rev, alertas, abierto, setAbierto, abastecimiento }: {
  filas: RendimientoMes[]; cargas: Awaited<ReturnType<typeof getCargasTarjeta>>
  rev?: Map<string, Revision>; alertas: Map<string, number>
  abierto: string | null; setAbierto: (k: string | null) => void; abastecimiento?: boolean
}) {
  return (
    <table className="w-full text-sm">
      <thead className="bg-gray-50 text-xs text-gray-600">
        <tr>
          <th className="p-2 text-left">Patente</th>
          <th className="p-2 text-right">Cargas</th><th className="p-2 text-right">Litros</th>
          {!abastecimiento && <th className="p-2 text-right" title="Litros del mes (proyectados si el mes está en curso) vs su normal">vs normal</th>}
          <th className="p-2 text-right">$</th>
          {!abastecimiento && <><th className="p-2 text-right">Km GPS</th><th className="p-2 text-right">Km/L</th><th className="p-2 text-right">$/km</th></>}
          <th className="p-2 text-right">Alertas</th><th />
        </tr>
      </thead>
      <tbody>
        {filas.map((f) => {
          const k = f.fuente + f.patente
          const detalle = cargas.filter((c) => c.patente_ver === f.patente)
          const r = rev?.get(f.patente)
          const nAl = alertas.get(f.patente) ?? 0
          return (
            <Fragment key={k}>
              <tr className="cursor-pointer border-t hover:bg-gray-50" onClick={() => setAbierto(abierto === k ? null : k)}>
                <td className="p-2 font-medium">{f.patente}<div className="text-xs font-normal text-gray-500">{f.tipo ?? ''}</div></td>
                <td className="p-2 text-right tabular-nums">{f.cargas ?? '—'}</td>
                <td className="p-2 text-right tabular-nums">{n1(f.litros)}</td>
                {!abastecimiento && (
                  <td className={cn('p-2 text-right tabular-nums', r?.desvio != null && r.desvio >= 0.5 ? 'font-semibold text-red-700' : 'text-gray-600')}>
                    {r?.desvio == null ? '—' : pct(r.desvio)}
                  </td>
                )}
                <td className="p-2 text-right tabular-nums">{pesos(f.monto)}</td>
                {!abastecimiento && <>
                  <td className="p-2 text-right tabular-nums">{f.km_gps == null ? <span className="text-xs text-gray-400">sin GPS</span> : n0(f.km_gps)}</td>
                  <td className="p-2 text-right font-semibold tabular-nums">{n1(f.km_l)}</td>
                  <td className="p-2 text-right tabular-nums">{f.costo_km == null ? '—' : pesos(f.costo_km)}</td>
                </>}
                <td className="p-2 text-right">{nAl > 0 ? <span className="rounded bg-amber-100 px-1.5 py-0.5 text-xs font-semibold text-amber-800">{nAl}</span> : ''}</td>
                <td className="p-2 text-gray-400">{abierto === k ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}</td>
              </tr>
              {abierto === k && (
                <tr className="bg-gray-50/60"><td colSpan={abastecimiento ? 6 : 10} className="p-2"><TablaCargas cargas={detalle} /></td></tr>
              )}
            </Fragment>
          )
        })}
      </tbody>
    </table>
  )
}

function TablaRenault({ filas }: { filas: RendimientoMes[] }) {
  return (
    <table className="w-full text-sm">
      <thead className="bg-gray-50 text-xs text-gray-600">
        <tr>
          <th className="p-2 text-left">Patente</th><th className="p-2 text-right">Litros</th><th className="p-2 text-right">Km</th>
          <th className="p-2 text-right">Km/L</th><th className="p-2 text-right">L/100 km</th><th className="p-2 text-right">Horas motor</th>
          <th className="p-2 text-right" title="Litros gastados con el motor en ralentí ÷ litros totales">% ralentí</th>
          <th className="p-2 text-right">$ estimado</th>
        </tr>
      </thead>
      <tbody>
        {filas.map((f) => (
          <tr key={f.patente} className="border-t">
            <td className="p-2 font-medium">{f.patente}<div className="text-xs font-normal text-gray-500">{f.tipo ?? ''}</div></td>
            <td className="p-2 text-right tabular-nums">{n1(f.litros)}</td>
            <td className="p-2 text-right tabular-nums">{n0(f.km_gps)}</td>
            <td className="p-2 text-right font-semibold tabular-nums">{n1(f.km_l)}</td>
            <td className="p-2 text-right tabular-nums">{f.km_gps && f.litros ? n1((Number(f.litros) / Number(f.km_gps)) * 100) : '—'}</td>
            <td className="p-2 text-right tabular-nums">{n1(f.horas)}</td>
            <td className="p-2 text-right tabular-nums">{f.litros && f.litros_ralenti != null ? `${Math.round((Number(f.litros_ralenti) / Number(f.litros)) * 100)} %` : '—'}</td>
            <td className="p-2 text-right tabular-nums text-gray-500">≈ {pesos(f.monto)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

// Qué es cada columna y de dónde sale. Mantener al día con MIG659-661
// (v_combustible_tarjeta_cargas, v_combustible_rendimiento_mes) y lib/combustible-tendencia.
function ComoSeCalcula() {
  const Item = ({ t, children }: { t: string; children: React.ReactNode }) => (
    <div><dt className="font-semibold text-gray-800">{t}</dt><dd className="text-gray-600">{children}</dd></div>
  )
  return (
    <details className="rounded-xl border bg-white p-4 text-sm">
      <summary className="cursor-pointer font-semibold text-gray-900">¿Cómo se calcula?</summary>
      <div className="mt-4 space-y-5">
        <section>
          <h3 className="mb-2 font-semibold text-blue-700">De dónde salen los datos</h3>
          <ul className="list-disc space-y-1 pl-5 text-gray-600">
            <li><b>Tarjeta Aramco Fleet</b> (Excel de portaltarjetas.cl): fecha, patente, estación, litros y $ de cada carga.
              El odómetro viene vacío en el portal (el chofer no lo digita), por eso los km salen del GPS.</li>
            <li><b>GPS</b> (Radicom): odómetro una vez al día y posición cada hora.</li>
            <li><b>Renault</b>: su computador (rFMS) informa los litros que gastó el motor; no usa tarjeta.</li>
            <li>Fuera del análisis: TCRB-71 (gerencia) y TSTB-48. Los aljibes de combustible van aparte, como abastecimiento.</li>
          </ul>
        </section>

        <section>
          <h3 className="mb-2 font-semibold text-blue-700">Cada carga</h3>
          <dl className="grid gap-3 md:grid-cols-2">
            <Item t="Fecha">Día y hora de la carga según Aramco (hora de Chile).</Item>
            <Item t="Patente">La del Excel, cruzada con la ficha del vehículo en SICOM.</Item>
            <Item t="Estación">La estación Aramco donde se cargó.</Item>
            <Item t="Litros">«Volumen (L)» del Excel.</Item>
            <Item t="$">«Total pago» del Excel: lo que se paga, ya con el descuento.</Item>
            <Item t="Km desde anterior">
              Odómetro GPS al cierre del día anterior a esta carga, menos el mismo dato de la carga anterior.
              Dos cargas el mismo día dan 0. Queda vacío si el GPS lleva más de 3 días sin odómetro o si el vehículo no tiene GPS.
            </Item>
            <Item t="Km/L tramo">
              Km desde anterior ÷ litros de esta carga (lleno a lleno: lo que se carga repone lo que se gastó desde la carga anterior).
              El número gris es la mediana del vehículo, para comparar. Una carga suelta puede salir rara (llenado parcial,
              odómetro diario); el del mes es el confiable.
            </Item>
            <Item t="GPS vs estación">
              Distancia entre donde estaba el vehículo según el GPS (la lectura más cercana a la hora de la carga, hasta 90 min) y la estación.
              La ubicación de la estación la aprende SICOM: es el punto medio de las cargas con GPS en esa estación (hacen falta 3).
              El link abre el mapa con la posición GPS. «ver» = la estación aún no tiene ubicación aprendida; «—» = no hubo lectura GPS cerca de esa hora.
            </Item>
          </dl>
        </section>

        <section>
          <h3 className="mb-2 font-semibold text-blue-700">Alertas</h3>
          <dl className="grid gap-3 md:grid-cols-2">
            <Item t={ALERTA_TXT.fuera_estacion}>Está a más de 5 km de la estación, más 1,2 km por cada minuto entre la lectura GPS y la carga (un vehículo en movimiento).</Item>
            <Item t={ALERTA_TXT.sobre_estanque}>Más de 90 L en camioneta o furgón, o más de 450 L en camión. No aplica a los aljibes.</Item>
            <Item t={ALERTA_TXT.sin_movimiento}>15 L o más cuando el GPS marcó menos de 5 km desde una carga de otro día.</Item>
            <Item t={ALERTA_TXT.rendimiento_bajo}>Tramo de 150 km o más con un km/L bajo el 60 % de la mediana del vehículo (con al menos 4 tramos medidos).</Item>
            <Item t={ALERTA_TXT.dos_cargas_dia}>Dos o más cargas de la misma patente el mismo día. Puede ser normal en viajes largos: mirar los km.</Item>
            <Item t="Grises (informativas)">«{ALERTA_TXT.sin_gps}» y «{ALERTA_TXT.sin_ficha}»: falta un dato, no es sospecha.</Item>
          </dl>
        </section>

        <section>
          <h3 className="mb-2 font-semibold text-blue-700">Tabla por vehículo (el mes)</h3>
          <dl className="grid gap-3 md:grid-cols-2">
            <Item t="Cargas, Litros, $">Suma de las cargas del mes con la tarjeta.</Item>
            <Item t="Km GPS">Km que recorrió en el mes según el odómetro GPS.</Item>
            <Item t="Km/L">
              Km de los tramos ÷ litros de esos mismos tramos. Solo cuentan las cargas con odómetro GPS en las dos puntas;
              así un mes con días sin GPS no da un rendimiento falso. Queda en blanco con menos de 100 km medidos.
            </Item>
            <Item t="$/km">$ de esos tramos ÷ km de esos tramos.</Item>
            <Item t="vs normal">Litros del mes contra la mediana de sus 6 meses anteriores (hacen falta 3 con cargas).</Item>
            <Item t="Renault">
              Tabla aparte: litros y km de su computador, no de la tarjeta. L/100 km = litros ÷ km × 100. % ralentí = litros con el motor
              en ralentí ÷ litros totales. El $ es estimado (≈): litros × lo que costó el litro de diésel ese mes con la tarjeta.
            </Item>
          </dl>
        </section>

        <section>
          <h3 className="mb-2 font-semibold text-blue-700">Tendencia y comparación</h3>
          <dl className="grid gap-3 md:grid-cols-2">
            <Item t="Se compara en litros">El precio del diésel pasó de ~$950/L a ~$1.550/L en 2026: en $ un mes parece raro solo por el precio.</Item>
            <Item t="Mes en curso (≈)">
              Litros y $ hasta el último día con cargas subidas, proyectados al cierre: litros × días del mes ÷ días con datos.
              El km/L no se proyecta (ya es un promedio).
            </Item>
            <Item t="vs mes anterior / vs prom. 3 meses">La variación de cada indicador contra el mes anterior o contra el promedio de los 3 meses anteriores con datos.</Item>
            <Item t="Km/L de la flota">Suma de km medidos ÷ suma de litros de esos tramos, de todos los vehículos. Hay km del GPS desde septiembre de 2026.</Item>
            <Item t="Mapa de calor">
              Cada celda = litros del mes. El color = cuánto se aleja de la mediana de los otros meses cerrados del mismo vehículo
              (hacen falta 3). El mes raro no entra en su propio normal. La primera fila es toda la flota, para comparar.
            </Item>
          </dl>
        </section>

        <section>
          <h3 className="mb-2 font-semibold text-blue-700">Para revisar</h3>
          <dl className="grid gap-3 md:grid-cols-2">
            <Item t="Revisar (rojo)">
              Cargó un 50 % o más sobre su normal <b>y</b> el km/L cayó bajo el 80 % de lo habitual; o el km/L cayó bajo el 80 % de su normal
              (si aún no tiene historia de km/L, bajo el de los otros de su tipo: camionetas con camionetas, furgones con furgones).
            </Item>
            <Item t="Mirar (ámbar)">Cargó un 50 % o más sobre su normal y no hay km del GPS para confirmarlo; o tiene cargas con alerta.</Item>
            <Item t="Explicado">Cargó un 50 % o más, pero el km/L se mantiene: anduvo más. Se muestra aparte para que se vea que se miró.</Item>
            <Item t="Mes recién empezado">Con menos de ~10 días de datos no se juzga por litros: la proyección todavía es ruido.</Item>
          </dl>
        </section>
      </div>
    </details>
  )
}

// La variación va con flecha y signo, no solo color. «subirEsMalo»: más litros o más $ es la señal de alerta.
function Kpi({ t, v, s, alerta, d, txtBase, subirEsMalo }: {
  t: string; v: string; s: string; alerta?: boolean; d?: number | null; txtBase?: string; subirEsMalo?: boolean
}) {
  const malo = d != null && Math.abs(d) >= 0.1 && (subirEsMalo ? d > 0 : d < 0)
  const Flecha = d != null && d < 0 ? ArrowDown : ArrowUp
  return (
    <div className={cn('rounded-xl border bg-white p-3', alerta && 'border-amber-300 bg-amber-50')}>
      <p className="text-xs text-gray-500">{t}</p>
      <p className="text-lg font-bold tabular-nums text-gray-900">{v}</p>
      <p className="text-xs text-gray-500">{s}</p>
      {txtBase && (
        <p className={cn('mt-1 flex items-center gap-0.5 text-xs tabular-nums', malo ? 'font-semibold text-red-700' : 'text-gray-600')}>
          {d == null ? <span className="text-gray-400">sin base para comparar</span>
            : <><Flecha className="h-3 w-3" aria-hidden />{pct(d)} {txtBase}</>}
        </p>
      )}
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
