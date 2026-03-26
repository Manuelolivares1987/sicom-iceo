'use client'

import { useState, useEffect, useMemo } from 'react'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import {
  ArrowLeft,
  Wrench,
  ShieldCheck,
  DollarSign,
  ClipboardList,
  Calendar,
  Gauge as GaugeIcon,
  MapPin,
  Hash,
  ChevronDown,
  ChevronUp,
  AlertTriangle,
  QrCode,
  History,
  Copy,
  RefreshCw,
  Camera,
  FileText,
  Package,
  Download,
  Printer,
} from 'lucide-react'
import QRCode from 'qrcode'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { Modal } from '@/components/ui/modal'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { cn, formatCLP, formatDate, getEstadoOTColor, getEstadoOTLabel } from '@/lib/utils'
import {
  getSemaforoDot,
  getCriticidadColor,
  getCriticidadLabel,
  getEstadoActivoLabel,
  getTipoActivoLabel,
} from '@/domain/activos/status'
import {
  useActivo,
  useOTsByActivo,
  usePlanesByActivo,
  useCertificacionesByActivo,
  useCostosByActivo,
  useHistorialMantenimiento,
  useGenerarQR,
} from '@/hooks/use-activos'

// ---------------------------------------------------------------------------
// Tab definitions
// ---------------------------------------------------------------------------
const TABS = [
  { key: 'ots', label: 'Historial OTs', icon: Wrench },
  { key: 'planes', label: 'Planes PM', icon: ClipboardList },
  { key: 'certificaciones', label: 'Certificaciones', icon: ShieldCheck },
  { key: 'costos', label: 'Costos', icon: DollarSign },
  { key: 'historial', label: 'Historial Completo', icon: History },
] as const

type TabKey = (typeof TABS)[number]['key']

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function InfoItem({ label, value }: { label: string; value: React.ReactNode }) {
  if (!value) return null
  return (
    <div>
      <p className="text-xs font-medium text-gray-500">{label}</p>
      <p className="mt-0.5 text-sm font-semibold text-gray-900">{value}</p>
    </div>
  )
}

function getPrioridadColor(p: string) {
  const m: Record<string, string> = {
    urgente: 'bg-red-100 text-red-700',
    alta: 'bg-orange-100 text-orange-700',
    media: 'bg-yellow-100 text-yellow-700',
    baja: 'bg-green-100 text-green-700',
  }
  return m[p] || 'bg-gray-100 text-gray-700'
}

function getPrioridadLabel(p: string) {
  const m: Record<string, string> = {
    urgente: 'Urgente',
    alta: 'Alta',
    media: 'Media',
    baja: 'Baja',
  }
  return m[p] || p
}

function getTipoPlanLabel(t: string) {
  const m: Record<string, string> = {
    por_tiempo: 'Por Tiempo',
    km: 'Por Km',
    horas: 'Por Horas',
    ciclos: 'Por Ciclos',
  }
  return m[t] || t
}

function getCertEstadoColor(estado: string) {
  const m: Record<string, string> = {
    vigente: 'bg-green-100 text-green-700',
    por_vencer: 'bg-yellow-100 text-yellow-700',
    vencido: 'bg-red-100 text-red-700',
  }
  return m[estado] || 'bg-gray-100 text-gray-700'
}

function getCertEstadoLabel(estado: string) {
  const m: Record<string, string> = {
    vigente: 'Vigente',
    por_vencer: 'Por Vencer',
    vencido: 'Vencido',
  }
  return m[estado] || estado
}

function getCertTipoLabel(tipo: string) {
  const m: Record<string, string> = {
    sec: 'SEC',
    sernageomin: 'SERNAGEOMIN',
    mutual: 'Mutual',
    revision_tecnica: 'Rev. Tecnica',
    otro: 'Otro',
  }
  return m[tipo] || tipo
}

function getProximaSemaforo(fecha: string | null) {
  if (!fecha) return 'bg-gray-400'
  const diff = (new Date(fecha).getTime() - Date.now()) / (1000 * 60 * 60 * 24)
  if (diff < 0) return 'bg-red-500'
  if (diff <= 7) return 'bg-yellow-400'
  return 'bg-green-500'
}

