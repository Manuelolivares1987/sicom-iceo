'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  ClipboardList, Truck, ArrowRight, AlertTriangle, ArrowLeft, Search,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { supabase } from '@/lib/supabase'

type ActivoDisponible = {
  id: string
  codigo: string
  nombre: string | null
  patente: string | null
  tipo: string
  tipo_equipamiento: string
  estado_comercial: string | null
  contrato_id: string | null
  contrato_codigo: string | null
  cliente: string | null
  checklist_en_progreso: string | null   // instance_id si ya hay uno abierto
}

export default function ChecklistSalidaListPage() {
  useRequireAuth()
  const [activos, setActivos] = useState<ActivoDisponible[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError]     = useState<string | null>(null)
  const [q, setQ]             = useState('')

  const cargar = async () => {
    setLoading(true); setError(null)
    // Activos en estado_comercial disponible (listos para entregar)
    const { data, error } = await supabase
      .from('activos')
      .select(`
        id, codigo, nombre, patente, tipo, tipo_equipamiento, estado_comercial,
        contrato:contratos!contrato_id ( id, codigo, cliente )
      `)
      .eq('estado_comercial', 'disponible')
      .neq('estado', 'dado_baja')
      .order('codigo')

    if (error) { setError(error.message); setLoading(false); return }

    type Row = {
      id: string; codigo: string; nombre: string | null; patente: string | null
      tipo: string; tipo_equipamiento: string; estado_comercial: string | null
      contrato: { id: string; codigo: string; cliente: string } | null
    }
    const rows = (data as unknown as Row[]) ?? []

    // Para cada activo, verificar si ya hay un checklist entrega en_progreso
    const ids = rows.map((r) => r.id)
    let checklistByActivo: Record<string, string> = {}
    if (ids.length) {
      const { data: cls } = await supabase
        .from('checklist_v2_instance')
        .select('id, activo_id')
        .in('activo_id', ids)
        .eq('momento_uso', 'entrega_arriendo')
        .eq('estado', 'en_progreso')
      for (const c of (cls ?? []) as Array<{ id: string; activo_id: string }>) {
        checklistByActivo[c.activo_id] = c.id
      }
    }

    setActivos(rows.map((r) => ({
      id:                    r.id,
      codigo:                r.codigo,
      nombre:                r.nombre,
      patente:               r.patente,
      tipo:                  r.tipo,
      tipo_equipamiento:     r.tipo_equipamiento,
      estado_comercial:      r.estado_comercial,
      contrato_id:           r.contrato?.id    ?? null,
      contrato_codigo:       r.contrato?.codigo ?? null,
      cliente:               r.contrato?.cliente ?? null,
      checklist_en_progreso: checklistByActivo[r.id] ?? null,
    })))
    setLoading(false)
  }

  useEffect(() => { cargar() }, [])

  const filtrados = q.trim()
    ? activos.filter((a) =>
        a.codigo.toLowerCase().includes(q.toLowerCase()) ||
        (a.patente ?? '').toLowerCase().includes(q.toLowerCase()) ||
        (a.nombre  ?? '').toLowerCase().includes(q.toLowerCase()) ||
        (a.cliente ?? '').toLowerCase().includes(q.toLowerCase()))
    : activos

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex items-center gap-3">
        <Link href="/dashboard/flota">
          <Button variant="ghost" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Flota
          </Button>
        </Link>
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <ClipboardList className="h-6 w-6 text-blue-600" /> Check-List de Entrega V02
          </h1>
          <p className="text-sm text-muted-foreground">
            Selecciona el activo a entregar al cliente. El check-list es obligatorio antes de marcar como arrendado.
          </p>
        </div>
      </div>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <CardTitle className="text-base">Activos disponibles ({filtrados.length})</CardTitle>
            <div className="relative w-full max-w-xs">
              <Search className="absolute left-2 top-2.5 h-4 w-4 text-gray-400" />
              <Input
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="Buscar por código, patente, cliente..."
                className="pl-8"
              />
            </div>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <div className="flex h-32 items-center justify-center"><Spinner /></div>
          ) : error ? (
            <div className="flex items-center gap-2 p-4 text-sm text-red-700">
              <AlertTriangle className="h-4 w-4" /> {error}
            </div>
          ) : filtrados.length === 0 ? (
            <div className="p-6 text-center text-sm text-muted-foreground">
              No hay activos en estado disponible.
            </div>
          ) : (
            <div className="divide-y">
              {filtrados.map((a) => (
                <div key={a.id} className="flex flex-wrap items-center justify-between gap-3 px-4 py-3 hover:bg-gray-50">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <Truck className="h-4 w-4 text-gray-400" />
                      <span className="font-semibold">{a.codigo}</span>
                      {a.patente && <span className="text-sm text-gray-500">· {a.patente}</span>}
                      <Badge variant="operativo">{a.tipo_equipamiento.replace(/_/g, ' ')}</Badge>
                      {a.checklist_en_progreso && (
                        <Badge variant="en_ejecucion">checklist en curso</Badge>
                      )}
                    </div>
                    <div className="mt-0.5 text-xs text-gray-600">
                      {a.cliente ? `Cliente: ${a.cliente}` : 'Sin contrato asignado'}
                      {a.contrato_codigo && ` · Contrato ${a.contrato_codigo}`}
                    </div>
                  </div>
                  <Link href={`/dashboard/flota/checklist-salida/${a.id}`}>
                    <Button size="sm" className="gap-1">
                      {a.checklist_en_progreso ? 'Continuar' : 'Iniciar'}
                      <ArrowRight className="h-4 w-4" />
                    </Button>
                  </Link>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
