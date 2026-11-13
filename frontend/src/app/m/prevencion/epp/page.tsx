'use client'

// Entrega de EPP desde el teléfono (MIG687): supervisor o prevención.

import { useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { ChevronLeft, FileDown, HardHat, Loader2, Plus } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/hooks/use-toast'
import { EppEntregaForm } from '@/components/prevencion/epp-entrega-form'
import { descargarComprobanteEpp } from '@/components/prevencion/pdf-comprobante-epp'
import { MOTIVO_EPP, getEntregasEpp } from '@/lib/services/prevencion-epp'

export default function EppMovilPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const toast = useToast()
  const [nueva, setNueva] = useState(false)
  const [pdfId, setPdfId] = useState<string | null>(null)
  const { data: mias, isLoading } = useQuery({
    queryKey: ['epp-entregas', 'mias'],
    queryFn: () => getEntregasEpp({ soloMias: true, limit: 30 }),
  })

  if (verificando) return <div className="flex min-h-screen items-center justify-center"><Spinner className="h-8 w-8" /></div>
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      <header className="border-b border-gray-200 bg-white px-4 pb-4 pt-[max(1.25rem,env(safe-area-inset-top))]">
        <Link href="/m/prevencion" className="mb-2 inline-flex items-center gap-1 text-xs text-gray-500">
          <ChevronLeft className="h-3.5 w-3.5" /> Prevención
        </Link>
        <p className="flex items-center gap-2 text-lg font-bold text-gray-900">
          <HardHat className="h-5 w-5 text-orange-500" /> Entrega de EPP
        </p>
        <p className="text-xs text-gray-500">Con firma del trabajador · {perfil?.nombre_completo ?? ''}</p>
      </header>

      <main className="space-y-4 px-4 py-5">
        {nueva ? (
          <div className="rounded-xl border border-gray-200 bg-white p-3">
            <EppEntregaForm faenaIdInicial={(perfil as any)?.faena_id ?? null}
                            onGuardado={() => setNueva(false)} onCancelar={() => setNueva(false)} />
          </div>
        ) : (
          <button onClick={() => setNueva(true)}
                  className="flex w-full items-center gap-3 rounded-xl border-2 border-orange-500 bg-white p-4 active:scale-[0.99]">
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-orange-500 text-white"><Plus className="h-6 w-6" /></div>
            <div className="min-w-0 flex-1 text-left">
              <p className="text-base font-bold text-gray-900">Nueva entrega</p>
              <p className="text-xs text-gray-500">Trabajador, elementos, talla y firma</p>
            </div>
          </button>
        )}

        <section>
          <h2 className="mb-2 text-sm font-bold text-gray-700">Mis últimas entregas</h2>
          {isLoading ? <div className="flex justify-center py-6"><Spinner /></div>
           : !mias?.length ? (
            <p className="rounded-xl border border-dashed border-gray-300 bg-white p-5 text-center text-sm text-gray-500">
              Todavía no registra entregas.
            </p>
          ) : (
            <ul className="space-y-1.5">
              {mias.map((e) => (
                <li key={e.id} className="flex items-center gap-2 rounded-lg border border-gray-200 bg-white px-3 py-2">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-gray-900">
                      {e.trabajador_nombre}{e.anulada && <span className="ml-1 text-[10px] font-bold text-red-600">ANULADA</span>}
                    </p>
                    <p className="truncate text-[11px] text-gray-500">
                      {e.fecha} · {MOTIVO_EPP[e.motivo]} · {e.items.map((i) => i.nombre).join(', ')}
                    </p>
                  </div>
                  <button className="shrink-0 p-1 text-gray-400 hover:text-gray-800" title="Comprobante PDF"
                          disabled={pdfId === e.id}
                          onClick={async () => {
                            setPdfId(e.id)
                            try { await descargarComprobanteEpp(e) } catch (err: any) { toast.error(err?.message ?? 'No se pudo generar el PDF') }
                            finally { setPdfId(null) }
                          }}>
                    {pdfId === e.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileDown className="h-4 w-4" />}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>
      </main>
    </div>
  )
}
