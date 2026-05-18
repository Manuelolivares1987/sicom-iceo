'use client'

import { useState } from 'react'
import { Check, X, Minus, Camera, Upload, AlertCircle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  actualizarItem, subirFotoItem,
  type ChecklistV2Item, type ResultadoItem,
} from '@/lib/services/checklist-v2'

interface Props {
  item: ChecklistV2Item
  instanceId: string
  bloqueado: boolean
  onChange: (updated: ChecklistV2Item) => void
}

export function ChecklistV2ItemRow({ item, instanceId, bloqueado, onChange }: Props) {
  const [saving, setSaving]   = useState(false)
  const [error, setError]     = useState<string | null>(null)
  const [obs, setObs]         = useState(item.observacion ?? '')
  const [valor, setValor]     = useState<string>(item.valor_numerico?.toString() ?? '')
  const [uploadingFoto, setUploadingFoto] = useState(false)

  const persist = async (patch: Partial<ChecklistV2Item>) => {
    setSaving(true); setError(null)
    try {
      await actualizarItem(item.id, patch)
      onChange({ ...item, ...patch })
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  const setResultado = (resultado: ResultadoItem) => persist({ resultado })

  const guardarValorNumerico = async () => {
    const num = valor === '' ? null : Number(valor)
    if (num !== null && Number.isNaN(num)) { setError('Valor no numérico'); return }
    const fueraRango = num !== null &&
      ((item.rango_min != null && num < item.rango_min) ||
       (item.rango_max != null && num > item.rango_max))
    await persist({
      valor_numerico: num,
      resultado: num == null ? 'pendiente' : (fueraRango ? 'no_ok' : 'ok'),
    })
  }

  const guardarObs = () => persist({ observacion: obs })

  const onFotoChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setUploadingFoto(true); setError(null)
    try {
      const url = await subirFotoItem(instanceId, item.id, file)
      await persist({ foto_url: url })
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setUploadingFoto(false)
      e.target.value = ''
    }
  }

  const colorBadge = item.resultado === 'ok' ? 'bg-green-100 text-green-700 border-green-300'
                  : item.resultado === 'no_ok' ? 'bg-red-100 text-red-700 border-red-300'
                  : item.resultado === 'na' ? 'bg-gray-100 text-gray-600 border-gray-300'
                  : 'bg-amber-50 text-amber-700 border-amber-200'

  return (
    <div className={`rounded-lg border p-3 ${item.resultado === 'pendiente' ? 'border-amber-200 bg-amber-50/30' : 'border-gray-200'}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-mono text-gray-500">{item.codigo}</span>
            {item.obligatorio && (
              <span className="rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-semibold text-red-700">
                OBLIGATORIO
              </span>
            )}
            {item.requiere_foto && (
              <span className="rounded bg-blue-100 px-1.5 py-0.5 text-[10px] font-semibold text-blue-700">
                FOTO
              </span>
            )}
            <span className={`rounded border px-2 py-0.5 text-[10px] font-semibold ${colorBadge}`}>
              {item.resultado.toUpperCase()}
            </span>
          </div>
          <div className="mt-1 text-sm">{item.descripcion}</div>
          {item.ayuda && <div className="mt-0.5 text-xs text-gray-500">{item.ayuda}</div>}
        </div>
      </div>

      {/* Input principal según instrumento */}
      <div className="mt-3 space-y-2">
        {/* CHECK / VISUAL / FIRMA — botones SI/NO/NA */}
        {(item.instrumento === 'check' || item.instrumento === 'visual') && (
          <div className="flex gap-2">
            <Button
              size="sm"
              variant={item.resultado === 'ok' ? 'primary' : 'outline'}
              className={item.resultado === 'ok' ? 'bg-green-600 hover:bg-green-700' : ''}
              onClick={() => setResultado('ok')}
              disabled={bloqueado || saving}>
              <Check className="mr-1 h-4 w-4" /> OK
            </Button>
            <Button
              size="sm"
              variant={item.resultado === 'no_ok' ? 'primary' : 'outline'}
              className={item.resultado === 'no_ok' ? 'bg-red-600 hover:bg-red-700' : ''}
              onClick={() => setResultado('no_ok')}
              disabled={bloqueado || saving}>
              <X className="mr-1 h-4 w-4" /> NO OK
            </Button>
            <Button
              size="sm"
              variant={item.resultado === 'na' ? 'primary' : 'outline'}
              onClick={() => setResultado('na')}
              disabled={bloqueado || saving}>
              <Minus className="mr-1 h-4 w-4" /> N/A
            </Button>
          </div>
        )}

        {/* Numerico / instrumentos de medicion */}
        {['numerico','manometro','caudalimetro','profundimetro','termometro','multimetro'].includes(item.instrumento) && (
          <div className="flex items-end gap-2">
            <div className="flex-1">
              <label className="block text-xs text-gray-500">
                Valor medido {item.unidad ? `(${item.unidad})` : ''}
                {item.rango_min != null && ` — min ${item.rango_min}`}
                {item.rango_max != null && ` — max ${item.rango_max}`}
              </label>
              <Input
                type="number"
                step="0.01"
                value={valor}
                onChange={(e) => setValor(e.target.value)}
                onBlur={guardarValorNumerico}
                disabled={bloqueado || saving}
                placeholder="—"
              />
            </div>
            <Button
              size="sm"
              variant="outline"
              onClick={() => setResultado('na')}
              disabled={bloqueado || saving}>
              N/A
            </Button>
          </div>
        )}

        {/* Scanner OBD / muestra lab — observacion libre + OK/NO_OK */}
        {(item.instrumento === 'scanner_obd' || item.instrumento === 'muestra_lab') && (
          <div className="flex gap-2">
            <Button
              size="sm"
              variant={item.resultado === 'ok' ? 'primary' : 'outline'}
              className={item.resultado === 'ok' ? 'bg-green-600 hover:bg-green-700' : ''}
              onClick={() => setResultado('ok')}
              disabled={bloqueado || saving}>
              Realizado / Sin códigos
            </Button>
            <Button
              size="sm"
              variant={item.resultado === 'no_ok' ? 'primary' : 'outline'}
              className={item.resultado === 'no_ok' ? 'bg-red-600 hover:bg-red-700' : ''}
              onClick={() => setResultado('no_ok')}
              disabled={bloqueado || saving}>
              Hallazgo / Con códigos
            </Button>
          </div>
        )}

        {/* Solo foto */}
        {item.instrumento === 'foto' && !item.foto_url && (
          <div className="text-xs text-amber-700">Foto pendiente — capturar abajo</div>
        )}

        {/* Foto (si requiere o instrumento foto) */}
        {(item.requiere_foto || item.instrumento === 'foto') && (
          <div className="flex items-center gap-2">
            <label className="cursor-pointer">
              <input
                type="file"
                accept="image/*"
                capture="environment"
                className="hidden"
                onChange={onFotoChange}
                disabled={bloqueado || uploadingFoto}
              />
              <span className="inline-flex items-center rounded-md border bg-white px-3 py-1.5 text-sm hover:bg-gray-50">
                {uploadingFoto ? <Upload className="mr-1 h-4 w-4 animate-pulse" /> : <Camera className="mr-1 h-4 w-4" />}
                {item.foto_url ? 'Cambiar foto' : 'Capturar foto'}
              </span>
            </label>
            {item.foto_url && (
              <a href={item.foto_url} target="_blank" rel="noopener noreferrer"
                 className="text-xs text-blue-600 underline">Ver foto</a>
            )}
          </div>
        )}

        {/* Observación libre — siempre disponible */}
        <div>
          <textarea
            value={obs}
            onChange={(e) => setObs(e.target.value)}
            onBlur={guardarObs}
            placeholder="Observación (opcional)"
            disabled={bloqueado || saving}
            className="w-full rounded border border-gray-200 px-2 py-1 text-sm focus:border-blue-500 focus:outline-none"
            rows={2}
          />
        </div>

        {error && (
          <div className="flex items-center gap-1 text-xs text-red-600">
            <AlertCircle className="h-3 w-3" /> {error}
          </div>
        )}
      </div>
    </div>
  )
}
