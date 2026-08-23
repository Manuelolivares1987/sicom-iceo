'use client'

// ============================================================================
// El cierre del mes: triángulo, variación acumulada y entregables (MIG330–333)
// ----------------------------------------------------------------------------
// Lo que ordena esta pantalla: la variación de UN día no sirve para decidir
// nada. Una varilla tiene ±0,3 % de incertidumbre por su propia física, y en un
// estanque de 50.000 litros eso son 150 litros de ruido legítimo todos los
// días. Perseguir el número del día es perseguir ruido.
//
// Lo que decide es el acumulado del mes: si el ruido es ruido, se compensa y la
// suma tiende a cero; si hay una pérdida real, la suma se va para un lado y no
// vuelve. Por eso el acumulado va arriba y el detalle diario va abajo,
// plegado — que es el orden inverso al que uno tiende a construir.
// ============================================================================

import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Download, TrendingUp, TrendingDown, Unlock, ChevronDown, ChevronRight,
  Upload, Loader2, Minus,
} from 'lucide-react'
import Link from 'next/link'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import {
  getTriangulo, getVariacionMes, getCierresMes, reabrirCierre,
  DIAGNOSTICO_UI, ESTADO_MES_UI,
} from '@/lib/services/combustible-orpak'
import {
  exportarBbdd, exportarFormAc066, exportarCierreRomeral,
} from '@/lib/services/combustible-entregables.js'

const miles = (n: number | null | undefined) =>
  n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

const conSigno = (n: number | null | undefined) =>
  n == null ? '—' : `${n > 0 ? '+' : ''}${miles(n)}`

