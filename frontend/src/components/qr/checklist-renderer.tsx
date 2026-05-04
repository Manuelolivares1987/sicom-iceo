'use client'

// ============================================================================
// Renderer del checklist por secciones. Maneja tipos de respuesta,
// captura de fotos (cámara forzada cuando solo_camara=true), validacion
// inline. Diseñado para terreno: botones grandes, una columna.
// ============================================================================

import { useMemo, useRef } from 'react'
import type {
  ChecklistOfflineRecord,
  QrTemplateItem,
  RespuestaItemLocal,
  TipoRespuesta,
  CriticidadItem,
} from '@/lib/offline/qr-checklist-types'

interface Props {
  items: QrTemplateItem[]
  respuestas: ChecklistOfflineRecord['respuestas']
  onRespuesta: (codigoItem: string, patch: Partial<RespuestaItemLocal>) => void
  onFoto: (codigoItem: string, blob: Blob, origen: 'camera' | 'galeria', mime?: string) => Promise<void>
}

function critBadge(c: CriticidadItem): { text: string; cls: string } | null {
  if (!c) return null
  const map: Record<NonNullable<CriticidadItem>, { text: string; cls: string }> = {
    amarillo: { text: 'Atención', cls: 'bg-yellow-100 text-yellow-800 border-yellow-300' },
    naranja:  { text: 'Riesgo',   cls: 'bg-orange-100 text-orange-800 border-orange-300' },
    rojo:     { text: 'Crítico',  cls: 'bg-red-100 text-red-800 border-red-300' },
  }
  return map[c]
}

function FotoPicker({
  codigoItem, soloCamara, currentBlobId, currentUrl, onFoto,
}: {
  codigoItem: string
  soloCamara: boolean
  currentBlobId: string | null
  currentUrl: string | null
  onFoto: Props['onFoto']
}) {
  const inputRef = useRef<HTMLInputElement | null>(null)
  const tieneFoto = Boolean(currentBlobId || currentUrl)

  const handleChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0]
    if (!f) return
    const origen: 'camera' | 'galeria' = soloCamara ? 'camera' : 'camera'
    await onFoto(codigoItem, f, origen, f.type)
    e.target.value = ''
  }

  return (
    <div className="mt-2">
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        capture={soloCamara ? 'environment' : undefined}
        onChange={handleChange}
        className="hidden"
      />
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        className={`w-full rounded-lg border-2 border-dashed px-4 py-3 text-sm font-medium ${
          tieneFoto ? 'border-pillado-green-500 bg-pillado-green-50 text-pillado-green-700' :
          'border-gray-300 bg-gray-50 text-gray-600 hover:bg-gray-100'
        }`}
      >
        {tieneFoto ? 'Foto adjunta — tomar otra' : (soloCamara ? 'Tomar foto con cámara' : 'Adjuntar foto')}
      </button>
      {soloCamara && (
        <p className="mt-1 text-[11px] text-gray-500">Solo captura por cámara permitida.</p>
      )}
    </div>
  )
}

