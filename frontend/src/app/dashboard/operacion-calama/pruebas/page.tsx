'use client'

import Link from 'next/link'
import { useState } from 'react'
import {
  FlaskConical, Plus, RefreshCw, ExternalLink, Smartphone, Camera,
  Activity, FileSignature, AlertCircle, ArrowLeft, Trash2,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '@/components/ui/table'
import { formatDate, formatDateTime, todayISO, cn } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  useListaPruebasTerreno, useCrearJornadaPrueba,
  useEvidenciasPrueba, useEventosPrueba,
  useEliminarPruebaTerreno,
} from '@/hooks/use-calama-pruebas'
import { useUsuariosAsignables } from '@/hooks/use-calama-plan-semanal'
import { useQueryClient } from '@tanstack/react-query'

export default function PruebasTerrenoPage() {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: pruebas, isLoading, isFetching } = useListaPruebasTerreno()
  const { data: usuarios } = useUsuariosAsignables()
  const crear = useCrearJornadaPrueba()

  const [responsableId, setResponsableId] = useState('')
  const [fechaJornada, setFechaJornada] = useState(todayISO())
  const [otDetalleId, setOtDetalleId] = useState<string | null>(null)
  const [confirmEliminar, setConfirmEliminar] = useState<string | null>(null)
  const eliminar = useEliminarPruebaTerreno()

  const onEliminar = (otId: string, folio: string) => {
    eliminar.mutate(otId, {
      onSuccess: (r) => {
        const e = r.eliminado
        const totalDb = e.evidencias + e.firmas + e.eventos + e.ejecuciones + e.jornadas + e.precheck + e.audit
        const sto = r.storage
        const totalSto = sto.evidencias_borradas + sto.firmas_borradas
        const erroresSto = sto.errores.length
        toast.success(
          `Prueba ${folio} eliminada. DB: ${totalDb} filas, Storage: ${totalSto} archivos${erroresSto > 0 ? `, ${erroresSto} errores Storage` : ''}.`,
        )
        if (otDetalleId === otId) setOtDetalleId(null)
        setConfirmEliminar(null)
      },
      onError: (err) => {
        const raw = err instanceof Error ? err.message : String(err)
        if (raw.toLowerCase().includes('no es de prueba')) {
          toast.error('Esta OT NO esta marcada como prueba. No se elimina.')
        } else if (raw.toLowerCase().includes('no autorizado') || raw.toLowerCase().includes('rol')) {
          toast.error('No tienes permiso para eliminar pruebas.')
        } else {
          toast.error(raw)
        }
      },
    })
  }

  const onCrear = () => {
    crear.mutate(
      { responsable_id: responsableId || null, fecha_jornada: fechaJornada },
      {
        onSuccess: (data) => {
          toast.success(`Prueba creada: ${data.folio}. Abrir ${data.url_mobile}`)
          setOtDetalleId(data.ot_id)
        },
        onError: (err) => {
          const raw = err instanceof Error ? err.message : String(err)
          const low = raw.toLowerCase()
          if (low.includes('no autenticado')) {
            toast.error('Sesión expirada. Vuelve a iniciar sesión.')
          } else if (low.includes('no autorizado') || low.includes('rol')) {
            toast.error('No tienes permiso para crear jornadas de prueba.')
          } else if (low.includes('planificacion')) {
            toast.error('No hay planificación Calama disponible. Importa una primero.')
          } else if (low.includes('faena')) {
            toast.error('No hay faena Calama disponible.')
          } else if (low.includes('responsable')) {
            toast.error('Falta responsable. Elige uno del selector o crea oocc@pillado.cl.')
          } else if (low.includes('schema cache') || low.includes('function') && low.includes('not found')) {
            toast.error('La función RPC aún no está visible. Ejecuta NOTIFY pgrst, \'reload schema\'; en Supabase.')
          } else {
            toast.error(raw)
          }
        },
      },
    )
  }

  return (
    <div className="space-y-4 p-6 max-w-6xl mx-auto">
      <header className="flex items-center gap-2 flex-wrap">
        <Link href="/dashboard/operacion-calama">
          <Button variant="outline" size="sm">
            <ArrowLeft className="h-4 w-4 mr-1" /> Volver
          </Button>
        </Link>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <FlaskConical className="h-6 w-6 text-purple-700" />
          Pruebas de Terreno (sandbox)
        </h1>
        <div className="flex-1" />
        <Button variant="outline" size="sm" onClick={() => qc.invalidateQueries({ queryKey: ['calama-pruebas'] })} disabled={isFetching}>
          <RefreshCw className={cn('h-4 w-4 mr-1', isFetching && 'animate-spin')} />
          Actualizar
        </Button>
      </header>

      <div className="rounded-lg border border-purple-200 bg-purple-50 p-3 text-xs text-purple-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Modo prueba.</strong> Las OTs creadas aquí están marcadas <code className="bg-white px-1 rounded">es_prueba=true</code>
          {' '}y <code className="bg-white px-1 rounded">excluida_estadisticas=true</code>.
          NO aparecen en el dashboard de avance ni en los reportes ejecutivos.
          Usar para probar fotos, GPS, offline, pausa/reanudación, firma y cierre.
        </div>
      </div>

      {/* Crear prueba */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Plus className="h-4 w-4 text-purple-700" />
            Crear nueva jornada de prueba
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="md:col-span-2">
              <label className="block text-xs font-medium text-gray-700 mb-1">Responsable</label>
              <select
                value={responsableId}
                onChange={(e) => setResponsableId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Default: oocc@pillado.cl —</option>
                {(usuarios ?? []).map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.nombre_completo ?? u.email} — {u.email}
                  </option>
                ))}
              </select>
              <div className="text-[11px] text-gray-500 mt-1">
                Si no eliges, intenta usar oocc@pillado.cl. Sino falla con mensaje claro.
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Fecha jornada</label>
              <Input type="date" value={fechaJornada} onChange={(e) => setFechaJornada(e.target.value)} />
            </div>
          </div>
          <div className="flex items-center justify-end">
            <Button onClick={onCrear} disabled={crear.isPending}>
              {crear.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Plus className="h-4 w-4 mr-2" />}
              {crear.isPending ? 'Creando...' : 'Crear prueba'}
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Listado */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            Pruebas existentes ({pruebas?.length ?? 0})
          </CardTitle>
        </CardHeader>
        <CardContent className="px-0">
          {isLoading ? (
            <div className="flex justify-center py-10"><Spinner /></div>
          ) : (pruebas?.length ?? 0) === 0 ? (
            <div className="text-center text-sm text-gray-500 py-10">
              Sin pruebas creadas. Crea la primera arriba.
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Folio</TableHead>
                  <TableHead>Fecha</TableHead>
                  <TableHead>Responsable</TableHead>
                  <TableHead>Estado OT</TableHead>
                  <TableHead className="text-right">Evidencias</TableHead>
                  <TableHead className="text-right">Eventos</TableHead>
                  <TableHead className="text-right">Firmas</TableHead>
                  <TableHead>Móvil</TableHead>
                  <TableHead></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(pruebas ?? []).map((p) => (
                  <TableRow key={p.ot_id} className={otDetalleId === p.ot_id ? 'bg-purple-50' : ''}>
                    <TableCell>
                      <div className="font-mono text-xs">{p.folio}</div>
                      <div className="text-[10px] text-gray-500">{formatDateTime(p.created_at)}</div>
                    </TableCell>
                    <TableCell className="text-xs">{formatDate(p.fecha_programada)}</TableCell>
                    <TableCell>
                      <div className="text-sm">{p.responsable_nombre ?? '—'}</div>
                      <div className="text-[10px] text-gray-500">{p.responsable_email ?? ''}</div>
                    </TableCell>
                    <TableCell>
                      <Badge className={
                        p.ot_estado === 'finalizada' ? 'bg-green-100 text-green-700'
                          : p.ot_estado === 'en_ejecucion' ? 'bg-amber-100 text-amber-700'
                          : p.ot_estado === 'en_pausa' ? 'bg-orange-100 text-orange-700'
                          : 'bg-gray-100 text-gray-700'
                      }>{p.ot_estado}</Badge>
                      {p.estado_plan && (
                        <div className="text-[10px] text-gray-500 mt-0.5">plan: {p.estado_plan}</div>
                      )}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      <span className="inline-flex items-center gap-1">
                        <Camera className="h-3 w-3" />{p.evidencias_count}
                      </span>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      <span className="inline-flex items-center gap-1">
                        <Activity className="h-3 w-3" />{p.eventos_count}
                      </span>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      <span className="inline-flex items-center gap-1">
                        <FileSignature className="h-3 w-3" />{p.firmas_count}
                      </span>
                    </TableCell>
                    <TableCell>
                      <Link
                        href={`/m/calama/ot/${p.ot_id}`}
                        target="_blank"
                        className="inline-flex items-center gap-1 text-xs text-amber-700 hover:text-amber-900 underline"
                      >
                        <Smartphone className="h-3 w-3" />
                        Abrir
                        <ExternalLink className="h-3 w-3" />
                      </Link>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1 flex-wrap">
                        <Button
                          variant="outline" size="sm"
                          onClick={() => setOtDetalleId(otDetalleId === p.ot_id ? null : p.ot_id)}
                        >
                          {otDetalleId === p.ot_id ? 'Cerrar' : 'Ver detalle'}
                        </Button>
                        {confirmEliminar === p.ot_id ? (
                          <div className="inline-flex items-center gap-1 rounded border border-red-300 bg-red-50 px-2 py-1">
                            <span className="text-[10px] text-red-800 font-medium">Confirmar?</span>
                            <Button
                              variant="outline" size="sm"
                              className="border-red-400 bg-white text-red-700 hover:bg-red-100"
                              onClick={() => onEliminar(p.ot_id, p.folio)}
                              disabled={eliminar.isPending}
                            >
                              {eliminar.isPending ? <Spinner className="h-3 w-3" /> : 'Si, borrar'}
                            </Button>
                            <Button
                              variant="ghost" size="sm"
                              onClick={() => setConfirmEliminar(null)}
                              disabled={eliminar.isPending}
                            >
                              Cancelar
                            </Button>
                          </div>
                        ) : (
                          <Button
                            variant="outline" size="sm"
                            className="border-red-300 text-red-700 hover:bg-red-50"
                            onClick={() => setConfirmEliminar(p.ot_id)}
                            disabled={eliminar.isPending}
                          >
                            <Trash2 className="h-3 w-3 mr-1" /> Eliminar
                          </Button>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Detalle OT */}
      {otDetalleId && <DetallePrueba otId={otDetalleId} />}
    </div>
  )
}

function DetallePrueba({ otId }: { otId: string }) {
  const { data: evidencias, isLoading: loadEv } = useEvidenciasPrueba(otId)
  const { data: eventos, isLoading: loadEvt } = useEventosPrueba(otId)

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Camera className="h-4 w-4 text-purple-700" />
            Evidencias ({evidencias?.length ?? 0})
          </CardTitle>
        </CardHeader>
        <CardContent className="px-0 max-h-96 overflow-y-auto">
          {loadEv ? <div className="flex justify-center py-6"><Spinner /></div>
            : (evidencias?.length ?? 0) === 0 ? <div className="text-center text-sm text-gray-500 py-6">Sin evidencias</div>
            : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Momento</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Sync</TableHead>
                  <TableHead>GPS</TableHead>
                  <TableHead>Fecha</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(evidencias ?? []).map((e) => (
                  <TableRow key={e.id}>
                    <TableCell className="text-xs">{e.momento}</TableCell>
                    <TableCell className="text-xs">{e.tipo ?? '—'}</TableCell>
                    <TableCell>
                      <Badge className={
                        e.sync_status === 'synced' ? 'bg-green-100 text-green-700'
                          : e.sync_status === 'pending' ? 'bg-amber-100 text-amber-700'
                          : e.sync_status === 'error' ? 'bg-red-100 text-red-700'
                          : 'bg-gray-100 text-gray-700'
                      }>{e.sync_status ?? 'n/a'}</Badge>
                    </TableCell>
                    <TableCell className="text-[10px] text-gray-600">
                      {e.lat != null && e.lng != null
                        ? `${e.lat.toFixed(4)}, ${e.lng.toFixed(4)}`
                        : '—'}
                    </TableCell>
                    <TableCell className="text-[10px]">{e.tomada_en ? formatDateTime(e.tomada_en) : '—'}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Activity className="h-4 w-4 text-purple-700" />
            Eventos ({eventos?.length ?? 0})
          </CardTitle>
        </CardHeader>
        <CardContent className="px-0 max-h-96 overflow-y-auto">
          {loadEvt ? <div className="flex justify-center py-6"><Spinner /></div>
            : (eventos?.length ?? 0) === 0 ? <div className="text-center text-sm text-gray-500 py-6">Sin eventos</div>
            : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Motivo</TableHead>
                  <TableHead>Avance</TableHead>
                  <TableHead>Fecha</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(eventos ?? []).map((e) => (
                  <TableRow key={e.id}>
                    <TableCell><Badge className="bg-blue-100 text-blue-700">{e.tipo}</Badge></TableCell>
                    <TableCell className="text-xs">{e.motivo ?? '—'}</TableCell>
                    <TableCell className="text-xs tabular-nums">{e.avance != null ? `${e.avance}%` : '—'}</TableCell>
                    <TableCell className="text-[10px]">{formatDateTime(e.created_at)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
