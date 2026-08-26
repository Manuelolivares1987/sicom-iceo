'use client'

import { useState, useMemo, useRef, useEffect } from 'react'
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
  Loader2,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { HistorialMantenimiento } from '@/components/activos/historial-mantenimiento'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { Modal } from '@/components/ui/modal'
import { EquipoQrCard } from '@/components/qr/equipo-qr-card'
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
} from '@/hooks/use-activos'
import { useQueryClient } from '@tanstack/react-query'
import { useToast } from '@/contexts/toast-context'
import {
  TIPOS_DOC_OPCIONES,
  subirDocumentoCert,
  renovarCertificacion,
  adjuntarArchivoCertificacion,
} from '@/lib/services/taller-planificacion'
import {
  documentosVigentes,
  documentosReemplazados,
  estadoDocumento,
  diasParaVencer,
} from '@/domain/activos/documentos'
import { useOEEActivo } from '@/hooks/use-flota'
import { HistorialEstadosChart } from '@/components/flota/historial-estados-chart'
import { CambiarContratoModal } from '@/components/activos/cambiar-contrato-modal'
import { CarpetaCertificados } from '@/components/activos/carpeta-certificados'
import { HistoricoContratosCard } from '@/components/activos/historico-contratos-card'
import { useHistorialArriendos, useUltimoArriendo } from '@/hooks/use-arriendos'
import { Building2 } from 'lucide-react'
import { leerDocumento, type LecturaDocumento } from '@/lib/documentos/leer-documento'
import { getVigenciasEstandar, sumarMeses, mesesEntre } from '@/lib/services/control-documental'

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
  { key: 'qr', label: 'QR / Bitácora', icon: QrCode },
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
  const [showContratoModal, setShowContratoModal] = useState(false)
  const [contratoRefreshKey, setContratoRefreshKey] = useState(0)

  const { data: activo, isLoading, refetch: refetchActivo } = useActivo(id)
  const { data: certs } = useCertificacionesByActivo(id)
  const { data: ultimoArriendo } = useUltimoArriendo(id)
  const updateActivo = useUpdateActivo()

  // OEE del mes actual
  const today = new Date()
  const firstOfMonth = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-01`
  const todayStr = todayISO()
  const { data: oee } = useOEEActivo(id, firstOfMonth, todayStr)

  // Alertas de certificaciones. Solo la versión vigente de cada papel: si se
  // cuenta el histórico, el equipo queda marcado vencido aunque ya se renovó.
  const certsAlerta = useMemo(() => {
    const vigentes = documentosVigentes(certs as any[] | undefined)
    const vencidas = vigentes.filter((c: any) => estadoDocumento(c.fecha_vencimiento) === 'vencido')
    const porVencer = vigentes.filter((c: any) => estadoDocumento(c.fecha_vencimiento) === 'por_vencer')
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
            <div className="flex flex-wrap items-center gap-1.5 text-sm text-gray-600">
              <MapPin className="h-4 w-4 text-gray-400" />
              <span>Lugar físico:&nbsp;
                <strong>
                  {a.faena?.nombre || a.ubicacion_actual
                    ? [a.faena?.nombre, a.ubicacion_actual].filter(Boolean).join(' · ')
                    : <em className="text-gray-400">Sin registrar</em>}
                </strong>
              </span>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <Building2 className="h-4 w-4 text-gray-400" />
              <span className="text-sm text-gray-600">
                Contrato:&nbsp;
                <strong>
                  {a.contrato?.codigo
                    ? `${a.contrato.codigo} — ${a.contrato.cliente ?? ''}`
                    : (a.contrato_id ? '(cargando...)' : <em className="text-gray-400">Sin contrato</em>)}
                </strong>
              </span>
              <Button size="sm" variant="outline" onClick={() => setShowContratoModal(true)} className="gap-1">
                <Pencil className="h-3 w-3" /> Cambiar contrato
              </Button>
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

        {/* Último arriendo — visible al pasar a recepción / disponible */}
        {(a.estado_comercial === 'en_recepcion' || a.estado_comercial === 'disponible') && ultimoArriendo && (
          <div className="mt-4 rounded-lg border border-blue-200 bg-blue-50 p-3 flex items-start gap-2">
            <History className="h-5 w-5 mt-0.5 text-blue-600" />
            <div className="text-sm">
              <p className="font-semibold text-blue-800">Último arriendo</p>
              <p className="text-gray-700">
                <strong>{ultimoArriendo.cliente ?? 'Cliente s/d'}</strong>
                {ultimoArriendo.lugar && <> en <strong>{ultimoArriendo.lugar}</strong></>}
                {' · '}
                {formatDate(ultimoArriendo.fecha_inicio)}
                {ultimoArriendo.fecha_fin ? ` → ${formatDate(ultimoArriendo.fecha_fin)}` : ' → vigente'}
                {` · ${ultimoArriendo.dias} día(s)`}
              </p>
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
        {tab === 'certificaciones' && (
          <div className="space-y-6">
            {/* Carpeta del equipo: certificados emitidos por el sistema (MIG219) */}
            <CarpetaCertificados activoId={id} />
            <TabCertificaciones activoId={id} patente={a.patente} />
          </div>
        )}
        {tab === 'ots' && <TabOTs activoId={id} />}
        {tab === 'planes' && <TabPlanes activoId={id} />}
        {tab === 'costos' && <TabCostos activoId={id} />}
        {tab === 'historial' && <TabHistorial activoId={id} contratoRefreshKey={contratoRefreshKey} />}
        {tab === 'qr' && (
          <EquipoQrCard
            activoId={a.id}
            codigo={a.patente || a.codigo}
            nombre={a.nombre}
            qrPublicoHabilitado={a.qr_publico_habilitado ?? false}
            toggleLoading={updateActivo.isPending}
            onToggleHabilitado={(next) =>
              updateActivo.mutate(
                { id: a.id, updates: { qr_publico_habilitado: next } },
                { onSuccess: () => refetchActivo() },
              )
            }
          />
        )}
      </div>

      {/* Modal cambio de contrato */}
      <CambiarContratoModal
        abierto={showContratoModal}
        onClose={() => setShowContratoModal(false)}
        activoId={id}
        activoCodigo={a.patente || a.codigo}
        contratoActualId={a.contrato_id ?? null}
        contratoActualCodigo={a.contrato?.codigo ?? null}
        clienteActual={a.contrato?.cliente ?? a.cliente_actual ?? null}
        estadoComercial={a.estado_comercial ?? null}
        onCambioOk={() => {
          refetchActivo()
          setContratoRefreshKey((k) => k + 1)
        }}
      />
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
const EMPTY_DOC_FORM = {
  tipo: 'revision_tecnica',
  fecha_emision: '',
  fecha_vencimiento: '',
  entidad_certificadora: '',
  numero_certificado: '',
  bloqueante: true,
}

function TabCertificaciones({ activoId, patente }: { activoId: string; patente?: string | null }) {
  const { data: certs, isLoading } = useCertificacionesByActivo(activoId)
  const queryClient = useQueryClient()
  const toast = useToast()
  const [showAdd, setShowAdd] = useState(false)
  const [newCert, setNewCert] = useState({ ...EMPTY_DOC_FORM })
  const [newFile, setNewFile] = useState<File | null>(null)
  // [26-08] El sistema lee el papel al momento de subirlo: comprueba que sea un
  // archivo de verdad, que hable de ESTE equipo y de este tipo de certificado, y
  // saca la fecha de vencimiento. Los 468 papeles sin fecha de la flota entraron
  // porque nadie abría el PDF; revisarlo acá evita que vuelva a pasar.
  const [lectura, setLectura] = useState<LecturaDocumento | null>(null)
  // [MIG415] Cuánto dura cada tipo según sus propios certificados. La
  // hermeticidad son 6 meses, no un año: cargarla con un año fue lo que dejó a
  // doce camiones circulando con el papel vencido y el sistema en verde.
  const [vigencias, setVigencias] = useState<Record<string, { meses: number; fuente: string }>>({})
  useEffect(() => { getVigenciasEstandar().then(setVigencias).catch(() => {}) }, [])
  const estandar = vigencias[newCert.tipo] ?? null
  const [leyendo, setLeyendo] = useState(false)

  const revisarArchivo = async (f: File | null) => {
    setNewFile(f); setLectura(null)
    if (!f) return
    setLeyendo(true)
    try {
      const r = await leerDocumento(f, { patente, tipo: newCert.tipo })
      setLectura(r)
      // Si el documento dice su vigencia, se rellena sola: menos tipeo y menos
      // margen para inventar una fecha.
      if (r.vencimiento) {
        setNewCert((p) => ({
          ...p,
          fecha_vencimiento: r.vencimiento!,
          fecha_emision: p.fecha_emision || (r.emision ?? p.fecha_emision),
        }))
      }
    } catch { /* leer es una ayuda, no un requisito: nunca bloquea la carga */ }
    finally { setLeyendo(false) }
  }
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState('')
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [uploadingCertId, setUploadingCertId] = useState<string | null>(null)
  const [subiendo, setSubiendo] = useState(false)
  const [verHistorial, setVerHistorial] = useState(false)

  // [MIG273] Renovar no pisa la fila: crea una versión nueva. Solo la última de
  // cada tipo rige; las anteriores se muestran aparte y no marcan vencido.
  const vigentes = useMemo(() => documentosVigentes(certs as any[] | undefined), [certs])
  // [MIG407] Qué tipos vencen: si algún certificado de ese tipo en TODA la
  // ficha tiene fecha real, el tipo vence. Mismo criterio que la vista.
  const tiposQueVencen = useMemo(() => {
    const s = new Set<string>()
    for (const c of (certs as any[] | undefined) ?? []) {
      const f = c.fecha_vencimiento as string | null
      if (f && f < '2099-01-01') s.add(c.tipo)
    }
    return s
  }, [certs])
  const reemplazados = useMemo(() => documentosReemplazados(certs as any[] | undefined), [certs])

  const refrescar = () => {
    queryClient.invalidateQueries({ queryKey: ['certificaciones-activo', activoId] })
    queryClient.invalidateQueries({ queryKey: ['certificaciones'] })
    queryClient.invalidateQueries({ queryKey: ['activo', activoId] })
    queryClient.invalidateQueries({ queryKey: ['documentos-por-vencer'] })
  }

  // [MIG272] Alta y renovación pasan por el RPC: valida el rol, calcula el
  // estado y deja registrado quién cargó el papel. Antes fallaba en silencio.
  const handleAdd = async () => {
    setFormError('')
    if (!newCert.fecha_emision || !newCert.fecha_vencimiento) {
      setFormError('Indica la fecha de emisión y la de vencimiento.')
      return
    }
    if (newCert.fecha_vencimiento < newCert.fecha_emision) {
      setFormError('El vencimiento no puede ser anterior a la emisión.')
      return
    }
    setSaving(true)
    try {
      let archivoUrl: string | null = null
      if (newFile) archivoUrl = await subirDocumentoCert(activoId, newCert.tipo, newFile)

      await renovarCertificacion({
        activoId,
        tipo: newCert.tipo,
        fechaEmision: newCert.fecha_emision,
        fechaVencimiento: newCert.fecha_vencimiento,
        archivoUrl,
        numero: newCert.numero_certificado || null,
        entidad: newCert.entidad_certificadora || null,
        bloqueante: newCert.bloqueante,
      })

      refrescar()
      toast.success(`${getTipoCertificacionLabel(newCert.tipo)} actualizado — vence ${newCert.fecha_vencimiento}`)
      setShowAdd(false)
      setNewFile(null)
      setNewCert({ ...EMPTY_DOC_FORM })
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'No se pudo guardar el documento.'
      setFormError(msg)
      toast.error(msg)
    } finally {
      setSaving(false)
    }
  }

  // Renovar = cargar la versión nueva del mismo documento (queda el historial).
  const handleRenovar = (c: any) => {
    setNewCert({
      tipo: c.tipo,
      fecha_emision: todayISO(),
      fecha_vencimiento: '',
      entidad_certificadora: c.entidad_certificadora ?? '',
      numero_certificado: '',
      bloqueante: c.bloqueante ?? true,
    })
    setNewFile(null)
    setFormError('')
    setShowAdd(true)
  }

  const handleFileUpload = (certId: string) => {
    setUploadingCertId(certId)
    fileInputRef.current?.click()
  }

  const handleFileSelected = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    const certId = uploadingCertId
    e.target.value = ''
    setUploadingCertId(null)
    if (!file || !certId) return

    const cert = (certs as any[] | undefined)?.find((c) => c.id === certId)
    setSubiendo(true)
    try {
      const url = await subirDocumentoCert(activoId, cert?.tipo ?? 'otra', file)
      await adjuntarArchivoCertificacion(certId, url)
      refrescar()
      toast.success('Archivo adjuntado al documento.')
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'No se pudo subir el archivo.')
    } finally {
      setSubiendo(false)
    }
  }

  if (isLoading) return <div className="flex justify-center py-12"><Spinner className="h-8 w-8" /></div>

  return (
    <div className="space-y-4">
      <input type="file" ref={fileInputRef} className="hidden" accept=".pdf,.jpg,.jpeg,.png" onChange={handleFileSelected} />

      <div className="flex justify-between items-center">
        <h3 className="text-base font-semibold">Documentos y Certificaciones</h3>
        <Button size="sm" onClick={() => { setNewCert({ ...EMPTY_DOC_FORM }); setNewFile(null); setFormError(''); setShowAdd(!showAdd) }}>
          <Plus className="h-4 w-4 mr-1" /> Agregar
        </Button>
      </div>

      {/* Form para agregar / renovar */}
      {showAdd && (
        <Card className="border-blue-200 bg-blue-50">
          <CardContent className="p-4 space-y-3">
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
              <div>
                <label className="text-xs font-medium text-gray-600">Tipo</label>
                <select className="w-full rounded border px-2 py-1.5 text-sm mt-1"
                  value={newCert.tipo} onChange={(e) => {
                    const t = e.target.value
                    const m = vigencias[t]?.meses
                    // Al elegir el tipo se propone su vencimiento real. Si la
                    // persona ya escribió uno a mano, no se le pisa.
                    setNewCert((p) => ({ ...p, tipo: t,
                      fecha_vencimiento: m && p.fecha_emision && !p.fecha_vencimiento
                        ? sumarMeses(p.fecha_emision, m) : p.fecha_vencimiento }))
                  }}>
                  {TIPOS_DOC_OPCIONES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">Fecha Emision</label>
                <input type="date" className="w-full rounded border px-2 py-1.5 text-sm mt-1"
                  value={newCert.fecha_emision} onChange={(e) => {
                    const em = e.target.value
                    const m = vigencias[newCert.tipo]?.meses
                    setNewCert((p) => ({ ...p, fecha_emision: em,
                      fecha_vencimiento: m && em ? sumarMeses(em, m) : p.fecha_vencimiento }))
                  }} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">Fecha Vencimiento</label>
                <input type="date" className="w-full rounded border px-2 py-1.5 text-sm mt-1"
                  value={newCert.fecha_vencimiento} onChange={(e) => setNewCert({ ...newCert, fecha_vencimiento: e.target.value })} />
                {estandar && (() => {
                  const m = mesesEntre(newCert.fecha_emision, newCert.fecha_vencimiento)
                  if (m === null) return (
                    <p className="text-[11px] text-gray-500 mt-1">
                      Este documento dura {estandar.meses} meses.
                    </p>
                  )
                  if (m === estandar.meses) return (
                    <p className="text-[11px] text-green-700 mt-1">
                      Calza con los {estandar.meses} meses que dura este documento.
                    </p>
                  )
                  return (
                    <p className="text-[11px] text-amber-700 mt-1">
                      Estás poniendo {m} {m === 1 ? 'mes' : 'meses'}, y este documento dura{' '}
                      <strong>{estandar.meses}</strong>. Si el papel dice otra cosa, mándate;
                      si no, el vencimiento correcto es {sumarMeses(newCert.fecha_emision, estandar.meses)}.
                    </p>
                  )
                })()}
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
            {/* Archivo de respaldo (opcional) — se sube al guardar */}
            <div>
              <label className="text-xs font-medium text-gray-600">Archivo de respaldo (PDF o imagen)</label>
              <input
                type="file"
                accept=".pdf,.jpg,.jpeg,.png"
                className="mt-1 block w-full text-sm file:mr-3 file:rounded file:border-0 file:bg-blue-100 file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-blue-700 hover:file:bg-blue-200"
                onChange={(e) => void revisarArchivo(e.target.files?.[0] ?? null)}
              />
              {newFile && <p className="mt-1 text-[11px] text-gray-500">Se subirá: {newFile.name}</p>}
              {leyendo && (
                <p className="mt-2 flex items-center gap-1.5 text-[11px] text-gray-500">
                  <Loader2 className="h-3 w-3 animate-spin" /> Revisando el documento…
                </p>
              )}
              {lectura && lectura.avisos.length > 0 && (
                <div className="mt-2 space-y-1">
                  {lectura.avisos.map((a, i) => (
                    <div key={i} className={cn('rounded-lg border px-2.5 py-1.5 text-[11px]',
                      a.severidad === 'bloqueante' ? 'border-red-300 bg-red-50 text-red-800'
                      : a.severidad === 'grave' ? 'border-orange-300 bg-orange-50 text-orange-900'
                      : a.severidad === 'aviso' ? 'border-amber-200 bg-amber-50 text-amber-900'
                      : 'border-green-200 bg-green-50 text-green-800')}>
                      <b>{a.titulo}</b>
                      {a.detalle && <span className="block opacity-90">{a.detalle}</span>}
                    </div>
                  ))}
                </div>
              )}
            </div>
            {formError && (
              <p className="rounded border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700">{formError}</p>
            )}
            <div className="flex gap-2">
              <Button size="sm" onClick={handleAdd} disabled={saving || lectura?.puedeGuardar === false}>
                <Save className="h-4 w-4 mr-1" /> {saving ? 'Guardando…' : 'Guardar'}
              </Button>
              <Button size="sm" variant="outline" onClick={() => setShowAdd(false)} disabled={saving}>Cancelar</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Lista de documentos: primero los que rigen hoy, y aparte las versiones
          ya reemplazadas por una renovación (que NO deben marcar vencido). */}
      {vigentes.length === 0 ? (
        <EmptyState icon={ShieldCheck} title="Sin certificaciones" description="Agregue los documentos del equipo." />
      ) : (
        <div className="space-y-2">
          {vigentes
            .sort((a: any, b: any) => {
              // [MIG407] «sin_fecha» va casi arriba: es un papel cargado cuya
              // vigencia nadie anotó, y hasta que alguien lo abra no se sabe si
              // el equipo puede operar. Pesa más que uno por vencer.
              const order: Record<string, number> = {
                vencido: 0, sin_fecha: 1, por_vencer: 2, vigente: 3, permanente: 4,
              }
              const est = (d: any) => estadoDocumento(d.fecha_vencimiento, {
                tieneArchivo: !!d.archivo_url, tipoVence: tiposQueVencen.has(d.tipo),
              })
              return (order[est(a)] ?? 5) - (order[est(b)] ?? 5)
            })
            .map((c: any) => (
              <DocumentoCard
                key={c.id}
                c={c}
                tipoVence={tiposQueVencen.has(c.tipo)}
                subiendo={subiendo}
                onSubirArchivo={() => handleFileUpload(c.id)}
                onRenovar={() => handleRenovar(c)}
              />
            ))}
        </div>
      )}

      {reemplazados.length > 0 && (
        <div className="pt-2">
          <button
            type="button"
            onClick={() => setVerHistorial((v) => !v)}
            className="inline-flex items-center gap-1 text-xs font-medium text-gray-500 hover:text-gray-700"
          >
            {verHistorial ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
            Versiones anteriores ({reemplazados.length}) — ya renovadas, no cuentan como vencidas
          </button>
          {verHistorial && (
            <div className="mt-2 space-y-2 opacity-60">
              {reemplazados.map((c: any) => (
                <DocumentoCard key={c.id} c={c} reemplazado />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function DocumentoCard({ c, subiendo, reemplazado, tipoVence, onSubirArchivo, onRenovar }: {
  c: any
  /** [MIG407] Si el tipo de este papel vence, un 2099 es un hueco, no «permanente». */
  tipoVence?: boolean
  subiendo?: boolean
  reemplazado?: boolean
  onSubirArchivo?: () => void
  onRenovar?: () => void
}) {
  const estado = reemplazado ? 'reemplazado' : estadoDocumento(c.fecha_vencimiento, {
    tieneArchivo: !!c.archivo_url, tipoVence,
  })
  const dias = diasParaVencer(c.fecha_vencimiento)

  return (
    <Card className={cn(
      'border-l-4',
      estado === 'reemplazado' ? 'border-l-gray-300' :
      estado === 'vencido' ? 'border-l-red-500' :
      estado === 'por_vencer' ? 'border-l-amber-500' :
      estado === 'permanente' ? 'border-l-gray-400' :
      estado === 'sin_fecha' ? 'border-l-orange-500' :
      'border-l-green-500'
    )}>
      <CardContent className="p-4">
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-2">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <span className="text-sm font-bold text-gray-900">
                {getTipoCertificacionLabel(c.tipo)}
              </span>
              {estado === 'reemplazado' ? (
                <Badge className="bg-gray-100 text-gray-600">Reemplazado</Badge>
              ) : estado === 'permanente' ? (
                <Badge className="bg-gray-100 text-gray-600">Sin vencimiento</Badge>
              ) : estado === 'sin_fecha' ? (
                /* [MIG407] Hay papel cargado y su tipo vence, pero nadie anotó
                   hasta cuándo. Decirle «sin vencimiento» es justo lo que dejó
                   invisibles las láminas vencidas del TGGF-57 y el SVBJ-57. */
                <Badge className="bg-orange-100 text-orange-800"
                       title="El archivo está cargado pero nadie anotó hasta cuándo vale. Ábrelo y registra la fecha.">
                  Falta la fecha — revisar el archivo
                </Badge>
              ) : (
                <Badge className={getCertEstadoColor(estado)}>{getCertEstadoLabel(estado)}</Badge>
              )}
              {c.bloqueante && estado !== 'reemplazado' && (
                <span className="flex items-center gap-0.5 text-xs text-red-600">
                  <AlertTriangle className="h-3 w-3" /> Bloqueante
                </span>
              )}
            </div>
            <div className="flex flex-wrap gap-3 text-xs text-gray-500">
              {c.numero_certificado && <span>N: {c.numero_certificado}</span>}
              {c.entidad_certificadora && <span>Entidad: {c.entidad_certificadora}</span>}
              <span>Emision: {formatDate(c.fecha_emision)}</span>
              {estado !== 'permanente' && (
                <span className={cn(
                  'font-semibold',
                  estado === 'vencido' ? 'text-red-600' :
                  estado === 'por_vencer' ? 'text-amber-600' : ''
                )}>
                  Vence: {formatDate(c.fecha_vencimiento)}
                  {dias != null && (dias < 0 ? ` (vencido hace ${Math.abs(dias)} dias)` :
                                    dias <= 45 ? ` (${dias} dias)` : '')}
                </span>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2">
            {c.archivo_url && (
              <a href={c.archivo_url} target="_blank" rel="noopener noreferrer"
                className="inline-flex items-center gap-1 text-xs text-blue-600 hover:underline">
                <FileText className="h-3.5 w-3.5" /> Ver documento
              </a>
            )}
            {!reemplazado && (
              <>
                <Button variant="outline" size="sm" onClick={onSubirArchivo} disabled={subiendo}>
                  <Upload className="h-3.5 w-3.5 mr-1" />
                  {c.archivo_url ? 'Reemplazar archivo' : 'Subir archivo'}
                </Button>
                <Button size="sm" onClick={onRenovar}>
                  <RefreshCw className="h-3.5 w-3.5 mr-1" /> Renovar
                </Button>
              </>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Tabs reutilizados (simplificados)
// ---------------------------------------------------------------------------
// El historial de mantenimiento reemplaza la lista de folios (MIG310). La
// pregunta que le hacen a un equipo no es cuántas OT tuvo, es qué le hicieron.
// Debajo quedan las OT abiertas, que son trabajo pendiente, no historia.
function TabOTs({ activoId }: { activoId: string }) {
  const { data: ots } = useOTsByActivo(activoId)
  const abiertas = (ots ?? []).filter(
    (ot: any) => !['ejecutada_ok', 'ejecutada_con_observaciones', 'cerrada', 'anulada'].includes(ot.estado),
  )

  return (
    <div className="space-y-5">
      {abiertas.length > 0 && (
        <div>
          <h3 className="mb-2 text-sm font-semibold text-gray-900">
            En curso ({abiertas.length})
          </h3>
          <div className="space-y-2">
            {abiertas.map((ot: any) => (
              <Card key={ot.id}>
                <CardContent className="flex flex-col gap-2 p-4 md:flex-row md:items-center md:justify-between">
                  <div className="flex flex-wrap items-center gap-3">
                    <Link href={`/dashboard/ordenes-trabajo/${ot.id}`} className="font-mono text-sm font-bold text-blue-600 hover:underline">{ot.folio}</Link>
                    <Badge variant="default">{ot.tipo}</Badge>
                    <Badge className={getEstadoOTColor(ot.estado)}>{getEstadoOTLabel(ot.estado)}</Badge>
                    <Badge className={getPrioridadColor(ot.prioridad)}>{ot.prioridad}</Badge>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-gray-500">
                    <span>{ot.fecha_programada ? formatDate(ot.fecha_programada) : '—'}</span>
                    <span>{ot.responsable?.nombre_completo ?? 'sin responsable'}</span>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      <div>
        <h3 className="mb-2 text-sm font-semibold text-gray-900">Historial de mantenimiento</h3>
        <HistorialMantenimiento activoId={activoId} />
      </div>
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

function TabHistorial({ activoId, contratoRefreshKey }: { activoId: string; contratoRefreshKey?: number }) {
  // El historial de intervenciones lo trae HistorialMantenimiento en una sola
  // consulta (MIG310). Aquí sólo quedan los arriendos, que son otra historia.
  const { data: arriendos } = useHistorialArriendos(activoId)

  return (
    <div className="space-y-4">
      {/* Acceso a la bitácora unificada (línea de tiempo completa con detalle) */}
      <Link href={`/dashboard/flota/bitacora/${activoId}`}
        className="inline-flex items-center gap-2 rounded-lg border bg-blue-50 border-blue-200 px-3 py-2 text-sm text-blue-700 hover:bg-blue-100">
        <History className="h-4 w-4" /> Ver bitácora unificada (línea de tiempo completa)
      </Link>

      {/* Histórico de cambios de contrato (comercial) */}
      <HistoricoContratosCard activoId={activoId} refrescarKey={contratoRefreshKey} />

      {/* Historial de arriendos (cliente + lugar físico por período) */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Building2 className="h-4 w-4 text-blue-700" /> Historial de arriendos
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0 overflow-x-auto">
          {!arriendos || arriendos.length === 0 ? (
            <p className="p-4 text-sm text-muted-foreground">Sin arriendos registrados aún.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Cliente</TableHead>
                  <TableHead>Lugar físico</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Desde</TableHead>
                  <TableHead>Hasta</TableHead>
                  <TableHead className="text-right">Días</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {arriendos.map((r, i) => (
                  <TableRow key={i}>
                    <TableCell className="font-medium">{r.cliente ?? '—'}</TableCell>
                    <TableCell>{r.lugar ?? r.faena_nombre ?? '—'}</TableCell>
                    <TableCell><Badge variant="default">{r.tipo_uso}</Badge></TableCell>
                    <TableCell>{formatDate(r.fecha_inicio)}</TableCell>
                    <TableCell>{r.vigente ? <span className="text-green-600 font-medium">vigente</span> : formatDate(r.fecha_fin!)}</TableCell>
                    <TableCell className="text-right">{r.dias}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Gráfico histórico anual de estados (barras apiladas) */}
      <HistorialEstadosChart activoId={activoId} />

      {/* ── Historial de mantenimiento (MIG310) ──
          Antes esto eran tres bloques que contaban la misma historia en tres
          formatos: una tabla de OS antiguas, una lista de OTs y un link a la
          bitácora. Ahora es una sola línea de vida del equipo, con el detalle
          de lo que se hizo en cada intervención. */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Wrench className="h-4 w-4 text-blue-700" /> Historial de mantenimiento
          </CardTitle>
        </CardHeader>
        <CardContent>
          <HistorialMantenimiento activoId={activoId} />
        </CardContent>
      </Card>
    </div>
  )
}
