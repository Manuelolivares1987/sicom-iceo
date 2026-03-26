'use client'

import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import Link from 'next/link'
import {
  Settings,
  Users,
  Database,
  BarChart3,
  Shield,
  Package,
  FileText,
  MapPin,
  Wrench,
  ClipboardList,
  ChevronRight,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { StatCard } from '@/components/ui/stat-card'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { getUsuarios, getSystemStats } from '@/lib/services/admin'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/hooks/use-toast'
import { EditarUsuarioModal } from '@/components/admin/editar-usuario-modal'
import type { RolUsuario } from '@/types/database'

// --- Hooks ---

function useUsuarios() {
  return useQuery({
    queryKey: ['admin', 'usuarios'],
    queryFn: async () => {
      const { data, error } = await getUsuarios()
      if (error) throw error
      return data
    },
  })
}

function useSystemStats() {
  return useQuery({
    queryKey: ['admin', 'system-stats'],
    queryFn: async () => {
      const { data, error } = await getSystemStats()
      if (error) throw error
      return data
    },
  })
}

// --- Helpers ---

const rolBadgeColors: Record<RolUsuario, string> = {
  administrador: 'bg-purple-100 text-purple-700',
  gerencia: 'bg-blue-100 text-blue-700',
  subgerente_operaciones: 'bg-blue-100 text-blue-700',
  supervisor: 'bg-green-100 text-green-700',
  planificador: 'bg-cyan-100 text-cyan-700',
  tecnico_mantenimiento: 'bg-orange-100 text-orange-700',
  bodeguero: 'bg-yellow-100 text-yellow-700',
  operador_abastecimiento: 'bg-amber-100 text-amber-700',
  auditor: 'bg-gray-100 text-gray-700',
  rrhh_incentivos: 'bg-pink-100 text-pink-700',
}

const rolLabels: Record<RolUsuario, string> = {
  administrador: 'Administrador',
  gerencia: 'Gerencia',
  subgerente_operaciones: 'Subgerente Ops',
  supervisor: 'Supervisor',
  planificador: 'Planificador',
  tecnico_mantenimiento: 'Tecnico',
  bodeguero: 'Bodeguero',
  operador_abastecimiento: 'Operador Abast.',
  auditor: 'Auditor',
  rrhh_incentivos: 'RRHH Incentivos',
}

const tabs = [
  { id: 'general', label: 'Vista General', icon: BarChart3 },
  { id: 'usuarios', label: 'Usuarios', icon: Users },
  { id: 'parametros', label: 'Parametros', icon: Settings },
] as const

type TabId = (typeof tabs)[number]['id']

// --- Tab Components ---

function VistaGeneralTab() {
  const { data: stats, isLoading } = useSystemStats()

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Spinner size="lg" />
      </div>
    )
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <StatCard
        title="Contratos"
        value={stats?.contratos ?? 0}
        icon={FileText}
        color="blue"
      />
      <StatCard
        title="Faenas"
        value={stats?.faenas ?? 0}
        icon={MapPin}
        color="green"
      />
      <StatCard
        title="Activos"
        value={stats?.activos ?? 0}
        icon={Wrench}
        color="orange"
      />
      <StatCard
        title="Ordenes de Trabajo"
        value={stats?.ordenes_trabajo ?? 0}
        icon={ClipboardList}
        color="blue"
      />
      <StatCard
        title="Productos"
        value={stats?.productos ?? 0}
        icon={Package}
        color="green"
      />
      <StatCard
        title="Usuarios"
        value={stats?.usuarios ?? 0}
        icon={Users}
        color="orange"
      />
    </div>
  )
}