function ItemRow({
  item, r, onRespuesta, onFoto,
}: {
  item: QrTemplateItem
  r: RespuestaItemLocal
  onRespuesta: Props['onRespuesta']
  onFoto: Props['onFoto']
}) {
  const crit = critBadge(item.criticidad_si_falla)
  const respondido = r.respuesta_valor !== null || r.es_falla || r.es_observacion

  const setEstado = (estado: 'ok' | 'observacion' | 'falla') => {
    onRespuesta(item.codigo_item, {
      respuesta_valor: estado,
      es_falla: estado === 'falla',
      es_observacion: estado === 'observacion',
    })
  }

  const renderBoton = (estado: 'ok' | 'observacion' | 'falla', label: string) => {
    const active =
      (estado === 'falla' && r.es_falla) ||
      (estado === 'observacion' && r.es_observacion) ||
      (estado === 'ok' && r.respuesta_valor === 'ok' && !r.es_falla && !r.es_observacion)
    const colorActive = estado === 'falla' ? 'bg-red-600 text-white border-red-600' :
                        estado === 'observacion' ? 'bg-yellow-500 text-white border-yellow-500' :
                        'bg-pillado-green-600 text-white border-pillado-green-600'
    return (
      <button
        type="button"
        onClick={() => setEstado(estado)}
        className={`flex-1 rounded-lg border-2 py-3 text-sm font-semibold ${
          active ? colorActive : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-50'
        }`}
      >
        {label}
      </button>
    )
  }

  return (
    <div className={`rounded-lg border bg-white p-4 ${
      respondido ? 'border-gray-200' : 'border-gray-300'
    }`}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1">
          <p className="text-sm font-semibold text-gray-900">{item.descripcion}</p>
          <p className="mt-0.5 text-[11px] uppercase tracking-wide text-gray-400">{item.codigo_item}</p>
        </div>
        {crit && (
          <span className={`shrink-0 rounded-full border px-2 py-0.5 text-[10px] font-bold uppercase ${crit.cls}`}>
            {crit.text}
          </span>
        )}
      </div>

      {/* Tipo respuesta */}
      {item.tipo_respuesta === 'ok_obs_falla' || item.tipo_respuesta === 'control_aleatorio' ? (
        <div className="mt-3 flex gap-2">
          {renderBoton('ok', 'OK')}
          {renderBoton('observacion', 'Observación')}
          {renderBoton('falla', 'Falla')}
        </div>
      ) : item.tipo_respuesta === 'si_no' ? (
        <div className="mt-3 flex gap-2">
          <button
            type="button"
            onClick={() => onRespuesta(item.codigo_item, {
              respuesta_valor: 'si', es_falla: false, es_observacion: false,
            })}
            className={`flex-1 rounded-lg border-2 py-3 text-sm font-semibold ${
              r.respuesta_valor === 'si' ? 'bg-pillado-green-600 text-white border-pillado-green-600' :
              'border-gray-300 bg-white text-gray-700'
            }`}
          >Sí</button>
          <button
            type="button"
            onClick={() => onRespuesta(item.codigo_item, {
              respuesta_valor: 'no',
              es_falla: item.criticidad_si_falla !== null,
              es_observacion: false,
            })}
            className={`flex-1 rounded-lg border-2 py-3 text-sm font-semibold ${
              r.respuesta_valor === 'no' ? 'bg-red-600 text-white border-red-600' :
              'border-gray-300 bg-white text-gray-700'
            }`}
          >No</button>
        </div>
      ) : item.tipo_respuesta === 'numerico' ? (
        <input
          type="number"
          step="any"
          min={item.valor_min ?? undefined}
          max={item.valor_max ?? undefined}
          inputMode="decimal"
          placeholder={item.unidad ? `Valor (${item.unidad})` : 'Valor'}
          value={r.respuesta_valor ?? ''}
          onChange={(e) => {
            const val = e.target.value
            const num = val === '' ? null : Number(val)
            const fueraRango = num !== null && (
              (item.valor_min !== null && num < item.valor_min) ||
              (item.valor_max !== null && num > item.valor_max)
            )
            onRespuesta(item.codigo_item, {
              respuesta_valor: val === '' ? null : val,
              es_falla: fueraRango && item.criticidad_si_falla !== null,
              es_observacion: false,
            })
          }}
          className="mt-3 w-full rounded-lg border border-gray-300 px-3 py-3 text-base"
        />
      ) : (
        <textarea
          placeholder="Respuesta"
          value={r.respuesta_valor ?? ''}
          onChange={(e) => onRespuesta(item.codigo_item, { respuesta_valor: e.target.value })}
          rows={2}
          className="mt-3 w-full rounded-lg border border-gray-300 px-3 py-3 text-base"
        />
      )}

      {/* Motivo si es_falla / es_observacion */}
      {(r.es_falla || r.es_observacion) && (
        <textarea
          placeholder={r.es_falla ? 'Describe la falla...' : 'Detalle de la observación...'}
          value={r.motivo ?? ''}
          onChange={(e) => onRespuesta(item.codigo_item, { motivo: e.target.value })}
          rows={2}
          className="mt-2 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
        />
      )}

      {/* Foto */}
      {(item.requiere_foto_siempre || (r.es_falla && item.requiere_foto_si_falla) || item.requiere_foto) && (
        <FotoPicker
          codigoItem={item.codigo_item}
          soloCamara={item.solo_camara}
          currentBlobId={r.foto_blob_id}
          currentUrl={r.foto_url}
          onFoto={onFoto}
        />
      )}

      {/* Hints */}
      {item.requiere_foto_siempre && !r.foto_blob_id && !r.foto_url && (
        <p className="mt-1 text-[11px] text-red-600">Foto obligatoria.</p>
      )}
      {r.es_falla && item.requiere_observacion_si_falla && (!r.motivo || r.motivo.length < 3) && (
        <p className="mt-1 text-[11px] text-red-600">Observación obligatoria por falla.</p>
      )}
    </div>
  )
}

export function ChecklistRenderer({ items, respuestas, onRespuesta, onFoto }: Props) {
  const secciones = useMemo<Array<[string, QrTemplateItem[]]>>(() => {
    const map = new Map<string, QrTemplateItem[]>()
    items.forEach((it) => {
      const arr = map.get(it.seccion) ?? []
      arr.push(it)
      map.set(it.seccion, arr)
    })
    Array.from(map.values()).forEach((arr: QrTemplateItem[]) => {
      arr.sort((a, b) => a.orden - b.orden)
    })
    return Array.from(map.entries())
  }, [items])

  const total = items.length
  const completados = items.filter((i) => {
    const r = respuestas[i.codigo_item]
    return r && (r.respuesta_valor !== null || r.es_falla || r.es_observacion)
  }).length
  const pct = total > 0 ? Math.round((completados / total) * 100) : 0

  return (
    <div className="space-y-5">
      {/* Progreso */}
      <div className="sticky top-0 z-10 rounded-lg bg-white p-3 shadow-sm border border-gray-200">
        <div className="mb-1 flex items-center justify-between text-xs text-gray-600">
          <span className="font-semibold">Progreso checklist</span>
          <span>{completados}/{total} ({pct}%)</span>
        </div>
        <div className="h-2 w-full overflow-hidden rounded-full bg-gray-200">
          <div
            className="h-full bg-pillado-green-600 transition-all"
            style={{ width: `${pct}%` }}
          />
        </div>
      </div>

      {/* Secciones */}
      {secciones.map(([seccion, sectionItems]) => (
        <section key={seccion}>
          <h2 className="mb-2 text-sm font-bold uppercase tracking-wide text-gray-500">
            {seccion}
          </h2>
          <div className="space-y-3">
            {sectionItems.map((item) => {
              const r = respuestas[item.codigo_item]
              if (!r) return null
              return (
                <ItemRow
                  key={item.codigo_item}
                  item={item}
                  r={r}
                  onRespuesta={onRespuesta}
                  onFoto={onFoto}
                />
              )
            })}
          </div>
        </section>
      ))}
    </div>
  )
}

export type { TipoRespuesta }
