'use client'

import { useMemo, useState } from 'react'
import {
  HardHat,
  AlertTriangle,
  FileWarning,
  FlaskConical,
  Recycle,
  ShieldAlert,
  FileCheck,
  Clock,
  Package,
  Truck,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  usePrevencionResumen,
  useSuspelProductos,
  useSuspelBodegas,
  useRespelMovimientos,
  useCertificacionesBloqueantes,
} from '@/hooks/use-prevencion'

function StatCard({
  label,
  value,
  icon: Icon,
  variant = 'default',
  sublabel,
  onClick,
  active,
}: {
  label: string
  value: number | string
  icon: any
  variant?: 'default' | 'danger' | 'warning' | 'success'
  sublabel?: string
  onClick?: () => void
  active?: boolean
}) {
  const colors = {
    default: 'bg-gray-50 border-gray-200 text-gray-900',
    danger: 'bg-red-50 border-red-200 text-red-900',
    warning: 'bg-amber-50 border-amber-200 text-amber-900',
    success: 'bg-green-50 border-green-200 text-green-900',
  }
  const iconColors = {
    default: 'text-gray-500',
    danger: 'text-red-500',
    warning: 'text-amber-500',
    success: 'text-green-500',
  }
  return (
    <div
      className={cn(
        'rounded-lg border p-4 transition-all',
        colors[variant],
        onClick && 'cursor-pointer hover:shadow-md hover:scale-[1.02]',
        active && 'ring-2 ring-blue-500 ring-offset-1',
      )}
      onClick={onClick}
    >
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium opacity-70">{label}</span>
        <Icon className={cn('h-4 w-4', iconColors[variant])} />
      </div>
      <div className="mt-2 text-3xl font-bold">{value}</div>
      {sublabel && <div className="mt-1 text-xs opacity-60">{sublabel}</div>}
    </div>
  )
}

