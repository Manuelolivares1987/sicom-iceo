'use client'

import { useState } from 'react'
import { Eye, Search, Filter, ChevronDown, ChevronRight } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { Input } from '@/components/ui/input'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatDateTime } from '@/lib/utils'
import { useAuditoria } from '@/hooks/use-auditoria'

// ---------------------------------------------------------------------------
// Filter options
// ---------------------------------------------------------------------------
const tablaOptions = [
  { value: '', label: 'Todas las tablas' },
  { value: 'ordenes_trabajo', label: 'Ordenes de Trabajo' },
  { value: 'movimientos_inventario', label: 'Movimientos Inventario' },
  { value: 'activos', label: 'Activos' },
  { value: 'stock_bodega', label: 'Stock Bodega' },
  { value: 'certificaciones', label: 'Certificaciones' },
  { value: 'incidentes', label: 'Incidentes' },
]

const accionOptions = [
  { value: '', label: 'Todas las acciones' },
  { value: 'INSERT', label: 'INSERT' },
  { value: 'UPDATE', label: 'UPDATE' },
  { value: 'DELETE', label: 'DELETE' },
]

// ---------------------------------------------------------------------------
// Select helper
// ---------------------------------------------------------------------------
function Select({
  label,
  value,
  onChange,
  options,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  options: { value: string; label: string }[]
}) {
  return (
    <div className="w-full sm:w-auto">
      <label className="mb-1 block text-xs font-medium text-gray-500">{label}</label>
      <div className="relative">
        <select
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="h-10 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20 sm:w-48"
        >
          {options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
        <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Accion badge
// ---------------------------------------------------------------------------
function getAccionBadge(accion: string) {
  const config: Record<string, { className: string; label: string }> = {
    INSERT: { className: 'bg-green-100 text-green-700', label: 'INSERT' },
    UPDATE: { className: 'bg-blue-100 text-blue-700', label: 'UPDATE' },
    DELETE: { className: 'bg-red-100 text-red-700', label: 'DELETE' },
  }
  const c = config[accion] || { className: 'bg-gray-100 text-gray-700', label: accion }
  return <Badge className={c.className}>{c.label}</Badge>
}

// ---------------------------------------------------------------------------
// Cambios summary
// ---------------------------------------------------------------------------
function getCambiosSummary(evento: any) {
  const accion = evento.accion || evento.action
  if (accion === 'INSERT') return 'Nuevo registro'
  if (accion === 'DELETE') return 'Registro eliminado'

  // UPDATE: try to show field diffs
  const oldData = evento.datos_anteriores || evento.old_data
  const newData = evento.datos_nuevos || evento.new_data

  if (!oldData || !newData) return 'Datos actualizados'

  const changes: string[] = []
  const keys = Array.from(new Set([...Object.keys(oldData), ...Object.keys(newData)]))
  for (const key of keys) {
    if (key === 'updated_at' || key === 'created_at') continue
    const oldVal = oldData[key]
    const newVal = newData[key]
    if (JSON.stringify(oldVal) !== JSON.stringify(newVal)) {
      const displayOld = oldVal === null ? 'null' : String(oldVal)
      const displayNew = newVal === null ? 'null' : String(newVal)
      changes.push(`${key}: ${displayOld.substring(0, 20)} → ${displayNew.substring(0, 20)}`)
    }
    if (changes.length >= 3) break
  }

  return changes.length > 0 ? changes.join(', ') : 'Sin cambios detectados'
}

// ---------------------------------------------------------------------------
// Expandable row
// ---------------------------------------------------------------------------
function CambiosDetail({ evento }: { evento: any }) {
  const accion = evento.accion || evento.action
  if (accion === 'INSERT') {
    const data = evento.datos_nuevos || evento.new_data
    return (
      <pre className="max-h-48 overflow-auto rounded-md bg-gray-50 p-3 text-xs text-gray-700">
        {data ? JSON.stringify(data, null, 2) : 'Sin datos'}
      </pre>
    )
  }
  if (accion === 'DELETE') {
    const data = evento.datos_anteriores || evento.old_data
    return (
      <pre className="max-h-48 overflow-auto rounded-md bg-gray-50 p-3 text-xs text-gray-700">
        {data ? JSON.stringify(data, null, 2) : 'Sin datos'}
      </pre>
    )
  }

  // UPDATE diff
  const oldData = evento.datos_anteriores || evento.old_data || {}
  const newData = evento.datos_nuevos || evento.new_data || {}
  const allKeys = Array.from(new Set([...Object.keys(oldData), ...Object.keys(newData)]))
  const diffs: { key: string; old: any; new: any }[] = []

  for (const key of allKeys) {
    if (JSON.stringify(oldData[key]) !== JSON.stringify(newData[key])) {
      diffs.push({ key, old: oldData[key], new: newData[key] })
    }
  }

  if (diffs.length === 0) return <p className="text-xs text-gray-400">Sin cambios detectados</p>

  return (
    <div className="space-y-1">
      {diffs.map((d) => (
        <div key={d.key} className="flex items-start gap-2 rounded-md bg-gray-50 px-3 py-1.5 text-xs">
          <span className="font-medium text-gray-700">{d.key}:</span>
          <span className="text-red-500 line-through">{d.old === null ? 'null' : String(d.old).substring(0, 50)}</span>
          <span className="text-gray-400">→</span>
          <span className="text-green-600">{d.new === null ? 'null' : String(d.new).substring(0, 50)}</span>
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Mobile card
// ---------------------------------------------------------------------------
function EventoMobileCard({ evento, expanded, onToggle }: { evento: any; expanded: boolean; onToggle: () => void }) {
  const accion = evento.accion || evento.action
  const registroId = evento.registro_id || ''
  const truncatedId = registroId.length > 8 ? `${registroId.substring(0, 8)}...` : registroId

  return (
    <Card className="mb-3">
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-xs text-gray-500">
              {evento.created_at ? formatDateTime(evento.created_at) : '—'}
            </p>
            <p className="text-sm font-bold text-gray-900 mt-0.5">{evento.tabla}</p>
          </div>
          {getAccionBadge(accion)}
        </div>
        <div className="mt-2 grid grid-cols-2 gap-y-1 text-xs text-gray-600">
          <span>ID: {truncatedId}</span>
          <span>Usuario: {evento.usuario_id?.substring(0, 8) || '—'}...</span>
        </div>
        <button
          onClick={onToggle}
          className="mt-2 flex items-center gap-1 text-xs font-medium text-pillado-green-600 hover:underline"
        >
          {expanded ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
          {expanded ? 'Ocultar cambios' : 'Ver cambios'}
        </button>
        {expanded && (
          <div className="mt-2">
            <CambiosDetail evento={evento} />
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function AuditoriaPage() {
  const [tablaFilter, setTablaFilter] = useState('')
  const [accionFilter, setAccionFilter] = useState('')
  const [fechaDesde, setFechaDesde] = useState('')
  const [fechaHasta, setFechaHasta] = useState('')
  const [searchId, setSearchId] = useState('')
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set())

  // Build filters
  const filters: Record<string, string> = {}
  if (tablaFilter) filters.tabla = tablaFilter
  if (accionFilter) filters.accion = accionFilter
  if (fechaDesde) filters.fecha_desde = fechaDesde
  if (fechaHasta) filters.fecha_hasta = fechaHasta
  if (searchId) filters.registro_id = searchId

  const { data: eventos, isLoading, error } = useAuditoria(
    Object.keys(filters).length > 0 ? filters : undefined
  )

  // Limit to 50 rows
  const displayed = (eventos ?? []).slice(0, 50)

  function toggleRow(id: string) {
    setExpandedRows((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Auditoria del Sistema</h1>
        <p className="mt-1 text-sm text-gray-500">
          Registro completo de acciones operacionales
        </p>
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
            <Select
              label="Tabla"
              value={tablaFilter}
              onChange={setTablaFilter}
              options={tablaOptions}
            />
            <Select
              label="Accion"
              value={accionFilter}
              onChange={setAccionFilter}
              options={accionOptions}
            />
            <div className="w-full sm:w-auto">
              <Input
                label="Fecha desde"
                type="date"
                value={fechaDesde}
                onChange={(e) => setFechaDesde(e.target.value)}
              />
            </div>
            <div className="w-full sm:w-auto">
              <Input
                label="Fecha hasta"
                type="date"
                value={fechaHasta}
                onChange={(e) => setFechaHasta(e.target.value)}
              />
            </div>
            <div className="w-full sm:w-auto sm:min-w-[200px]">
              <Input
                label="Buscar por Registro ID"
                placeholder="UUID del registro..."
                value={searchId}
                onChange={(e) => setSearchId(e.target.value)}
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Loading */}
      {isLoading && (
        <div className="flex items-center justify-center py-12">
          <Spinner size="lg" className="text-pillado-green-500" />
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-center text-sm text-red-700">
          Error al cargar eventos de auditoria. Intente nuevamente.
        </div>
      )}

      {/* Content */}
      {!isLoading && !error && (
        <>
          {displayed.length === 0 ? (
            <Card>
              <EmptyState
                icon={Eye}
                title="Sin eventos de auditoria"
                description="No se encontraron eventos con los filtros seleccionados."
              />
            </Card>
          ) : (
            <>
              <p className="text-xs text-gray-400">
                Mostrando ultimos {displayed.length} eventos
              </p>

              {/* Desktop table */}
              <Card className="hidden md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Fecha/Hora</TableHead>
                      <TableHead>Tabla</TableHead>
                      <TableHead>Accion</TableHead>
                      <TableHead>Registro ID</TableHead>
                      <TableHead>Usuario</TableHead>
                      <TableHead>Cambios</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {displayed.map((evento: any) => {
                      const registroId = evento.registro_id || ''
                      const truncatedId = registroId.length > 8
                        ? `${registroId.substring(0, 8)}...`
                        : registroId
                      const accion = evento.accion || evento.action
                      const isExpanded = expandedRows.has(evento.id)

                      return (
                        <>
                          <TableRow key={evento.id}>
                            <TableCell className="text-xs whitespace-nowrap">
                              {evento.created_at ? formatDateTime(evento.created_at) : '—'}
                            </TableCell>
                            <TableCell>
                              <span className="rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700">
                                {evento.tabla}
                              </span>
                            </TableCell>
                            <TableCell>{getAccionBadge(accion)}</TableCell>
                            <TableCell className="font-mono text-xs text-gray-500" title={registroId}>
                              {truncatedId}
                            </TableCell>
                            <TableCell className="text-xs">
                              {evento.usuario_id ? `${evento.usuario_id.substring(0, 8)}...` : '—'}
                            </TableCell>
                            <TableCell>
                              <button
                                onClick={() => toggleRow(evento.id)}
                                className="flex items-center gap-1 text-xs text-gray-600 hover:text-pillado-green-600"
                              >
                                {isExpanded ? (
                                  <ChevronDown className="h-3 w-3" />
                                ) : (
                                  <ChevronRight className="h-3 w-3" />
                                )}
                                <span className="max-w-[200px] truncate">
                                  {getCambiosSummary(evento)}
                                </span>
                              </button>
                            </TableCell>
                          </TableRow>
                          {isExpanded && (
                            <TableRow key={`${evento.id}-detail`}>
                              <TableCell colSpan={6} className="bg-gray-50/50 p-4">
                                <CambiosDetail evento={evento} />
                              </TableCell>
                            </TableRow>
                          )}
                        </>
                      )
                    })}
                  </TableBody>
                </Table>
              </Card>

              {/* Mobile cards */}
              <div className="md:hidden">
                {displayed.map((evento: any) => (
                  <EventoMobileCard
                    key={evento.id}
                    evento={evento}
                    expanded={expandedRows.has(evento.id)}
                    onToggle={() => toggleRow(evento.id)}
                  />
                ))}
              </div>
            </>
          )}
        </>
      )}
    </div>
  )
}