// ---------------------------------------------------------------------------
// Tab: Historial OTs
// ---------------------------------------------------------------------------
function TabOTs({ activoId }: { activoId: string }) {
  const { data: ots, isLoading } = useOTsByActivo(activoId)

  if (isLoading) return <div className="flex justify-center py-12"><Spinner size="lg" className="text-pillado-green-600" /></div>

  if (!ots || ots.length === 0) {
    return <EmptyState icon={Wrench} title="Sin ordenes de trabajo" description="Este activo no tiene OTs registradas." />
  }

  return (
    <>
      {/* Mobile cards */}
      <div className="space-y-3 md:hidden">
        {ots.map((ot: any) => (
          <Card key={ot.id}>
            <CardContent className="p-4 space-y-2">
              <div className="flex items-center justify-between">
                <Link href={`/dashboard/ordenes-trabajo/${ot.id}`} className="font-mono text-sm font-bold text-pillado-green-600 hover:underline">
                  {ot.folio}
                </Link>
                <Badge className={getEstadoOTColor(ot.estado)}>{getEstadoOTLabel(ot.estado)}</Badge>
              </div>
              <div className="flex flex-wrap gap-2">
                <Badge variant="default">{ot.tipo}</Badge>
                <Badge className={getPrioridadColor(ot.prioridad)}>{getPrioridadLabel(ot.prioridad)}</Badge>
              </div>
              <div className="flex items-center justify-between text-xs text-gray-500">
                <span>{ot.fecha_programada ? formatDate(ot.fecha_programada) : '—'}</span>
                <span className="font-semibold text-gray-700">{ot.costo_total ? formatCLP(ot.costo_total) : '—'}</span>
              </div>
              {ot.responsable?.nombre_completo && (
                <p className="text-xs text-gray-500">{ot.responsable.nombre_completo}</p>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Desktop table */}
      <Card className="hidden md:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Folio</TableHead>
              <TableHead>Tipo</TableHead>
              <TableHead>Estado</TableHead>
              <TableHead>Prioridad</TableHead>
              <TableHead>Fecha</TableHead>
              <TableHead className="text-right">Costo</TableHead>
              <TableHead>Responsable</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {ots.map((ot: any) => (
              <TableRow key={ot.id}>
                <TableCell>
                  <Link href={`/dashboard/ordenes-trabajo/${ot.id}`} className="font-mono text-xs font-bold text-pillado-green-600 hover:underline">
                    {ot.folio}
                  </Link>
                </TableCell>
                <TableCell><Badge variant="default">{ot.tipo}</Badge></TableCell>
                <TableCell><Badge className={getEstadoOTColor(ot.estado)}>{getEstadoOTLabel(ot.estado)}</Badge></TableCell>
                <TableCell><Badge className={getPrioridadColor(ot.prioridad)}>{getPrioridadLabel(ot.prioridad)}</Badge></TableCell>
                <TableCell className="text-xs text-gray-500">{ot.fecha_programada ? formatDate(ot.fecha_programada) : '—'}</TableCell>
                <TableCell className="text-right text-xs font-semibold">{ot.costo_total ? formatCLP(ot.costo_total) : '—'}</TableCell>
                <TableCell className="text-xs text-gray-500">{ot.responsable?.nombre_completo ?? '—'}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </>
  )
}

// ---------------------------------------------------------------------------
// Tab: Planes PM
// ---------------------------------------------------------------------------
function TabPlanes({ activoId }: { activoId: string }) {
  const { data: planes, isLoading } = usePlanesByActivo(activoId)
  const [expanded, setExpanded] = useState<string | null>(null)

  if (isLoading) return <div className="flex justify-center py-12"><Spinner size="lg" className="text-pillado-green-600" /></div>

  if (!planes || planes.length === 0) {
    return <EmptyState icon={ClipboardList} title="Sin planes de mantenimiento" description="Este activo no tiene planes PM activos." />
  }

  return (
    <div className="space-y-3">
      {planes.map((plan: any) => {
        const pauta = plan.pauta
        const isOpen = expanded === plan.id
        const tipoPlan = pauta?.tipo_plan ?? '—'
        const frecuencia =
          pauta?.frecuencia_dias ? `${pauta.frecuencia_dias} dias` :
          pauta?.frecuencia_km ? `${pauta.frecuencia_km.toLocaleString('es-CL')} km` :
          pauta?.frecuencia_horas ? `${pauta.frecuencia_horas.toLocaleString('es-CL')} hrs` :
          pauta?.frecuencia_ciclos ? `${pauta.frecuencia_ciclos.toLocaleString('es-CL')} ciclos` :
          '—'

        return (
          <Card key={plan.id}>
            <CardContent className="p-4">
              <div className="flex items-start justify-between">
                <div className="space-y-1">
                  <p className="text-sm font-bold text-gray-900">{plan.nombre ?? pauta?.nombre ?? 'Plan sin nombre'}</p>
                  <div className="flex flex-wrap gap-2">
                    <Badge variant="primary">{getTipoPlanLabel(tipoPlan)}</Badge>
                    <span className="text-xs text-gray-500">Frec: {frecuencia}</span>
                  </div>
                </div>
                <button
                  onClick={() => setExpanded(isOpen ? null : plan.id)}
                  className="rounded-md p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
                >
                  {isOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                </button>
              </div>

              <div className="mt-3 grid grid-cols-2 gap-4 text-xs">
                <div>
                  <span className="text-gray-500">Ultima ejecucion</span>
                  <p className="font-medium text-gray-700">{plan.ultima_ejecucion_fecha ? formatDate(plan.ultima_ejecucion_fecha) : '—'}</p>
                </div>
                <div>
                  <span className="text-gray-500">Proxima ejecucion</span>
                  <div className="flex items-center gap-1.5">
                    <span className={cn('h-2.5 w-2.5 rounded-full', getProximaSemaforo(plan.proxima_ejecucion_fecha))} />
                    <p className="font-medium text-gray-700">{plan.proxima_ejecucion_fecha ? formatDate(plan.proxima_ejecucion_fecha) : '—'}</p>
                  </div>
                </div>
              </div>

              {isOpen && pauta && (
                <div className="mt-4 space-y-3 border-t pt-3">
                  {pauta.items_checklist && Array.isArray(pauta.items_checklist) && pauta.items_checklist.length > 0 && (
                    <div>
                      <p className="mb-1 text-xs font-semibold text-gray-600">Checklist</p>
                      <ul className="space-y-1">
                        {pauta.items_checklist.map((item: any, i: number) => (
                          <li key={i} className="flex items-start gap-2 text-xs text-gray-600">
                            <span className="mt-0.5 h-1.5 w-1.5 shrink-0 rounded-full bg-gray-400" />
                            {typeof item === 'string' ? item : item.descripcion ?? JSON.stringify(item)}
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                  {pauta.materiales_estimados && Array.isArray(pauta.materiales_estimados) && pauta.materiales_estimados.length > 0 && (
                    <div>
                      <p className="mb-1 text-xs font-semibold text-gray-600">Materiales estimados</p>
                      <ul className="space-y-1">
                        {pauta.materiales_estimados.map((mat: any, i: number) => (
                          <li key={i} className="text-xs text-gray-600">
                            {typeof mat === 'string' ? mat : mat.nombre ?? JSON.stringify(mat)}
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              )}
            </CardContent>
          </Card>
        )
      })}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tab: Certificaciones
// ---------------------------------------------------------------------------
function TabCertificaciones({ activoId }: { activoId: string }) {
  const { data: certs, isLoading } = useCertificacionesByActivo(activoId)

  if (isLoading) return <div className="flex justify-center py-12"><Spinner size="lg" className="text-pillado-green-600" /></div>

  if (!certs || certs.length === 0) {
    return <EmptyState icon={ShieldCheck} title="Sin certificaciones" description="Este activo no tiene certificaciones registradas." />
  }

  return (
    <>
      {/* Mobile cards */}
      <div className="space-y-3 md:hidden">
        {certs.map((c: any) => (
          <Card key={c.id}>
            <CardContent className="p-4 space-y-2">
              <div className="flex items-center justify-between">
                <Badge variant="default">{getCertTipoLabel(c.tipo)}</Badge>
                <Badge className={getCertEstadoColor(c.estado)}>{getCertEstadoLabel(c.estado)}</Badge>
              </div>
              <p className="text-sm font-medium text-gray-900">{c.numero_certificado ?? '—'}</p>
              <p className="text-xs text-gray-500">{c.entidad_certificadora ?? '—'}</p>
              <div className="flex items-center justify-between text-xs text-gray-500">
                <span>Emision: {c.fecha_emision ? formatDate(c.fecha_emision) : '—'}</span>
                <span>Vence: {c.fecha_vencimiento ? formatDate(c.fecha_vencimiento) : '—'}</span>
              </div>
              {c.bloqueante && (
                <div className="flex items-center gap-1 text-xs text-red-600">
                  <AlertTriangle className="h-3.5 w-3.5" />
                  Bloqueante
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Desktop table */}
      <Card className="hidden md:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Tipo</TableHead>
              <TableHead>N Certificado</TableHead>
              <TableHead>Entidad</TableHead>
              <TableHead>Emision</TableHead>
              <TableHead>Vencimiento</TableHead>
              <TableHead>Estado</TableHead>
              <TableHead>Bloq.</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {certs.map((c: any) => (
              <TableRow key={c.id}>
                <TableCell><Badge variant="default">{getCertTipoLabel(c.tipo)}</Badge></TableCell>
                <TableCell className="text-xs font-medium">{c.numero_certificado ?? '—'}</TableCell>
                <TableCell className="text-xs text-gray-500">{c.entidad_certificadora ?? '—'}</TableCell>
                <TableCell className="text-xs text-gray-500">{c.fecha_emision ? formatDate(c.fecha_emision) : '—'}</TableCell>
                <TableCell className="text-xs text-gray-500">{c.fecha_vencimiento ? formatDate(c.fecha_vencimiento) : '—'}</TableCell>
                <TableCell><Badge className={getCertEstadoColor(c.estado)}>{getCertEstadoLabel(c.estado)}</Badge></TableCell>
                <TableCell>
                  {c.bloqueante && <AlertTriangle className="h-4 w-4 text-red-500" />}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </>
  )
}

// ---------------------------------------------------------------------------
// Tab: Costos
// ---------------------------------------------------------------------------
function TabCostos({ activoId }: { activoId: string }) {
  const { data: movimientos, isLoading } = useCostosByActivo(activoId)

  const totalInvertido = useMemo(() => {
    if (!movimientos) return 0
    return movimientos.reduce((sum: number, m: any) => sum + (m.costo_unitario ?? 0) * (m.cantidad ?? 0), 0)
  }, [movimientos])

  if (isLoading) return <div className="flex justify-center py-12"><Spinner size="lg" className="text-pillado-green-600" /></div>

  if (!movimientos || movimientos.length === 0) {
    return <EmptyState icon={DollarSign} title="Sin consumos registrados" description="Este activo no tiene movimientos de costos." />
  }

  return (
    <div className="space-y-4">
      {/* Summary card */}
      <Card>
        <CardContent className="flex items-center justify-between p-4">
          <div>
            <p className="text-xs font-medium text-gray-500">Total invertido en este activo</p>
            <p className="text-2xl font-bold text-gray-900">{formatCLP(totalInvertido)}</p>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-pillado-green-50">
            <DollarSign className="h-6 w-6 text-pillado-green-600" />
          </div>
        </CardContent>
      </Card>

      {/* Mobile cards */}
      <div className="space-y-3 md:hidden">
        {movimientos.map((m: any, i: number) => (
          <Card key={i}>
            <CardContent className="p-4 space-y-1">
              <div className="flex items-center justify-between">
                <p className="text-sm font-medium text-gray-900">{m.producto?.nombre ?? '—'}</p>
                <span className="text-sm font-bold text-gray-900">{formatCLP((m.costo_unitario ?? 0) * (m.cantidad ?? 0))}</span>
              </div>
              <div className="flex items-center justify-between text-xs text-gray-500">
                <span>{m.created_at ? formatDate(m.created_at) : '—'}</span>
                <span>Cant: {m.cantidad} x {formatCLP(m.costo_unitario ?? 0)}</span>
              </div>
              {m.ot?.folio && (
                <Link href={`/dashboard/ordenes-trabajo/${m.ot.id ?? ''}`} className="text-xs text-pillado-green-600 hover:underline">
                  OT {m.ot.folio}
                </Link>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Desktop table */}
      <Card className="hidden md:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Fecha</TableHead>
              <TableHead>Producto</TableHead>
              <TableHead className="text-right">Cantidad</TableHead>
              <TableHead className="text-right">Costo Unit.</TableHead>
              <TableHead className="text-right">Costo Total</TableHead>
              <TableHead>OT</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {movimientos.map((m: any, i: number) => (
              <TableRow key={i}>
                <TableCell className="text-xs text-gray-500">{m.created_at ? formatDate(m.created_at) : '—'}</TableCell>
                <TableCell className="text-xs font-medium">{m.producto?.nombre ?? '—'}</TableCell>
                <TableCell className="text-right text-xs">{m.cantidad}</TableCell>
                <TableCell className="text-right text-xs">{formatCLP(m.costo_unitario ?? 0)}</TableCell>
                <TableCell className="text-right text-xs font-semibold">{formatCLP((m.costo_unitario ?? 0) * (m.cantidad ?? 0))}</TableCell>
                <TableCell className="text-xs">
                  {m.ot?.folio ? (
                    <span className="text-pillado-green-600">{m.ot.folio}</span>
                  ) : '—'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tab: Historial Completo
// ---------------------------------------------------------------------------
function TabHistorial({ activoId }: { activoId: string }) {
  const { data: historial, isLoading } = useHistorialMantenimiento(activoId)

  if (isLoading) return <div className="flex justify-center py-12"><Spinner size="lg" className="text-pillado-green-600" /></div>

  if (!historial || historial.length === 0) {
    return <EmptyState icon={History} title="Sin historial" description="No hay intervenciones registradas para este activo." />
  }

  return (
    <div className="space-y-3">
      {(historial as any[]).map((item: any, idx: number) => (
        <Card key={item.id ?? idx}>
          <CardContent className="p-4 space-y-2">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-500">
                  {item.fecha_programada ? formatDate(item.fecha_programada) : '—'}
                </span>
                <Badge variant="default">{item.tipo ?? '—'}</Badge>
              </div>
              <Badge className={getEstadoOTColor(item.estado)}>{getEstadoOTLabel(item.estado)}</Badge>
            </div>

            <div className="flex items-center justify-between">
              {item.folio ? (
                <Link
                  href={`/dashboard/ordenes-trabajo/${item.ot_id ?? item.id}`}
                  className="font-mono text-sm font-bold text-pillado-green-600 hover:underline"
                >
                  {item.folio}
                </Link>
              ) : (
                <span className="text-sm text-gray-400">Sin folio</span>
              )}
              {item.responsable && (
                <span className="text-xs text-gray-500">{item.responsable}</span>
              )}
            </div>

            <div className="flex flex-wrap gap-3 text-xs text-gray-500">
              {item.checklist_ok != null && (
                <span className="flex items-center gap-1">
                  <ClipboardList className="h-3.5 w-3.5" />
                  {item.checklist_ok}/{item.checklist_total}
                  {item.checklist_no_ok > 0 && (
                    <span className="text-red-500"> ({item.checklist_no_ok} no ok)</span>
                  )}
                </span>
              )}
              {item.evidencias_count > 0 && (
                <span className="flex items-center gap-1">
                  <Camera className="h-3.5 w-3.5" />
                  {item.evidencias_count}
                </span>
              )}
              {item.materiales_count > 0 && (
                <span className="flex items-center gap-1">
                  <Package className="h-3.5 w-3.5" />
                  {item.materiales_count}
                </span>
              )}
              {item.costo_total > 0 && (
                <span className="flex items-center gap-1">
                  <DollarSign className="h-3.5 w-3.5" />
                  {formatCLP(item.costo_total)}
                </span>
              )}
              {item.horas_fuera_servicio > 0 && (
                <span className="flex items-center gap-1 text-orange-600">
                  <AlertTriangle className="h-3.5 w-3.5" />
                  {item.horas_fuera_servicio}h fuera de servicio
                </span>
              )}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// QR Modal
// ---------------------------------------------------------------------------
function QRModal({
  open,
  onClose,
  activo,
}: {
  open: boolean
  onClose: () => void
  activo: any
}) {
  const generarQR = useGenerarQR()
  const [copied, setCopied] = useState(false)
  const [qrImageUrl, setQrImageUrl] = useState<string>('')

  const qrUrl =
    typeof window !== 'undefined'
      ? `${window.location.origin}/equipo/${activo.id}`
      : `/equipo/${activo.id}`

  // Generate QR image when modal opens
  useEffect(() => {
    if (open) {
      const urlToEncode = activo.qr_url || `https://pilladoiceo.netlify.app/equipo/${activo.id}`
      QRCode.toDataURL(urlToEncode, {
        width: 300,
        margin: 2,
        color: { dark: '#000000', light: '#FFFFFF' },
      }).then(setQrImageUrl).catch(() => {})
    }
  }, [open, activo.qr_url, activo.id])

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(qrUrl)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      // ignore
    }
  }

  const handleGenerar = () => {
    generarQR.mutate(activo.id)
  }

  function handleDownload() {
    if (!qrImageUrl) return
    const link = document.createElement('a')
    link.download = `QR-${activo.codigo}.png`
    link.href = qrImageUrl
    link.click()
  }

  function handlePrint() {
    if (!qrImageUrl) return
    const printWindow = window.open('', '_blank')
    if (!printWindow) return
    printWindow.document.write(`
      <html><head><title>QR - ${activo.codigo}</title>
      <style>body{text-align:center;font-family:sans-serif;padding:20px}
      img{width:250px}h2{margin:10px 0 5px}p{color:#666;margin:2px}</style></head>
      <body>
      <img src="${qrImageUrl}" />
      <h2>${activo.codigo}</h2>
      <p>${activo.nombre || ''}</p>
      <p>${activo.modelo?.marca?.nombre || ''} — ${activo.modelo?.nombre || ''}</p>
      <p>SICOM-ICEO — Pillado Empresas</p>
      </body></html>
    `)
    printWindow.document.close()
    printWindow.print()
  }

  return (
    <Modal open={open} onClose={onClose} title="Codigo QR del equipo">
      <div className="space-y-5">
        {/* QR Image */}
        {qrImageUrl && (
          <div className="flex flex-col items-center rounded-lg bg-gray-50 px-4 py-6">
            <img src={qrImageUrl} alt={`QR ${activo.codigo}`} className="h-[250px] w-[250px]" />
            <p className="mt-3 font-mono text-lg font-bold text-gray-900">{activo.codigo}</p>
            <p className="text-sm text-gray-500">{activo.nombre || ''}</p>
          </div>
        )}

        {/* QR value */}
        {activo.qr_code && (
          <div className="rounded-lg bg-gray-50 px-4 py-4 text-center">
            <p className="text-[10px] font-medium uppercase tracking-wider text-gray-400 mb-2">
              Valor QR
            </p>
            <p className="font-mono text-lg font-bold text-gray-900 break-all">
              {activo.qr_code}
            </p>
          </div>
        )}

        {/* URL */}
        <div>
          <p className="text-xs font-medium text-gray-500 mb-1">URL publica</p>
          <div className="flex items-center gap-2">
            <code className="flex-1 rounded-md bg-gray-100 px-3 py-2 text-xs font-mono text-gray-700 break-all">
              {qrUrl}
            </code>
            <Button
              variant="outline"
              size="sm"
              onClick={handleCopy}
              className="shrink-0"
            >
              <Copy className="h-4 w-4 mr-1" />
              {copied ? 'Copiado!' : 'Copiar URL'}
            </Button>
          </div>
        </div>

        {/* Action buttons */}
        <div className="grid grid-cols-2 gap-3">
          <Button
            variant="outline"
            onClick={handleDownload}
            disabled={!qrImageUrl}
          >
            <Download className="h-4 w-4 mr-2" />
            Descargar QR
          </Button>
          <Button
            variant="outline"
            onClick={handlePrint}
            disabled={!qrImageUrl}
          >
            <Printer className="h-4 w-4 mr-2" />
            Imprimir
          </Button>
        </div>

        {/* Generate / Regenerate button */}
        <Button
          onClick={handleGenerar}
          disabled={generarQR.isPending}
          className="w-full"
        >
          {generarQR.isPending ? (
            <Spinner size="sm" className="mr-2" />
          ) : (
            <RefreshCw className="h-4 w-4 mr-2" />
          )}
          {activo.qr_code ? 'Regenerar QR' : 'Generar QR'}
        </Button>

        <p className="text-center text-xs text-gray-400">
          Imprima este codigo QR y peguelo en el equipo
        </p>
      </div>
    </Modal>
  )
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function ActivoDetailPage() {
  const params = useParams()
  const id = params.id as string
  const [activeTab, setActiveTab] = useState<TabKey>('ots')
  const [qrOpen, setQrOpen] = useState(false)

  const { data: activo, isLoading, error } = useActivo(id)

  if (isLoading) {
    return (
      <div className="flex justify-center py-24">
        <Spinner size="lg" className="text-pillado-green-600" />
      </div>
    )
  }

  if (error || !activo) {
    return (
      <div className="py-24 text-center">
        <p className="text-lg font-medium text-red-500">Error al cargar el activo</p>
        <p className="mt-1 text-sm text-gray-400">{(error as Error)?.message ?? 'Activo no encontrado'}</p>
        <Link href="/dashboard/activos" className="mt-4 inline-flex items-center gap-1 text-sm text-pillado-green-600 hover:underline">
          <ArrowLeft className="h-4 w-4" /> Volver a activos
        </Link>
      </div>
    )
  }

  const marcaNombre = activo.modelo?.marca?.nombre ?? ''
  const modeloNombre = activo.modelo?.nombre ?? ''
  const faenaNombre = activo.faena?.nombre ?? '—'

  return (
    <div className="space-y-6">
      {/* Back link */}
      <Link href="/dashboard/activos" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-pillado-green-600">
        <ArrowLeft className="h-4 w-4" />
        Volver a activos
      </Link>

      {/* Header */}
      <Card>
        <CardContent className="p-6">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div className="flex items-center gap-3">
              <span className={cn('h-4 w-4 rounded-full', getSemaforoDot(activo.estado))} />
              <div>
                <h1 className="font-mono text-2xl font-bold text-gray-900">{activo.codigo}</h1>
                <p className="text-sm text-gray-500">{activo.nombre ?? activo.codigo}</p>
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="default">{getTipoActivoLabel(activo.tipo)}</Badge>
              <Badge className={getCriticidadColor(activo.criticidad)}>{getCriticidadLabel(activo.criticidad)}</Badge>
              <Badge variant={activo.estado as any}>{getEstadoActivoLabel(activo.estado)}</Badge>
              <button
                onClick={() => setQrOpen(true)}
                className="rounded-md p-1.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-pillado-green-600"
                title="Ver codigo QR"
              >
                <QrCode className="h-5 w-5" />
              </button>
            </div>
          </div>

          {/* Info grid */}
          <div className="mt-6 grid grid-cols-2 gap-x-6 gap-y-4 md:grid-cols-4">
            <InfoItem label="Marca / Modelo" value={marcaNombre || modeloNombre ? `${marcaNombre}${marcaNombre && modeloNombre ? ' — ' : ''}${modeloNombre}` : null} />
            <InfoItem label="Numero de serie" value={activo.numero_serie} />
            <InfoItem label="Faena" value={faenaNombre} />
            <InfoItem label="Fecha de alta" value={activo.fecha_alta ? formatDate(activo.fecha_alta) : null} />
            <InfoItem
              label="Kilometraje actual"
              value={activo.kilometraje_actual > 0 ? `${activo.kilometraje_actual.toLocaleString('es-CL')} km` : null}
            />
            <InfoItem
              label="Horas de uso"
              value={activo.horas_uso_actual > 0 ? `${activo.horas_uso_actual.toLocaleString('es-CL')} hrs` : null}
            />
            <InfoItem
              label="Ciclos"
              value={activo.ciclos_actual > 0 ? activo.ciclos_actual.toLocaleString('es-CL') : null}
            />
            <InfoItem label="Ubicacion detalle" value={activo.ubicacion_detalle} />
          </div>
        </CardContent>
      </Card>

      {/* Tabs */}
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex gap-4 overflow-x-auto">
          {TABS.map((tab) => {
            const Icon = tab.icon
            const isActive = activeTab === tab.key
            return (
              <button
                key={tab.key}
                onClick={() => setActiveTab(tab.key)}
                className={cn(
                  'flex items-center gap-1.5 whitespace-nowrap border-b-2 px-1 pb-3 text-sm font-medium transition-colors',
                  isActive
                    ? 'border-pillado-green-600 text-pillado-green-600'
                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                )}
              >
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            )
          })}
        </nav>
      </div>

      {/* Tab content */}
      {activeTab === 'ots' && <TabOTs activoId={id} />}
      {activeTab === 'planes' && <TabPlanes activoId={id} />}
      {activeTab === 'certificaciones' && <TabCertificaciones activoId={id} />}
      {activeTab === 'costos' && <TabCostos activoId={id} />}
      {activeTab === 'historial' && <TabHistorial activoId={id} />}

      {/* QR Modal */}
      <QRModal open={qrOpen} onClose={() => setQrOpen(false)} activo={activo} />
    </div>
  )
}
