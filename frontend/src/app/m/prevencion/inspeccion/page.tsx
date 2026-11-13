'use client'

// ============================================================================
// Inspección de terreno APR — inicio (MIG685)
// ----------------------------------------------------------------------------
// «Preparar» se hace en Calama, con señal: baja la plantilla y el estado
// documental de la cuadrilla al teléfono. Desde ahí la inspección se completa
// en faena aunque no haya conexión, y se envía al volver.
// ============================================================================

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { ChevronLeft, ChevronRight, ClipboardCheck, FileDown, Loader2, Plus, Smartphone, Trash2 } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Modal } from '@/components/ui/modal'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import {
  ESTADO_LABEL, RESULTADO_LABEL, getFaenasInspeccion, getHabilitacion, getMisInspecciones, getPlantilla,
} from '@/lib/services/prevencion-inspeccion'
import {
  borrarBorrador, fotosPendientes, guardarBorrador, listarBorradores,
  type BorradorInspeccion,
} from '@/lib/offline/inspeccion-apr-db'
import { avanceBorrador } from '@/components/prevencion/inspeccion-apr-form'
import { descargarPdfInspeccion } from '@/components/prevencion/pdf-inspeccion-apr'

const ROLES_APR = ['administrador', 'prevencionista', 'jefe_operaciones', 'subgerente_operaciones']

function hoy() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

const RES_CLASE: Record<string, string> = {
  conforme: 'bg-emerald-100 text-emerald-800',
  con_desviaciones: 'bg-amber-100 text-amber-800',
  critico: 'bg-red-600 text-white',
}