function UsuariosTab({ onEditUsuario }: { onEditUsuario: (usuario: any) => void }) {
  const { data: usuarios, isLoading } = useUsuarios()

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Spinner size="lg" />
      </div>
    )
  }

  if (!usuarios || usuarios.length === 0) {
    return (
      <Card>
        <CardContent className="py-12 text-center">
          <Users className="h-10 w-10 text-gray-300 mx-auto mb-3" />
          <p className="text-gray-500">No hay usuarios registrados.</p>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle>Usuarios del Sistema</CardTitle>
          <span className="text-sm text-gray-500">
            {usuarios.length} usuario{usuarios.length !== 1 ? 's' : ''}
          </span>
        </div>
      </CardHeader>
      <CardContent>
        <Table striped>
          <TableHeader>
            <TableRow>
              <TableHead>Nombre Completo</TableHead>
              <TableHead>Email</TableHead>
              <TableHead className="hidden md:table-cell">RUT</TableHead>
              <TableHead className="hidden lg:table-cell">Cargo</TableHead>
              <TableHead>Rol</TableHead>
              <TableHead className="hidden md:table-cell">Faena</TableHead>
              <TableHead>Activo</TableHead>
              <TableHead className="text-right">Acciones</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {usuarios.map((usuario: any) => (
              <TableRow key={usuario.id}>
                <TableCell className="font-medium">
                  {usuario.nombre_completo}
                </TableCell>
                <TableCell className="text-gray-500 text-sm">
                  {usuario.email}
                </TableCell>
                <TableCell className="hidden md:table-cell text-sm text-gray-500">
                  {usuario.rut || '-'}
                </TableCell>
                <TableCell className="hidden lg:table-cell text-sm text-gray-500">
                  {usuario.cargo || '-'}
                </TableCell>
                <TableCell>
                  <span
                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                      rolBadgeColors[usuario.rol as RolUsuario] ||
                      'bg-gray-100 text-gray-700'
                    }`}
                  >
                    {rolLabels[usuario.rol as RolUsuario] || usuario.rol}
                  </span>
                </TableCell>
                <TableCell className="hidden md:table-cell text-sm text-gray-500">
                  {usuario.faena?.nombre || '-'}
                </TableCell>
                <TableCell>
                  <span className="flex items-center gap-1.5">
                    <span
                      className={`h-2.5 w-2.5 rounded-full ${
                        usuario.activo ? 'bg-green-500' : 'bg-red-500'
                      }`}
                    />
                    <span className="text-sm text-gray-500">
                      {usuario.activo ? 'Si' : 'No'}
                    </span>
                  </span>
                </TableCell>
                <TableCell className="text-right">
                  <Button variant="ghost" size="sm" onClick={() => onEditUsuario(usuario)}>
                    Editar
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}

function ParametrosTab() {
  return (
    <div className="space-y-6">
      {/* ICEO Configuration */}
      <Card>
        <CardHeader>
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-purple-50">
              <Shield className="h-5 w-5 text-purple-500" />
            </div>
            <div>
              <CardTitle>Configuracion ICEO</CardTitle>
              <p className="text-sm text-gray-500 mt-0.5">
                Pesos y umbrales del indice de cumplimiento
              </p>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div className="rounded-lg border border-gray-100 p-4">
              <p className="text-xs font-medium text-gray-500 uppercase tracking-wider">
                Peso Area A
              </p>
              <p className="text-lg font-bold text-gray-900 mt-1">
                Administracion Combustibles
              </p>
              <p className="text-sm text-gray-500">Configurable por contrato</p>
            </div>
            <div className="rounded-lg border border-gray-100 p-4">
              <p className="text-xs font-medium text-gray-500 uppercase tracking-wider">
                Peso Area B
              </p>
              <p className="text-lg font-bold text-gray-900 mt-1">
                Mantenimiento Fijos
              </p>
              <p className="text-sm text-gray-500">Configurable por contrato</p>
            </div>
            <div className="rounded-lg border border-gray-100 p-4">
              <p className="text-xs font-medium text-gray-500 uppercase tracking-wider">
                Peso Area C
              </p>
              <p className="text-lg font-bold text-gray-900 mt-1">
                Mantenimiento Moviles
              </p>
              <p className="text-sm text-gray-500">Configurable por contrato</p>
            </div>
          </div>
          <div className="mt-4 grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div className="rounded-lg bg-red-50 p-3 text-center">
              <p className="text-xs text-red-600 font-medium">Deficiente</p>
              <p className="text-sm font-bold text-red-700">&lt; 70%</p>
            </div>
            <div className="rounded-lg bg-yellow-50 p-3 text-center">
              <p className="text-xs text-yellow-600 font-medium">Aceptable</p>
              <p className="text-sm font-bold text-yellow-700">70% - 84%</p>
            </div>
            <div className="rounded-lg bg-green-50 p-3 text-center">
              <p className="text-xs text-green-600 font-medium">Bueno</p>
              <p className="text-sm font-bold text-green-700">85% - 94%</p>
            </div>
            <div className="rounded-lg bg-purple-50 p-3 text-center">
              <p className="text-xs text-purple-600 font-medium">Excelencia</p>
              <p className="text-sm font-bold text-purple-700">&ge; 95%</p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* KPI por area */}
      <Card>
        <CardHeader>
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-blue-50">
              <BarChart3 className="h-5 w-5 text-blue-500" />
            </div>
            <div>
              <CardTitle>KPI por Area</CardTitle>
              <p className="text-sm text-gray-500 mt-0.5">
                Indicadores de desempeno configurados
              </p>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="rounded-lg border border-gray-100 p-4">
              <p className="text-sm font-semibold text-gray-900">
                Area A - Administracion Combustibles
              </p>
              <p className="text-xs text-gray-500 mt-1">
                Control de inventario, mermas, abastecimiento
              </p>
            </div>
            <div className="rounded-lg border border-gray-100 p-4">
              <p className="text-sm font-semibold text-gray-900">
                Area B - Mantenimiento Fijos
              </p>
              <p className="text-xs text-gray-500 mt-1">
                Preventivo, correctivo, certificaciones
              </p>
            </div>
            <div className="rounded-lg border border-gray-100 p-4">
              <p className="text-sm font-semibold text-gray-900">
                Area C - Mantenimiento Moviles
              </p>
              <p className="text-xs text-gray-500 mt-1">
                Flota, disponibilidad, cumplimiento planes
              </p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Checklist Templates Link */}
      <Card>
        <CardContent className="p-0">
          <Link
            href="/dashboard/admin/checklist-templates"
            className="flex items-center justify-between rounded-lg px-6 py-5 transition-colors hover:bg-gray-50"
          >
            <div className="flex items-center gap-4">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-orange-50">
                <ClipboardList className="h-5 w-5 text-orange-500" />
              </div>
              <div>
                <p className="text-sm font-semibold text-gray-900">
                  Plantillas de Checklist
                </p>
                <p className="text-xs text-gray-500 mt-0.5">
                  Gestionar los checklists por defecto para cada tipo de OT
                </p>
              </div>
            </div>
            <ChevronRight className="h-5 w-5 text-gray-400" />
          </Link>
        </CardContent>
      </Card>

      {/* Storage & App */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-green-50">
                <Database className="h-5 w-5 text-green-500" />
              </div>
              <div>
                <CardTitle>Storage Buckets</CardTitle>
                <p className="text-sm text-gray-500 mt-0.5">
                  Almacenamiento de archivos
                </p>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {[
                { name: 'documentos-ot', desc: 'Documentos de ordenes de trabajo' },
                { name: 'firmas', desc: 'Firmas digitales de tecnicos y supervisores' },
                { name: 'certificaciones', desc: 'Certificados y documentos normativos' },
                { name: 'evidencias', desc: 'Fotografias y evidencias de terreno' },
              ].map((bucket) => (
                <div
                  key={bucket.name}
                  className="flex items-center justify-between rounded-lg border border-gray-100 px-4 py-3"
                >
                  <div>
                    <p className="text-sm font-medium text-gray-900">
                      {bucket.name}
                    </p>
                    <p className="text-xs text-gray-500">{bucket.desc}</p>
                  </div>
                  <Badge variant="operativo">Activo</Badge>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-pillado-green-50">
                <Settings className="h-5 w-5 text-pillado-green-500" />
              </div>
              <div>
                <CardTitle>Informacion del Sistema</CardTitle>
                <p className="text-sm text-gray-500 mt-0.5">
                  Version y configuracion general
                </p>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {[
                { label: 'Aplicacion', value: 'SICOM-ICEO' },
                { label: 'Version', value: '1.0.0' },
                { label: 'Framework', value: 'Next.js 15 + React 19' },
                { label: 'Base de datos', value: 'Supabase (PostgreSQL)' },
                { label: 'Autenticacion', value: 'Supabase Auth' },
                { label: 'Entorno', value: process.env.NODE_ENV || 'development' },
              ].map((item) => (
                <div
                  key={item.label}
                  className="flex items-center justify-between rounded-lg border border-gray-100 px-4 py-3"
                >
                  <p className="text-sm text-gray-500">{item.label}</p>
                  <p className="text-sm font-medium text-gray-900">{item.value}</p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

// --- Main Page ---

export default function AdminPage() {
  const [activeTab, setActiveTab] = useState<TabId>('general')
  const [selectedUsuario, setSelectedUsuario] = useState<any>(null)
  const [showEditModal, setShowEditModal] = useState(false)
  const toast = useToast()
  const queryClient = useQueryClient()

  function handleEditUsuario(usuario: any) {
    setSelectedUsuario(usuario)
    setShowEditModal(true)
  }

  function handleSaved() {
    queryClient.invalidateQueries({ queryKey: ['admin', 'usuarios'] })
    toast.success('Usuario actualizado correctamente.')
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Administracion del Sistema
        </h1>
        <p className="text-sm text-gray-500 mt-1">
          Gestion de usuarios, parametros y configuracion general de SICOM-ICEO
        </p>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex gap-6" aria-label="Tabs">
          {tabs.map((tab) => {
            const Icon = tab.icon
            const isActive = activeTab === tab.id
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-2 border-b-2 px-1 py-3 text-sm font-medium transition-colors ${
                  isActive
                    ? 'border-pillado-green-500 text-pillado-green-600'
                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                }`}
              >
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            )
          })}
        </nav>
      </div>

      {/* Tab Content */}
      {activeTab === 'general' && <VistaGeneralTab />}
      {activeTab === 'usuarios' && <UsuariosTab onEditUsuario={handleEditUsuario} />}
      {activeTab === 'parametros' && <ParametrosTab />}

      {/* Edit User Modal */}
      <EditarUsuarioModal
        open={showEditModal}
        onClose={() => setShowEditModal(false)}
        usuario={selectedUsuario}
        onSaved={handleSaved}
      />
    </div>
  )
}
