'use client'

// ============================================================================
// Vista mantenedor /dashboard/mantencion/equipos/[id]
// Requiere login + rol mantencion (administrador, gerencia, subgerente_operaciones,
// jefe_operaciones, supervisor, planificador, tecnico_mantenimiento, auditor).
// ============================================================================

import { useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useFichaActivo } from '@/hooks/use-activos'
import { EquipoQrCard } from '@/components/qr/equipo-qr-card'
import {
  obtenerHistorialMantencionActivo,
  marcarChecklistRevisado,
  registrarMantencionPreventiva,
  cerrarAlertaTemprana,
  type RegistrarMantencionPayload,
} from '@/lib/services/qr-checklist'

const ROLES_MANTENCION = new Set([
  'administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones',
  'supervisor', 'planificador', 'tecnico_mantenimiento', 'auditor',
  // jefe_mantenimiento no esta en el enum del backend; lo mantenemos por compatibilidad
  'jefe_mantenimiento',
])

interface HistorialResp {
  activo_id: string
  checklists_recientes: Array<{
    id: string; fecha: string; semaforo: string;
    items_falla: number; items_observacion: number;
    operador: string | null; observacion: string | null
  }>
  mantenciones: Array<{
    id: string; fecha: string; tipo: string; descripcion: string;
    costo_total: number | null; kilometraje: number | null;
    horometro: number | null; ot_id: string | null; repuestos_usados: unknown
  }>
  alertas_abiertas: Array<{
    id: string; codigo: string; descripcion: string;
    semaforo: string; estado: string; created_at: string;
    repeticiones_7d: number
  }>
  ordenes_trabajo: Array<{
    id: string; folio: string; tipo: string; estado: string;
    fecha_programada: string | null; created_at: string
  }>
}

function semaforoCls(s: string): string {
  if (s === 'rojo')     return 'bg-red-100 text-red-800 border-red-300'
  if (s === 'naranja')  return 'bg-orange-100 text-orange-800 border-orange-300'
  if (s === 'amarillo') return 'bg-yellow-100 text-yellow-800 border-yellow-300'
  return 'bg-green-100 text-green-800 border-green-300'
}

