'use client'

// ============================================================================
// Ruta publica /equipo/[id]/checklist — sin login, offline-first.
// El operador externo escanea el QR del equipo y completa la inspeccion.
// ============================================================================

import { useEffect, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { Spinner } from '@/components/ui/spinner'
import { ChecklistRenderer } from '@/components/qr/checklist-renderer'
import { ChecklistSyncStatus } from '@/components/qr/checklist-sync-status'
import { ChecklistQualityResult } from '@/components/qr/checklist-quality-result'
import { useOfflineChecklist, useChecklistSyncQueue } from '@/hooks/use-offline-checklist'

export default function ChecklistPublicoPage() {
  const params = useParams()
  const router = useRouter()
  const activoId = params.id as string

  const {
    loading, errorTemplate, template, items, itemsAleatorios, activo,
    checklist, resultado,
    syncing, syncError, online,
    setRespuestaItem, attachFotoItem,
    setOperador, setLecturas, setObservacionGeneral, setFirmaDeclaracion,
    capturarGpsInicial,
    submit, validarPreEnvio,
  } = useOfflineChecklist({ activoId })

  // Sync queue activo en background (procesa pendientes al volver online)
  useChecklistSyncQueue()

  const [mostrandoFaltantes, setMostrandoFaltantes] = useState<string[]>([])
  const [iniciado, setIniciado] = useState(false)

  // Capturar GPS inicial al iniciar el flujo
  const handleIniciar = async () => {
    setIniciado(true)
    await capturarGpsInicial()
  }

  // Submit handler
  const handleSubmit = async () => {
    const { ok, faltantes } = validarPreEnvio()
    if (!ok) {
      setMostrandoFaltantes(faltantes.slice(0, 8))
      window.scrollTo({ top: 0, behavior: 'smooth' })
      return
    }
    setMostrandoFaltantes([])
    await submit()
  }

  // ── Loading / error de carga ──
  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-100">
        <Spinner size="lg" className="text-pillado-green-600" />
      </div>
    )
  }

  if (errorTemplate || !template || !activo || !checklist) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-100 p-4">
        <div className="w-full max-w-md rounded-2xl bg-white p-8 text-center shadow-lg">
          <p className="text-lg font-semibold text-red-500">No se pudo cargar el checklist</p>
          <p className="mt-2 text-sm text-gray-500">{errorTemplate ?? 'Error desconocido'}</p>
          <button
            type="button"
            onClick={() => router.push(`/equipo/${activoId}`)}
            className="mt-6 rounded-lg bg-pillado-green-600 px-4 py-2 text-sm font-semibold text-white"
          >Volver a la ficha del equipo</button>
        </div>
      </div>
    )
  }

  // ── Resultado post-sync ──
  if (resultado) {
    return (
      <div className="min-h-screen bg-gray-100 px-4 py-6">
        <div className="mx-auto max-w-md space-y-4">
          <div className="rounded-2xl bg-white p-5 shadow-lg">
            <p className="text-center text-xs font-bold uppercase tracking-wider text-gray-400">
              Checklist enviado
            </p>
            <p className="mt-1 text-center text-lg font-bold text-gray-900">
              {activo.codigo}
            </p>
          </div>
          <ChecklistQualityResult resultado={resultado} />
          <button
            type="button"
            onClick={() => router.push(`/equipo/${activoId}`)}
            className="w-full rounded-lg bg-pillado-green-600 px-4 py-3 text-sm font-semibold text-white"
          >Volver a la ficha del equipo</button>
        </div>
      </div>
    )
  }

  // ── Pantalla pre-inicio (datos operador + boton iniciar) ──
  if (!iniciado) {
    return (
      <div className="min-h-screen bg-gray-100 px-4 py-6">
        <div className="mx-auto max-w-md space-y-4">
          <div className="rounded-2xl bg-white p-5 shadow-lg">
            <p className="text-center text-xs font-bold uppercase tracking-wider text-gray-400">
              Checklist QR — {template.nombre}
            </p>
            <p className="mt-1 text-center text-lg font-bold text-gray-900">{activo.codigo}</p>
            <p className="text-center text-sm text-gray-600">
              {activo.marca} {activo.modelo}
            </p>
            <p className="mt-3 text-center text-xs text-gray-500">
              Tiempo mínimo de inspección: {template.duracion_minima_segundos}s.
              <br />Ítems: {items.length} + {itemsAleatorios.length} preguntas de control.
            </p>
            {/* Menú del equipo: mismo QR da acceso a ficha y documentación vigente */}
            <div className="mt-3 grid grid-cols-2 gap-2">
              <button type="button" onClick={() => router.push(`/equipo/${activoId}`)}
                      className="rounded-lg border border-gray-300 px-2 py-2 text-xs font-semibold text-gray-600 hover:bg-gray-50">
                Ficha del equipo
              </button>
              <button type="button" onClick={() => router.push(`/equipo/${activoId}/documentos`)}
                      className="rounded-lg border border-pillado-green-600 px-2 py-2 text-xs font-semibold text-pillado-green-600 hover:bg-pillado-green-50">
                📄 Documentación vigente
              </button>
            </div>
          </div>

          <div className="rounded-2xl bg-white p-5 shadow-lg space-y-3">
            <p className="text-sm font-bold text-gray-900">Datos del operador</p>
            <div>
              <label className="block text-xs font-medium text-gray-600">Nombre completo *</label>
              <input
                type="text"
                value={checklist.operador_nombre ?? ''}
                onChange={(e) => setOperador({ operador_nombre: e.target.value })}
                className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-3 text-base"
                placeholder="Nombre y apellido"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-600">RUT</label>
                <input
                  type="text"
                  value={checklist.rut_operador ?? ''}
                  onChange={(e) => setOperador({ rut_operador: e.target.value })}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-3 text-base"
                  placeholder="12345678-9"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600">Teléfono</label>
                <input
                  type="tel"
                  value={checklist.operador_telefono ?? ''}
                  onChange={(e) => setOperador({ operador_telefono: e.target.value })}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-3 text-base"
                  placeholder="+56..."
                />
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600">Empresa</label>
              <input
                type="text"
                value={checklist.operador_empresa ?? ''}
                onChange={(e) => setOperador({ operador_empresa: e.target.value })}
                className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-3 text-base"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-600">Kilometraje</label>
                <input
                  type="number"
                  inputMode="numeric"
                  value={checklist.kilometraje_reportado ?? ''}
                  onChange={(e) => setLecturas(
                    e.target.value === '' ? null : Number(e.target.value),
                    checklist.horometro_reportado
                  )}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-3 text-base"
                  placeholder="km"
                />
                <p className="mt-1 text-[10px] text-gray-400">Actual: {Number(activo.kilometraje_actual).toLocaleString('es-CL')}</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600">Horómetro</label>
                <input
                  type="number"
                  inputMode="numeric"
                  value={checklist.horometro_reportado ?? ''}
                  onChange={(e) => setLecturas(
                    checklist.kilometraje_reportado,
                    e.target.value === '' ? null : Number(e.target.value)
                  )}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-3 text-base"
                  placeholder="hrs"
                />
                <p className="mt-1 text-[10px] text-gray-400">Actual: {Number(activo.horometro_actual).toLocaleString('es-CL')}</p>
              </div>
            </div>
          </div>

          <button
            type="button"
            onClick={handleIniciar}
            disabled={!checklist.operador_nombre || checklist.operador_nombre.trim().length < 2}
            className="w-full rounded-lg bg-pillado-green-600 px-4 py-4 text-base font-bold text-white disabled:bg-gray-300"
          >Iniciar inspección</button>

          <p className="text-center text-[11px] text-gray-500">
            Al iniciar, se solicitará permiso de ubicación (opcional).
          </p>
        </div>
      </div>
    )
  }

  // ── Pantalla principal: render checklist + footer envio ──
  const allItems = [...items, ...itemsAleatorios]

  return (
    <div className="min-h-screen bg-gray-100 px-4 py-4 pb-32">
      <div className="mx-auto max-w-md space-y-4">
        {/* Header sticky */}
        <div className="rounded-xl bg-white p-3 shadow-sm border border-gray-200">
          <p className="text-[11px] font-bold uppercase tracking-wider text-gray-400">{template.nombre}</p>
          <p className="text-base font-bold text-gray-900">{activo.codigo} - {activo.marca} {activo.modelo}</p>
        </div>

        <ChecklistSyncStatus
          estado={checklist.estado}
          online={online}
          syncError={syncError}
          intentos={checklist.intentos_sync}
        />

        {mostrandoFaltantes.length > 0 && (
          <div className="rounded-lg border-2 border-red-300 bg-red-50 p-4">
            <p className="text-sm font-bold text-red-800">Faltan campos obligatorios:</p>
            <ul className="mt-2 list-disc pl-5 text-xs text-red-700 space-y-0.5">
              {mostrandoFaltantes.map((f, i) => <li key={i}>{f}</li>)}
            </ul>
          </div>
        )}

        <ChecklistRenderer
          items={allItems}
          respuestas={checklist.respuestas}
          onRespuesta={setRespuestaItem}
          onFoto={attachFotoItem}
        />

        {/* Observación general */}
        <div className="rounded-lg border bg-white p-4">
          <label className="block text-sm font-semibold text-gray-900">Observación general</label>
          <textarea
            value={checklist.observacion_general ?? ''}
            onChange={(e) => setObservacionGeneral(e.target.value)}
            rows={3}
            placeholder="Comentarios adicionales..."
            className="mt-2 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
          />
        </div>

        {/* Declaracion */}
        <div className="rounded-lg border-2 border-pillado-green-300 bg-pillado-green-50 p-4">
          <label className="flex items-start gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={Boolean(checklist.firma_declaracion && checklist.firma_declaracion.length >= 5)}
              onChange={(e) => setFirmaDeclaracion(
                e.target.checked ? template.declaracion_obligatoria : null
              )}
              className="mt-1 h-5 w-5 rounded border-gray-300 text-pillado-green-600"
            />
            <span className="text-sm font-medium text-pillado-green-900">
              {template.declaracion_obligatoria}
            </span>
          </label>
        </div>

        {/* Footer fixed */}
        <div className="fixed bottom-0 left-0 right-0 border-t border-gray-200 bg-white p-4 shadow-lg z-20">
          <div className="mx-auto max-w-md">
            <button
              type="button"
              onClick={handleSubmit}
              disabled={syncing}
              className="w-full rounded-lg bg-pillado-green-600 px-4 py-4 text-base font-bold text-white disabled:bg-gray-400"
            >
              {syncing ? 'Enviando...' : online ? 'Enviar checklist' : 'Guardar (sin señal)'}
            </button>
            {!online && (
              <p className="mt-1 text-center text-[11px] text-gray-500">
                Se enviará cuando vuelva la señal.
              </p>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
