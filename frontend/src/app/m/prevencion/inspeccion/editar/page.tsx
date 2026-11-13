'use client'

// Inspección de terreno APR — edición del borrador del teléfono (MIG685).
// La ruta es una sola página (?id=…) para que el service worker la tenga
// guardada y abra sin señal.

import { Suspense, useEffect, useState } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import { ChevronLeft } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { useToast } from '@/hooks/use-toast'
import { leerBorrador, type BorradorInspeccion } from '@/lib/offline/inspeccion-apr-db'
import { InspeccionAprForm } from '@/components/prevencion/inspeccion-apr-form'
import { descargarPdfInspeccion } from '@/components/prevencion/pdf-inspeccion-apr'

function Editor() {
  const id = useSearchParams().get('id')
  const toast = useToast()
  const [b, setB] = useState<BorradorInspeccion | null | undefined>(undefined)

  useEffect(() => {
    if (!id) { setB(null); return }
    leerBorrador(id).then((x) => setB(x ?? null)).catch(() => setB(null))
  }, [id])

  if (b === undefined) return <div className="flex min-h-screen items-center justify-center"><Spinner className="h-8 w-8" /></div>
  if (b === null) {
    return (
      <div className="space-y-3 p-6 text-center text-sm text-gray-600">
        <p>Esta inspección no está en este teléfono.</p>
        <Link href="/m/prevencion/inspeccion" className="inline-flex items-center gap-1 font-semibold text-pillado-green-600">
          <ChevronLeft className="h-4 w-4" /> Volver
        </Link>
      </div>
    )
  }
  return (
    <InspeccionAprForm
      inicial={b}
      volver={(
        <Link href="/m/prevencion/inspeccion" className="-ml-1 shrink-0 p-1 text-gray-500" aria-label="Volver">
          <ChevronLeft className="h-5 w-5" />
        </Link>
      )}
      onPdf={async (sid) => {
        try { await descargarPdfInspeccion(sid, b.faena_nombre) }
        catch (e: any) { toast.error(e?.message ?? 'No se pudo generar el PDF') }
      }}
    />
  )
}

export default function EditarInspeccionPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  if (verificando) return <div className="flex min-h-screen items-center justify-center"><Spinner className="h-8 w-8" /></div>
  if (sinSesionOffline) return <SinSesionOffline />
  return (
    <Suspense fallback={<div className="flex min-h-screen items-center justify-center"><Spinner className="h-8 w-8" /></div>}>
      <Editor />
    </Suspense>
  )
}
