'use client'

// ============================================================================
// Prevención en el teléfono — carga directa del supervisor (MIG546)
// ----------------------------------------------------------------------------
// El flujo que pidió prevención en su levantamiento:
//   Supervisor → carga directa del registro → repositorio centralizado →
//   consolidación automática → Informe de Gestión Mensual.
// Sin este canal, cada RIT/VAT/VCT se pide por correo a fin de mes.
// ============================================================================

import { useMemo, useState } from 'react'
import { CheckCircle2, ClipboardList, HardHat, Loader2, Paperclip, Plus } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { Modal } from '@/components/ui/modal'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import { RegistroTerrenoForm } from '@/components/prevencion/registro-terreno-form'
import { useCerrarRegistro, useMisRegistros } from '@/hooks/use-prevencion-reportabilidad'

const ROLES_CREAR = ['administrador', 'prevencionista', 'supervisor',
  'jefe_operaciones', 'jefe_mantenimiento', 'subgerente_operaciones']

export default function PrevencionMobileHome() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const toast = useToast()
  const { data: registros, isLoading } = useMisRegistros(30)
  const cerrar = useCerrarRegistro()

  const [nuevoOpen, setNuevoOpen] = useState(false)
  const [cerrandoId, setCerrandoId] = useState<string | null>(null)
  const [obsCierre, setObsCierre] = useState('')

  const puedeCrear = !!perfil?.rol && ROLES_CREAR.includes(perfil.rol)

  const abiertos = useMemo(
    () => (registros ?? []).filter((r) => r.estado === 'abierto'),
    [registros],
  )

  if (verificando) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }
  if (sinSesionOffline) return <SinSesionOffline />

  const confirmarCierre = async () => {
    if (!cerrandoId) return
    try {
      await cerrar.mutateAsync({ id: cerrandoId, observacion: obsCierre.trim() || undefined })
      toast.success('Registro cerrado')
      setCerrandoId(null)
      setObsCierre('')
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo cerrar el registro')
    }
  }

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      <header className="border-b border-gray-200 bg-white px-4 pb-5 pt-[max(1.25rem,env(safe-area-inset-top))]">
        <p className="flex items-center gap-2 text-lg font-bold leading-tight text-gray-900">
          <HardHat className="h-5 w-5 text-pillado-green-500" />
          Prevención — registro de terreno
        </p>
        <p className="text-xs text-gray-500">
          RIT · VAT · VCT · charlas · inspecciones
          {perfil?.nombre_completo ? ` · ${perfil.nombre_completo}` : ''}
        </p>
      </header>

      <main className="space-y-4 px-4 py-5">
        {!puedeCrear && (
          <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
            Su cuenta no tiene el rol para cargar registros de prevención.
            Avise a quien administra el sistema.
          </p>
        )}

        {puedeCrear && (
          <button
            onClick={() => setNuevoOpen(true)}
            className="flex w-full items-center gap-3 rounded-xl border-2 border-pillado-green-500 bg-white p-4 active:scale-[0.99]"
          >
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-pillado-green-500 text-white">
              <Plus className="h-6 w-6" />
            </div>
            <div className="min-w-0 flex-1 text-left">
              <p className="text-base font-bold text-gray-900">Nuevo registro</p>
              <p className="text-xs text-gray-500">
                Con foto queda respaldado para el informe mensual
              </p>
            </div>
          </button>
        )}

        {abiertos.length > 0 && (
          <section>
            <h2 className="mb-2 text-sm font-bold text-amber-700">
              Mis abiertos ({abiertos.length}) — ciérrelos cuando la medida esté lista
            </h2>
            <ul className="space-y-2">
              {abiertos.map((r) => (
                <li key={r.id} className="rounded-xl border border-amber-200 bg-white p-3">
                  <div className="flex items-center gap-2">
                    <span className="rounded bg-gray-100 px-1.5 py-0.5 text-xs font-bold">{r.tipo_codigo}</span>
                    <span className="min-w-0 flex-1 truncate text-sm font-medium">{r.titulo}</span>
                  </div>
                  <div className="mt-2 flex items-center justify-between">
                    <span className="text-xs text-gray-500">{r.fecha_actividad}</span>
                    <Button size="sm" variant="outline" onClick={() => setCerrandoId(r.id)}>
                      <CheckCircle2 className="mr-1 h-4 w-4" /> Cerrar
                    </Button>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        )}

        <section>
          <h2 className="mb-2 flex items-center gap-1.5 text-sm font-bold text-gray-700">
            <ClipboardList className="h-4 w-4" /> Mis últimos registros
          </h2>
          {isLoading ? (
            <div className="flex justify-center py-8"><Spinner className="h-6 w-6" /></div>
          ) : !registros?.length ? (
            <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
              Todavía no carga registros desde este teléfono.
            </p>
          ) : (
            <ul className="space-y-1.5">
              {registros.map((r) => (
                <li key={r.id} className="flex items-center gap-2 rounded-lg border border-gray-200 bg-white px-3 py-2">
                  <span className="w-20 shrink-0 rounded bg-gray-100 px-1.5 py-0.5 text-center text-xs font-bold">
                    {r.tipo_codigo}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-gray-900">{r.titulo}</p>
                    <p className="text-[11px] text-gray-500">{r.fecha_actividad}</p>
                  </div>
                  {(r.evidencias?.length ?? 0) > 0 && (
                    <span className="flex items-center gap-0.5 text-xs text-gray-400">
                      <Paperclip className="h-3 w-3" />{r.evidencias.length}
                    </span>
                  )}
                  <span className={cn(
                    'shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold',
                    r.estado === 'abierto' ? 'bg-amber-100 text-amber-700' : 'bg-green-100 text-green-700',
                  )}>
                    {r.estado}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </main>

      <Modal open={nuevoOpen} onClose={() => setNuevoOpen(false)}
             title="Nuevo registro" className="max-w-[480px]">
        <RegistroTerrenoForm
          faenaIdInicial={(perfil as any)?.faena_id ?? null}
          onGuardado={() => setNuevoOpen(false)}
          onCancelar={() => setNuevoOpen(false)}
        />
      </Modal>

      <Modal open={!!cerrandoId} onClose={() => setCerrandoId(null)}
             title="Cerrar registro" className="max-w-[480px]">
        <div className="space-y-3">
          <label className="block text-sm font-medium text-gray-700">
            ¿Qué se hizo? (observación de cierre)
          </label>
          <textarea
            className="min-h-[80px] w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            value={obsCierre}
            onChange={(e) => setObsCierre(e.target.value)}
          />
          <div className="flex gap-2">
            <Button className="flex-1" onClick={confirmarCierre} disabled={cerrar.isPending}>
              {cerrar.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Cerrar registro
            </Button>
            <Button variant="outline" onClick={() => setCerrandoId(null)}>Cancelar</Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
