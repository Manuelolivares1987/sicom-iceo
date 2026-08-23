'use client'

// ============================================================================
// Control diario de combustible — Romeral (MIG321)
// ----------------------------------------------------------------------------
// La pantalla de la Secretaría Técnica. No es un tablero para mirar: es una
// lista de lo que hay que resolver.
//
// LA DECISIÓN QUE ORDENA TODO: el día tiene DOS estados, no uno.
//   · Volumen — varilla contra cuentalitros. Se cierra siempre, el mismo día.
//   · Imputación — a quién se le cargó. Depende de Orpak, y en agosto Orpak
//     llegó una vez en nueve días.
// Mostrarlos juntos, como hoy, hace que un mes entero se vea "atrasado" cuando
// en realidad el volumen está medido y lo que falta es saber a quién imputarlo.
//
// Control por excepción: hoy se revisa el 100 % de las transacciones, y revisar
// todo es no revisar nada. Acá sólo aparece lo que se sale del patrón.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Fuel, AlertTriangle, CheckCircle2, Clock, Ruler, Gauge, Truck,
  FileWarning, Check, ChevronRight, Droplets, Thermometer,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage, formatDate } from '@/lib/utils'
import { FAENA_ROMERAL, getFaenaPorCodigo } from '@/lib/services/combustible-faena'
import {
  getControlDiario, getExcepciones, confirmarCeco,
  type ControlDia, type Excepcion,
} from '@/lib/services/combustible-cierre'
import { CierreMensual } from '@/components/combustible/cierre-mensual'
import { PendientesTurno } from '@/components/combustible/pendientes-turno'

const miles = (n: number | null | undefined) =>
  n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

const VOLUMEN_UI: Record<string, { label: string; cls: string }> = {
  cuadrado:   { label: 'Cuadrado',    cls: 'bg-emerald-100 text-emerald-800' },
  revisar:    { label: 'Revisar',     cls: 'bg-amber-100 text-amber-800' },
  // Sin contador leído no hay control cruzado. No es verde ni rojo: es que no
  // se puede saber, y esa es una tercera cosa.
  incompleto: { label: 'Sin contador', cls: 'bg-orange-100 text-orange-800' },
  borrador:   { label: 'Sin firmar',  cls: 'bg-blue-100 text-blue-800' },
  sin_cierre: { label: 'Sin cerrar',  cls: 'bg-gray-100 text-gray-500' },
}
const IMPUTACION_UI: Record<string, { label: string; cls: string }> = {
  completa:   { label: 'Completa',     cls: 'bg-emerald-100 text-emerald-800' },
  // Se sabe perfectamente de quién es la carga: el código viene en la
  // transacción y no está en el maestro de la faena. Es una ficha que falta
  // crear, no información que falte. Mezclarlo con «falta CECO» dejaba un mes
  // entero en rojo por una tarea de escritorio de diez minutos.
  por_registrar: { label: 'CECO por dar de alta', cls: 'bg-blue-100 text-blue-800' },
  incompleta: { label: 'Falta CECO',   cls: 'bg-amber-100 text-amber-800' },
  sin_datos:  { label: 'Sin registro', cls: 'bg-red-100 text-red-700' },
}
const EXCEPCION_UI: Record<string, { label: string; icono: any; cls: string }> = {
  // Arriba lo más grave: salió combustible del estanque y no hay a quién
  // cargárselo. Es el hallazgo que justifica todo el control de inventario.
  salida_sin_imputar:       { label: 'Salió sin imputar',    icono: AlertTriangle, cls: 'text-red-600' },
  agua_en_estanque:         { label: 'Agua en el estanque',  icono: Droplets,    cls: 'text-red-600' },
  diferencia_por_temperatura: { label: 'Diferencia por temperatura', icono: Thermometer, cls: 'text-blue-600' },
  ceco_por_confirmar:       { label: 'CECO por confirmar',   icono: FileWarning, cls: 'text-blue-600' },
  despacho_sin_ceco:        { label: 'Carga sin CECO',       icono: FileWarning, cls: 'text-amber-600' },
  fuera_de_tolerancia:      { label: 'Fuera de tolerancia',  icono: Gauge,       cls: 'text-red-600' },
  contador_sin_leer:        { label: 'Contador sin leer',    icono: Gauge,       cls: 'text-orange-600' },
  medicion_sin_foto:        { label: 'Medición sin foto',    icono: AlertTriangle, cls: 'text-amber-600' },
  recepcion_con_diferencia: { label: 'Guía no coincide',     icono: Truck,       cls: 'text-amber-600' },
}

