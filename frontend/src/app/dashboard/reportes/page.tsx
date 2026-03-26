'use client'

import { useState } from 'react'
import {
  ClipboardList,
  Package,
  ArrowLeftRight,
  Wrench,
  ShieldCheck,
  BarChart3,
  Gauge,
  Cog,
  Download,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { useToast } from '@/hooks/use-toast'
import { exportToCSV, exportToExcel } from '@/lib/export'
import { formatCLP, formatDate, formatPercent } from '@/lib/utils'
import { getOrdenesTrabajo } from '@/lib/services/ordenes-trabajo'
import { getStockBodega, getMovimientos } from '@/lib/services/inventario'
import { getPlanesMantenmiento } from '@/lib/services/mantenimiento'
import { getAllCertificaciones } from '@/lib/services/certificaciones'
import { getMedicionesKPI, getICEOHistorico } from '@/lib/services/kpi-iceo'
import { getActivos } from '@/lib/services/activos'
import type { LucideIcon } from 'lucide-react'

// ── Types ─────────────────────────────────────────────────────────────

interface ReportColumn {
  key: string
  label: string
}

interface ReportConfig {
  id: string
  title: string
  description: string
  icon: LucideIcon
  iconColor: string
  iconBg: string
  columns: ReportColumn[]
  fetchData: () => Promise<Record<string, any>[]>
  needsActivoSelect?: boolean
}

// ── Helper: flatten nested objects for export ─────────────────────────

function flattenOT(ot: any): Record<string, any> {
  return {
    folio: ot.folio,
    tipo: ot.tipo,
    estado: ot.estado,
    prioridad: ot.prioridad,
    activo: ot.activo?.nombre || ot.activo?.codigo || '',
    faena: ot.faena?.nombre || '',
    responsable: ot.responsable?.nombre_completo || '',
    fecha_programada: ot.fecha_programada ? formatDate(ot.fecha_programada) : '',
    costo_total: formatCLP(ot.costo_total || 0),
  }
}

function flattenStock(s: any): Record<string, any> {
  return {
    producto: s.producto?.nombre || '',
    codigo: s.producto?.codigo || '',
    categoria: s.producto?.categoria || '',
    bodega: s.bodega_id || '',
    cantidad: s.cantidad,
    unidad: s.producto?.unidad_medida || '',
    costo_promedio: formatCLP(s.costo_promedio || 0),
    valor_total: formatCLP(s.valor_total || 0),
  }
}

function flattenMovimiento(m: any): Record<string, any> {
  return {
    fecha: m.created_at ? formatDate(m.created_at) : '',
    tipo: m.tipo,
    producto: m.producto_id || '',
    cantidad: m.cantidad,
    costo_unitario: formatCLP(m.costo_unitario || 0),
    costo_total: formatCLP(m.costo_total || 0),
    ot: m.ot_id || '',
    bodega: m.bodega_id || '',
  }
}

function flattenPlan(p: any): Record<string, any> {
  return {
    activo: p.activo?.nombre || p.activo?.codigo || '',
    pauta: p.pauta?.nombre || '',
    tipo_plan: p.pauta?.tipo_plan || '',
    frecuencia: p.pauta?.frecuencia_dias ? `${p.pauta.frecuencia_dias} días` : p.pauta?.frecuencia_km ? `${p.pauta.frecuencia_km} km` : p.pauta?.frecuencia_horas ? `${p.pauta.frecuencia_horas} hrs` : '',
    ultima_ejecucion: p.ultima_ejecucion_fecha ? formatDate(p.ultima_ejecucion_fecha) : '',
    proxima_ejecucion: p.proxima_ejecucion_fecha ? formatDate(p.proxima_ejecucion_fecha) : '',
    estado: p.activo_plan ? 'Activo' : 'Inactivo',
  }
}

function flattenCertificacion(c: any): Record<string, any> {
  return {
    activo: c.activo?.nombre || c.activo?.codigo || '',
    tipo: c.tipo,
    numero: c.numero_certificado || '',
    entidad: c.entidad_certificadora || '',
    emision: c.fecha_emision ? formatDate(c.fecha_emision) : '',
    vencimiento: c.fecha_vencimiento ? formatDate(c.fecha_vencimiento) : '',
    estado: c.estado,
    bloqueante: c.bloqueante ? 'Sí' : 'No',
  }
}

function flattenMedicionKPI(m: any): Record<string, any> {
  return {
    codigo: m.kpi?.codigo || '',
    kpi: m.kpi?.nombre || '',
    area: m.kpi?.area || '',
    valor_medido: m.valor_medido,
    meta: m.kpi?.meta ?? '',
    cumplimiento: m.porcentaje_cumplimiento != null ? formatPercent(m.porcentaje_cumplimiento) : '',
    puntaje: m.puntaje,
    bloqueante: m.bloqueante_activado ? 'Sí' : 'No',
  }
}

function flattenICEO(i: any): Record<string, any> {
  return {
    periodo: i.periodo_inicio ? formatDate(i.periodo_inicio) : '',
    area_a: i.puntaje_area_a ?? '',
    area_b: i.puntaje_area_b ?? '',
    area_c: i.puntaje_area_c ?? '',
    iceo_bruto: i.iceo_bruto,
    iceo_final: i.iceo_final,
    clasificacion: i.clasificacion,
    incentivo: i.incentivo_habilitado ? 'Sí' : 'No',
  }
}

// ── Report definitions ────────────────────────────────────────────────

const reportConfigs: ReportConfig[] = [
  {
    id: 'ordenes-trabajo',
    title: 'Órdenes de Trabajo',
    description: 'OTs por estado, tipo, faena y período',
    icon: ClipboardList,
    iconColor: 'text-green-600',
    iconBg: 'bg-green-50',
    columns: [
      { key: 'folio', label: 'Folio' },
      { key: 'tipo', label: 'Tipo' },
      { key: 'estado', label: 'Estado' },
      { key: 'prioridad', label: 'Prioridad' },
      { key: 'activo', label: 'Activo' },
      { key: 'faena', label: 'Faena' },
      { key: 'responsable', label: 'Responsable' },
      { key: 'fecha_programada', label: 'Fecha Programada' },
      { key: 'costo_total', label: 'Costo Total' },
    ],
    fetchData: async () => {
      const { data, error } = await getOrdenesTrabajo()
      if (error || !data) throw new Error(error?.message || 'Error al obtener OTs')
      return data.map(flattenOT)
    },
  },
  {
    id: 'inventario-valorizado',
    title: 'Inventario Valorizado',
    description: 'Stock actual por bodega con valorización',
    icon: Package,
    iconColor: 'text-blue-600',
    iconBg: 'bg-blue-50',
    columns: [
      { key: 'producto', label: 'Producto' },
      { key: 'codigo', label: 'Código' },
      { key: 'categoria', label: 'Categoría' },
      { key: 'bodega', label: 'Bodega' },
      { key: 'cantidad', label: 'Cantidad' },
      { key: 'unidad', label: 'Unidad' },
      { key: 'costo_promedio', label: 'Costo Promedio' },
      { key: 'valor_total', label: 'Valor Total' },
    ],
    fetchData: async () => {
      const { data, error } = await getStockBodega()
      if (error || !data) throw new Error(error?.message || 'Error al obtener stock')
      return data.map(flattenStock)
    },
  },
  {
    id: 'movimientos-inventario',
    title: 'Movimientos de Inventario',
    description: 'Entradas, salidas, ajustes y transferencias',
    icon: ArrowLeftRight,
    iconColor: 'text-orange-600',
    iconBg: 'bg-orange-50',
    columns: [
      { key: 'fecha', label: 'Fecha' },
      { key: 'tipo', label: 'Tipo' },
      { key: 'producto', label: 'Producto' },
      { key: 'cantidad', label: 'Cantidad' },
      { key: 'costo_unitario', label: 'Costo Unitario' },
      { key: 'costo_total', label: 'Costo Total' },
      { key: 'ot', label: 'OT' },
      { key: 'bodega', label: 'Bodega' },
    ],
    fetchData: async () => {
      const { data, error } = await getMovimientos()
      if (error || !data) throw new Error(error?.message || 'Error al obtener movimientos')
      return data.map(flattenMovimiento)
    },
  },
  {
    id: 'cumplimiento-pm',
    title: 'Cumplimiento PM',
    description: 'Cumplimiento de mantenimiento preventivo por activo',
    icon: Wrench,
    iconColor: 'text-green-600',
    iconBg: 'bg-green-50',
    columns: [
      { key: 'activo', label: 'Activo' },
      { key: 'pauta', label: 'Pauta' },
      { key: 'tipo_plan', label: 'Tipo Plan' },
      { key: 'frecuencia', label: 'Frecuencia' },
      { key: 'ultima_ejecucion', label: 'Última Ejecución' },
      { key: 'proxima_ejecucion', label: 'Próxima Ejecución' },
      { key: 'estado', label: 'Estado' },
    ],
    fetchData: async () => {
      const { data, error } = await getPlanesMantenmiento()
      if (error || !data) throw new Error(error?.message || 'Error al obtener planes')
      return data.map(flattenPlan)
    },
  },
  {
    id: 'certificaciones',
    title: 'Certificaciones',
    description: 'Estado de certificaciones y vencimientos',
    icon: ShieldCheck,
    iconColor: 'text-yellow-600',
    iconBg: 'bg-yellow-50',
    columns: [
      { key: 'activo', label: 'Activo' },
      { key: 'tipo', label: 'Tipo' },
      { key: 'numero', label: 'Número' },
      { key: 'entidad', label: 'Entidad' },
      { key: 'emision', label: 'Emisión' },
      { key: 'vencimiento', label: 'Vencimiento' },
      { key: 'estado', label: 'Estado' },
      { key: 'bloqueante', label: 'Bloqueante' },
    ],
    fetchData: async () => {
      const { data, error } = await getAllCertificaciones()
      if (error || !data) throw new Error(error?.message || 'Error al obtener certificaciones')
      return data.map(flattenCertificacion)
    },
  },
  {
    id: 'kpi-mensual',
    title: 'KPI Mensual',
    description: 'Mediciones KPI del período actual',
    icon: BarChart3,
    iconColor: 'text-purple-600',
    iconBg: 'bg-purple-50',
    columns: [
      { key: 'codigo', label: 'Código' },
      { key: 'kpi', label: 'KPI' },
      { key: 'area', label: 'Área' },
      { key: 'valor_medido', label: 'Valor Medido' },
      { key: 'meta', label: 'Meta' },
      { key: 'cumplimiento', label: '% Cumplimiento' },
      { key: 'puntaje', label: 'Puntaje' },
      { key: 'bloqueante', label: 'Bloqueante' },
    ],
    fetchData: async () => {
      const { data, error } = await getMedicionesKPI('')
      if (error || !data) throw new Error(error?.message || 'Error al obtener KPIs')
      return data.map(flattenMedicionKPI)
    },
  },
  {
    id: 'iceo',
    title: 'ICEO',
    description: 'Índice Compuesto de Excelencia Operacional',
    icon: Gauge,
    iconColor: 'text-purple-600',
    iconBg: 'bg-purple-50',
    columns: [
      { key: 'periodo', label: 'Período' },
      { key: 'area_a', label: 'Área A' },
      { key: 'area_b', label: 'Área B' },
      { key: 'area_c', label: 'Área C' },
      { key: 'iceo_bruto', label: 'ICEO Bruto' },
      { key: 'iceo_final', label: 'ICEO Final' },
      { key: 'clasificacion', label: 'Clasificación' },
      { key: 'incentivo', label: 'Incentivo' },
    ],
    fetchData: async () => {
      const { data, error } = await getICEOHistorico('')
      if (error || !data) throw new Error(error?.message || 'Error al obtener ICEO')
      return data.map(flattenICEO)
    },
  },
]

// ── Components ────────────────────────────────────────────────────────

function ReportCard({ config }: { config: ReportConfig }) {
  const [loadingCSV, setLoadingCSV] = useState(false)
  const [loadingExcel, setLoadingExcel] = useState(false)
  const toast = useToast()
  const Icon = config.icon

  const handleExport = async (format: 'csv' | 'excel') => {
    const setLoading = format === 'csv' ? setLoadingCSV : setLoadingExcel
    setLoading(true)
    try {
      const rows = await config.fetchData()
      if (rows.length === 0) {
        toast.warning('No hay datos para exportar')
        return
      }
      const timestamp = new Date().toISOString().slice(0, 10)
      const filename = `${config.id}_${timestamp}`
      if (format === 'csv') {
        exportToCSV(rows, filename, config.columns)
      } else {
        exportToExcel(rows, filename, config.columns)
      }
      toast.success(`Reporte "${config.title}" exportado correctamente`)
    } catch (err: any) {
      toast.error(err.message || 'Error al exportar')
    } finally {
      setLoading(false)
    }
  }

  return (
    <Card className="flex flex-col">
      <CardContent className="flex flex-col flex-1 pt-6 pb-4">
        <div className="flex items-start gap-3 mb-3">
          <div className={`w-10 h-10 rounded-lg ${config.iconBg} flex items-center justify-center flex-shrink-0`}>
            <Icon className={`w-5 h-5 ${config.iconColor}`} />
          </div>
          <div className="min-w-0">
            <h3 className="font-semibold text-gray-900 text-sm leading-tight">{config.title}</h3>
            <p className="text-xs text-gray-500 mt-0.5">{config.description}</p>
          </div>
        </div>
        <div className="flex items-center gap-2 mt-auto pt-3 border-t border-gray-100">
          <Button
            variant="outline"
            size="sm"
            onClick={() => handleExport('csv')}
            loading={loadingCSV}
            disabled={loadingExcel}
            className="flex-1 text-xs"
          >
            <Download className="w-3.5 h-3.5" />
            CSV
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => handleExport('excel')}
            loading={loadingExcel}
            disabled={loadingCSV}
            className="flex-1 text-xs"
          >
            <Download className="w-3.5 h-3.5" />
            Excel
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

function HistorialActivoCard() {
  const [activos, setActivos] = useState<any[]>([])
  const [selectedActivo, setSelectedActivo] = useState('')
  const [loadingActivos, setLoadingActivos] = useState(false)
  const [loadingCSV, setLoadingCSV] = useState(false)
  const [loadingExcel, setLoadingExcel] = useState(false)
  const toast = useToast()

  const columns: ReportColumn[] = [
    { key: 'folio', label: 'Folio' },
    { key: 'tipo', label: 'Tipo' },
    { key: 'estado', label: 'Estado' },
    { key: 'prioridad', label: 'Prioridad' },
    { key: 'responsable', label: 'Responsable' },
    { key: 'fecha_programada', label: 'Fecha Programada' },
    { key: 'costo_total', label: 'Costo Total' },
  ]

  const loadActivos = async () => {
    if (activos.length > 0) return
    setLoadingActivos(true)
    try {
      const { data } = await getActivos()
      setActivos(data || [])
    } finally {
      setLoadingActivos(false)
    }
  }

  const handleExport = async (format: 'csv' | 'excel') => {
    if (!selectedActivo) {
      toast.warning('Seleccione un activo primero')
      return
    }
    const setLoading = format === 'csv' ? setLoadingCSV : setLoadingExcel
    setLoading(true)
    try {
      const { data, error } = await getOrdenesTrabajo()
      if (error || !data) throw new Error(error?.message || 'Error al obtener OTs')
      const filtered = data.filter((ot: any) => ot.activo_id === selectedActivo)
      if (filtered.length === 0) {
        toast.warning('No hay OTs para este activo')
        return
      }
      const rows = filtered.map(flattenOT)
      const activo = activos.find((a) => a.id === selectedActivo)
      const activoCodigo = activo?.codigo || 'activo'
      const timestamp = new Date().toISOString().slice(0, 10)
      const filename = `historial_${activoCodigo}_${timestamp}`
      if (format === 'csv') {
        exportToCSV(rows, filename, columns)
      } else {
        exportToExcel(rows, filename, columns)
      }
      toast.success(`Historial de "${activo?.nombre || activoCodigo}" exportado`)
    } catch (err: any) {
      toast.error(err.message || 'Error al exportar')
    } finally {
      setLoading(false)
    }
  }

  return (
    <Card className="flex flex-col">
      <CardContent className="flex flex-col flex-1 pt-6 pb-4">
        <div className="flex items-start gap-3 mb-3">
          <div className="w-10 h-10 rounded-lg bg-gray-50 flex items-center justify-center flex-shrink-0">
            <Cog className="w-5 h-5 text-gray-600" />
          </div>
          <div className="min-w-0">
            <h3 className="font-semibold text-gray-900 text-sm leading-tight">Historial por Activo</h3>
            <p className="text-xs text-gray-500 mt-0.5">Historial completo de intervenciones por activo</p>
          </div>
        </div>
        <div className="mb-3">
          <Select
            placeholder="Seleccionar activo..."
            value={selectedActivo}
            onChange={(e) => setSelectedActivo(e.target.value)}
            onFocus={loadActivos}
            options={
              loadingActivos
                ? [{ value: '', label: 'Cargando...', disabled: true }]
                : activos.map((a) => ({
                    value: a.id,
                    label: `${a.codigo} - ${a.nombre || a.tipo}`,
                  }))
            }
          />
        </div>
        <div className="flex items-center gap-2 mt-auto pt-3 border-t border-gray-100">
          <Button
            variant="outline"
            size="sm"
            onClick={() => handleExport('csv')}
            loading={loadingCSV}
            disabled={loadingExcel || !selectedActivo}
            className="flex-1 text-xs"
          >
            <Download className="w-3.5 h-3.5" />
            CSV
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => handleExport('excel')}
            loading={loadingExcel}
            disabled={loadingCSV || !selectedActivo}
            className="flex-1 text-xs"
          >
            <Download className="w-3.5 h-3.5" />
            Excel
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

// ── Page ──────────────────────────────────────────────────────────────

export default function ReportesPage() {
  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Reportes</h1>
        <p className="text-gray-500 mt-1">Generación y exportación de reportes operacionales</p>
      </div>

      {/* Report cards grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        {reportConfigs.map((config) => (
          <ReportCard key={config.id} config={config} />
        ))}
        <HistorialActivoCard />
      </div>
    </div>
  )
}
