'use client'

import { useState, useMemo, useRef } from 'react'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import {
  ArrowLeft,
  Wrench,
  ShieldCheck,
  DollarSign,
  ClipboardList,
  History,
  AlertTriangle,
  QrCode,
  Camera,
  Package,
  Truck,
  FileText,
  Upload,
  Save,
  X,
  Pencil,
  Plus,
  Trash2,
  ExternalLink,
  Activity,
  Calendar,
  MapPin,
  Hash,
  ChevronDown,
  ChevronUp,
  Copy,
  Download,
  Printer,
  RefreshCw,
  CheckCircle2,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
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
import { cn, formatCLP, formatDate, getEstadoOTColor, getEstadoOTLabel, todayISO } from '@/lib/utils'
import {
  getSemaforoDot,
  getCriticidadColor,
  getCriticidadLabel,
  getEstadoActivoLabel,
  getTipoActivoLabel,
  getTipoCertificacionLabel,
  getEstadoComercialLabel,
  getEstadoComercialColor,
} from '@/domain/activos/status'
import {
  useActivo,
  useUpdateActivo,
  useOTsByActivo,
  usePlanesByActivo,
  useCertificacionesByActivo,
  useCostosByActivo,
  useHistorialMantenimiento,
  useUpsertCertificacion,
  useUploadCertificado,
} from '@/hooks/use-activos'
import { useOEEActivo } from '@/hooks/use-flota'

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------
const TABS = [
  { key: 'identificacion', label: 'Identificacion', icon: Truck },
  { key: 'certificaciones', label: 'Documentos', icon: ShieldCheck },
  { key: 'ots', label: 'OTs', icon: Wrench },
  { key: 'planes', label: 'Planes PM', icon: ClipboardList },
  { key: 'costos', label: 'Costos', icon: DollarSign },
  { key: 'historial', label: 'Historial', icon: History },
] as const
type TabKey = (typeof TABS)[number]['key']

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function InfoItem({ label, value, editable, onSave }: {
  label: string; value: React.ReactNode; editable?: boolean;
  onSave?: (val: string) => void
}) {
  const [editing, setEditing] = useState(false)
  const [editVal, setEditVal] = useState(String(value ?? ''))

  if (editing && editable && onSave) {
    return (
      <div>
        <p className="text-xs font-medium text-gray-500">{label}</p>
        <div className="flex items-center gap-1 mt-0.5">
          <input
            className="flex-1 rounded border border-gray-300 px-2 py-1 text-sm"
            value={editVal}
            onChange={(e) => setEditVal(e.target.value)}
            autoFocus
          />
          <button onClick={() => { onSave(editVal); setEditing(false) }}
            className="p-1 text-green-600 hover:bg-green-50 rounded">
            <Save className="h-3.5 w-3.5" />
          </button>
          <button onClick={() => setEditing(false)}
            className="p-1 text-gray-400 hover:bg-gray-50 rounded">
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="group">
      <p className="text-xs font-medium text-gray-500">{label}</p>
      <div className="flex items-center gap-1 mt-0.5">
        <p className="text-sm font-semibold text-gray-900">{value || '—'}</p>
        {editable && (
          <button onClick={() => { setEditVal(String(value ?? '')); setEditing(true) }}
            className="opacity-0 group-hover:opacity-100 p-0.5 text-gray-400 hover:text-blue-600">
            <Pencil className="h-3 w-3" />
          </button>
        )}
      </div>
    </div>
  )
}

function getCertEstadoColor(estado: string) {
  return { vigente: 'bg-green-100 text-green-700', por_vencer: 'bg-yellow-100 text-yellow-700', vencido: 'bg-red-100 text-red-700' }[estado] || 'bg-gray-100 text-gray-700'
}
function getCertEstadoLabel(estado: string) {
  return { vigente: 'Vigente', por_vencer: 'Por Vencer', vencido: 'Vencido' }[estado] || estado
}
function getDiasRestantes(fecha: string) {
  const diff = Math.ceil((new Date(fecha).getTime() - Date.now()) / (1000 * 60 * 60 * 24))
  return diff
}
function getPrioridadColor(p: string) {
  return { urgente: 'bg-red-100 text-red-700', alta: 'bg-orange-100 text-orange-700', media: 'bg-yellow-100 text-yellow-700', baja: 'bg-green-100 text-green-700' }[p] || 'bg-gray-100 text-gray-700'
}

// ---------------------------------------------------------------------------
// Main Page
// ---------------------------------------------------------------------------
export default function ActivoDetailPage() {
  const { id } = useParams<{ id: string }>()
  const [tab, setTab] = useState<TabKey>('identificacion')

  const { data: activo, isLoading } = useActivo(id)
  const { data: certs } = useCertificacionesByActivo(id)
  const updateActivo = useUpdateActivo()

  // OEE del mes actual
  const today = new Date()
  const firstOfMonth = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-01`
  const todayStr = todayISO()
  const { data: oee } = useOEEActivo(id, firstOfMonth, todayStr)

  // Alertas de certificaciones
  const certsAlerta = useMemo(() => {
    if (!certs) return { vencidas: 0, porVencer: 0, items: [] as any[] }
    const vencidas = certs.filter((c: any) => c.estado === 'vencido')
    const porVencer = certs.filter((c: any) => c.estado === 'por_vencer')
    return {
      vencidas: vencidas.length,
      porVencer: porVencer.length,
      items: [...vencidas, ...porVencer],
    }
  }, [certs])

  const handleUpdateField = (field: string) => (value: string) => {
    if (!id) return
    updateActivo.mutate({ id, updates: { [field]: value || null } as any })
  }

  if (isLoading || !activo) {
    return <div className="flex items-center justify-center h-64"><Spinner className="h-8 w-8" /></div>
  }

  const a: any = activo
  const modelo = a.modelo as any
  const marca = modelo?.marca as any

  return (
    <div className="space-y-6">
      {/* ── Back link ── */}
      <Link href="/dashboard/activos" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a activos
      </Link>

      {/* ── Header principal ── */}
      <div className="bg-white rounded-lg border p-4 md:p-6">
        <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              <span className={cn('h-3 w-3 rounded-full', getSemaforoDot(a.estado))} />
              <h1 className="text-xl md:text-2xl font-bold text-gray-900">
                {a.patente || a.codigo}
              </h1>
              <Badge className={getCriticidadColor(a.criticidad)}>{getCriticidadLabel(a.criticidad)}</Badge>
              <Badge variant="default">{getEstadoActivoLabel(a.estado)}</Badge>
              {a.estado_comercial && (
                <Badge className={getEstadoComercialColor(a.estado_comercial)}>
                  {getEstadoComercialLabel(a.estado_comercial)}
                </Badge>
              )}
            </div>
            <p className="text-sm text-gray-600">
              {a.nombre} — {marca?.nombre} {modelo?.nombre}
            </p>
            <div className="flex flex-wrap gap-4 text-xs text-gray-500">
              {a.centro_costo && <span>CECO: <strong>{a.centro_costo}</strong></span>}
              {a.anio_fabricacion && <span>Ano: <strong>{a.anio_fabricacion}</strong></span>}
              {a.potencia && <span>Potencia: <strong>{a.potencia}</strong></span>}
              {a.operacion && <span>Op: <strong>{a.operacion}</strong></span>}
              {a.cliente_actual && <span>Cliente: <strong>{a.cliente_actual}</strong></span>}
            </div>
          </div>

          {/* OEE badge */}
          {oee && (
            <div className={cn('rounded-lg border p-3 text-center min-w-[120px]',
              oee.oee >= 80 ? 'bg-green-50 border-green-200' :
              oee.oee >= 64 ? 'bg-blue-50 border-blue-200' :
              oee.oee >= 50 ? 'bg-amber-50 border-amber-200' :
              'bg-red-50 border-red-200'
            )}>
              <div className="text-xs text-gray-500">OEE Mes</div>
              <div className={cn('text-2xl font-bold',
                oee.oee >= 80 ? 'text-green-600' :
                oee.oee >= 64 ? 'text-blue-600' :
                oee.oee >= 50 ? 'text-amber-600' :
                'text-red-600'
              )}>{oee.oee?.toFixed(1)}%</div>
            </div>
          )}
        </div>

        {/* Alertas de certificaciones */}
        {(certsAlerta.vencidas > 0 || certsAlerta.porVencer > 0) && (
          <div className={cn('mt-4 rounded-lg p-3 flex items-start gap-2',
            certsAlerta.vencidas > 0 ? 'bg-red-50 border border-red-200' : 'bg-amber-50 border border-amber-200'
          )}>
            <AlertTriangle className={cn('h-5 w-5 mt-0.5', certsAlerta.vencidas > 0 ? 'text-red-600' : 'text-amber-600')} />
            <div>
              <p className={cn('text-sm font-semibold', certsAlerta.vencidas > 0 ? 'text-red-700' : 'text-amber-700')}>
                {certsAlerta.vencidas > 0
                  ? `${certsAlerta.vencidas} documento(s) VENCIDO(S)`
                  : `${certsAlerta.porVencer} documento(s) por vencer`
                }
              </p>
              <div className="mt-1 space-y-0.5">
                {certsAlerta.items.slice(0, 5).map((c: any) => (
                  <p key={c.id} className="text-xs text-gray-600">
                    {getTipoCertificacionLabel(c.tipo)}: vence {formatDate(c.fecha_vencimiento)}
                    {c.estado === 'vencido' && <span className="text-red-600 font-bold"> (VENCIDO)</span>}
                    {c.estado === 'por_vencer' && <span className="text-amber-600"> ({getDiasRestantes(c.fecha_vencimiento)} dias)</span>}
                  </p>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* ── Tabs ── */}
      <div className="flex overflow-x-auto border-b">
        {TABS.map((t) => {
          const Icon = t.icon
          const isActive = tab === t.key
          const hasBadge = t.key === 'certificaciones' && (certsAlerta.vencidas + certsAlerta.porVencer) > 0
          return (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={cn(
                'flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 -mb-px',
                isActive ? 'border-blue-600 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700'
              )}
            >
              <Icon className="h-4 w-4" />
              {t.label}
              {hasBadge && (
                <span className="ml-1 bg-red-500 text-white text-xs rounded-full px-1.5 py-0.5 leading-none">
                  {certsAlerta.vencidas + certsAlerta.porVencer}
                </span>
              )}
            </button>
          )
        })}
      </div>

      {/* ── Tab content ── */}
      <div>
        {tab === 'identificacion' && <TabIdentificacion activo={a} onUpdate={handleUpdateField} />}
        {tab === 'certificaciones' && <TabCertificaciones activoId={id} />}
        {tab === 'ots' && <TabOTs activoId={id} />}
        {tab === 'planes' && <TabPlanes activoId={id} />}
        {tab === 'costos' && <TabCostos activoId={id} />}
        {tab === 'historial' && <TabHistorial activoId={id} />}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tab: Identificacion (NUEVO — campos editables del maestro)
// ---------------------------------------------------------------------------
function TabIdentificacion({ activo, onUpdate }: { activo: any; onUpdate: (field: string) => (val: string) => void }) {
  const ss = activo.sistemas_seguridad || {}

  return (
    <div className="space-y-6">
      {/* Datos del vehículo */}
      <Card>
        <CardHeader><CardTitle className="text-base">Datos del Vehiculo</CardTitle></CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <InfoItem label="Patente (PPU)" value={activo.patente} editable onSave={onUpdate('patente')} />
            <InfoItem label="Centro de Costo" value={activo.centro_costo} editable onSave={onUpdate('centro_costo')} />
            <InfoItem label="Codigo Interno" value={activo.codigo} />
            <InfoItem label="Tipo" value={getTipoActivoLabel(activo.tipo)} />
            <InfoItem label="Marca" value={activo.modelo?.marca?.nombre} />
            <InfoItem label="Modelo" value={activo.modelo?.nombre} />
            <InfoItem label="Equipamiento" value={activo.nombre} editable onSave={onUpdate('nombre')} />
            <InfoItem label="Ano Fabricacion" value={activo.anio_fabricacion} editable onSave={(v) => onUpdate('anio_fabricacion')(v)} />
          </div>
        </CardContent>
      </Card>

      {/* Datos técnicos */}
      <Card>
        <CardHeader><CardTitle className="text-base">Datos Tecnicos</CardTitle></CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <InfoItem label="VIN / Chasis" value={activo.vin_chasis} editable onSave={onUpdate('vin_chasis')} />
            <InfoItem label="N Motor" value={activo.numero_motor} editable onSave={onUpdate('numero_motor')} />
            <InfoItem label="N Serie" value={activo.numero_serie} editable onSave={onUpdate('numero_serie')} />
            <InfoItem label="Potencia" value={activo.potencia} editable onSave={onUpdate('potencia')} />
            <InfoItem label="Kilometraje" value={activo.kilometraje_actual ? `${Number(activo.kilometraje_actual).toLocaleString('es-CL')} km` : '—'} />
            <InfoItem label="Horometro" value={activo.horas_uso_actual ? `${Number(activo.horas_uso_actual).toLocaleString('es-CL')} hrs` : '—'} />
            <InfoItem label="Criticidad" value={getCriticidadLabel(activo.criticidad)} />
            <InfoItem label="Fecha Alta" value={activo.fecha_alta ? formatDate(activo.fecha_alta) : '—'} />
          </div>
        </CardContent>
      </Card>

      {/* Situación comercial */}
      <Card>
        <CardHeader><CardTitle className="text-base">Situacion Comercial</CardTitle></CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <InfoItem label="Estado Operativo" value={getEstadoActivoLabel(activo.estado)} />
            <InfoItem label="Estado Comercial" value={activo.estado_comercial ? getEstadoComercialLabel(activo.estado_comercial) : '—'} />
            <InfoItem label="Operacion" value={activo.operacion} editable onSave={onUpdate('operacion')} />
            <InfoItem label="Cliente Actual" value={activo.cliente_actual} editable onSave={onUpdate('cliente_actual')} />
            <InfoItem label="Ubicacion Actual" value={activo.ubicacion_actual} editable onSave={onUpdate('ubicacion_actual')} />
            <InfoItem label="Faena" value={activo.faena?.nombre} />
          </div>
        </CardContent>
      </Card>

      {/* Sistemas de seguridad */}
      <Card>
        <CardHeader><CardTitle className="text-base">Sistemas de Seguridad</CardTitle></CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {[
              { key: 'antisomnolencia', label: 'Sist. Antisomnolencia' },
              { key: 'mobileye', label: 'Sist. Mobileye (ADAS)' },
              { key: 'ecam', label: 'Sist. ECAM (360)' },
              { key: 'gps', label: 'GPS Certificado' },
              { key: 'tacografo', label: 'Tacografo' },
              { key: 'limitador_velocidad', label: 'Limitador Velocidad' },
              { key: 'alarma_retroceso', label: 'Alarma Retroceso' },
              { key: 'camara_retroceso', label: 'Camara Retroceso' },
            ].map(({ key, label }) => {
              const val = ss[key]
              const installed = val === true || val === 'Sist. Instalado' || val === 'Sist. Instalado '
              return (
                <div key={key} className="flex items-center gap-2">
                  <span className={cn(
                    'h-3 w-3 rounded-full',
                    installed ? 'bg-green-500' : val === false || val === '/' ? 'bg-gray-300' : 'bg-gray-200'
                  )} />
                  <span className="text-sm text-gray-700">{label}</span>
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tab: Certificaciones / Documentos (REESCRITO — con upload y alertas)
// ---------------------------------------------------------------------------
function TabCertificaciones({ activoId }: { activoId: string }) {
  const { data: certs, isLoading } = useCertificacionesByActivo(activoId)
  const upsertCert = useUpsertCertificacion()
  const uploadCert = useUploadCertificado()
  const [showAdd, setShowAdd] = useState(false)
  const [newCert, setNewCert] = useState({ tipo: 'revision_tecnica', fecha_emision: '', fecha_vencimiento: '', entidad_certificadora: '', numero_certificado: '', bloqueante: true })
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [uploadingCertId, setUploadingCertId] = useState<string | null>(null)

  const handleAdd = () => {
    upsertCert.mutate({
      activo_id: activoId,
      ...newCert,
    }, {
      onSuccess: () => {
        setShowAdd(false)
        setNewCert({ tipo: 'revision_tecnica', fecha_emision: '', fecha_vencimiento: '', entidad_certificadora: '', numero_certificado: '', bloqueante: true })
      },
    })
  }

  const handleFileUpload = (certId: string) => {
    setUploadingCertId(certId)
    fileInputRef.current?.click()
  }

  const handleFileSelected = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !uploadingCertId) return
    uploadCert.mutate({ activoId, certId: uploadingCertId, file })
    setUploadingCertId(null)
    e.target.value = ''
  }

  if (isLoading) return <div className="flex justify-center py-12"><Spinner className="h-8 w-8" /></div>

  const certTypes = ['revision_tecnica', 'soap', 'permiso_circulacion', 'hermeticidad', 'tc8_sec', 'inscripcion_sec', 'seguro_rc', 'cert_gancho', 'fops_rops', 'calibracion', 'otra']

  return (
    <div className="space-y-4">
      <input type="file" ref={fileInputRef} className="hidden" accept=".pdf,.jpg,.jpeg,.png" onChange={handleFileSelected} />

      <div className="flex justify-between items-center">
        <h3 className="text-base font-semibold">Documentos y Certificaciones</h3>
        <Button size="sm" onClick={() => setShowAdd(!showAdd)}>
          <Plus className="h-4 w-4 mr-1" /> Agregar
        </Button>
      </div>

      {/* Form para agregar */}
      {showAdd && (
        <Card className="border-blue-200 bg-blue-50">
          <CardContent className="p-4 space-y-3">
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
              <div>
                <label className="text-xs font-medium text-gray-600">Tipo</label>
                <select className="w-full rounded border px-2 py-1.5 text-sm mt-1"
                  value={newCert.tipo} onChange={(e) => setNewCert({ ...newCert, tipo: e.target.value })}>
                  {certTypes.map((t) => <option key={t} value={t}>{getTipoCertificacionLabel(t)}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">Fecha Emision</label>
                <input type="date" className="w-full rounded border px-2 py-1.5 text-sm mt-1"
                  value={newCert.fecha_emision} onChange={(e) => setNewCert({ ...newCert, fecha_emision: e.target.value })} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">Fecha Vencimiento</label>
                <input type="date" className="w-full rounded border px-2 py-1.5 text-sm mt-1"
                  value={newCert.fecha_vencimiento} onChange={(e) => setNewCert({ ...newCert, fecha_vencimiento: e.target.value })} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">Entidad</label>
                <input className="w-full rounded border px-2 py-1.5 text-sm mt-1" placeholder="Ej: PRT, SEC..."
                  value={newCert.entidad_certificadora} onChange={(e) => setNewCert({ ...newCert, entidad_certificadora: e.target.value })} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">N Certificado</label>
                <input className="w-full rounded border px-2 py-1.5 text-sm mt-1"
                  value={newCert.numero_certificado} onChange={(e) => setNewCert({ ...newCert, numero_certificado: e.target.value })} />
              </div>
              <div className="flex items-end">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={newCert.bloqueante}
                    onChange={(e) => setNewCert({ ...newCert, bloqueante: e.target.checked })} />
                  Bloqueante
                </label>
              </div>
            </div>
            <div className="flex gap-2">
              <Button size="sm" onClick={handleAdd} disabled={!newCert.fecha_emision || !newCert.fecha_vencimiento || upsertCert.isPending}>
                <Save className="h-4 w-4 mr-1" /> Guardar
              </Button>
              <Button size="sm" variant="outline" onClick={() => setShowAdd(false)}>Cancelar</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Lista de certificaciones */}
      {(!certs || certs.length === 0) ? (
        <EmptyState icon={ShieldCheck} title="Sin certificaciones" description="Agregue los documentos del equipo." />
      ) : (
        <div className="space-y-2">
          {(certs as any[])
            .sort((a, b) => {
              const order = { vencido: 0, por_vencer: 1, vigente: 2 }
              return (order[a.estado as keyof typeof order] ?? 3) - (order[b.estado as keyof typeof order] ?? 3)
            })
            .map((c: any) => {
              const dias = getDiasRestantes(c.fecha_vencimiento)
              return (
                <Card key={c.id} className={cn(
                  'border-l-4',
                  c.estado === 'vencido' ? 'border-l-red-500' :
                  c.estado === 'por_vencer' ? 'border-l-amber-500' :
                  'border-l-green-500'
                )}>
                  <CardContent className="p-4">
                    <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-2">
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-bold text-gray-900">
                            {getTipoCertificacionLabel(c.tipo)}
                          </span>
                          <Badge className={getCertEstadoColor(c.estado)}>{getCertEstadoLabel(c.estado)}</Badge>
                          {c.bloqueante && (
                            <span className="flex items-center gap-0.5 text-xs text-red-600">
                              <AlertTriangle className="h-3 w-3" /> Bloqueante
                            </span>
                          )}
                        </div>
                        <div className="flex flex-wrap gap-3 text-xs text-gray-500">
                          {c.numero_certificado && <span>N: {c.numero_certificado}</span>}
                          {c.entidad_certificadora && <span>Entidad: {c.entidad_certificadora}</span>}
                          <span>Emision: {formatDate(c.fecha_emision)}</span>
                          <span className={cn(
                            'font-semibold',
                            c.estado === 'vencido' ? 'text-red-600' :
                            c.estado === 'por_vencer' ? 'text-amber-600' : ''
                          )}>
                            Vence: {formatDate(c.fecha_vencimiento)}
                            {dias < 0 ? ` (vencido hace ${Math.abs(dias)} dias)` :
                             dias <= 45 ? ` (${dias} dias)` : ''}
                          </span>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        {c.archivo_url ? (
                          <a href={c.archivo_url} target="_blank" rel="noopener noreferrer"
                            className="inline-flex items-center gap-1 text-xs text-blue-600 hover:underline">
                            <FileText className="h-3.5 w-3.5" /> Ver documento
                          </a>
                        ) : (
                          <Button variant="outline" size="sm" onClick={() => handleFileUpload(c.id)}
                            disabled={uploadCert.isPending}>
                            <Upload className="h-3.5 w-3.5 mr-1" /> Subir archivo
                          </Button>
                        )}
                      </div>
                    </div>
                  </CardContent>
                </Card>
              )
            })}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tabs reutilizados (simplificados)
// ---------------------------------------------------------------------------
function TabOTs({ activoId }: { activoId: string }) {
  const { data: ots, isLoading } = useOTsByActivo(activoId)
  if (isLoading) return <div className="flex justify-center py-12"><Spinner className="h-8 w-8" /></div>
  if (!ots || ots.length === 0) return <EmptyState icon={Wrench} title="Sin ordenes de trabajo" description="Este activo no tiene OTs registradas." />

  return (
    <div className="space-y-2">
      {ots.map((ot: any) => (
        <Card key={ot.id}>
          <CardContent className="p-4 flex flex-col md:flex-row md:items-center md:justify-between gap-2">
            <div className="flex items-center gap-3">
              <Link href={`/dashboard/ordenes-trabajo/${ot.id}`} className="font-mono text-sm font-bold text-blue-600 hover:underline">{ot.folio}</Link>
              <Badge variant="default">{ot.tipo}</Badge>
              <Badge className={getEstadoOTColor(ot.estado)}>{getEstadoOTLabel(ot.estado)}</Badge>
              <Badge className={getPrioridadColor(ot.prioridad)}>{ot.prioridad}</Badge>
            </div>
            <div className="flex items-center gap-4 text-xs text-gray-500">
              <span>{ot.fecha_programada ? formatDate(ot.fecha_programada) : '—'}</span>
              <span className="font-semibold">{ot.costo_total ? formatCLP(ot.costo_total) : '—'}</span>
              <span>{ot.responsable?.nombre_completo ?? '—'}</span>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

function TabPlanes({ activoId }: { activoId: string }) {
  const { data: planes, isLoading } = usePlanesByActivo(activoId)
  if (isLoading) return <div className="flex justify-center py-12"><Spinner className="h-8 w-8" /></div>
  if (!planes || planes.length === 0) return <EmptyState icon={ClipboardList} title="Sin planes PM" description="Este activo no tiene planes PM activos." />

  return (
    <div className="space-y-2">
      {planes.map((plan: any) => (
        <Card key={plan.id}>
          <CardContent className="p-4">
            <p className="text-sm font-bold">{plan.nombre ?? plan.pauta?.nombre}</p>
            <div className="flex gap-4 text-xs text-gray-500 mt-1">
              <span>Ult: {plan.ultima_ejecucion_fecha ? formatDate(plan.ultima_ejecucion_fecha) : '—'}</span>
              <span>Prox: {plan.proxima_ejecucion_fecha ? formatDate(plan.proxima_ejecucion_fecha) : '—'}</span>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

function TabCostos({ activoId }: { activoId: string }) {
  const { data: movs, isLoading } = useCostosByActivo(activoId)
  const total = useMemo(() => !movs ? 0 : movs.reduce((s: number, m: any) => s + (m.costo_unitario ?? 0) * (m.cantidad ?? 0), 0), [movs])
  if (isLoading) return <div className="flex justify-center py-12"><Spinner className="h-8 w-8" /></div>
  if (!movs || movs.length === 0) return <EmptyState icon={DollarSign} title="Sin costos" description="Sin consumos registrados." />

  return (
    <div className="space-y-4">
      <Card><CardContent className="p-4 flex justify-between items-center">
        <div><p className="text-xs text-gray-500">Total invertido</p><p className="text-2xl font-bold">{formatCLP(total)}</p></div>
        <DollarSign className="h-8 w-8 text-green-600" />
      </CardContent></Card>
      {movs.map((m: any, i: number) => (
        <Card key={i}><CardContent className="p-3 flex justify-between text-sm">
          <span>{m.producto?.nombre ?? '—'}</span>
          <span className="font-semibold">{formatCLP((m.costo_unitario ?? 0) * (m.cantidad ?? 0))}</span>
        </CardContent></Card>
      ))}
    </div>
  )
}

function TabHistorial({ activoId }: { activoId: string }) {
  const { data: historial, isLoading } = useHistorialMantenimiento(activoId)
  if (isLoading) return <div className="flex justify-center py-12"><Spinner className="h-8 w-8" /></div>
  if (!historial || historial.length === 0) return <EmptyState icon={History} title="Sin historial" description="Sin intervenciones registradas." />

  return (
    <div className="space-y-2">
      {(historial as any[]).map((item: any, idx: number) => (
        <Card key={item.id ?? idx}>
          <CardContent className="p-4 flex flex-col md:flex-row md:items-center md:justify-between gap-2">
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500">{item.fecha_programada ? formatDate(item.fecha_programada) : '—'}</span>
              {item.folio && (
                <Link href={`/dashboard/ordenes-trabajo/${item.ot_id ?? item.id}`} className="font-mono text-sm font-bold text-blue-600 hover:underline">{item.folio}</Link>
              )}
              <Badge variant="default">{item.tipo}</Badge>
              <Badge className={getEstadoOTColor(item.estado)}>{getEstadoOTLabel(item.estado)}</Badge>
            </div>
            <div className="flex gap-3 text-xs text-gray-500">
              {item.costo_total > 0 && <span>{formatCLP(item.costo_total)}</span>}
              {item.responsable && <span>{item.responsable}</span>}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}