function Pill({ cls, children }: { cls: string; children: React.ReactNode }) {
  return (
    <span className={cn('inline-block rounded px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide', cls)}>
      {children}
    </span>
  )
}

export default function ControlCombustibleRomeralPage() {
  useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()

  const hoy = new Date()
  const [desde, setDesde] = useState(
    `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-01`,
  )
  const [hasta, setHasta] = useState(
    `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-${String(hoy.getDate()).padStart(2, '0')}`,
  )

  const { data: faena } = useQuery({
    queryKey: ['faena', FAENA_ROMERAL],
    queryFn: () => getFaenaPorCodigo(FAENA_ROMERAL),
  })

  const { data: dias, isLoading } = useQuery({
    queryKey: ['comb-control-diario', faena?.id, desde, hasta],
    queryFn: () => getControlDiario(faena!.id, desde, hasta),
    enabled: !!faena?.id,
  })

  const { data: excepciones } = useQuery({
    queryKey: ['comb-excepciones', faena?.id],
    queryFn: () => getExcepciones(faena!.id),
    enabled: !!faena?.id,
  })

  const confirmar = useMutation({
    mutationFn: ({ id, codigo }: { id: string; codigo?: string }) => confirmarCeco(id, codigo),
    onSuccess: (r) => {
      qc.invalidateQueries({ queryKey: ['comb-excepciones'] })
      qc.invalidateQueries({ queryKey: ['comb-control-diario'] })
      toast.success(
        r.fusionado_con
          ? `Fusionado con el CECO existente · ${r.despachos_movidos} carga(s) reapuntada(s)`
          : 'CECO confirmado',
      )
    },
    onError: (e) => toast.error(errorMessage(e, 'No se pudo confirmar')),
  })

  const resumen = useMemo(() => {
    const d = dias ?? []
    return {
      dias: d.length,
      atencion: d.reduce((a, x) => a + Number(x.grupos_atencion ?? 0), 0),
      volumenCerrado: d.filter((x) => x.volumen_estado === 'cuadrado').length,
      volumenRevisar: d.filter((x) => x.volumen_estado === 'revisar').length,
      volumenSinCerrar: d.filter((x) => x.volumen_estado === 'sin_cierre').length,
      volumenIncompleto: d.filter((x) => x.volumen_estado === 'incompleto').length,
      // Lo que de verdad hay que decirle al mandante: cuántos días de
      // imputación están esperando data que no depende de nosotros.
      sinOrpak: d.filter((x) => x.imputacion_estado === 'sin_datos').length,
      porRegistrar: d.filter((x) => x.imputacion_estado === 'por_registrar').length,
      cecosPorDarDeAlta: d.reduce((a, x) => a + Number(x.ceco_fuera_del_maestro ?? 0), 0),
      litrosSinImputar: d
        .filter((x) => x.imputacion_estado === 'sin_datos')
        .reduce((a, x) => a + Number(x.v_mec ?? 0), 0),
    }
  }, [dias])

  const porTipo = useMemo(() => {
    const m = new Map<string, Excepcion[]>()
    for (const e of excepciones ?? []) {
      const arr = m.get(e.tipo) ?? []
      arr.push(e)
      m.set(e.tipo, arr)
    }
    return m
  }, [excepciones])

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-gray-900">
            <Fuel className="h-7 w-7 text-orange-500" />
            Control diario de combustible
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-gray-500">
            Faena Romeral. El día tiene dos cierres independientes: el de <strong>volumen</strong>
            {' '}se cierra siempre el mismo día con varilla y contador; el de <strong>imputación</strong>
            {' '}espera a Orpak y no bloquea al primero. Se cuadra por grupo: los dos tanques de la
            isla Mina están interconectados y separados dan diferencias de miles de litros que se
            cancelan entre sí. Umbral: cuadra bajo 200 L, atención hasta 500 L.
          </p>
        </div>
        <div className="flex gap-2">
          <div>
            <label className="block text-[10px] uppercase text-gray-400">Desde</label>
            <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)}
                   className="h-9 rounded border border-gray-300 px-2 text-sm" />
          </div>
          <div>
            <label className="block text-[10px] uppercase text-gray-400">Hasta</label>
            <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)}
                   className="h-9 rounded border border-gray-300 px-2 text-sm" />
          </div>
        </div>
      </div>

      {/* Lo primero: si hay días de imputación esperando, decirlo con número */}
      {resumen.sinOrpak > 0 && (
        <Card className="border-amber-300 bg-amber-50">
          <CardContent className="flex items-start gap-3 p-4">
            <Clock className="mt-0.5 h-5 w-5 shrink-0 text-amber-600" />
            <div>
              <p className="text-sm font-bold text-amber-900">
                {resumen.sinOrpak} día{resumen.sinOrpak > 1 ? 's' : ''} con el volumen medido y sin ningún movimiento registrado
              </p>
              <p className="mt-0.5 text-xs leading-relaxed text-amber-800">
                Son {miles(resumen.litrosSinImputar)} L que salieron y están medidos por contador, y
                no hay ni una transacción que diga a quién. Falta cargar Orpak de esos días, o el
                combustible salió sin registrarse. El cierre de volumen igual se puede firmar.
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* CECO que vienen en la transacción y no están en el maestro. No es
          información que falte: es una ficha que falta crear. */}
      {resumen.porRegistrar > 0 && (
        <Card className="border-blue-300 bg-blue-50">
          <CardContent className="flex items-start gap-3 p-4">
            <FileWarning className="mt-0.5 h-5 w-5 shrink-0 text-blue-600" />
            <div>
              <p className="text-sm font-bold text-blue-900">
                {miles(resumen.cecosPorDarDeAlta)} cargas con un CECO que no está en el maestro
              </p>
              <p className="mt-0.5 text-xs leading-relaxed text-blue-800">
                Traen el código y se sabe de quién son —casi siempre transportistas nuevos—, pero no
                tienen ficha en la faena. Darlos de alta cierra la imputación de {resumen.porRegistrar}
                {' '}día{resumen.porRegistrar > 1 ? 's' : ''}.
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Cifras del período */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[
          { label: 'Días con volumen cuadrado', valor: resumen.volumenCerrado, icono: CheckCircle2, cls: 'text-emerald-600' },
          { label: 'Días para revisar', valor: resumen.volumenRevisar, icono: AlertTriangle, cls: 'text-amber-600' },
          { label: 'Días sin contador leído', valor: resumen.volumenIncompleto, icono: Gauge, cls: 'text-orange-500' },
          { label: 'Excepciones abiertas', valor: excepciones?.length ?? 0, icono: FileWarning, cls: 'text-blue-600' },
        ].map((k) => (
          <Card key={k.label}>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium text-gray-500">{k.label}</span>
                <k.icono className={cn('h-4 w-4', k.cls)} />
              </div>
              <p className="mt-2 text-3xl font-bold tabular-nums text-gray-900">{k.valor}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Lo que se le pidió a la faena y todavía no se hace. Va arriba porque es
          lo que el turno tiene que ver antes de salir, no al final del mes. */}
      {faena?.id && <PendientesTurno faenaId={faena.id} />}

      {/* El cierre del mes: acumulado, entregables y el detalle de las tres medidas */}
      {faena?.id && <CierreMensual faenaId={faena.id} desde={desde} hasta={hasta} />}

      {/* Excepciones: lo que hay que resolver */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base text-gray-700">Qué hay que resolver</CardTitle>
          <p className="text-xs text-gray-500">
            Sólo lo que se sale del patrón. Revisar el cien por ciento es no revisar nada.
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          {(excepciones ?? []).length === 0 ? (
            <p className="py-6 text-center text-sm text-gray-400">
              Nada pendiente en este momento.
            </p>
          ) : (
            Array.from(porTipo.entries()).map(([tipo, lista]) => {
              const ui = EXCEPCION_UI[tipo] ?? { label: tipo, icono: FileWarning, cls: 'text-gray-500' }
              return (
                <div key={tipo}>
                  <p className="mb-1.5 flex items-center gap-2 text-xs font-bold uppercase tracking-wide text-gray-500">
                    <ui.icono className={cn('h-4 w-4', ui.cls)} />
                    {ui.label} <span className="text-gray-400">({lista.length})</span>
                  </p>
                  <div className="overflow-hidden rounded-lg border border-gray-200">
                    {lista.slice(0, 12).map((e, i) => (
                      <div key={`${tipo}-${i}`}
                           className="flex items-center gap-3 border-b border-gray-100 px-3 py-2 last:border-0">
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-medium text-gray-800">{e.referencia}</p>
                          <p className="truncate text-xs text-gray-500">
                            {e.fecha ? `${formatDate(e.fecha)} · ` : ''}{e.detalle}
                          </p>
                        </div>
                        {e.litros != null && (
                          <span className="shrink-0 text-sm font-semibold tabular-nums text-gray-600">
                            {miles(e.litros)} L
                          </span>
                        )}
                      </div>
                    ))}
                    {lista.length > 12 && (
                      <p className="px-3 py-2 text-xs text-gray-400">y {lista.length - 12} más</p>
                    )}
                  </div>
                </div>
              )
            })
          )}
        </CardContent>
      </Card>

      {/* El mes, día por día */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base text-gray-700">Día por día</CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto p-0">
          {isLoading ? (
            <div className="flex justify-center py-10"><Spinner className="h-6 w-6" /></div>
          ) : (dias ?? []).length === 0 ? (
            <p className="py-10 text-center text-sm text-gray-400">
              Sin movimiento registrado en el período.
            </p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-gray-50 text-left text-[11px] uppercase tracking-wide text-gray-500">
                  <th className="px-3 py-2">Día</th>
                  <th className="px-3 py-2">Volumen</th>
                  <th className="px-3 py-2 text-right">Varilla</th>
                  <th className="px-3 py-2 text-right">Contador</th>
                  <th className="px-3 py-2 text-right">Dif.</th>
                  <th className="px-3 py-2">Imputación</th>
                  <th className="px-3 py-2 text-right">Cargas</th>
                  <th className="px-3 py-2 text-right">Recibido</th>
                  <th className="px-3 py-2">Midió</th>
                </tr>
              </thead>
              <tbody>
                {(dias ?? []).map((d: ControlDia) => {
                  const v = VOLUMEN_UI[d.volumen_estado] ?? VOLUMEN_UI.sin_cierre
                  const im = IMPUTACION_UI[d.imputacion_estado] ?? IMPUTACION_UI.sin_datos
                  return (
                    <tr key={d.fecha} className="border-b last:border-0 hover:bg-gray-50">
                      <td className="whitespace-nowrap px-3 py-2 font-medium">{formatDate(d.fecha)}</td>
                      <td className="px-3 py-2">
                        <Pill cls={v.cls}>{v.label}</Pill>
                        {(d.puntos_medidos ?? 0) > 0 && (
                          <span className="ml-1.5 text-xs text-gray-400">
                            {d.puntos_medidos}/{d.puntos_total}
                          </span>
                        )}
                      </td>
                      <td className="px-3 py-2 text-right tabular-nums text-gray-600">{miles(d.v_fis)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-gray-600">{miles(d.v_mec)}</td>
                      <td className={cn(
                        'px-3 py-2 text-right font-semibold tabular-nums',
                        (d.puntos_fuera_tolerancia ?? 0) > 0 ? 'text-amber-700' : 'text-gray-500',
                      )}>
                        {d.var1 != null ? `${Number(d.var1) > 0 ? '+' : ''}${miles(d.var1)}` : '—'}
                      </td>
                      <td className="px-3 py-2">
                        <Pill cls={im.cls}>{im.label}</Pill>
                        {(d.sin_ceco ?? 0) > 0 && (
                          <span className="ml-1.5 text-xs font-semibold text-amber-700">{d.sin_ceco}</span>
                        )}
                      </td>
                      <td className="px-3 py-2 text-right tabular-nums text-gray-600">{d.despachos ?? '—'}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-gray-600">{miles(d.litros_recibidos)}</td>
                      <td className="truncate px-3 py-2 text-xs text-gray-500">{d.medido_por ?? '—'}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>

      {/* CECO anotados en terreno: la acción está acá */}
      {(porTipo.get('ceco_por_confirmar') ?? []).length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base text-gray-700">CECO anotados en terreno</CardTitle>
            <p className="text-xs text-gray-500">
              Los escribió quien despachó porque no estaban en el catálogo. Confirmar uno lo incorpora;
              si el código ya existía, las cargas se reapuntan al bueno sin duplicar.
            </p>
          </CardHeader>
          <CardContent className="space-y-2">
            {(porTipo.get('ceco_por_confirmar') ?? []).map((e, i) => (
              <div key={i} className="flex flex-wrap items-center gap-3 rounded-lg border border-blue-200 bg-blue-50 px-3 py-2.5">
                <div className="min-w-0 flex-1">
                  <p className="font-mono text-sm font-bold text-gray-900">{e.referencia}</p>
                  <p className="text-xs text-gray-600">{e.detalle}</p>
                </div>
                <span className="shrink-0 text-sm tabular-nums text-gray-600">
                  {e.cantidad} carga{e.cantidad === 1 ? '' : 's'} · {miles(e.litros)} L
                </span>
                <ConfirmarCeco
                  codigo={e.referencia ?? ''}
                  onConfirmar={(codigo) => {
                    // La vista trae el código, no el id: se resuelve por código.
                    void confirmarPorCodigo(codigo, e.referencia ?? '', confirmar)
                  }}
                  pendiente={confirmar.isPending}
                />
              </div>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  )
}

/**
 * La vista de excepciones expone el código del CECO, no su id. Para confirmar
 * hay que resolverlo — se hace acá y no en la vista para que la vista siga
 * sirviendo a cualquier consumidor sin arrastrar ids internos.
 */
async function confirmarPorCodigo(
  codigoNuevo: string,
  codigoActual: string,
  mut: { mutate: (v: { id: string; codigo?: string }) => void },
) {
  const { supabase } = await import('@/lib/supabase')
  const { data } = await supabase
    .from('combustible_faena_cecos')
    .select('id').eq('codigo', codigoActual).eq('confirmado', false).limit(1).maybeSingle()
  if (data?.id) mut.mutate({ id: data.id, codigo: codigoNuevo || undefined })
}

function ConfirmarCeco({
  codigo, onConfirmar, pendiente,
}: {
  codigo: string
  onConfirmar: (codigo: string) => void
  pendiente: boolean
}) {
  const [valor, setValor] = useState(codigo)
  return (
    <div className="flex shrink-0 items-center gap-2">
      <input
        value={valor}
        onChange={(e) => setValor(e.target.value)}
        className="h-9 w-32 rounded border border-gray-300 px-2 font-mono text-sm"
        aria-label="Código de CECO"
      />
      <button
        onClick={() => onConfirmar(valor)}
        disabled={pendiente}
        className="inline-flex h-9 items-center gap-1 rounded bg-blue-600 px-3 text-sm font-semibold text-white hover:bg-blue-700 disabled:opacity-50"
      >
        <Check className="h-4 w-4" /> Confirmar
      </button>
    </div>
  )
}