export default function PrevencionPage() {
  useRequireAuth()

  const { data: resumen, isLoading } = usePrevencionResumen()
  const { data: productos } = useSuspelProductos()
  const { data: bodegas } = useSuspelBodegas()
  const { data: movimientos } = useRespelMovimientos(20)
  const { data: allCerts } = useCertificacionesBloqueantes()

  // ── Filtro interactivo desde tarjetas ──
  type CertFiltro = 'vencidas' | 'por_vencer_30d' | 'por_vencer_60d' | null
  const [certFiltro, setCertFiltro] = useState<CertFiltro>(null)

  const toggleFiltro = (f: CertFiltro) => {
    setCertFiltro(certFiltro === f ? null : f)
  }

  const certsFiltradas = useMemo(() => {
    if (!allCerts) return []
    const now = Date.now()
    const d30 = 30 * 86400000
    const d60 = 60 * 86400000

    return allCerts.filter((c: any) => {
      const venc = new Date(c.fecha_vencimiento).getTime()
      const diff = venc - now

      if (certFiltro === 'vencidas') return diff < 0
      if (certFiltro === 'por_vencer_30d') return diff >= 0 && diff <= d30
      if (certFiltro === 'por_vencer_60d') return diff >= 0 && diff <= d60
      return true // sin filtro, mostrar todas
    })
  }, [allCerts, certFiltro])

  const balanceRespel = useMemo(() => {
    if (!resumen) return 0
    return resumen.respel_generado_mes_kg - resumen.respel_retirado_mes_kg
  }, [resumen])

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* ── Header ── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <HardHat className="h-7 w-7 text-amber-500" />
            Prevención de Riesgos
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            Cumplimiento normativo: DS 43 (SUSPEL) · DS 148 (RESPEL) · DS 298 (Transporte SP)
          </p>
        </div>
      </div>

      {/* ── Alertas críticas ── */}
      {resumen && (resumen.certificaciones_vencidas > 0 || resumen.bodegas_autorizacion_vencida > 0 || resumen.documentos_vencidos > 0) && (
        <Card className="border-red-200 bg-red-50">
          <CardHeader className="pb-2">
            <CardTitle className="text-red-700 flex items-center gap-2 text-base">
              <AlertTriangle className="h-5 w-5" />
              Incumplimientos críticos
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm text-red-800">
            {resumen.certificaciones_vencidas > 0 && (
              <div>⚠️ {resumen.certificaciones_vencidas} certificaciones bloqueantes vencidas</div>
            )}
            {resumen.bodegas_autorizacion_vencida > 0 && (
              <div>⚠️ {resumen.bodegas_autorizacion_vencida} bodegas con autorización sanitaria vencida</div>
            )}
            {resumen.documentos_vencidos > 0 && (
              <div>⚠️ {resumen.documentos_vencidos} documentos normativos vencidos</div>
            )}
          </CardContent>
        </Card>
      )}

      {/* ── Resumen general en tarjetas ── */}
      <div>
        <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Certificaciones de Flota</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard
            label="Vencidas"
            value={resumen?.certificaciones_vencidas ?? 0}
            icon={AlertTriangle}
            variant={(resumen?.certificaciones_vencidas ?? 0) > 0 ? 'danger' : 'success'}
            sublabel="Click para filtrar"
            onClick={() => toggleFiltro('vencidas')}
            active={certFiltro === 'vencidas'}
          />
          <StatCard
            label="Por vencer 30d"
            value={resumen?.certificaciones_por_vencer_30d ?? 0}
            icon={Clock}
            variant={(resumen?.certificaciones_por_vencer_30d ?? 0) > 0 ? 'warning' : 'default'}
            onClick={() => toggleFiltro('por_vencer_30d')}
            active={certFiltro === 'por_vencer_30d'}
          />
          <StatCard
            label="Por vencer 60d"
            value={resumen?.certificaciones_por_vencer_60d ?? 0}
            icon={Clock}
            variant="default"
            onClick={() => toggleFiltro('por_vencer_60d')}
            active={certFiltro === 'por_vencer_60d'}
          />
          <StatCard
            label="Conductores SEMEP vencido"
            value={resumen?.conductores_semep_vencido ?? 0}
            icon={ShieldAlert}
            variant={(resumen?.conductores_semep_vencido ?? 0) > 0 ? 'danger' : 'success'}
            sublabel="Ley 16.744"
          />
        </div>
      </div>

      <div>
        <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">SUSPEL — Sustancias Peligrosas (DS 43)</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard
            label="Productos en catálogo"
            value={resumen?.productos_suspel_activos ?? 0}
            icon={FlaskConical}
            variant="default"
          />
          <StatCard
            label="HDS por revisar"
            value={resumen?.hds_por_revisar ?? 0}
            icon={FileWarning}
            variant={(resumen?.hds_por_revisar ?? 0) > 0 ? 'warning' : 'success'}
            sublabel="Próximos 90 días"
          />
          <StatCard
            label="Bodegas SP"
            value={resumen?.bodegas_total ?? 0}
            icon={Package}
            variant="default"
          />
          <StatCard
            label="Inspecciones vencidas"
            value={resumen?.bodegas_inspeccion_vencida ?? 0}
            icon={AlertTriangle}
            variant={(resumen?.bodegas_inspeccion_vencida ?? 0) > 0 ? 'warning' : 'success'}
          />
        </div>
      </div>

      <div>
        <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">RESPEL — Residuos Peligrosos (DS 148)</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard
            label="Generado mes"
            value={`${(resumen?.respel_generado_mes_kg ?? 0).toLocaleString()} kg`}
            icon={Recycle}
            variant="default"
            sublabel="Taller + flota"
          />
          <StatCard
            label="Retirado mes"
            value={`${(resumen?.respel_retirado_mes_kg ?? 0).toLocaleString()} kg`}
            icon={Truck}
            variant="default"
          />
          <StatCard
            label="Saldo en bodega"
            value={`${balanceRespel.toLocaleString()} kg`}
            icon={Package}
            variant={balanceRespel > 5000 ? 'warning' : 'default'}
            sublabel="Pendiente de retiro"
          />
          <StatCard
            label="Sin SIDREP"
            value={resumen?.retiros_sin_sidrep ?? 0}
            icon={FileWarning}
            variant={(resumen?.retiros_sin_sidrep ?? 0) > 0 ? 'danger' : 'success'}
            sublabel="Declaración pendiente"
          />
        </div>
      </div>

      {/* ── Listado de certificaciones próximas ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <FileCheck className="h-5 w-5 text-gray-600" />
            Certificaciones Bloqueantes
            {certFiltro && (
              <button className="ml-2 text-xs font-medium text-blue-600 hover:underline" onClick={() => setCertFiltro(null)}>
                Limpiar filtro
              </button>
            )}
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {certsFiltradas.length > 0 ? (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b text-left text-gray-500 uppercase">
                  <th className="px-2 py-2">Equipo</th>
                  <th className="px-2 py-2">Tipo</th>
                  <th className="px-2 py-2">Vencimiento</th>
                  <th className="px-2 py-2">Días</th>
                  <th className="px-2 py-2">Estado</th>
                </tr>
              </thead>
              <tbody>
                {certsFiltradas.map((c: any) => {
                  const dias = Math.floor((new Date(c.fecha_vencimiento).getTime() - Date.now()) / 86400000)
                  return (
                    <tr key={c.id} className="border-b hover:bg-gray-50">
                      <td className="px-2 py-2 font-mono">{c.activo?.patente || c.activo?.codigo}</td>
                      <td className="px-2 py-2">{c.tipo}</td>
                      <td className="px-2 py-2">{c.fecha_vencimiento}</td>
                      <td className={cn('px-2 py-2 font-semibold', dias < 15 ? 'text-red-600' : dias < 30 ? 'text-amber-600' : 'text-gray-600')}>
                        {dias}
                      </td>
                      <td className="px-2 py-2">
                        <span className={cn('inline-block rounded px-2 py-0.5 text-xs',
                          c.estado === 'vencido' ? 'bg-red-100 text-red-700' :
                          c.estado === 'por_vencer' ? 'bg-amber-100 text-amber-700' :
                          'bg-green-100 text-green-700'
                        )}>
                          {c.estado}
                        </span>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-400">Sin certificaciones próximas a vencer</p>
          )}
        </CardContent>
      </Card>

      {/* ── SUSPEL productos ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <FlaskConical className="h-5 w-5 text-blue-600" />
            Productos SUSPEL en Catálogo ({productos?.length ?? 0})
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {productos && productos.length > 0 ? (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b text-left text-gray-500 uppercase">
                  <th className="px-2 py-2">Código</th>
                  <th className="px-2 py-2">Producto</th>
                  <th className="px-2 py-2">Clase UN</th>
                  <th className="px-2 py-2">UN#</th>
                  <th className="px-2 py-2">Proveedor</th>
                  <th className="px-2 py-2">HDS revisión</th>
                </tr>
              </thead>
              <tbody>
                {productos.map((p) => (
                  <tr key={p.id} className="border-b hover:bg-gray-50">
                    <td className="px-2 py-2 font-mono">{p.codigo}</td>
                    <td className="px-2 py-2">{p.nombre}</td>
                    <td className="px-2 py-2">
                      <span className="inline-block rounded bg-blue-100 px-2 py-0.5 text-xs text-blue-700">
                        {p.clase_un.replace('clase_', 'Clase ')}
                      </span>
                    </td>
                    <td className="px-2 py-2">{p.numero_un || '—'}</td>
                    <td className="px-2 py-2 text-gray-600">{p.proveedor || '—'}</td>
                    <td className="px-2 py-2 text-gray-500">{p.hds_proxima_revision || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-400">Sin productos registrados</p>
          )}
        </CardContent>
      </Card>

      {/* ── RESPEL movimientos ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Recycle className="h-5 w-5 text-green-600" />
            Últimos Movimientos RESPEL
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {movimientos && movimientos.length > 0 ? (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b text-left text-gray-500 uppercase">
                  <th className="px-2 py-2">Fecha</th>
                  <th className="px-2 py-2">Tipo Mov.</th>
                  <th className="px-2 py-2">Residuo</th>
                  <th className="px-2 py-2 text-right">Cantidad</th>
                  <th className="px-2 py-2">Receptor</th>
                  <th className="px-2 py-2">SIDREP</th>
                </tr>
              </thead>
              <tbody>
                {movimientos.map((m) => (
                  <tr key={m.id} className="border-b hover:bg-gray-50">
                    <td className="px-2 py-2">{m.fecha}</td>
                    <td className="px-2 py-2">
                      <span className={cn('inline-block rounded px-2 py-0.5 text-xs',
                        m.tipo_movimiento === 'generacion' ? 'bg-amber-100 text-amber-700' :
                        m.tipo_movimiento === 'retiro' ? 'bg-green-100 text-green-700' :
                        'bg-gray-100 text-gray-700'
                      )}>
                        {m.tipo_movimiento}
                      </span>
                    </td>
                    <td className="px-2 py-2">{m.respel_tipo?.nombre}</td>
                    <td className="px-2 py-2 text-right font-mono">
                      {m.cantidad.toLocaleString()} {m.unidad}
                    </td>
                    <td className="px-2 py-2 text-gray-600">{m.empresa_receptora?.nombre || '—'}</td>
                    <td className="px-2 py-2">
                      {m.numero_sidrep ? (
                        <span className="text-green-700 font-mono">{m.numero_sidrep}</span>
                      ) : m.tipo_movimiento === 'retiro' ? (
                        <span className="text-red-600">Pendiente</span>
                      ) : (
                        '—'
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-400">Sin movimientos registrados</p>
          )}
        </CardContent>
      </Card>

      {/* ── Bodegas SUSPEL ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Package className="h-5 w-5 text-gray-600" />
            Bodegas SUSPEL / RESPEL ({bodegas?.length ?? 0})
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {bodegas && bodegas.length > 0 ? (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b text-left text-gray-500 uppercase">
                  <th className="px-2 py-2">Código</th>
                  <th className="px-2 py-2">Nombre</th>
                  <th className="px-2 py-2">Tipo</th>
                  <th className="px-2 py-2">Autorización</th>
                  <th className="px-2 py-2">Vence</th>
                  <th className="px-2 py-2">Próx. inspección</th>
                </tr>
              </thead>
              <tbody>
                {bodegas.map((b) => (
                  <tr key={b.id} className="border-b hover:bg-gray-50">
                    <td className="px-2 py-2 font-mono">{b.codigo}</td>
                    <td className="px-2 py-2">{b.nombre}</td>
                    <td className="px-2 py-2 text-gray-600">{b.tipo}</td>
                    <td className="px-2 py-2 font-mono text-xs">{b.autorizacion_numero || '—'}</td>
                    <td className="px-2 py-2">{b.autorizacion_vencimiento || '—'}</td>
                    <td className="px-2 py-2">{b.proxima_inspeccion || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <div className="text-sm text-gray-400 py-4">
              <p>No hay bodegas registradas aún.</p>
              <p className="mt-2">Registra las bodegas SUSPEL/RESPEL de tu operación para empezar a trackear autorizaciones e inspecciones.</p>
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── Referencias normativas ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Referencias Normativas</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
            <div className="rounded bg-blue-50 p-3">
              <h4 className="font-semibold text-blue-700">DS 43/2016 MINSAL</h4>
              <p className="text-xs text-gray-600 mt-1">Reglamento de Almacenamiento de Sustancias Peligrosas (SUSPEL)</p>
            </div>
            <div className="rounded bg-green-50 p-3">
              <h4 className="font-semibold text-green-700">DS 148/2003 MINSAL</h4>
              <p className="text-xs text-gray-600 mt-1">Reglamento Sanitario sobre Manejo de Residuos Peligrosos (RESPEL → SIDREP)</p>
            </div>
            <div className="rounded bg-purple-50 p-3">
              <h4 className="font-semibold text-purple-700">DS 298/1995 MTT</h4>
              <p className="text-xs text-gray-600 mt-1">Transporte de Cargas Peligrosas por Calles y Caminos</p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
