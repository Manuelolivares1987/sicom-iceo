'use client'

// ============================================================================
// Cuánto nos estamos demorando. [MIG399]
// ----------------------------------------------------------------------------
// Manuel: «necesito empezar a medir cuánto me estoy demorando en checklist, en
// la ejecución de las NC, en conseguir repuestos, porque esos parámetros
// impactan en la remuneración».
//
// Un número que paga sueldos no puede salir de un promedio inventado. Por eso
// esta pantalla muestra siempre CUÁNTOS datos hay detrás de cada cifra, y
// cuando no hay ninguno lo dice con todas sus letras en vez de mostrar un cero.
// Con pocos casos manda la mediana: un solo trabajo que se alargó tres días
// mueve el promedio y engaña.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Clock, Package, AlertTriangle, ClipboardList, Info } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getTiemposChecklist, getTiemposRepuesto, getTiemposNC,
  promedio, mediana, horasLegibles,
} from '@/lib/services/taller-tiempos'

type Tab = 'repuestos' | 'checklist' | 'nc'

// ── Una cifra, con el respaldo a la vista ───────────────────────────────────
function Cifra({ titulo, valor, casos, ayuda }: {
  titulo: string; valor: string; casos: number; ayuda?: string
}) {
  const sinDatos = casos === 0
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-3">
      <div className="text-[11px] font-medium uppercase tracking-wide text-gray-500">{titulo}</div>
      <div className={`mt-1 text-2xl font-bold tabular-nums ${sinDatos ? 'text-gray-300' : 'text-gray-900'}`}>
        {sinDatos ? 'Sin datos' : valor}
      </div>
      <div className="mt-0.5 text-[11px] text-gray-500">
        {sinDatos ? 'todavía nadie registró uno' : `sobre ${casos} caso${casos !== 1 ? 's' : ''}`}
      </div>
      {ayuda && <div className="mt-1 text-[11px] leading-tight text-gray-400">{ayuda}</div>}
    </div>
  )
}

function Aviso({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-start gap-2 rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-[12px] text-blue-900">
      <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
      <div>{children}</div>
    </div>
  )
}

