'use client'

import { useState } from 'react'
import Link from 'next/link'
import { FileText, ExternalLink, FileCheck, Clock, CheckCircle2 } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useInformesRecepcionLista } from '@/hooks/use-informe-recepcion'
import type { EstadoInformeRecepcion } from '@/lib/services/informe-recepcion'
import { cn } from '@/lib/utils'

export default function ListaInformesRecepcionPage() {
  useRequireAuth()
  const [filtroEstado, setFiltroEstado] = useState<EstadoInformeRecepcion | 'todos'>('todos')

  const { data: informes = [], isLoading } = useInformesRecepcionLista(
    filtroEstado === 'todos' ? undefined : filtroEstado,
  )

  const fmt = (n: number) => `$${Number(n).toLocaleString('es-CL')}`

  const counts = {
    en_inspeccion: informes.filter((i) => i.estado === 'en_inspeccion').length,
    borrador:      informes.filter((i) => i.estado === 'borrador').length,
    emitido:       informes.filter((i) => i.estado === 'emitido').length,
  }

  return (
    <div className="space-y-4">
      <div className="rounded-xl bg-gradient-to-r from-slate-700 to-indigo-700 p-5 text-white">
        <h1 className="text-xl font-bold flex items-center gap-2">
          <FileText className="h-6 w-6" />
          Informes de Recepción
        </h1>
        <p className="text-xs text-white/80 mt-1">
          Devoluciones de arriendo con daños imputables al cliente.
        </p>
      </div>

      {/* Tabs por estado */}
      <div className="flex gap-2 text-sm">
        <TabBtn active={filtroEstado === 'todos'} onClick={() => setFiltroEstado('todos')} label="Todos" count={informes.length} />
        <TabBtn active={filtroEstado === 'en_inspeccion'} onClick={() => setFiltroEstado('en_inspeccion')} label="En inspección" count={counts.en_inspeccion} icon={<Clock className="h-3 w-3" />} />
        <TabBtn active={filtroEstado === 'borrador'} onClick={() => setFiltroEstado('borrador')} label="Borrador" count={counts.borrador} icon={<FileCheck className="h-3 w-3" />} />
        <TabBtn active={filtroEstado === 'emitido'} onClick={() => setFiltroEstado('emitido')} label="Emitidos" count={counts.emitido} icon={<CheckCircle2 className="h-3 w-3" />} />
      </div>

      <Card>
        <CardContent className="overflow-x-auto p-0">
          {isLoading ? (
            <div className="flex h-32 items-center justify-center"><Spinner className="h-6 w-6" /></div>
          ) : informes.length === 0 ? (
            <p className="text-sm text-gray-400 text-center py-10">Sin informes con ese filtro.</p>
          ) : (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b bg-gray-50 text-left text-gray-500 uppercase">
                  <th className="px-3 py-2">Folio</th>
                  <th className="px-3 py-2">Equipo</th>
                  <th className="px-3 py-2">Cliente</th>
                  <th className="px-3 py-2">Recibido</th>
                  <th className="px-3 py-2 text-right">Hallazgos</th>
                  <th className="px-3 py-2 text-right">Total cobro</th>
                  <th className="px-3 py-2">Estado</th>
                  <th className="px-3 py-2"></th>
                </tr>
              </thead>
              <tbody>
                {informes.map((i) => (
                  <tr key={i.id} className="border-b hover:bg-gray-50">
                    <td className="px-3 py-2 font-mono font-semibold">{i.folio}</td>
                    <td className="px-3 py-2">
                      <div className="font-mono text-xs text-gray-500">{i.patente ?? i.activo_codigo}</div>
                      <div>{i.activo_nombre}</div>
                    </td>
                    <td className="px-3 py-2 text-gray-600 max-w-[180px] truncate">{i.cliente_nombre ?? '—'}</td>
                    <td className="px-3 py-2 text-gray-500">{i.fecha_recepcion}</td>
                    <td className="px-3 py-2 text-right">
                      {i.n_atrib_cliente}/{i.n_hallazgos}
                    </td>
                    <td className="px-3 py-2 text-right font-semibold text-green-700">
                      {fmt(Number(i.total))}
                    </td>
                    <td className="px-3 py-2">
                      <EstadoBadge estado={i.estado} />
                    </td>
                    <td className="px-3 py-2 text-right">
                      {i.estado === 'en_inspeccion' && (
                        <Link href={`/dashboard/flota/inspeccion-recepcion/${i.id}`} className="text-blue-600 hover:underline">
                          continuar <ExternalLink className="inline h-3 w-3" />
                        </Link>
                      )}
                      {(i.estado === 'borrador' || i.estado === 'emitido') && (
                        <Link href={`/dashboard/flota/recepcion/${i.id}/emitir`} className="text-blue-600 hover:underline">
                          {i.estado === 'borrador' ? 'revisar' : 'ver'} <ExternalLink className="inline h-3 w-3" />
                        </Link>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

function TabBtn({ active, onClick, label, count, icon }: {
  active: boolean; onClick: () => void; label: string; count: number; icon?: React.ReactNode
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition',
        active ? 'bg-blue-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-100 border border-gray-200',
      )}
    >
      {icon}
      {label}
      <span className={cn('rounded-full px-1.5 text-[10px]', active ? 'bg-blue-700' : 'bg-gray-200')}>
        {count}
      </span>
    </button>
  )
}

function EstadoBadge({ estado }: { estado: string }) {
  const map: Record<string, string> = {
    en_inspeccion: 'bg-amber-100 text-amber-800',
    borrador: 'bg-blue-100 text-blue-800',
    emitido: 'bg-green-100 text-green-800',
    cancelado: 'bg-gray-100 text-gray-600',
  }
  return <Badge className={map[estado] ?? 'bg-gray-100'}>{estado}</Badge>
}
