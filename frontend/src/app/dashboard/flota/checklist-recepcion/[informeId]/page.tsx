'use client'

import { useEffect, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, ClipboardCheck, AlertTriangle } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { ChecklistV2Wizard } from '@/components/flota/checklist-v2-wizard'
import {
  buscarInstanceRecepcionPorInforme, type ChecklistV2Instance,
} from '@/lib/services/checklist-v2'
import { supabase } from '@/lib/supabase'

type InformeInfo = {
  id: string
  folio: string | null
  cliente_nombre: string | null
  activo_codigo: string | null
  activo_patente: string | null
}

export default function ChecklistRecepcionWizardPage() {
  useRequireAuth()
  const params = useParams<{ informeId: string }>()
  const router = useRouter()
  const informeId = params.informeId

  const [instance, setInstance] = useState<ChecklistV2Instance | null>(null)
  const [informe, setInforme]   = useState<InformeInfo | null>(null)
  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setLoading(true); setError(null)
      try {
        // 1. Cargar info del informe (cabecera)
        const { data: inf, error: e1 } = await supabase
          .from('informes_recepcion')
          .select(`
            id, folio, cliente_nombre,
            activo:activos!activo_id ( codigo, patente )
          `)
          .eq('id', informeId)
          .single()
        if (e1 || !inf) throw e1 ?? new Error('Informe no encontrado')
        type Row = {
          id: string; folio: string | null; cliente_nombre: string | null
          activo: { codigo: string; patente: string | null } | null
        }
        const i = inf as unknown as Row
        if (cancelled) return
        setInforme({
          id: i.id,
          folio: i.folio,
          cliente_nombre: i.cliente_nombre,
          activo_codigo: i.activo?.codigo ?? null,
          activo_patente: i.activo?.patente ?? null,
        })

        // 2. Buscar instance recepcion vinculado (creado por trigger)
        const inst = await buscarInstanceRecepcionPorInforme(informeId)
        if (cancelled) return
        if (!inst) {
          setError('No hay checklist V02 de recepcion vinculado a este informe. ' +
                   'El sistema lo crea automaticamente al pasar el activo a estado "en_recepcion".')
          return
        }
        setInstance(inst)
      } catch (e) {
        if (!cancelled) setError((e as Error).message)
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
  }, [informeId])

  if (loading) return <div className="flex h-96 items-center justify-center"><Spinner /></div>
  if (!instance || !informe) {
    return (
      <div className="p-6 space-y-3">
        <Link href={`/dashboard/flota/inspeccion-recepcion/${informeId}`}>
          <Button variant="ghost" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Volver al informe
          </Button>
        </Link>
        <Card className="border-amber-200 bg-amber-50">
          <CardContent className="flex items-center gap-2 p-4 text-sm text-amber-800">
            <AlertTriangle className="h-4 w-4" /> {error ?? 'Sin instance de recepcion'}
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-center gap-3">
        <Link href={`/dashboard/flota/inspeccion-recepcion/${informeId}`}>
          <Button variant="ghost" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Volver al informe
          </Button>
        </Link>
        <div className="flex-1">
          <h1 className="flex items-center gap-2 text-xl font-bold">
            <ClipboardCheck className="h-5 w-5 text-red-600" />
            Check-List Recepción V02 — {informe.activo_codigo ?? '—'}
          </h1>
          <p className="text-xs text-muted-foreground">
            Informe {informe.folio ?? informeId.slice(0, 8)}
            {informe.activo_patente && ` · ${informe.activo_patente}`}
            {informe.cliente_nombre && ` · Cliente: ${informe.cliente_nombre}`}
          </p>
        </div>
        {instance.estado === 'cerrado' && <Badge variant="ejecutada_ok">CERRADO</Badge>}
      </div>

      <ChecklistV2Wizard
        instanceId={instance.id}
        onClosed={() => router.push(`/dashboard/flota/inspeccion-recepcion/${informeId}`)}
      />
    </div>
  )
}