export default function TiemposTallerPage() {
  const { loading: authLoading } = useRequireAuth()
  const [tab, setTab] = useState<Tab>('repuestos')

  const rep = useQuery({ queryKey: ['tiempos-repuesto'], queryFn: getTiemposRepuesto })
  const chk = useQuery({ queryKey: ['tiempos-checklist'], queryFn: getTiemposChecklist })
  const nc  = useQuery({ queryKey: ['tiempos-nc'], queryFn: getTiemposNC })

  const R = useMemo(() => rep.data ?? [], [rep.data])
  const C = useMemo(() => chk.data ?? [], [chk.data])
  const N = useMemo(() => nc.data ?? [], [nc.data])

  if (authLoading) return <div className="flex justify-center py-20"><Spinner /></div>

  const tabs: Array<{ v: Tab; label: string; icon: typeof Clock; n: number }> = [
    { v: 'repuestos', label: 'Conseguir un repuesto', icon: Package, n: R.length },
    { v: 'checklist', label: 'Hacer el checklist', icon: ClipboardList, n: C.length },
    { v: 'nc', label: 'Resolver una NC', icon: AlertTriangle, n: N.length },
  ]

  return (
    <div className="space-y-4 p-4 md:p-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold">
          <Clock className="h-6 w-6 text-indigo-600" /> Cuánto nos demoramos
        </h1>
        <p className="mt-1 max-w-3xl text-sm text-gray-600">
          Los tres tramos del trabajo del taller, medidos con los relojes que el sistema ya
          venía guardando. Cada cifra dice sobre cuántos casos está calculada: si no hay
          casos, dice «sin datos» en vez de inventar un cero.
        </p>
      </div>

      <div className="flex flex-wrap gap-1 border-b border-gray-200">
        {tabs.map((t) => (
          <button key={t.v} type="button" onClick={() => setTab(t.v)}
                  className={`flex items-center gap-1.5 rounded-t-lg px-3 py-2 text-sm font-medium ${
                    tab === t.v
                      ? 'border-b-2 border-indigo-600 text-indigo-700'
                      : 'text-gray-500 hover:text-gray-700'}`}>
            <t.icon className="h-4 w-4" /> {t.label}
            <span className="rounded-full bg-gray-100 px-1.5 text-[10px] text-gray-600">{t.n}</span>
          </button>
        ))}
      </div>

      {/* ── Repuestos ────────────────────────────────────────────────────── */}
      {tab === 'repuestos' && (
        rep.isLoading ? <div className="flex justify-center py-10"><Spinner /></div> : (
        <div className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {/* [MIG404] Sólo lo que pidió un operador. Lo que la jefatura agrega
                nace aprobado en el mismo instante: mide cero por construcción y
                arrastraba la mediana de todos a cero. */}
            <Cifra titulo="Pedir → aprobar"
                   valor={horasLegibles(mediana(R.map((r) => r.h_pedir_a_aprobar)))}
                   casos={R.filter((r) => r.h_pedir_a_aprobar != null).length}
                   ayuda="Sólo lo que pidió un operador y esperó respuesta. Lo que agrega la jefatura nace aprobado y no cuenta acá" />
            <Cifra titulo="Aprobar → vale"
                   valor={horasLegibles(mediana(R.map((r) => r.h_aprobar_a_vale)))}
                   casos={R.filter((r) => r.h_aprobar_a_vale != null).length}
                   ayuda="Desde agosto el vale sale al aprobar: este tramo debería ir a cero" />
            <Cifra titulo="Vale → entrega"
                   valor={horasLegibles(mediana(R.map((r) => r.h_vale_a_entrega)))}
                   casos={R.filter((r) => r.h_vale_a_entrega != null).length}
                   ayuda="Desde que bodega tiene el vale hasta que entrega el repuesto" />
            <Cifra titulo="Total, de punta a punta"
                   valor={horasLegibles(mediana(R.map((r) => r.h_total)))}
                   casos={R.filter((r) => r.h_total != null).length}
                   ayuda="Sólo cuenta lo que ya se entregó" />
          </div>

          {R.filter((r) => r.h_vale_a_entrega != null).length === 0 && R.length > 0 && (
            <Aviso>
              <b>Todavía no hay ninguna entrega registrada.</b> El tramo «vale → entrega» y el
              total van a aparecer cuando bodega despache el primer vale desde el sistema. Los
              otros dos tramos ya tienen datos reales.
            </Aviso>
          )}

          <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-left text-[11px] uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="p-2">Qué se pidió</th>
                  <th className="p-2">Equipo</th>
                  <th className="p-2">Lo pidió</th>
                  <th className="p-2 text-right">Pedir→aprobar</th>
                  <th className="p-2 text-right">Aprobar→vale</th>
                  <th className="p-2 text-right">Vale→entrega</th>
                  <th className="p-2 text-right">Lleva esperando</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {R.map((r) => (
                  <tr key={r.recurso_id} className="hover:bg-gray-50">
                    <td className="p-2">
                      <div className="font-medium text-gray-800">{r.que_se_pidio ?? '—'}</div>
                      {r.producto_codigo
                        ? <div className="font-mono text-[10px] text-gray-500">{r.producto_codigo}</div>
                        : <div className="text-[10px] text-amber-600">sin código de catálogo</div>}
                    </td>
                    <td className="p-2 whitespace-nowrap text-gray-600">
                      {r.activo_patente ?? r.activo_codigo ?? '—'}
                      <div className="font-mono text-[10px] text-gray-400">{r.ot_folio}</div>
                    </td>
                    <td className="p-2 text-gray-600">
                      {r.lo_pidio ?? '—'}
                      {!r.lo_pidio_el_operador && (
                        <div className="text-[10px] text-gray-400"
                             title="La jefatura lo agregó ya aprobado: no hubo espera que medir">
                          lo agregó la jefatura
                        </div>
                      )}
                    </td>
                    <td className="p-2 text-right tabular-nums">{horasLegibles(r.h_pedir_a_aprobar)}</td>
                    <td className="p-2 text-right tabular-nums">{horasLegibles(r.h_aprobar_a_vale)}</td>
                    <td className="p-2 text-right tabular-nums">{horasLegibles(r.h_vale_a_entrega)}</td>
                    <td className={`p-2 text-right tabular-nums font-semibold ${
                      (r.h_esperando ?? 0) > 120 ? 'text-red-600'
                      : (r.h_esperando ?? 0) > 48 ? 'text-amber-600' : 'text-gray-400'}`}>
                      {r.h_esperando != null ? horasLegibles(r.h_esperando) : 'entregado'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        )
      )}

      {/* ── Checklist ────────────────────────────────────────────────────── */}
      {tab === 'checklist' && (
        chk.isLoading ? <div className="flex justify-center py-10"><Spinner /></div> : (
        <div className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Cifra titulo="Horas efectivas por checklist"
                   valor={`${mediana(C.map((c) => c.horas_efectivas)) ?? '—'} h`}
                   casos={C.filter((c) => c.horas_efectivas != null).length}
                   ayuda="Descuenta pausas y colación" />
            <Cifra titulo="Minutos por ítem"
                   valor={`${mediana(C.map((c) => c.min_por_item)) ?? '—'} min`}
                   casos={C.filter((c) => c.min_por_item != null).length}
                   ayuda="La medida comparable entre checklists de distinto largo" />
            {/* [MIG400] La demora que duele es la de adentro del día. La noche
                y la colación van aparte: un checklist repartido en tres
                jornadas no es un checklist demorado. */}
            <Cifra titulo="Demora real"
                   valor={`${mediana(C.map((c) => c.horas_demora_real)) ?? '—'} h`}
                   casos={C.filter((c) => (c.horas_demora_real ?? 0) > 0).length}
                   ayuda="Espera de repuesto, equipo no disponible u otro. NO cuenta la noche ni la colación" />
            <Cifra titulo="Jornadas por checklist"
                   valor={`${mediana(C.map((c) => c.jornadas)) ?? '—'}`}
                   casos={C.filter((c) => c.jornadas != null).length}
                   ayuda="En cuántos días distintos se trabajó" />
          </div>

          {C.some((c) => (c.pausas_sin_declarar ?? 0) > 0) && (
            <Aviso>
              <b>Hay pausas que nadie clasificó.</b> Cuando el mecánico no dice por qué para, el
              motivo se deduce de cuánto duró: si cruza la medianoche o pasa de 10 horas, se toma
              como fin de jornada y no cuenta como demora. Es una suposición razonable, pero es
              una suposición — están marcadas como «sin declarar».
            </Aviso>
          )}

          {C.length < 20 && (
            <Aviso>
              <b>Hay muy pocas ejecuciones registradas ({C.length}).</b> El cronómetro corre sólo
              cuando el mecánico aprieta «Iniciar» y «Finalizar» en su teléfono. Mientras el
              taller no use esos botones de forma pareja, estos promedios no sirven para
              comparar personas ni para pagar: sirven para ver que el registro todavía no está
              instalado como costumbre.
            </Aviso>
          )}

          <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-left text-[11px] uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="p-2">OT</th>
                  <th className="p-2">Equipo</th>
                  <th className="p-2">Quién</th>
                  <th className="p-2 text-right">Ítems</th>
                  <th className="p-2 text-right">Jornadas</th>
                  <th className="p-2 text-right">Calendario</th>
                  <th className="p-2 text-right">Efectivas</th>
                  <th className="p-2 text-right">Demora real</th>
                  <th className="p-2 text-right">Min/ítem</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {C.map((c) => (
                  <tr key={c.ejecucion_id} className="hover:bg-gray-50">
                    <td className="p-2 font-mono text-xs">{c.ot_folio}</td>
                    <td className="p-2 whitespace-nowrap text-gray-600">{c.activo_patente ?? c.activo_codigo ?? '—'}</td>
                    <td className="p-2 text-gray-600">{c.ejecutor}</td>
                    <td className="p-2 text-right tabular-nums text-gray-600">{c.items_hechos ?? 0}/{c.items_totales ?? 0}</td>
                    <td className="p-2 text-right tabular-nums text-gray-600">{c.jornadas ?? '—'}</td>
                    <td className="p-2 text-right tabular-nums text-gray-500">
                      {c.dias_calendario != null ? `${c.dias_calendario} d` : '—'}
                    </td>
                    <td className="p-2 text-right tabular-nums font-semibold">{c.horas_efectivas ?? '—'}</td>
                    <td className="p-2 text-right tabular-nums">
                      {(c.horas_demora_real ?? 0) > 0
                        ? <span className="font-semibold text-amber-700">{c.horas_demora_real} h</span>
                        : <span className="text-gray-400">—</span>}
                      {(c.pausas_sin_declarar ?? 0) > 0 && (
                        <div className="text-[10px] font-normal text-gray-400"
                             title="Nadie declaró por qué se pausó: el motivo se dedujo de cuánto duró">
                          {c.pausas_sin_declarar} sin declarar
                        </div>
                      )}
                    </td>
                    <td className="p-2 text-right tabular-nums">{c.min_por_item ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        )
      )}

      {/* ── No conformidades ─────────────────────────────────────────────── */}
      {tab === 'nc' && (
        nc.isLoading ? <div className="flex justify-center py-10"><Spinner /></div> : (
        <div className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Cifra titulo="Detectada → al taller"
                   valor={`${mediana(N.map((x) => x.dias_detectada_a_taller)) ?? '—'} días`}
                   casos={N.filter((x) => x.dias_detectada_a_taller != null).length}
                   ayuda="Desde que se levanta hasta que la OT arranca" />
            <Cifra titulo="Detectada → resuelta"
                   valor={`${mediana(N.map((x) => x.dias_detectada_a_resuelta)) ?? '—'} días`}
                   casos={N.filter((x) => x.dias_detectada_a_resuelta != null).length}
                   ayuda="El ciclo completo" />
            <Cifra titulo="Lo que lleva abierta la más vieja"
                   valor={`${Math.max(0, ...N.map((x) => x.dias_abierta ?? 0))} días`}
                   casos={N.filter((x) => x.dias_abierta != null).length}
                   ayuda="La que más tiempo lleva sin cerrarse" />
            <Cifra titulo="Abiertas ahora"
                   valor={String(N.filter((x) => !x.resuelto).length)}
                   casos={N.length} />
          </div>

          {N.filter((x) => x.resuelto).length === 0 && N.length > 0 && (
            <Aviso>
              <b>No hay ninguna NC marcada como resuelta.</b> Sin cierres, el ciclo completo no
              se puede medir todavía; lo único real por ahora es cuánto llevan abiertas. El
              cierre se registra cuando la OT correctiva se cierra.
            </Aviso>
          )}

          <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-left text-[11px] uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="p-2">Hallazgo</th>
                  <th className="p-2">Equipo</th>
                  <th className="p-2">Estado</th>
                  <th className="p-2 text-right">Al taller</th>
                  <th className="p-2 text-right">Resuelta</th>
                  <th className="p-2 text-right">Lleva abierta</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {N.slice(0, 200).map((x) => (
                  <tr key={x.nc_id} className="hover:bg-gray-50">
                    <td className="p-2">
                      <div className="line-clamp-1 max-w-md text-gray-800">{x.descripcion ?? '—'}</div>
                    </td>
                    <td className="p-2 whitespace-nowrap text-gray-600">{x.activo_patente ?? x.activo_codigo ?? '—'}</td>
                    <td className="p-2 text-gray-600">{x.estado_planificacion ?? '—'}</td>
                    <td className="p-2 text-right tabular-nums">{x.dias_detectada_a_taller ?? '—'}</td>
                    <td className="p-2 text-right tabular-nums">{x.dias_detectada_a_resuelta ?? '—'}</td>
                    <td className={`p-2 text-right tabular-nums font-semibold ${
                      (x.dias_abierta ?? 0) > 30 ? 'text-red-600'
                      : (x.dias_abierta ?? 0) > 14 ? 'text-amber-600' : 'text-gray-500'}`}>
                      {x.dias_abierta != null ? `${x.dias_abierta} d` : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        )
      )}
    </div>
  )
}
