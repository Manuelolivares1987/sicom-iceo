'use client'

import { useEffect, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, ClipboardList, AlertTriangle } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { supabase } from '@/lib/supabase'
import { ChecklistV2Wizard } from '@/components/flota/checklist-v2-wizard'
import { iniciarChecklistEntrega } from '@/lib/services/checklist-v2'

type ActivoInfo = {
  id: string
  codigo: string
  nombre: string | null
  patente: string | null
  tipo_equipamiento: string
  contrato_id: string | null
  contrato_codigo: string | null
  cliente: string | null
  horas_uso_actual: number | null
  kilometraje_actual: number | null
}

export default function ChecklistSalidaWizardPage() {
  useRequireAuth()
  const { user } = useAuth()
  const params = useParams<{ activoId: string }>()
  const router = useRouter()
  const activoId = params.activoId

  const [activo, setActivo]     = useState<ActivoInfo | null>(null)
  const [instanceId, setInstanceId] = useState<string | null>(null)
  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setLoading(true); setError(null)
      try {
        const { data: act, error: errA } = await supabase
          .from('activos')
          .select(`
            id, codigo, nombre, patente, tipo_equipamiento,
            horas_uso_actual, kilometraje_actual,
            contrato:contratos!contrato_id ( id, codigo, cliente )
          `)
          .eq('id', activoId)
          .single()
        if (errA || !act) throw errA ?? new Error('Activo no encontrado')
        type ActRow = {
          id: string; codigo: string; nombre: string | null; patente: string | null
          tipo_equipamiento: string; horas_uso_actual: number | null
          kilometraje_actual: number | null
          contrato: { id: string; codigo: string; cliente: string } | null
        }
        const a = act as unknown as ActRow
        const info: ActivoInfo = {
          id: a.id, codigo: a.codigo, nombre: a.nombre, patente: a.patente,
          tipo_equipamiento: a.tipo_equipamiento,
          horas_uso_actual: a.horas_uso_actual,
          kilometraje_actual: a.kilometraje_actual,
          contrato_id: a.contrato?.id ?? null,
          contrato_codigo: a.contrato?.codigo ?? null,
          cliente: a.contrato?.cliente ?? null,
        }
        if (cancelled) return
        setActivo(info)

        const { instanceId } = await iniciarChecklistEntrega({
          activoId:    info.id,
          contratoId:  info.contrato_id,
          horometro:   info.horas_uso_actual,
          kilometraje: info.kilometraje_actual,
          operadorId:  user?.id ?? null,
        })
        if (cancelled) return
        setInstanceId(instanceId)
      } catch (e) {
        if (!cancelled) setError((e as Error).message)
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
  }, [activoId, user?.id])

  if (loading) return <div className="flex h-96 items-center justify-center"><Spinner /></div>
  if (!activo || !instanceId) {
    return (
      <div className="p-6">
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-4 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error ?? 'No se pudo cargar el checklist'}
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-center gap-3">
        <Link href="/dashboard/flota/checklist-salida">
          <Button variant="ghost" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Volver
          </Button>
        </Link>
        <div className="flex-1">
          <h1 className="flex items-center gap-2 text-xl font-bold">
            <ClipboardList className="h-5 w-5 text-blue-600" />
            Check-List Entrega V02 — {activo.codigo}
          </h1>
          <p className="text-xs text-muted-foreground">
            {activo.patente && `${activo.patente} · `}
            {activo.cliente ? `Cliente: ${activo.cliente}` : 'Sin contrato'}
            {activo.contrato_codigo && ` · Contrato ${activo.contrato_codigo}`}
          </p>
        </div>
        <Badge variant="operativo">{activo.tipo_equipamiento.replace(/_/g, ' ')}</Badge>
      </div>

      <ChecklistV2Wizard
        instanceId={instanceId}
        onClosed={() => router.push('/dashboard/flota/checklist-salida?ok=1')}
      />
    </div>
  )
}