export default function MantencionEquipoPage() {
  const params = useParams()
  const router = useRouter()
  const activoId = params.id as string
  const { perfil, loading: authLoading } = useRequireAuth()
  const queryClient = useQueryClient()

  const rolValido = perfil?.rol && ROLES_MANTENCION.has(perfil.rol)

  const ficha = useFichaActivo(activoId)
  const historial = useQuery({
    queryKey: ['qr-mantencion-historial', activoId],
    queryFn: async () => {
      const { data, error } = await obtenerHistorialMantencionActivo(activoId)
      if (error) throw error
      return data as HistorialResp
    },
    enabled: !!activoId && !!rolValido,
  })

  const revisar = useMutation({
    mutationFn: async (vars: { respuestaId: string; estado: 'validado' | 'requiere_reinspeccion' | 'sin_hallazgo' | 'escalado'; observacion?: string }) => {
      const { data, error } = await marcarChecklistRevisado(vars.respuestaId, vars.estado, vars.observacion ?? null)
      if (error) throw error
      return data
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['qr-mantencion-historial', activoId] }),
  })

  const cerrarAlerta = useMutation({
    mutationFn: async (vars: { alertaId: string; accion: string }) => {
      const { data, error } = await cerrarAlertaTemprana(vars.alertaId, vars.accion)
      if (error) throw error
      return data
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['qr-mantencion-historial', activoId] }),
  })

  const registrarMant = useMutation({
    mutationFn: async (payload: RegistrarMantencionPayload) => {
      const { data, error } = await registrarMantencionPreventiva(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['qr-mantencion-historial', activoId] }),
  })

  const [mantForm, setMantForm] = useState<RegistrarMantencionPayload>({
    activo_id: activoId,
    tipo: 'preventiva',
    descripcion: '',
  })
  const [mantOpen, setMantOpen] = useState(false)

  if (authLoading || ficha.isLoading || historial.isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Spinner size="lg" className="text-pillado-green-600" />
      </div>
    )
  }

  if (!rolValido) {
    return (
      <div className="p-6 max-w-2xl mx-auto">
        <div className="rounded-lg border-2 border-red-300 bg-red-50 p-4">
          <p className="font-semibold text-red-800">Acceso denegado</p>
          <p className="text-sm text-red-700 mt-1">
            Tu rol ({perfil?.rol ?? 'sin rol'}) no tiene permisos para acceder al módulo de mantención.
          </p>
        </div>
      </div>
    )
  }

  const f = ficha.data as Record<string, unknown> | null
  const h = historial.data

  return (
    <div className="p-4 sm:p-6 max-w-5xl mx-auto space-y-5">
      {/* Header activo */}
      <div className="rounded-2xl bg-white p-5 shadow-sm border">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-[11px] font-bold uppercase tracking-wide text-gray-400">Equipo</p>
            <p className="font-mono text-2xl font-bold text-gray-900">{(f?.codigo as string) ?? '-'}</p>
            <p className="text-sm text-gray-600">
              {(f?.marca_nombre as string) ?? ''} {(f?.modelo_nombre as string) ?? ''}
            </p>
          </div>
          <button
            type="button"
            onClick={() => router.push(`/dashboard/activos/${activoId}`)}
            className="rounded-lg border border-gray-300 px-3 py-2 text-xs font-semibold text-gray-700"
          >Ficha completa</button>
        </div>
      </div>

      {/* QR del equipo para checklist */}
      <EquipoQrCard
        activoId={activoId}
        codigo={(f?.codigo as string) ?? '-'}
        nombre={(f?.nombre as string | null | undefined) ?? null}
        qrPublicoHabilitado={f?.qr_publico_habilitado as boolean | null | undefined}
      />

      {/* Alertas abiertas */}
      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-gray-500 mb-2">
          Alertas abiertas ({h?.alertas_abiertas.length ?? 0})
        </h2>
        {h?.alertas_abiertas.length === 0 ? (
          <p className="text-sm text-gray-500">Sin alertas abiertas.</p>
        ) : (
          <div className="space-y-2">
            {h?.alertas_abiertas.map((a) => (
              <div key={a.id} className={`rounded-lg border-2 px-4 py-3 ${semaforoCls(a.semaforo)}`}>
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1">
                    <p className="text-xs font-mono opacity-70">{a.codigo}</p>
                    <p className="text-sm font-semibold">{a.descripcion}</p>
                    <p className="mt-1 text-[11px] opacity-70">
                      Repeticiones 7d: {a.repeticiones_7d} | {new Date(a.created_at).toLocaleString('es-CL')}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      const accion = window.prompt('Acción / motivo de cierre (mín. 5 caracteres):')
                      if (accion && accion.length >= 5) {
                        cerrarAlerta.mutate({ alertaId: a.id, accion })
                      }
                    }}
                    className="shrink-0 rounded-md bg-white px-3 py-2 text-xs font-semibold border border-current"
                  >Cerrar</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Checklists recientes */}
      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-gray-500 mb-2">
          Checklists recientes ({h?.checklists_recientes.length ?? 0})
        </h2>
        {h?.checklists_recientes.length === 0 ? (
          <p className="text-sm text-gray-500">Sin checklists registrados aún.</p>
        ) : (
          <div className="space-y-2">
            {h?.checklists_recientes.map((c) => (
              <div key={c.id} className="rounded-lg bg-white border border-gray-200 p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <span className={`rounded-full border px-2 py-0.5 text-[10px] font-bold uppercase ${semaforoCls(c.semaforo)}`}>
                        {c.semaforo}
                      </span>
                      <span className="text-xs text-gray-500">
                        {new Date(c.fecha).toLocaleString('es-CL')}
                      </span>
                    </div>
                    <p className="mt-1 text-sm font-semibold text-gray-900">
                      {c.operador ?? 'Sin operador'}
                    </p>
                    <p className="text-[11px] text-gray-500">
                      Fallas: {c.items_falla} | Observaciones: {c.items_observacion}
                    </p>
                    {c.observacion && (
                      <p className="mt-1 text-xs italic text-gray-600">{c.observacion}</p>
                    )}
                  </div>
                  <div className="flex flex-col gap-1">
                    <button
                      type="button"
                      onClick={() => revisar.mutate({ respuestaId: c.id, estado: 'validado' })}
                      className="rounded-md bg-pillado-green-600 px-3 py-1.5 text-[11px] font-semibold text-white"
                    >Validar</button>
                    <button
                      type="button"
                      onClick={() => {
                        const obs = window.prompt('Motivo de reinspección:')
                        if (obs) revisar.mutate({ respuestaId: c.id, estado: 'requiere_reinspeccion', observacion: obs })
                      }}
                      className="rounded-md bg-orange-600 px-3 py-1.5 text-[11px] font-semibold text-white"
                    >Reinspección</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Mantenciones */}
      <section>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="text-sm font-bold uppercase tracking-wide text-gray-500">
            Mantenciones registradas ({h?.mantenciones.length ?? 0})
          </h2>
          <button
            type="button"
            onClick={() => setMantOpen(true)}
            className="rounded-md bg-pillado-green-600 px-3 py-1.5 text-xs font-semibold text-white"
          >Registrar mantención</button>
        </div>
        {h?.mantenciones.length === 0 ? (
          <p className="text-sm text-gray-500">Sin mantenciones aún.</p>
        ) : (
          <div className="space-y-2">
            {h?.mantenciones.map((m) => (
              <div key={m.id} className="rounded-lg bg-white border border-gray-200 p-4">
                <div className="flex items-start justify-between">
                  <div>
                    <Badge>{m.tipo}</Badge>
                    <p className="mt-1 text-xs text-gray-500">
                      {new Date(m.fecha).toLocaleDateString('es-CL')}
                    </p>
                    <p className="mt-1 text-sm font-medium text-gray-900">{m.descripcion}</p>
                    {m.kilometraje !== null && (
                      <p className="text-[11px] text-gray-500 mt-1">
                        KM: {Number(m.kilometraje).toLocaleString('es-CL')}
                        {m.horometro !== null && ` | Horómetro: ${Number(m.horometro).toLocaleString('es-CL')}`}
                      </p>
                    )}
                  </div>
                  {m.costo_total !== null && (
                    <p className="text-sm font-bold text-gray-900">
                      ${Number(m.costo_total).toLocaleString('es-CL')}
                    </p>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* OTs */}
      <section>
        <h2 className="text-sm font-bold uppercase tracking-wide text-gray-500 mb-2">
          Órdenes de trabajo ({h?.ordenes_trabajo.length ?? 0})
        </h2>
        {h?.ordenes_trabajo.length === 0 ? (
          <p className="text-sm text-gray-500">Sin OTs.</p>
        ) : (
          <div className="space-y-2">
            {h?.ordenes_trabajo.map((o) => (
              <div key={o.id} className="rounded-lg bg-white border border-gray-200 p-3 flex items-center justify-between">
                <div>
                  <p className="text-xs font-mono font-bold">{o.folio}</p>
                  <p className="text-[11px] text-gray-500">
                    {o.tipo} | {o.estado}
                    {o.fecha_programada && ` | ${new Date(o.fecha_programada).toLocaleDateString('es-CL')}`}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => router.push(`/dashboard/ordenes-trabajo/${o.id}`)}
                  className="rounded-md border border-gray-300 px-3 py-1.5 text-[11px] font-semibold text-gray-700"
                >Ver</button>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Modal registrar mantencion */}
      {mantOpen && (
        <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4">
          <div className="w-full max-w-md rounded-2xl bg-white p-5 shadow-2xl space-y-3">
            <p className="text-base font-bold">Registrar mantención</p>
            <select
              value={mantForm.tipo}
              onChange={(e) => setMantForm((p) => ({ ...p, tipo: e.target.value as RegistrarMantencionPayload['tipo'] }))}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            >
              <option value="preventiva">Preventiva</option>
              <option value="correctiva">Correctiva</option>
              <option value="inspeccion">Inspección</option>
              <option value="lubricacion">Lubricación</option>
              <option value="otro">Otro</option>
            </select>
            <textarea
              value={mantForm.descripcion}
              onChange={(e) => setMantForm((p) => ({ ...p, descripcion: e.target.value }))}
              placeholder="Descripción (mín. 5 caracteres)"
              rows={3}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <div className="grid grid-cols-2 gap-2">
              <input
                type="number" placeholder="KM"
                value={mantForm.kilometraje_al_momento ?? ''}
                onChange={(e) => setMantForm((p) => ({ ...p, kilometraje_al_momento: e.target.value === '' ? null : Number(e.target.value) }))}
                className="rounded-lg border border-gray-300 px-3 py-2 text-sm"
              />
              <input
                type="number" placeholder="Horómetro"
                value={mantForm.horometro_al_momento ?? ''}
                onChange={(e) => setMantForm((p) => ({ ...p, horometro_al_momento: e.target.value === '' ? null : Number(e.target.value) }))}
                className="rounded-lg border border-gray-300 px-3 py-2 text-sm"
              />
            </div>
            <input
              type="number" placeholder="Costo total (opcional)"
              value={mantForm.costo_total ?? ''}
              onChange={(e) => setMantForm((p) => ({ ...p, costo_total: e.target.value === '' ? null : Number(e.target.value) }))}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <div className="flex gap-2 pt-2">
              <button
                type="button"
                onClick={() => setMantOpen(false)}
                className="flex-1 rounded-lg border border-gray-300 px-4 py-2 text-sm font-semibold"
              >Cancelar</button>
              <button
                type="button"
                disabled={mantForm.descripcion.length < 5 || registrarMant.isPending}
                onClick={async () => {
                  await registrarMant.mutateAsync(mantForm)
                  setMantOpen(false)
                  setMantForm({ activo_id: activoId, tipo: 'preventiva', descripcion: '' })
                }}
                className="flex-1 rounded-lg bg-pillado-green-600 px-4 py-2 text-sm font-semibold text-white disabled:bg-gray-300"
              >Guardar</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
