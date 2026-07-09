'use client'

import { useEffect, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, ClipboardCheck, AlertTriangle, FileWarning, Loader2 } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { ChecklistV2Wizard } from '@/components/flota/checklist-v2-wizard'
import {
  buscarInstanceRecepcionPorInforme, type ChecklistV2Instance,
} from '@/lib/services/checklist-v2'
import { generarHallazgosDesdeChecklist } from '@/lib/services/informe-recepcion'
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

  const toast = useToast()
  const [instance, setInstance] = useState<ChecklistV2Instance | null>(null)
  const [informe, setInforme]   = useState<InformeInfo | null>(null)
  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState<string | null>(null)
  // Al cerrar el checklist: opción de crear el informe de recobro con TODOS
  // los hallazgos NO OK encontrados (MIG214).
  const [recobro, setRecobro]   = useState<{ noOk: number } | null>(null)
  const [creando, setCreando]   = useState(false)

  const irAlInforme = () => router.push(`/dashboard/flota/inspeccion-recepcion/${informeId}`)

  async function onWizardClosed() {
    try {
      const { count } = await supabase
        .from('checklist_v2_instance_item')
        .select('id', { count: 'exact', head: true })
        .eq('instance_id', instance!.id)
        .eq('resultado', 'no_ok')
      if ((count ?? 0) > 0) { setRecobro({ noOk: count! }); return }
    } catch { /* si falla el conteo, seguimos al informe */ }
    irAlInforme()
  }

  async function crearInformeRecobro() {
    setCreando(true)
    try {
      const r = await generarHallazgosDesdeChecklist(informeId)
      toast.success(`${r.creados} hallazgo(s) volcado(s) al informe de recobro${r.ya_existian ? ` (${r.ya_existian} ya estaban)` : ''}`)
      irAlInforme()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al generar los hallazgos')
    } finally { setCreando(false) }
  }

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
        onClosed={onWizardClosed}
      />

      {recobro && (
        <Modal open onClose={() => { setRecobro(null); irAlInforme() }} title="Checklist cerrado ✓">
          <div className="space-y-3">
            <div className="flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 p-3">
              <FileWarning className="mt-0.5 h-6 w-6 shrink-0 text-red-600" />
              <div className="text-sm text-gray-700">
                Se encontraron <b>{recobro.noOk} hallazgo{recobro.noOk !== 1 ? 's' : ''}</b> (ítems NO OK)
                en el checklist de <b>{informe.activo_patente ?? informe.activo_codigo}</b>.
                ¿Quieres crear el informe de recobro con todos los hallazgos (sección, descripción,
                foto y observación de cada uno)?
              </div>
            </div>
            <p className="text-[11px] text-gray-500">
              Los hallazgos quedan marcados «atribuible al cliente» por defecto — después puedes
              ajustar gravedad, cobrable y costos antes de emitir el informe.
            </p>
          </div>
          <ModalFooter>
            <Button variant="outline" disabled={creando} onClick={() => { setRecobro(null); irAlInforme() }}>
              Ahora no
            </Button>
            <Button disabled={creando} onClick={crearInformeRecobro} className="bg-red-600 hover:bg-red-700">
              {creando ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <FileWarning className="mr-1 h-4 w-4" />}
              Crear informe de recobro ({recobro.noOk})
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
