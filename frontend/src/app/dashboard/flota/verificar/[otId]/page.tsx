'use client'

import { useMemo, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import {
  CheckCircle2, XCircle, MinusCircle, Camera, ChevronRight, ChevronLeft,
  ClipboardCheck, Timer, PenTool, Send, AlertTriangle,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { SignaturePad } from '@/components/ui/signature-pad'
import {
  useChecklistOT, useUpdateChecklistItem,
  useVerificacionPorOT,
} from '@/hooks/use-verificacion'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { supabase } from '@/lib/supabase'
import { subirEvidenciaItem, subirFirma } from '@/lib/services/verificacion'
import { cn } from '@/lib/utils'
import type { ChecklistItemOT } from '@/lib/services/verificacion'

type Step = 1 | 2 | 3 | 4

export default function VerificarOTPage() {
  useRequireAuth()
  const { user } = useAuth()
  const { otId } = useParams<{ otId: string }>()
  const router = useRouter()

  const [step, setStep] = useState<Step>(1)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  // Road test
  const [horoIni, setHoroIni] = useState<string>('')
  const [horoFin, setHoroFin] = useState<string>('')
  const [kmIni, setKmIni] = useState<string>('')
  const [kmFin, setKmFin] = useState<string>('')
  const [minutos, setMinutos] = useState<string>('')
  const [obsPrueba, setObsPrueba] = useState<string>('')

  // Firma
  const [firmaTecnicoDataUrl, setFirmaTecnicoDataUrl] = useState<string | null>(null)

  const { data: checklist = [], isLoading: loadingItems } = useChecklistOT(otId)
  const { data: verif, isLoading: loadingVerif } = useVerificacionPorOT(otId)
  const updateItem = useUpdateChecklistItem()

  // Agrupación por sección
  const grupos = useMemo(() => {
    const map = new Map<string, ChecklistItemOT[]>()
    for (const it of checklist) {
      const sec = it.seccion ?? 'GENERAL'
      if (!map.has(sec)) map.set(sec, [])
      map.get(sec)!.push(it)
    }
    return Array.from(map.entries())
  }, [checklist])

  const resumen = useMemo(() => {
    const total = checklist.length
    const ok = checklist.filter((x) => x.resultado === 'ok').length
    const no_ok = checklist.filter((x) => x.resultado === 'no_ok').length
    const na = checklist.filter((x) => x.resultado === 'na').length
    const pend = total - ok - no_ok - na
    const obligPend = checklist.filter(
      (x) => x.obligatorio && x.resultado !== 'ok' && x.resultado !== 'na',
    ).length
    const noOkObligat = checklist.filter(
      (x) => x.obligatorio && x.resultado === 'no_ok',
    ).length
    return { total, ok, no_ok, na, pend, obligPend, noOkObligat }
  }, [checklist])

  const checklistCompleto = resumen.obligPend === 0 && resumen.noOkObligat === 0
  const roadTestCompleto =
    horoIni && horoFin && minutos &&
    Number(horoFin) > Number(horoIni) && Number(minutos) >= 5

  const setResultado = (it: ChecklistItemOT, r: 'ok' | 'no_ok' | 'na') => {
    updateItem.mutate({ itemId: it.id, otId: otId!, resultado: r })
  }
  const setObservacion = (it: ChecklistItemOT, v: string) => {
    updateItem.mutate({ itemId: it.id, otId: otId!, observacion: v })
  }
  const handleFoto = async (it: ChecklistItemOT, file: File) => {
    try {
      setSaving(true)
      const { data, error } = await subirEvidenciaItem(otId!, it.id, file)
      if (error) throw error
      updateItem.mutate({ itemId: it.id, otId: otId!, foto_url: data })
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al subir foto')
    } finally {
      setSaving(false)
    }
  }

  const enviarAAprobacion = async () => {
    if (!otId || !verif) return
    setSaving(true)
    setErrorMsg(null)
    try {
      // 1. Subir firma del técnico
      let firmaUrl: string | null = verif.firma_tecnico_url
      if (firmaTecnicoDataUrl) {
        const { data, error } = await subirFirma(otId, 'tecnico', firmaTecnicoDataUrl)
        if (error) throw error
        firmaUrl = data
      }
      if (!firmaUrl) throw new Error('Falta firma del técnico')

      // 2. UPDATE directo a verificaciones_disponibilidad con los datos del técnico.
      //    Guardamos road test y firma. El resultado queda 'pendiente' hasta
      //    que el Jefe de Taller apruebe desde /aprobar/[otId].
      const { error: upErr } = await supabase
        .from('verificaciones_disponibilidad')
        .update({
          horometro_inicial: Number(horoIni),
          horometro_final: Number(horoFin),
          km_inicial: kmIni ? Number(kmIni) : null,
          km_final: kmFin ? Number(kmFin) : null,
          road_test_minutos: Number(minutos),
          road_test_observacion: obsPrueba || null,
          firma_tecnico_url: firmaUrl,
          verificado_por: user?.id ?? null,
          fecha_verificacion: new Date().toISOString(),
        })
        .eq('id', verif.id)
      if (upErr) throw upErr

      // 3. Pasar la OT a 'en_ejecucion' o 'ejecutada_con_observaciones' según si hubo no_ok
      //    El aprobador es quien finaliza con 'ejecutada_ok'.
      router.push(`/dashboard/flota`)
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al enviar')
    } finally {
      setSaving(false)
    }
  }

  if (loadingItems || loadingVerif) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  if (!verif || checklist.length === 0) {
    return (
      <Card>
        <CardContent className="py-10 text-center space-y-2">
          <AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" />
          <h3 className="text-lg font-semibold">OT sin checklist</h3>
          <p className="text-sm text-gray-500">
            No se encontró la verificación asociada a esta OT o el checklist está vacío.
          </p>
        </CardContent>
      </Card>
    )
  }

  // ── Progreso global ──
  const stepLabels: Record<Step, string> = {
    1: 'Checklist',
    2: 'Road Test',
    3: 'Firma Técnico',
    4: 'Enviar a Aprobación',
  }

  return (
    <div className="space-y-4">
      {/* Header progreso */}
      <div className="rounded-xl bg-gradient-to-r from-emerald-600 to-teal-600 p-5 text-white">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold flex items-center gap-2">
              <ClipboardCheck className="h-6 w-6" />
              Verificación Ready-to-Rent
            </h1>
            <p className="text-xs text-white/80 mt-1">
              OT en curso. El equipo NO será arrendable hasta que un Jefe de Taller apruebe.
            </p>
          </div>
          <div className="text-right">
            <div className="text-xs text-white/70">Checklist</div>
            <div className="text-lg font-bold">
              {resumen.ok + resumen.na}/{resumen.total}
            </div>
          </div>
        </div>
        <div className="mt-4 flex gap-2">
          {([1, 2, 3, 4] as Step[]).map((s) => (
            <button
              key={s}
              className={cn(
                'flex-1 rounded-md px-2 py-1 text-xs font-medium transition',
                step === s
                  ? 'bg-white text-emerald-700 shadow'
                  : 'bg-white/20 text-white',
              )}
              onClick={() => setStep(s)}
            >
              {s}. {stepLabels[s]}
            </button>
          ))}
        </div>
      </div>

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {errorMsg}
        </div>
      )}

      {/* ═════════ STEP 1 — Checklist ═════════ */}
      {step === 1 && (
        <div className="space-y-4">
          {grupos.map(([seccion, items]) => (
            <Card key={seccion}>
              <CardHeader className="pb-2 bg-gray-50">
                <CardTitle className="text-sm text-gray-700">{seccion}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2 p-3">
                {items.map((it) => (
                  <ItemRow
                    key={it.id}
                    item={it}
                    onResultado={(r) => setResultado(it, r)}
                    onObservacion={(v) => setObservacion(it, v)}
                    onFoto={(f) => handleFoto(it, f)}
                    uploading={saving}
                  />
                ))}
              </CardContent>
            </Card>
          ))}

          <div className="rounded-lg border bg-white p-3 sticky bottom-4 shadow-lg">
            <div className="flex items-center justify-between">
              <div className="text-xs">
                <span className="text-green-700 font-semibold">{resumen.ok}</span>{' '}ok ·{' '}
                <span className="text-red-700 font-semibold">{resumen.no_ok}</span>{' '}no_ok ·{' '}
                <span className="text-gray-500">{resumen.na}</span>{' '}na ·{' '}
                <span className="text-amber-700 font-semibold">{resumen.pend}</span>{' '}pendientes
                {resumen.obligPend > 0 && (
                  <div className="text-amber-700 text-[11px] mt-1">
                    ⚠ {resumen.obligPend} obligatorios pendientes
                  </div>
                )}
              </div>
              <Button
                onClick={() => setStep(2)}
                disabled={!checklistCompleto}
                variant="primary"
              >
                Road Test
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* ═════════ STEP 2 — Road Test ═════════ */}
      {step === 2 && (
        <Card>
          <CardHeader className="flex items-center gap-2">
            <Timer className="h-5 w-5 text-gray-600" />
            <CardTitle className="text-base">Prueba Operativa (Road Test)</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-xs text-gray-500">
              Prueba obligatoria. Mínimo 5 minutos. Registre horómetro de inicio/fin.
              El horómetro final debe ser mayor al inicial.
            </p>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-medium text-gray-600">Horómetro inicial (h)</label>
                <Input type="number" step="0.01" value={horoIni} onChange={(e) => setHoroIni(e.target.value)} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">Horómetro final (h)</label>
                <Input type="number" step="0.01" value={horoFin} onChange={(e) => setHoroFin(e.target.value)} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">Km inicial (opcional)</label>
                <Input type="number" step="1" value={kmIni} onChange={(e) => setKmIni(e.target.value)} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600">Km final (opcional)</label>
                <Input type="number" step="1" value={kmFin} onChange={(e) => setKmFin(e.target.value)} />
              </div>
              <div className="col-span-2">
                <label className="text-xs font-medium text-gray-600">Duración prueba (min) *</label>
                <Input type="number" step="1" min="5" value={minutos} onChange={(e) => setMinutos(e.target.value)} />
              </div>
              <div className="col-span-2">
                <label className="text-xs font-medium text-gray-600">Observaciones</label>
                <textarea
                  className="min-h-[60px] w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
                  value={obsPrueba}
                  onChange={(e) => setObsPrueba(e.target.value)}
                  placeholder="Notas de la prueba: frenos OK, sin ruidos anómalos…"
                />
              </div>
            </div>
            <div className="flex justify-between">
              <Button variant="ghost" onClick={() => setStep(1)}>
                <ChevronLeft className="h-4 w-4" /> Checklist
              </Button>
              <Button variant="primary" onClick={() => setStep(3)} disabled={!roadTestCompleto}>
                Firma
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ═════════ STEP 3 — Firma Técnico ═════════ */}
      {step === 3 && (
        <Card>
          <CardHeader className="flex items-center gap-2">
            <PenTool className="h-5 w-5 text-gray-600" />
            <CardTitle className="text-base">Firma del Técnico</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-xs text-gray-500">
              Dibuje su firma con el mouse o el dedo. Al guardar, se sube como evidencia.
              Un Jefe de Taller DISTINTO a usted deberá aprobar la verificación.
            </p>
            <SignaturePad
              label="Técnico que ejecutó la verificación"
              onCapture={setFirmaTecnicoDataUrl}
            />
            <div className="flex justify-between">
              <Button variant="ghost" onClick={() => setStep(2)}>
                <ChevronLeft className="h-4 w-4" /> Road Test
              </Button>
              <Button variant="primary" onClick={() => setStep(4)} disabled={!firmaTecnicoDataUrl}>
                Resumen
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ═════════ STEP 4 — Resumen + Enviar ═════════ */}
      {step === 4 && (
        <Card>
          <CardHeader className="flex items-center gap-2">
            <Send className="h-5 w-5 text-gray-600" />
            <CardTitle className="text-base">Enviar a Aprobación</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <SummaryBox label="Items OK" value={resumen.ok} color="text-green-700" />
              <SummaryBox label="NO OK" value={resumen.no_ok} color="text-red-700" />
              <SummaryBox label="N/A" value={resumen.na} color="text-gray-500" />
              <SummaryBox label="Total" value={resumen.total} />
              <SummaryBox label="Horómetro" value={`${horoIni} → ${horoFin} h`} />
              <SummaryBox label="Prueba" value={`${minutos} min`} />
            </div>
            {resumen.noOkObligat > 0 && (
              <div className="rounded border border-red-200 bg-red-50 p-2 text-xs text-red-700">
                ⚠ Hay {resumen.noOkObligat} items obligatorios en NO OK. La aprobación será rechazada.
                Corríjalos primero.
              </div>
            )}
            <p className="text-xs text-gray-500">
              Al enviar, la verificación queda "pendiente de aprobación". Un Jefe de Taller
              la revisará y emitirá el certificado o la rechazará.
            </p>
            <div className="flex justify-between">
              <Button variant="ghost" onClick={() => setStep(3)}>
                <ChevronLeft className="h-4 w-4" /> Firma
              </Button>
              <Button
                variant="primary"
                onClick={enviarAAprobacion}
                loading={saving}
                disabled={!firmaTecnicoDataUrl || !checklistCompleto || !roadTestCompleto}
              >
                Enviar a aprobación
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

// ────────────────────────────────────────────────────────
// Componentes internos
// ────────────────────────────────────────────────────────
function ItemRow({
  item, onResultado, onObservacion, onFoto, uploading,
}: {
  item: ChecklistItemOT
  onResultado: (r: 'ok' | 'no_ok' | 'na') => void
  onObservacion: (v: string) => void
  onFoto: (f: File) => void
  uploading: boolean
}) {
  const [obs, setObs] = useState(item.observacion ?? '')
  const needsFoto = item.requiere_foto && !item.foto_url
  const fotoMissingWithOk = item.requiere_foto && item.resultado === 'ok' && !item.foto_url

  return (
    <div className={cn(
      'rounded border p-2 transition',
      item.resultado === 'ok' ? 'border-green-200 bg-green-50/40' :
      item.resultado === 'no_ok' ? 'border-red-200 bg-red-50/40' :
      item.resultado === 'na' ? 'border-gray-200 bg-gray-50/60' :
      'border-gray-200 bg-white',
    )}>
      <div className="flex items-start gap-2">
        <span className="text-xs text-gray-400 font-mono mt-0.5 w-6">#{item.orden}</span>
        <div className="flex-1 text-sm">
          {item.descripcion}
          {item.obligatorio && <span className="ml-1 text-red-500">*</span>}
        </div>
        <div className="flex gap-1 shrink-0">
          <IconBtn
            Icon={CheckCircle2} active={item.resultado === 'ok'}
            color="green" onClick={() => onResultado('ok')} title="OK"
          />
          <IconBtn
            Icon={XCircle} active={item.resultado === 'no_ok'}
            color="red" onClick={() => onResultado('no_ok')} title="NO OK"
          />
          <IconBtn
            Icon={MinusCircle} active={item.resultado === 'na'}
            color="gray" onClick={() => onResultado('na')} title="N/A"
          />
        </div>
      </div>

      {(item.resultado === 'no_ok' || item.requiere_foto) && (
        <div className="mt-2 space-y-1 pl-8">
          {item.resultado === 'no_ok' && (
            <textarea
              className="w-full rounded border border-gray-300 p-1.5 text-xs"
              placeholder="Observación / motivo"
              value={obs}
              onChange={(e) => setObs(e.target.value)}
              onBlur={() => onObservacion(obs)}
            />
          )}
          {item.requiere_foto && (
            <div className="flex items-center gap-2">
              {item.foto_url ? (
                <img src={item.foto_url} alt="Evidencia" className="h-16 w-16 rounded border object-cover" />
              ) : (
                <span className={cn(
                  'text-[11px]',
                  fotoMissingWithOk ? 'text-red-600 font-semibold' : 'text-gray-500',
                )}>
                  {fotoMissingWithOk ? '⚠ Falta foto requerida' : 'Requiere foto'}
                </span>
              )}
              <label className="cursor-pointer">
                <div className="inline-flex items-center gap-1 rounded bg-blue-600 px-2 py-1 text-[11px] text-white hover:bg-blue-700">
                  <Camera className="h-3 w-3" />
                  {item.foto_url ? 'Cambiar' : 'Subir'}
                </div>
                <input
                  type="file"
                  accept="image/*"
                  capture="environment"
                  className="hidden"
                  disabled={uploading}
                  onChange={(e) => {
                    const f = e.target.files?.[0]
                    if (f) onFoto(f)
                  }}
                />
              </label>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function IconBtn({
  Icon, active, color, onClick, title,
}: {
  Icon: React.ComponentType<{ className?: string }>
  active: boolean
  color: 'green' | 'red' | 'gray'
  onClick: () => void
  title: string
}) {
  const colors = {
    green: active ? 'bg-green-600 text-white' : 'text-green-600 hover:bg-green-50',
    red: active ? 'bg-red-600 text-white' : 'text-red-600 hover:bg-red-50',
    gray: active ? 'bg-gray-600 text-white' : 'text-gray-500 hover:bg-gray-100',
  }
  return (
    <button
      title={title}
      onClick={onClick}
      className={cn('rounded p-1 transition', colors[color])}
    >
      <Icon className="h-5 w-5" />
    </button>
  )
}

function SummaryBox({ label, value, color }: { label: string; value: number | string; color?: string }) {
  return (
    <div className="rounded border border-gray-200 p-2 text-center">
      <div className="text-[10px] uppercase text-gray-500">{label}</div>
      <div className={cn('text-lg font-bold', color ?? 'text-gray-900')}>{value}</div>
    </div>
  )
}
