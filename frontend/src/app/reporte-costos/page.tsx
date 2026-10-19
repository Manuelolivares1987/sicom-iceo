'use client'

import { Fragment, useEffect, useMemo, useState } from 'react'
import { Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { supabase } from '@/lib/supabase'
import { fmtClp, fmtMM, fmtPct, variacionPct } from '@/lib/costos-operacion'
import { nombreTipo } from '@/components/costos/comunes'
import {
  NOMBRE_AREA_CC, copiarReporteCostos, linkPanelCostos, getReporteCostos, getTokenReporteCostos, mesCerradoIso, mesLargo,
  type ReporteCostos,
} from '@/lib/reporte-costos'

// ============================================================================
// /reporte-costos — informe mensual de costos (MIG617)
// Se abre desde el correo sin iniciar sesión (?t=token, como fiabilidad) o con
// sesión de quien tiene permiso de costos. Corto a propósito: top 10 del mes
// por equipo, familia y centro de costo. Clic en un mes del gráfico cambia el
// informe; clic en un equipo muestra en qué se gastó.
// ============================================================================

const MES_CORTO = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
const fmtMesCorto = (iso: string) => `${MES_CORTO[Number(iso.slice(5, 7)) - 1]} ${iso.slice(2, 4)}`
const sumarMes = (iso: string, n: number) => {
  const d = new Date(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1 + n, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

function Variacion({ actual, anterior }: { actual: number; anterior: number | null | undefined }) {
  const v = variacionPct(actual, anterior)
  if (v == null) return <span className="text-gray-400">antes $0</span>
  return (
    <span className={`font-semibold ${v > 0 ? 'text-red-600' : 'text-green-700'}`}>
      {v > 0 ? '▲' : '▼'} {fmtPct(Math.abs(v))}
    </span>
  )
}

function Kpi({ valor, titulo, detalle, tono = 'verde' }: {
  valor: string; titulo: string; detalle?: React.ReactNode; tono?: 'verde' | 'rojo' | 'ambar'
}) {
  const color = { verde: 'text-[#1e5929]', rojo: 'text-red-700', ambar: 'text-amber-700' }[tono]
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-500">{titulo}</div>
      <div className={`mt-1 text-2xl font-extrabold ${color}`}>{valor}</div>
      {detalle && <div className="mt-1 text-xs text-gray-500">{detalle}</div>}
    </div>
  )
}

function Seccion({ titulo, nota, children }: { titulo: string; nota?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-gray-200 bg-white">
      <div className="border-b border-gray-100 px-4 py-3">
        <h2 className="text-sm font-bold text-[#1e5929]">{titulo}</h2>
        {nota && <p className="text-xs text-gray-500">{nota}</p>}
      </div>
      <div className="overflow-x-auto">{children}</div>
    </section>
  )
}

const th = 'px-3 py-2 text-[11px] font-semibold uppercase tracking-wide text-gray-500'
const td = 'px-3 py-2'

export default function ReporteCostosPage() {
  const [mes, setMes] = useState(mesCerradoIso())
  const [data, setData] = useState<ReporteCostos | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [cargando, setCargando] = useState(true)
  const [abierto, setAbierto] = useState<number | null>(null)
  const [msg, setMsg] = useState<string | null>(null)
  // null = verificando; el informe pide sesión con permiso o el token del correo.
  const [sesionOk, setSesionOk] = useState<boolean | null>(null)
  // undefined = URL aún no leída; null = la URL no trae token.
  const [tokenLink, setTokenLink] = useState<string | null | undefined>(undefined)

  useEffect(() => {
    let cancel = false
    supabase.auth.getSession().then(({ data: { session } }) => { if (!cancel) setSesionOk(!!session) })
    const q = new URLSearchParams(window.location.search)
    const m = q.get('mes')
    if (m && /^\d{4}-\d{2}$/.test(m)) setMes(`${m}-01`)
    setTokenLink(q.get('t'))
    return () => { cancel = true }
  }, [])

  useEffect(() => {
    if (tokenLink === undefined) return
    if (sesionOk !== true && !tokenLink) return
    let cancel = false
    setCargando(true); setError(null); setAbierto(null)
    getReporteCostos(mes, tokenLink)
      .then((d) => { if (!cancel) setData(d) })
      .catch((e: Error) => { if (!cancel) setError(e.message) })
      .finally(() => { if (!cancel) setCargando(false) })
    return () => { cancel = true }
  }, [mes, sesionOk, tokenLink])

  // El mes queda en la URL: copiar el link comparte exactamente lo que se ve.
  const cambiarMes = (m: string) => {
    setMes(m)
    const q = new URLSearchParams(window.location.search)
    q.set('mes', m.slice(0, 7))
    window.history.replaceState(null, '', `${window.location.pathname}?${q.toString()}`)
  }

  const copiar = async () => {
    if (!data) return
    setMsg(null)
    try {
      const token = tokenLink ?? await getTokenReporteCostos()
      setMsg(await copiarReporteCostos(data, token))
    } catch (e) {
      setMsg(`No se pudo copiar: ${(e as Error).message}`)
    }
  }

  const tendencia = useMemo(() => (data?.tendencia ?? []).map((t) => ({ ...t, etiqueta: fmtMesCorto(t.mes) })), [data])
  const mesMax = mesCerradoIso(new Date(new Date().getFullYear(), new Date().getMonth() + 1, 1)) // mes en curso

  if (tokenLink === undefined || (sesionOk === null && !tokenLink)) {
    return <div className="min-h-screen bg-gray-50 py-20 text-center text-gray-400">Verificando acceso…</div>
  }
  if (sesionOk === false && !tokenLink) {
    return (
      <div className="min-h-screen bg-gray-50 py-20">
        <div className="mx-auto max-w-md rounded-lg border border-gray-200 bg-white p-8 text-center shadow-sm">
          <h1 className="text-lg font-bold text-[#1e5929]">Costos de operación — Pillado</h1>
          <p className="mt-3 text-sm text-gray-600">Este informe es de uso interno y requiere iniciar sesión.</p>
          <a href={`/login?next=${encodeURIComponent('/reporte-costos')}`}
             className="mt-5 inline-block rounded-lg bg-[#1e5929] px-5 py-2 text-sm font-semibold text-white">
            Iniciar sesión
          </a>
        </div>
      </div>
    )
  }

  const k = data?.kpi
  const vTotal = k ? variacionPct(k.total, k.total_anterior) : null

  return (
    <div className="min-h-screen bg-[#eef3ef] py-6">
      <div className="mx-auto max-w-5xl space-y-4 px-4">
        <header className="rounded-2xl bg-[#1e5929] px-5 py-5 text-white">
          <div className="text-[11px] font-bold uppercase tracking-[2px] text-[#8bcc95]">Pillado Empresas · SICOM</div>
          <div className="mt-1 flex flex-wrap items-end justify-between gap-3">
            <div>
              <h1 className="text-2xl font-extrabold">Costos de operación · {mesLargo(mes)}</h1>
              <p className="text-sm text-[#dbf0de]">Salidas de bodega Softland (consumo y EPP). Sin petróleo, que se revende.</p>
            </div>
            <div className="flex items-center gap-2">
              <button onClick={() => cambiarMes(sumarMes(mes, -1))}
                      className="h-9 rounded-lg bg-white/15 px-3 text-sm font-semibold hover:bg-white/25" aria-label="Mes anterior">◀</button>
              <span className="min-w-[7rem] text-center text-sm font-semibold capitalize">{mesLargo(mes)}</span>
              <button onClick={() => cambiarMes(sumarMes(mes, 1))} disabled={mes >= mesMax}
                      className="h-9 rounded-lg bg-white/15 px-3 text-sm font-semibold hover:bg-white/25 disabled:opacity-40" aria-label="Mes siguiente">▶</button>
              <a href={linkPanelCostos('', tokenLink)}
                 className="ml-2 inline-flex h-9 items-center rounded-lg bg-white/15 px-3 text-sm font-semibold hover:bg-white/25">
                Panel completo →
              </a>
              <button onClick={copiar} disabled={!data}
                      className="ml-2 h-9 rounded-lg bg-white px-4 text-sm font-semibold text-[#1e5929] hover:bg-[#dbf0de] disabled:opacity-50"
                      title="Copia el informe con formato para pegarlo en Outlook">
                📋 Copiar para correo
              </button>
            </div>
          </div>
        </header>
        {msg && <div className="rounded-lg bg-green-50 px-3 py-2 text-sm text-green-800">{msg}</div>}
        {error && <div className="rounded-lg bg-red-50 p-4 text-sm text-red-700">No se pudo cargar: {error}</div>}
        {cargando && <div className="py-16 text-center text-gray-400">Cargando…</div>}

        {!cargando && data && k && (
          <>
            {mes >= mesMax && (
              <div className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800">
                Mes en curso: Softland todavía se está cargando, los números van a subir.
              </div>
            )}
            <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
              <Kpi titulo="Gasto del mes" valor={fmtMM(k.total)}
                   detalle={<>{mesLargo(data.mes_anterior)}: {fmtMM(k.total_anterior)}</>} />
              <Kpi titulo="vs mes anterior" tono={vTotal != null && vTotal > 0 ? 'rojo' : 'verde'}
                   valor={vTotal == null ? '—' : `${vTotal > 0 ? '+' : ''}${fmtPct(vTotal)}`} />
              <Kpi titulo="Asignado a equipos" valor={k.total > 0 ? fmtPct((k.asignado_equipo / k.total) * 100) : '—'}
                   detalle={<>{k.equipos_con_gasto} equipos con gasto</>} />
              <Kpi titulo="Costo/h flota (12 m)" tono="ambar" valor={k.costo_hora_12m == null ? '—' : fmtClp(k.costo_hora_12m)}
                   detalle={<>{k.equipos_medidos_12m} equipos medidos</>} />
            </div>

            <Seccion titulo="Últimos 12 meses" nota="Clic en una barra para ver ese mes.">
              <div className="h-44 px-2 py-3">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={tendencia} margin={{ left: 8, right: 8 }}>
                    <XAxis dataKey="etiqueta" tick={{ fontSize: 11 }} />
                    <YAxis tickFormatter={(v: number) => `${Math.round(v / 1e6)}M`} tick={{ fontSize: 11 }} width={36} />
                    <Tooltip formatter={(v: number) => fmtClp(v)} labelFormatter={(l: string) => l} />
                    <Bar dataKey="total" radius={[4, 4, 0, 0]} cursor="pointer"
                         onClick={(d: { mes?: string }) => d.mes && cambiarMes(d.mes)}>
                      {tendencia.map((t) => <Cell key={t.mes} fill={t.mes === data.mes ? '#2D8B3D' : '#b7d9bd'} />)}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </Seccion>

            <Seccion titulo="Los 10 equipos con más gasto"
                     nota="Clic en un equipo para ver en qué se gastó. Costo/h = últimos 12 meses (gasto entre dos lecturas de horómetro ÷ horas).">
              <table className="w-full text-sm">
                <thead className="border-b border-gray-100 text-left">
                  <tr><th className={th}>Equipo</th><th className={`${th} text-right`}>Gasto</th>
                    <th className={`${th} text-right`}>vs mes ant.</th><th className={`${th} text-right`}>Costo/h 12 m</th></tr>
                </thead>
                <tbody>
                  {data.equipos.items.map((e, i) => (
                    <Fragment key={i}>
                      <tr className="cursor-pointer border-b border-gray-50 hover:bg-green-50/50" onClick={() => setAbierto(abierto === i ? null : i)}>
                        <td className={td}>
                          <div className="font-semibold">{i + 1}. {e.etiqueta} <span className="text-gray-400">{abierto === i ? '▾' : '▸'}</span></div>
                          <div className="text-xs text-gray-500">{[e.tipo_equipo && nombreTipo(e.tipo_equipo), e.faena].filter(Boolean).join(' · ')}</div>
                        </td>
                        <td className={`${td} text-right font-semibold`}>{fmtClp(e.total)}</td>
                        <td className={`${td} text-right`}><Variacion actual={e.total} anterior={e.total_anterior} /></td>
                        <td className={`${td} text-right`}>
                          {e.costo_hora_12m == null ? <span className="text-xs text-gray-400">sin medición</span> : (
                            <>
                              {fmtClp(e.costo_hora_12m)}
                              {e.mediana_tipo != null && <div className="text-[11px] text-gray-400">tipo: {fmtClp(e.mediana_tipo)}</div>}
                            </>
                          )}
                        </td>
                      </tr>
                      {abierto === i && (
                        <tr className="bg-gray-50">
                          <td colSpan={4} className="px-6 py-2">
                            <div className="text-[11px] font-semibold uppercase text-gray-500">En qué se gastó</div>
                            {e.familias.map((f) => (
                              <div key={f.nombre} className="flex justify-between py-0.5 text-sm">
                                <span>{f.nombre}</span>
                                <span>{fmtClp(f.total)} <span className="text-xs text-gray-400">({fmtPct((f.total / e.total) * 100)})</span></span>
                              </div>
                            ))}
                            {e.horas_12m != null && <div className="mt-1 text-xs text-gray-500">{Math.round(e.horas_12m).toLocaleString('es-CL')} h medidas en 12 meses</div>}
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  ))}
                  {data.equipos.n > data.equipos.items.length && (
                    <tr><td colSpan={4} className="px-3 py-2 text-xs text-gray-500">
                      Otros {data.equipos.n - data.equipos.items.length} equipos: {fmtClp(data.equipos.resto)}
                    </td></tr>
                  )}
                </tbody>
              </table>
            </Seccion>

            <div className="grid gap-4 md:grid-cols-2">
              <Seccion titulo="Las 10 familias con más gasto">
                <table className="w-full text-sm">
                  <thead className="border-b border-gray-100 text-left">
                    <tr><th className={th}>Familia</th><th className={`${th} text-right`}>Gasto</th><th className={`${th} text-right`}>vs ant.</th></tr>
                  </thead>
                  <tbody>
                    {data.familias.items.map((f, i) => (
                      <tr key={f.familia} className="border-b border-gray-50">
                        <td className={td}>
                          <div className="font-semibold">{i + 1}. {f.nombre}</div>
                          <div className="text-xs text-gray-500">{k.total > 0 ? fmtPct((f.total / k.total) * 100) : ''} del mes</div>
                        </td>
                        <td className={`${td} text-right font-semibold`}>{fmtClp(f.total)}</td>
                        <td className={`${td} text-right`}><Variacion actual={f.total} anterior={f.total_anterior} /></td>
                      </tr>
                    ))}
                    {data.familias.n > data.familias.items.length && (
                      <tr><td colSpan={3} className="px-3 py-2 text-xs text-gray-500">
                        Otras {data.familias.n - data.familias.items.length}: {fmtClp(data.familias.resto)}
                      </td></tr>
                    )}
                  </tbody>
                </table>
              </Seccion>

              <Seccion titulo="Centros de costo" nota="Los que no son un equipo: operación de faena, taller, proyectos.">
                <table className="w-full text-sm">
                  <thead className="border-b border-gray-100 text-left">
                    <tr><th className={th}>Centro de costo</th><th className={`${th} text-right`}>Gasto</th><th className={`${th} text-right`}>vs ant.</th></tr>
                  </thead>
                  <tbody>
                    {data.centros_costo.items.length === 0 && (
                      <tr><td colSpan={3} className="px-3 py-4 text-center text-xs text-gray-400">Sin gasto fuera de los equipos este mes.</td></tr>
                    )}
                    {data.centros_costo.items.map((c, i) => (
                      <tr key={c.codi_cc} className="border-b border-gray-50">
                        <td className={td}>
                          <div className="font-semibold">{i + 1}. {c.descripcion ?? c.codi_cc}</div>
                          <div className="text-xs text-gray-500">{c.codi_cc} · {NOMBRE_AREA_CC[c.area] ?? c.area}</div>
                        </td>
                        <td className={`${td} text-right font-semibold`}>{fmtClp(c.total)}</td>
                        <td className={`${td} text-right`}><Variacion actual={c.total} anterior={c.total_anterior} /></td>
                      </tr>
                    ))}
                    {data.centros_costo.n > data.centros_costo.items.length && (
                      <tr><td colSpan={3} className="px-3 py-2 text-xs text-gray-500">
                        Otros {data.centros_costo.n - data.centros_costo.items.length}: {fmtClp(data.centros_costo.resto)}
                      </td></tr>
                    )}
                  </tbody>
                </table>
              </Seccion>
            </div>

            <p className="pb-6 text-center text-[11px] text-gray-500">
              Datos de Softland{data.sync?.ultima ? ` · última sincronización ${new Date(data.sync.ultima).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' })}` : ''}
              {k.lineas_sin_precio > 0 ? ` · ${k.lineas_sin_precio} líneas sin precio en Softland` : ''} · SICOM · Pillado Empresas
            </p>
          </>
        )}
      </div>
    </div>
  )
}
