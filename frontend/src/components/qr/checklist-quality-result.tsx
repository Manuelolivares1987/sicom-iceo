'use client'

// ============================================================================
// Resultado del checklist al server: semaforo + score calidad + alertas.
// Mensaje claro al operador (no expone detalles internos sensibles).
// ============================================================================

import type {
  ClasificacionCalidad,
  GuardarChecklistResponse,
  SemaforoTecnico,
} from '@/lib/offline/qr-checklist-types'

interface Props {
  resultado: GuardarChecklistResponse
}

function semaforoStyle(s: SemaforoTecnico): { label: string; cls: string; dot: string } {
  switch (s) {
    case 'rojo':     return { label: 'CRÍTICO',  cls: 'bg-red-50 text-red-800 border-red-400',           dot: 'bg-red-600' }
    case 'naranja':  return { label: 'RIESGO',   cls: 'bg-orange-50 text-orange-800 border-orange-400',  dot: 'bg-orange-500' }
    case 'amarillo': return { label: 'ATENCIÓN', cls: 'bg-yellow-50 text-yellow-800 border-yellow-400',  dot: 'bg-yellow-500' }
    case 'verde':    return { label: 'OK',       cls: 'bg-pillado-green-50 text-pillado-green-800 border-pillado-green-400', dot: 'bg-pillado-green-600' }
  }
}

function calidadStyle(c: ClasificacionCalidad): { label: string; cls: string } {
  switch (c) {
    case 'alta':       return { label: 'Calidad alta',       cls: 'bg-pillado-green-100 text-pillado-green-800' }
    case 'media':      return { label: 'Calidad media',      cls: 'bg-yellow-100 text-yellow-800' }
    case 'baja':       return { label: 'Calidad baja',       cls: 'bg-orange-100 text-orange-800' }
    case 'sospechoso': return { label: 'Revisión requerida', cls: 'bg-red-100 text-red-800' }
  }
}

export function ChecklistQualityResult({ resultado }: Props) {
  const sem = semaforoStyle(resultado.semaforo)
  const cal = calidadStyle(resultado.clasificacion_calidad)
  const duracionFmt = `${Math.floor(resultado.duracion_segundos / 60)}m ${resultado.duracion_segundos % 60}s`

  return (
    <div className="space-y-4">
      {/* Semaforo tecnico */}
      <div className={`rounded-2xl border-2 px-5 py-5 ${sem.cls}`}>
        <div className="flex items-center gap-3">
          <span className={`h-5 w-5 rounded-full ${sem.dot}`} />
          <div className="flex-1">
            <p className="text-xs font-bold uppercase tracking-wide opacity-70">Estado técnico</p>
            <p className="text-2xl font-extrabold">{sem.label}</p>
          </div>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-3 text-sm">
          <div>
            <p className="text-[11px] uppercase opacity-60">Ítems con falla</p>
            <p className="text-lg font-bold">{resultado.items_falla}</p>
          </div>
          <div>
            <p className="text-[11px] uppercase opacity-60">Observaciones</p>
            <p className="text-lg font-bold">{resultado.items_observacion}</p>
          </div>
        </div>
        {resultado.alertas_tecnicas_generadas > 0 && (
          <p className="mt-3 text-xs">
            Se generaron {resultado.alertas_tecnicas_generadas} alerta(s) técnica(s) que el equipo de mantención revisará.
          </p>
        )}
      </div>

      {/* Calidad del checklist */}
      <div className="rounded-2xl border-2 border-gray-200 bg-white px-5 py-5">
        <p className="text-xs font-bold uppercase tracking-wide text-gray-500">Calidad del checklist</p>
        <div className="mt-2 flex items-end gap-3">
          <p className="text-4xl font-extrabold text-gray-900">{resultado.score_calidad}</p>
          <p className="text-sm text-gray-500 pb-1">/ 100</p>
        </div>
        <span className={`mt-2 inline-block rounded-full px-3 py-1 text-xs font-semibold ${cal.cls}`}>
          {cal.label}
        </span>
        <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
          <div>
            <p className="text-gray-500">Duración</p>
            <p className="font-semibold text-gray-900">{duracionFmt}</p>
          </div>
          <div>
            <p className="text-gray-500">Mínimo esperado</p>
            <p className="font-semibold text-gray-900">{resultado.duracion_minima_segundos}s</p>
          </div>
        </div>

        {resultado.alertas_calidad_generadas > 0 && (
          <div className="mt-3 rounded-lg bg-yellow-50 border border-yellow-300 px-3 py-2">
            <p className="text-xs font-bold text-yellow-800">
              {resultado.alertas_calidad_generadas} alerta(s) de calidad generada(s)
            </p>
            <p className="mt-1 text-[11px] text-yellow-700">
              El equipo de mantención revisará este checklist.
            </p>
          </div>
        )}

        {resultado.sospechoso && (
          <div className="mt-3 rounded-lg bg-red-50 border border-red-300 px-3 py-2">
            <p className="text-xs font-bold text-red-800">Revisión requerida</p>
            <p className="mt-1 text-[11px] text-red-700">
              Este checklist requiere revisión por el equipo de mantención.
            </p>
          </div>
        )}
      </div>

      {/* Mensaje motivacional para operador */}
      <div className="rounded-lg bg-gray-50 px-4 py-3 text-center text-sm text-gray-600">
        {resultado.semaforo === 'rojo' ? (
          <p>
            <strong className="text-red-700">No operar el equipo</strong> hasta validación del responsable de mantención.
          </p>
        ) : resultado.semaforo === 'naranja' ? (
          <p>
            Operar con precaución. Reportar al supervisor las observaciones encontradas.
          </p>
        ) : resultado.semaforo === 'amarillo' ? (
          <p>
            Equipo operativo con observaciones menores. Programar revisión.
          </p>
        ) : (
          <p>Equipo en condiciones operativas. Buen trabajo.</p>
        )}
      </div>
    </div>
  )
}