export function CierreMensual({ faenaId, desde, hasta }: {
  faenaId: string; desde: string; hasta: string
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const [abierto, setAbierto] = useState(false)
  const [bajando, setBajando] = useState<string | null>(null)
  const [reabriendo, setReabriendo] = useState<string | null>(null)
  const [motivo, setMotivo] = useState('')

  const mes = `${desde.slice(0, 7)}-01`

  const { data: variacion } = useQuery({
    queryKey: ['comb-variacion-mes', faenaId, mes],
    queryFn: () => getVariacionMes(faenaId, mes),
    enabled: !!faenaId,
  })

  const { data: triangulo } = useQuery({
    queryKey: ['comb-triangulo', faenaId, desde, hasta],
    queryFn: () => getTriangulo(faenaId, desde, hasta),
    enabled: !!faenaId,
  })

  const { data: cierres } = useQuery({
    queryKey: ['comb-cierres-mes', faenaId, desde, hasta],
    queryFn: () => getCierresMes(faenaId, desde, hasta),
    enabled: !!faenaId,
  })

  const cierrePorFecha = new Map((cierres ?? []).map((c) => [c.fecha, c]))

  async function bajar(cual: 'cierre' | 'ac066' | 'bbdd') {
    setBajando(cual)
    try {
      const n = cual === 'cierre' ? await exportarCierreRomeral(faenaId, mes)
        : cual === 'ac066' ? await exportarFormAc066(faenaId, mes)
        : await exportarBbdd(faenaId, mes)
      if (!n) toast.warning('El mes todavía no tiene datos que exportar.')
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo generar el archivo'))
    } finally {
      setBajando(null)
    }
  }

  async function confirmarReapertura(cierreId: string) {
    try {
      const r = await reabrirCierre(cierreId, motivo)
      toast.success(r.reaperturas === 1
        ? 'Cierre reabierto. Queda en borrador para corregir.'
        : `Cierre reabierto (${r.reaperturas}ª vez). Queda en bitácora.`)
      setReabriendo(null)
      setMotivo('')
      qc.invalidateQueries({ queryKey: ['comb-cierres-mes'] })
      qc.invalidateQueries({ queryKey: ['comb-control-diario'] })
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo reabrir'))
    }
  }

  const conVariacion = (variacion ?? []).filter((v) => v.estado_mes !== 'sin_datos')

  return (
    <div className="space-y-4">
      {/* ── Lo primero: cómo viene el mes ── */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base text-gray-700">Variación acumulada del mes</CardTitle>
          <p className="text-xs text-gray-500">
            La diferencia de un día es ruido: leer una varilla tiene un error propio de unos
            cientos de litros. Lo que dice algo es el acumulado — si es ruido se compensa solo,
            si es pérdida no vuelve.
          </p>
        </CardHeader>
        <CardContent>
          {conVariacion.length === 0 ? (
            <p className="py-4 text-center text-sm text-gray-400">
              Todavía no hay días cerrados con contador leído en este mes.
            </p>
          ) : (
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
              {conVariacion.map((v) => {
                const ui = ESTADO_MES_UI[v.estado_mes]
                const Icono = v.variacion_acumulada > 50 ? TrendingUp
                  : v.variacion_acumulada < -50 ? TrendingDown : Minus
                return (
                  <div key={v.grupo}
                       className="rounded-lg border border-gray-200 p-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold uppercase tracking-wide text-gray-600">
                        {v.grupo}
                      </span>
                      <span className={cn('rounded px-1.5 py-0.5 text-[10px] font-bold uppercase', ui.cls)}>
                        {ui.label}
                      </span>
                    </div>
                    <div className="mt-1.5 flex items-baseline gap-1.5">
                      <Icono className={cn('h-4 w-4',
                        v.estado_mes === 'investigar' ? 'text-red-600'
                          : v.estado_mes === 'vigilar' ? 'text-amber-600' : 'text-gray-400')} />
                      <span className="text-2xl font-bold tabular-nums text-gray-900">
                        {conSigno(v.variacion_acumulada)}
                      </span>
                      <span className="text-xs text-gray-500">L</span>
                    </div>
                    <p className="mt-0.5 text-xs text-gray-500">
                      {v.variacion_pct != null && <>{v.variacion_pct > 0 ? '+' : ''}{v.variacion_pct} % · </>}
                      sobre {miles(v.despachado_acumulado)} L movidos
                    </p>
                  </div>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── Entregables ── */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base text-gray-700">Entregables del cierre</CardTitle>
          <p className="text-xs text-gray-500">
            Salen del dato que ya está en el sistema. Los encabezados son los de las planillas de
            siempre, para que quien las recibe lea los números a la misma altura de siempre.
          </p>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {[
            { id: 'cierre' as const, label: 'Cierre Romeral', sub: 'una hoja por día y por estación' },
            { id: 'ac066' as const, label: 'FORM AC 066', sub: 'stock diario y KPI de llenado' },
            { id: 'bbdd' as const, label: 'BBDD', sub: 'transacciones con Semana ENAP' },
          ].map((b) => (
            <button key={b.id} onClick={() => bajar(b.id)} disabled={!!bajando}
                    className="flex flex-1 min-w-[180px] items-center gap-2 rounded-lg border
                               border-gray-300 px-3 py-2.5 text-left transition
                               hover:border-blue-400 hover:bg-blue-50 disabled:opacity-50">
              {bajando === b.id
                ? <Loader2 className="h-4 w-4 shrink-0 animate-spin text-blue-600" />
                : <Download className="h-4 w-4 shrink-0 text-gray-500" />}
              <span className="min-w-0">
                <span className="block text-sm font-medium text-gray-800">{b.label}</span>
                <span className="block truncate text-xs text-gray-500">{b.sub}</span>
              </span>
            </button>
          ))}
          <Link href="/dashboard/combustible/romeral/orpak/"
                className="flex flex-1 min-w-[180px] items-center gap-2 rounded-lg border
                           border-blue-300 bg-blue-50 px-3 py-2.5 transition hover:bg-blue-100">
            <Upload className="h-4 w-4 shrink-0 text-blue-600" />
            <span className="min-w-0">
              <span className="block text-sm font-medium text-blue-900">Cargar Orpak</span>
              <span className="block truncate text-xs text-blue-700">la tercera medida del cierre</span>
            </span>
          </Link>
        </CardContent>
      </Card>

      {/* ── El detalle diario, plegado ── */}
      <Card>
        <CardHeader className="cursor-pointer pb-2" onClick={() => setAbierto((v) => !v)}>
          <CardTitle className="flex items-center gap-2 text-base text-gray-700">
            {abierto ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
            Día por día: las tres medidas
            <span className="text-xs font-normal text-gray-400">({triangulo?.length ?? 0})</span>
          </CardTitle>
          {!abierto && (
            <p className="text-xs text-gray-500">
              Varilla, cuentalitros y Orpak. Dos de las tres siempre se parecen; la que se desvía
              dice dónde mirar.
            </p>
          )}
        </CardHeader>
        {abierto && (
          <CardContent className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-sm">
              <thead>
                <tr className="border-b border-gray-200 text-left text-[10px] uppercase tracking-wide text-gray-500">
                  <th className="py-1.5 pr-3">Día</th>
                  <th className="py-1.5 pr-3">Grupo</th>
                  <th className="py-1.5 pr-3 text-right">Varilla</th>
                  <th className="py-1.5 pr-3 text-right">Contador</th>
                  <th className="py-1.5 pr-3 text-right">Orpak</th>
                  <th className="py-1.5 pr-3 text-right">Cont − var</th>
                  <th className="py-1.5 pr-3 text-right">Cont − Orpak</th>
                  <th className="py-1.5 pr-3">Diagnóstico</th>
                  <th className="py-1.5" />
                </tr>
              </thead>
              <tbody>
                {(triangulo ?? [])
                  .filter((t) => t.diagnostico !== 'sin movimiento')
                  .map((t) => {
                    const ui = DIAGNOSTICO_UI[t.diagnostico]
                      ?? { label: t.diagnostico, cls: 'bg-gray-100 text-gray-600', explica: '' }
                    const c = cierrePorFecha.get(t.fecha)
                    return (
                      <tr key={`${t.fecha}-${t.grupo}`} className="border-b border-gray-100 last:border-0">
                        <td className="py-1.5 pr-3 tabular-nums text-gray-700">{t.fecha.slice(5)}</td>
                        <td className="py-1.5 pr-3 font-medium text-gray-800">{t.grupo}</td>
                        <td className="py-1.5 pr-3 text-right tabular-nums">{miles(t.por_varilla)}</td>
                        <td className="py-1.5 pr-3 text-right tabular-nums">{miles(t.por_contador)}</td>
                        <td className="py-1.5 pr-3 text-right tabular-nums">
                          {t.fuente === 'sin_registro'
                            ? <span className="text-gray-300">—</span>
                            : miles(t.por_sistema)}
                        </td>
                        <td className={cn('py-1.5 pr-3 text-right tabular-nums',
                          Math.abs(t.contador_menos_varilla) > 200 ? 'font-bold text-amber-700' : 'text-gray-500')}>
                          {conSigno(t.contador_menos_varilla)}
                        </td>
                        <td className={cn('py-1.5 pr-3 text-right tabular-nums',
                          Math.abs(t.contador_menos_sistema) > 200 ? 'font-bold text-amber-700' : 'text-gray-500')}>
                          {conSigno(t.contador_menos_sistema)}
                        </td>
                        <td className="py-1.5 pr-3">
                          <span title={ui.explica}
                                className={cn('rounded px-1.5 py-0.5 text-[10px] font-bold uppercase', ui.cls)}>
                            {ui.label}
                          </span>
                        </td>
                        <td className="py-1.5 text-right">
                          {c?.estado === 'firmado' && (
                            <button onClick={() => { setReabriendo(c.id); setMotivo('') }}
                                    title="Reabrir para corregir"
                                    className="text-gray-400 transition hover:text-blue-600">
                              <Unlock className="h-3.5 w-3.5" />
                            </button>
                          )}
                          {!!c?.reaperturas && (
                            <span className="ml-1 text-[10px] text-amber-700">×{c.reaperturas}</span>
                          )}
                        </td>
                      </tr>
                    )
                  })}
              </tbody>
            </table>
            {(triangulo ?? []).length === 0 && (
              <p className="py-6 text-center text-sm text-gray-400">
                No hay días cerrados en este período.
              </p>
            )}
          </CardContent>
        )}
      </Card>

      {/* ── Reabrir un cierre firmado ── */}
      {reabriendo && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
             onClick={() => setReabriendo(null)}>
          <div className="w-full max-w-md rounded-lg bg-white p-5" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-base font-bold text-gray-900">Reabrir el cierre</h3>
            <p className="mt-1 text-sm text-gray-600">
              Este cierre ya está firmado y ya se informó. Reabrirlo queda registrado con su
              motivo, y el documento que salga después va a ser distinto al que se envió.
            </p>
            <textarea
              value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3}
              placeholder="Por qué hay que corregirlo"
              className="mt-3 w-full rounded border border-gray-300 p-2 text-sm"
            />
            <div className="mt-3 flex gap-2">
              <button
                onClick={() => confirmarReapertura(reabriendo)}
                disabled={motivo.trim().length < 10}
                className="flex-1 rounded bg-blue-600 py-2 text-sm font-medium text-white
                           hover:bg-blue-700 disabled:opacity-40"
              >
                Reabrir
              </button>
              <button onClick={() => setReabriendo(null)}
                      className="rounded border border-gray-300 px-4 py-2 text-sm text-gray-700">
                Cancelar
              </button>
            </div>
            {motivo.trim().length > 0 && motivo.trim().length < 10 && (
              <p className="mt-1.5 text-xs text-amber-700">
                Escriba el motivo completo: quien lea la bitácora en tres meses no va a estar acá
                para preguntar.
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