export default function InspeccionAprHome() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const router = useRouter()
  const toast = useToast()
  const [borradores, setBorradores] = useState<BorradorInspeccion[] | null>(null)
  const [nuevaOpen, setNuevaOpen] = useState(false)
  const [faenaSel, setFaenaSel] = useState('')
  const [preparando, setPreparando] = useState(false)
  const [pdfId, setPdfId] = useState<string | null>(null)

  const esApr = !!perfil?.rol && ROLES_APR.includes(perfil.rol)
  const { data: faenas } = useQuery({ queryKey: ['prev-insp-faenas'], queryFn: getFaenasInspeccion, enabled: esApr })
  const { data: enviadas } = useQuery({ queryKey: ['prev-insp-mias'], queryFn: () => getMisInspecciones(20), enabled: esApr })

  useEffect(() => { listarBorradores().then(setBorradores).catch(() => setBorradores([])) }, [])

  if (verificando) return <div className="flex min-h-screen items-center justify-center"><Spinner className="h-8 w-8" /></div>
  if (sinSesionOffline) return <SinSesionOffline />

  const preparar = async () => {
    const f = (faenas ?? []).find((x) => x.faena_id === faenaSel)
    if (!f) return toast.error('Elija la faena')
    if (!navigator.onLine) return toast.error('Para preparar una inspección se necesita señal (baja el estado documental de la cuadrilla).')
    setPreparando(true)
    try {
      const [plantilla, habilitacion] = await Promise.all([getPlantilla(), getHabilitacion(f.grupo_personal)])
      const ahora = new Date()
      const b: BorradorInspeccion = {
        cliente_uuid: crypto.randomUUID(),
        servidor_id: null,
        faena_id: f.faena_id,
        faena_nombre: f.nombre,
        grupo: f.grupo_personal,
        fecha: hoy(),
        hora_inicio: `${String(ahora.getHours()).padStart(2, '0')}:${String(ahora.getMinutes()).padStart(2, '0')}`,
        instalacion: '', area_sector: '', trabajo: '', supervisor: '',
        trabajo_cruzado: false, empresas_cruzadas: '', observacion: '',
        personas: [], respuestas: {}, plantilla, habilitacion,
        ultimo_envio: null,
        created_at: ahora.toISOString(), updated_at: ahora.toISOString(),
      }
      await guardarBorrador(b)
      router.push(`/m/prevencion/inspeccion/editar/?id=${b.cliente_uuid}`)
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo preparar la inspección')
    } finally {
      setPreparando(false)
    }
  }

  const descartar = async (b: BorradorInspeccion) => {
    const pend = fotosPendientes(b)
    if (!b.ultimo_envio || pend > 0) {
      // Sin confirm() nativo (bloquea en algunos navegadores de terreno): se
      // pide un segundo toque.
      if ((window as any).__descartar !== b.cliente_uuid) {
        ;(window as any).__descartar = b.cliente_uuid
        return toast.error(b.ultimo_envio
          ? `Tiene ${pend} foto(s) sin enviar. Toque de nuevo para descartar igual.`
          : 'Esta inspección NO se ha enviado. Toque de nuevo para descartarla.')
      }
    }
    await borrarBorrador(b.cliente_uuid)
    setBorradores((prev) => (prev ?? []).filter((x) => x.cliente_uuid !== b.cliente_uuid))
  }

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      <header className="border-b border-gray-200 bg-white px-4 pb-4 pt-[max(1.25rem,env(safe-area-inset-top))]">
        <Link href="/m/prevencion" className="mb-2 inline-flex items-center gap-1 text-xs text-gray-500">
          <ChevronLeft className="h-3.5 w-3.5" /> Prevención
        </Link>
        <p className="flex items-center gap-2 text-lg font-bold text-gray-900">
          <ClipboardCheck className="h-5 w-5 text-pillado-green-500" /> Inspección de terreno APR
        </p>
        <p className="text-xs text-gray-500">Traslado · ingreso · documentos · ejecución · término · cierre ART</p>
      </header>

      <main className="space-y-4 px-4 py-5">
        {!esApr ? (
          <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
            La inspección de terreno la registra prevención (APR). Su cuenta no tiene ese rol.
          </p>
        ) : (
          <button onClick={() => setNuevaOpen(true)}
                  className="flex w-full items-center gap-3 rounded-xl border-2 border-pillado-green-500 bg-white p-4 active:scale-[0.99]">
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-pillado-green-500 text-white"><Plus className="h-6 w-6" /></div>
            <div className="min-w-0 flex-1 text-left">
              <p className="text-base font-bold text-gray-900">Nueva inspección</p>
              <p className="text-xs text-gray-500">Prepárela con señal; después funciona sin conexión</p>
            </div>
          </button>
        )}

        {(borradores?.length ?? 0) > 0 && (
          <section>
            <h2 className="mb-2 flex items-center gap-1.5 text-sm font-bold text-gray-700">
              <Smartphone className="h-4 w-4" /> En este teléfono
            </h2>
            <ul className="space-y-2">
              {borradores!.map((b) => {
                const av = avanceBorrador(b)
                const pend = fotosPendientes(b)
                return (
                  <li key={b.cliente_uuid} className="rounded-xl border border-gray-200 bg-white p-3">
                    <Link href={`/m/prevencion/inspeccion/editar/?id=${b.cliente_uuid}`} className="flex items-center gap-2">
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-semibold text-gray-900">{b.trabajo || 'Sin título'}</p>
                        <p className="text-[11px] text-gray-500">{b.faena_nombre} · {b.fecha} · {av.total - av.pend}/{av.total} puntos</p>
                      </div>
                      <ChevronRight className="h-4 w-4 text-gray-400" />
                    </Link>
                    <div className="mt-2 flex flex-wrap items-center gap-1.5">
                      {b.ultimo_envio
                        ? <span className="rounded-full bg-blue-100 px-2 py-0.5 text-[10px] font-bold text-blue-700">enviada · {b.ultimo_envio.estado.replaceAll('_', ' ')}</span>
                        : <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800">sin enviar</span>}
                      {pend > 0 && <span className="rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-semibold text-amber-800">{pend} foto(s) en teléfono</span>}
                      <button onClick={() => descartar(b)} className="ml-auto p-1 text-gray-300 hover:text-red-500" title="Quitar del teléfono">
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  </li>
                )
              })}
            </ul>
          </section>
        )}

        {esApr && (
          <section>
            <h2 className="mb-2 text-sm font-bold text-gray-700">Mis inspecciones enviadas</h2>
            {!enviadas?.length ? (
              <p className="rounded-xl border border-dashed border-gray-300 bg-white p-5 text-center text-sm text-gray-500">
                Todavía no hay inspecciones enviadas.
              </p>
            ) : (
              <ul className="space-y-1.5">
                {enviadas.map((i) => (
                  <li key={i.id} className="flex items-center gap-2 rounded-lg border border-gray-200 bg-white px-3 py-2">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-gray-900">{i.trabajo}</p>
                      <p className="text-[11px] text-gray-500">
                        {i.fecha} · {ESTADO_LABEL[i.estado]}{i.pct_cumplimiento != null ? ` · ${i.pct_cumplimiento}%` : ''}
                      </p>
                    </div>
                    <span className={cn('shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold', RES_CLASE[i.resultado])}>
                      {RESULTADO_LABEL[i.resultado]}
                    </span>
                    <button className="shrink-0 p-1 text-gray-400 hover:text-gray-800" title="Informe PDF"
                            disabled={pdfId === i.id}
                            onClick={async () => {
                              setPdfId(i.id)
                              try {
                                await descargarPdfInspeccion(i.id, (faenas ?? []).find((f) => f.faena_id === i.faena_id)?.nombre ?? 'Faena')
                              } catch (e: any) { toast.error(e?.message ?? 'No se pudo generar el PDF') }
                              finally { setPdfId(null) }
                            }}>
                      {pdfId === i.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileDown className="h-4 w-4" />}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>
        )}
      </main>

      <Modal open={nuevaOpen} onClose={() => setNuevaOpen(false)} title="Nueva inspección de terreno" className="max-w-[480px]">
        <div className="space-y-3">
          <Select label="Faena" value={faenaSel} onChange={(e) => setFaenaSel(e.target.value)}
                  placeholder="Elegir faena…"
                  options={(faenas ?? []).map((f) => ({ value: f.faena_id, label: f.nombre }))} />
          <p className="text-[12px] text-gray-500">
            Se descarga al teléfono el estado documental del personal de la faena. Hágalo antes de subir: en
            terreno la inspección funciona sin señal.
          </p>
          <div className="flex gap-2">
            <Button className="flex-1" onClick={preparar} disabled={preparando}>
              {preparando && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Preparar inspección
            </Button>
            <Button variant="outline" onClick={() => setNuevaOpen(false)}>Cancelar</Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
