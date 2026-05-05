'use client'

import { useMemo } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'
import {
  ArrowLeft, Calendar, ClipboardList, Hammer, MessageSquare, Phone,
  Play, MapPin, ListChecks, AlertTriangle,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import {
  useCalamaOT, useCalamaSubtareas, useCalamaObservaciones,
  useCalamaMateriales, useCalamaContactos, useCalamaPrecheck,
  useCalamaZonas, useIniciarEjecucionOT,
} from '@/hooks/use-calama'
import { PrecheckPanel } from '@/components/calama/precheck-panel'
import { EstadoBadge, BarraAvanceDual } from '@/components/calama/gantt-table'
import { zonaCodeFromFolio, excelCodigoFromFolio, desviacionPp } from '@/lib/services/calama'
import { useEventosAvanceOT } from '@/hooks/use-calama-avance'

export default function OTDetallePage() {
  useRequireAuth()
  const params = useParams<{ id: string }>()
  const id = params?.id as string | undefined

  const { data: ot, isLoading, error } = useCalamaOT(id)
  const { data: subtareas } = useCalamaSubtareas(id)
  const { data: observaciones } = useCalamaObservaciones(id)
  const { data: precheck } = useCalamaPrecheck(id)

  const planificacionId = ot?.planificacion_id
  const faenaId = ot?.faena_calama_id

  const { data: zonas } = useCalamaZonas(planificacionId)
  const zonaCodigoFolio = ot ? zonaCodeFromFolio(ot.folio) : null
  const zonaProyectoId = useMemo(() => {
    if (!zonas || !zonaCodigoFolio) return undefined
    return zonas.find((z) => z.codigo_zona === zonaCodigoFolio)?.id
  }, [zonas, zonaCodigoFolio])

  const { data: materiales } = useCalamaMateriales(planificacionId, zonaProyectoId)
  const { data: contactos } = useCalamaContactos(faenaId, planificacionId ?? undefined)

  const iniciar = useIniciarEjecucionOT()

  const { rol } = usePermissions()
  const puedeEditarPrecheck = useMemo(() => {
    return ['administrador', 'gerencia', 'subgerente_operaciones', 'planificador', 'supervisor', 'jefe_operaciones'].includes(rol ?? '')
  }, [rol])

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 text-sm text-gray-500">
        <Spinner className="h-4 w-4" />
        Cargando OT…
      </div>
    )
  }

  if (error || !ot) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
        OT no encontrada o sin permisos: {error instanceof Error ? error.message : ''}
      </div>
    )
  }

  const codigoTarea = excelCodigoFromFolio(ot.folio)
  const zonaCodigo = zonaCodigoFolio
  const matsZona = materiales ?? []
  const avanceReal = Number(ot.avance_pct ?? 0)
  const avanceExcel = Number((ot as { avance_excel_pct?: number }).avance_excel_pct ?? 0)
  const delta = desviacionPp(avanceReal, avanceExcel)

  return (
    <div className="space-y-4">
      <Link
        href="/dashboard/operacion-calama/ots"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" />
        Volver al listado
      </Link>

      {/* Header */}
      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-6 text-white shadow-lg">
        <div className="flex flex-wrap justify-between items-start gap-2">
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <ClipboardList className="h-6 w-6" />
              {ot.titulo}
            </h1>
            <p className="text-sm text-white/90 mt-1 font-mono">{ot.folio}</p>
          </div>
          <div className="flex items-center gap-2 text-xs">
            <EstadoBadge estado={ot.estado} />
            <span className="rounded bg-black/20 px-2 py-1 font-mono">{ot.avance_pct.toFixed(1)}%</span>
          </div>
        </div>
      </div>

      {/* Avance de la OT — bloque prominente */}
      <AvanceOTCard
        otId={ot.id}
        avanceReal={avanceReal}
        avanceExcel={avanceExcel}
        delta={delta}
        horasReales={ot.horas_reales ?? null}
        estado={ot.estado}
      />

      {/* Info general */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <MapPin className="h-4 w-4" />
            Informacion general
          </CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3 text-xs">
          <Info label="Codigo tarea (Excel)" value={codigoTarea ?? '—'} mono />
          <Info label="Zona" value={zonaCodigo ?? '—'} mono />
          <Info label="Faena" value={ot.faena?.codigo ?? '—'} />
          <Info label="Linea de negocio" value={ot.planificacion?.linea_negocio ?? '—'} />
          <Info label="Planificacion" value={ot.planificacion?.codigo ?? '—'} mono />
          <Info label="Fecha programada" value={ot.fecha_programada} />
          <Info label="Inicio real" value={ot.fecha_inicio_real ? ot.fecha_inicio_real.slice(0, 10) : '—'} />
          <Info label="Fin real" value={ot.fecha_termino_real ? ot.fecha_termino_real.slice(0, 10) : '—'} />
          <Info label="Horas estimadas" value={ot.horas_estimadas?.toString() ?? '—'} />
          <Info label="Horas reales" value={ot.horas_reales?.toString() ?? '—'} />
          <Info label="Prioridad" value={ot.prioridad} />
          <Info
            label="Vehiculo especial"
            value={ot.requiere_vehiculo_especial ? 'Si requiere' : 'No requiere'}
          />
        </CardContent>
        {ot.estado === 'liberada' && precheck?.liberada_para_ejecucion && (
          <CardContent className="border-t pt-3 flex justify-end">
            <Button
              variant="primary"
              loading={iniciar.isPending}
              onClick={async () => {
                try {
                  await iniciar.mutateAsync(ot.id)
                } catch (e) {
                  alert(e instanceof Error ? e.message : 'Error al iniciar')
                }
              }}
            >
              <Play className="h-4 w-4" />
              Iniciar ejecucion
            </Button>
          </CardContent>
        )}
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Precheck */}
        <PrecheckPanel ot={ot} puedeEditar={puedeEditarPrecheck} />

        {/* Subtareas */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <ListChecks className="h-4 w-4" />
              Subtareas ({subtareas?.length ?? 0})
            </CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto">
            {!subtareas || subtareas.length === 0 ? (
              <p className="text-sm text-gray-400">Sin subtareas registradas.</p>
            ) : (
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                    <th className="px-2 py-2 w-10">#</th>
                    <th className="px-2 py-2">Descripcion</th>
                    <th className="px-2 py-2">Estado</th>
                    <th className="px-2 py-2 text-right">Avance</th>
                  </tr>
                </thead>
                <tbody>
                  {subtareas.slice(0, 100).map((s) => (
                    <tr key={s.id} className="border-b">
                      <td className="px-2 py-1.5 font-mono text-gray-500">{s.orden}</td>
                      <td className="px-2 py-1.5">{s.descripcion}</td>
                      <td className="px-2 py-1.5">
                        <EstadoBadge estado={s.estado} />
                      </td>
                      <td className="px-2 py-1.5 text-right font-mono">{s.avance_pct.toFixed(0)}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            {subtareas && subtareas.length > 100 && (
              <p className="mt-2 text-xs text-gray-400 text-center">
                Mostrando 100 de {subtareas.length} subtareas.
              </p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Materiales */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Hammer className="h-4 w-4" />
            Materiales planificados ({matsZona.length})
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {matsZona.length === 0 ? (
            <p className="text-sm text-gray-400">Sin materiales para esta planificacion.</p>
          ) : (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                  <th className="px-2 py-2">Actividad</th>
                  <th className="px-2 py-2">Descripcion</th>
                  <th className="px-2 py-2 text-right">CLP</th>
                  <th className="px-2 py-2 text-right">UF</th>
                  <th className="px-2 py-2">Bloque</th>
                </tr>
              </thead>
              <tbody>
                {matsZona.slice(0, 50).map((m) => (
                  <tr key={m.id} className="border-b">
                    <td className="px-2 py-1.5">{m.actividad_relacionada ?? '—'}</td>
                    <td className="px-2 py-1.5">{m.descripcion}</td>
                    <td className="px-2 py-1.5 text-right">
                      {m.precio_clp != null ? Math.round(m.precio_clp).toLocaleString('es-CL') : '—'}
                    </td>
                    <td className="px-2 py-1.5 text-right">{m.valor_uf?.toFixed(2) ?? '—'}</td>
                    <td className="px-2 py-1.5 text-gray-500">{m.bloque ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          {matsZona.length > 50 && (
            <p className="mt-2 text-xs text-gray-400 text-center">
              Mostrando 50 de {matsZona.length} materiales (filtrar por zona en futuro).
            </p>
          )}
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Observaciones */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <MessageSquare className="h-4 w-4" />
              Observaciones ({observaciones?.length ?? 0})
            </CardTitle>
          </CardHeader>
          <CardContent>
            {!observaciones || observaciones.length === 0 ? (
              <p className="text-sm text-gray-400">Sin observaciones.</p>
            ) : (
              <ul className="space-y-2">
                {observaciones.slice(0, 20).map((o) => (
                  <li key={o.id} className="rounded border border-gray-200 bg-white p-2 text-sm">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs font-mono text-gray-500">{o.tipo}</span>
                      <span className={`text-xs px-2 rounded ${
                        o.severidad === 'alta' ? 'bg-red-100 text-red-700'
                        : o.severidad === 'media' ? 'bg-amber-100 text-amber-700'
                        : 'bg-gray-100 text-gray-600'
                      }`}>
                        {o.severidad}
                      </span>
                    </div>
                    <p className="text-gray-800">{o.detalle}</p>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        {/* Contactos */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <Phone className="h-4 w-4" />
              Contactos mandante ({contactos?.length ?? 0})
            </CardTitle>
          </CardHeader>
          <CardContent>
            {!contactos || contactos.length === 0 ? (
              <p className="text-sm text-gray-400">Sin contactos.</p>
            ) : (
              <ul className="space-y-2">
                {contactos.slice(0, 20).map((c) => (
                  <li key={c.id} className="rounded border border-gray-200 bg-white p-2 text-sm">
                    <div className="font-medium">{c.descripcion}</div>
                    <div className="text-xs text-gray-500">{c.rol}</div>
                    {c.telefono && <div className="text-xs font-mono text-gray-700">{c.telefono}</div>}
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Aviso sobre precheck */}
      <Card className="border-amber-100 bg-amber-50/50">
        <CardContent className="p-3 text-xs text-amber-900 flex gap-2">
          <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
          <div>
            <p className="font-semibold">Sobre los gates del precheck:</p>
            <p>
              MIG17 define 7 booleans: <span className="font-mono">epp_completo</span>,{' '}
              <span className="font-mono">herramientas_ok</span>, <span className="font-mono">vehiculo_confirmado</span>,{' '}
              <span className="font-mono">vehiculo_especial_confirmado</span>, <span className="font-mono">charla_ods_realizada</span>,{' '}
              <span className="font-mono">permisos_trabajo_ok</span>. Si se requiere agregar gates como{' '}
              <span className="font-mono">materiales_confirmados</span> o <span className="font-mono">personal_acreditado</span>{' '}
              como columnas separadas, se necesita un parche SQL nuevo (no se modifica MIG17 validada).
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

function Info({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <div className="text-gray-500 uppercase text-[10px]">{label}</div>
      <div className={`text-gray-900 ${mono ? 'font-mono text-xs' : 'text-sm'}`}>{value}</div>
    </div>
  )
}

function AvanceOTCard({
  otId, avanceReal, avanceExcel, delta, horasReales, estado,
}: {
  otId: string
  avanceReal: number
  avanceExcel: number
  delta: number
  horasReales: number | null
  estado: string
}) {
  const { data: eventos } = useEventosAvanceOT(otId)
  const ultimoEvento = eventos?.[0]
  const fuenteTxt = ultimoEvento?.fuente
    ? ultimoEvento.fuente.charAt(0).toUpperCase() + ultimoEvento.fuente.slice(1)
    : null
  const fechaActualizacion = ultimoEvento?.created_at
    ? new Date(ultimoEvento.created_at).toLocaleString('es-CL', {
        day: '2-digit', month: '2-digit', year: '2-digit',
        hour: '2-digit', minute: '2-digit',
      })
    : null

  const tone = avanceReal >= 100 ? 'green'
    : avanceReal >= avanceExcel ? 'green'
    : avanceReal > 0 ? 'amber'
    : 'red'
  const toneText = tone === 'green' ? 'Al dia o sobre plan'
    : tone === 'amber' ? 'Avance parcial'
    : 'Sin avance'
  const toneColor = tone === 'green' ? 'border-green-300 bg-green-50'
    : tone === 'amber' ? 'border-amber-300 bg-amber-50'
    : 'border-red-300 bg-red-50'

  return (
    <Card className={toneColor}>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center justify-between">
          <span>Avance de la OT</span>
          <span className={`text-xs rounded-full px-2 py-0.5 font-semibold ${
            tone === 'green' ? 'bg-green-200 text-green-900'
            : tone === 'amber' ? 'bg-amber-200 text-amber-900'
            : 'bg-red-200 text-red-900'
          }`}>{toneText}</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {/* Cifras grandes */}
        <div className="grid grid-cols-3 gap-2">
          <div className="rounded-lg bg-white border border-gray-200 p-3 text-center">
            <div className="text-[10px] uppercase text-gray-500">Avance Real</div>
            <div className="font-mono text-3xl font-bold text-gray-900 mt-0.5">{avanceReal.toFixed(0)}<span className="text-base">%</span></div>
          </div>
          <div className="rounded-lg bg-white border border-gray-200 p-3 text-center">
            <div className="text-[10px] uppercase text-gray-500">Avance Excel</div>
            <div className="font-mono text-3xl font-semibold text-gray-600 mt-0.5">{avanceExcel.toFixed(0)}<span className="text-base">%</span></div>
          </div>
          <div className={`rounded-lg bg-white border p-3 text-center ${
            delta >= 0 ? 'border-green-200' : 'border-red-200'
          }`}>
            <div className="text-[10px] uppercase text-gray-500">Desviacion</div>
            <div className={`font-mono text-3xl font-semibold mt-0.5 ${
              delta >= 0 ? 'text-green-700' : 'text-red-700'
            }`}>
              {delta >= 0 ? '+' : ''}{delta.toFixed(0)}<span className="text-base">pp</span>
            </div>
          </div>
        </div>

        {/* Barra dual con marcador del Excel */}
        <div className="space-y-1">
          <div className="flex items-center justify-between text-[10px] uppercase text-gray-500">
            <span>Progreso real vs plan</span>
            <span className="text-indigo-600">- - - plan Excel</span>
          </div>
          <BarraAvanceDual real={avanceReal} excel={avanceExcel} />
        </div>

        {/* Metadata */}
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 text-xs text-gray-600">
          <div>
            <div className="text-[10px] uppercase text-gray-500">Estado</div>
            <div className="font-medium">{estado}</div>
          </div>
          {horasReales != null && (
            <div>
              <div className="text-[10px] uppercase text-gray-500">Horas reales</div>
              <div className="font-mono">{Number(horasReales).toFixed(2)}h</div>
            </div>
          )}
          {fuenteTxt && (
            <div>
              <div className="text-[10px] uppercase text-gray-500">Ultima fuente</div>
              <div className="font-medium">{fuenteTxt}</div>
            </div>
          )}
          {fechaActualizacion && (
            <div className="sm:col-span-3">
              <div className="text-[10px] uppercase text-gray-500">Ultima actualizacion</div>
              <div>{fechaActualizacion}</div>
            </div>
          )}
        </div>

        {ultimoEvento?.comentario && (
          <div className="rounded border border-gray-200 bg-white px-3 py-2 text-xs">
            <div className="text-[10px] uppercase text-gray-500 mb-0.5">Ultimo comentario</div>
            <div className="text-gray-800">{ultimoEvento.comentario}</div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
