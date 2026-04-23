'use client'

import { useMemo, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import {
  ShieldCheck, AlertTriangle, CheckCircle2, XCircle, MinusCircle,
  PenTool, Camera,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { usePermissions } from '@/hooks/use-permissions'
import { useChecklistOT, useVerificacionPorOT, useAprobarVerificacion } from '@/hooks/use-verificacion'
import { subirFirma } from '@/lib/services/verificacion'
import { supabase } from '@/lib/supabase'
import { cn } from '@/lib/utils'

export default function AprobarVerificacionPage() {
  useRequireAuth()
  const { user, perfil } = useAuth()
  const { canEdit } = usePermissions()
  const { otId } = useParams<{ otId: string }>()
  const router = useRouter()

  const [firmaDataUrl, setFirmaDataUrl] = useState<string | null>(null)
  const [diasVigencia, setDiasVigencia] = useState(3)
  const [motivoRechazo, setMotivoRechazo] = useState('')
  const [saving, setSaving] = useState(false)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  const { data: checklist = [], isLoading: loadingItems } = useChecklistOT(otId)
  const { data: verif, isLoading: loadingVerif } = useVerificacionPorOT(otId)
  const aprobarMut = useAprobarVerificacion()

  const puedeAprobar =
    perfil?.rol === 'administrador' ||
    perfil?.rol === 'jefe_mantenimiento' ||
    perfil?.rol === 'jefe_operaciones' ||
    perfil?.rol === 'supervisor' ||
    canEdit('flota')

  const resumen = useMemo(() => {
    const total = checklist.length
    const ok = checklist.filter((x) => x.resultado === 'ok').length
    const no_ok = checklist.filter((x) => x.resultado === 'no_ok').length
    const na = checklist.filter((x) => x.resultado === 'na').length
    const oblgPend = checklist.filter(
      (x) => x.obligatorio && x.resultado !== 'ok' && x.resultado !== 'na',
    ).length
    return { total, ok, no_ok, na, oblgPend }
  }, [checklist])

  const esMismoTecnico = verif?.verificado_por && user?.id === verif.verificado_por
  const verificacionLista =
    verif &&
    verif.resultado === 'pendiente' &&
    resumen.oblgPend === 0 &&
    verif.horometro_inicial != null &&
    verif.horometro_final != null &&
    verif.road_test_minutos != null

  const hayNoOks = resumen.no_ok > 0

  if (loadingItems || loadingVerif) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  if (!verif) {
    return (
      <Card>
        <CardContent className="py-10 text-center space-y-2">
          <AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" />
          <h3 className="text-lg font-semibold">Verificación no encontrada</h3>
        </CardContent>
      </Card>
    )
  }

  const handleAprobar = async () => {
    if (!otId) return
    setSaving(true)
    setErrorMsg(null)
    try {
      // Subir firma del aprobador
      let firmaAprobadorUrl = verif.firma_aprobador_url
      if (firmaDataUrl) {
        const { data, error } = await subirFirma(otId, 'aprobador', firmaDataUrl)
        if (error) throw error
        firmaAprobadorUrl = data
      }
      if (!firmaAprobadorUrl) throw new Error('Falta firma del aprobador')

      // Llamar al RPC — el RPC valida doble firma, road test, items ok.
      await aprobarMut.mutateAsync({
        ot_id: otId,
        horometro_inicial: Number(verif.horometro_inicial),
        horometro_final: Number(verif.horometro_final),
        km_inicial: verif.km_inicial ?? null,
        km_final: verif.km_final ?? null,
        road_test_minutos: Number(verif.road_test_minutos),
        road_test_observacion: verif.road_test_observacion ?? null,
        firma_tecnico_url: verif.firma_tecnico_url ?? null,
        firma_aprobador_url: firmaAprobadorUrl,
        dias_vigencia: diasVigencia,
      })
      router.push('/dashboard/flota')
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al aprobar')
    } finally {
      setSaving(false)
    }
  }

  const handleRechazar = async () => {
    if (!otId || !motivoRechazo.trim()) {
      setErrorMsg('Ingrese motivo del rechazo.')
      return
    }
    setSaving(true)
    setErrorMsg(null)
    try {
      const { error } = await supabase
        .from('verificaciones_disponibilidad')
        .update({
          resultado: 'rechazado',
          motivo_rechazo: motivoRechazo,
          aprobado_por: user?.id ?? null,
          aprobado_en: new Date().toISOString(),
        })
        .eq('id', verif.id)
      if (error) throw error
      router.push('/dashboard/flota')
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al rechazar')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-4">
      <div className="rounded-xl bg-gradient-to-r from-blue-600 to-indigo-700 p-5 text-white">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold flex items-center gap-2">
              <ShieldCheck className="h-6 w-6" />
              Aprobación Ready-to-Rent
            </h1>
            <p className="text-xs text-white/80 mt-1">
              Revise el checklist, road test y firma del técnico. Su firma como aprobador
              emite el certificado para comercial.
            </p>
          </div>
          <Badge className={cn(
            verif.resultado === 'pendiente' ? 'bg-amber-100 text-amber-800' :
            verif.resultado === 'aprobado' ? 'bg-green-100 text-green-800' :
            'bg-red-100 text-red-800',
          )}>
            {verif.resultado}
          </Badge>
        </div>
      </div>

      {!puedeAprobar && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-700">
          No tienes permiso para aprobar verificaciones. Requiere rol administrador,
          jefe_taller o supervisor.
        </div>
      )}

      {esMismoTecnico && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 flex gap-2">
          <AlertTriangle className="h-5 w-5 shrink-0" />
          <div>
            <strong>Doble firma obligatoria:</strong> tú ejecutaste la verificación.
            Otro usuario con rol de supervisor debe aprobar.
          </div>
        </div>
      )}

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {errorMsg}
        </div>
      )}

      {/* ─── Resumen checklist ─── */}
      <div className="grid grid-cols-4 gap-3">
        <KpiCell label="OK" value={resumen.ok} color="text-green-700" />
        <KpiCell label="NO OK" value={resumen.no_ok} color="text-red-700" />
        <KpiCell label="N/A" value={resumen.na} color="text-gray-500" />
        <KpiCell label="Obligatorios pendientes" value={resumen.oblgPend} color={resumen.oblgPend > 0 ? 'text-amber-700' : 'text-gray-700'} />
      </div>

      {/* ─── Road test ─── */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Road Test</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 md:grid-cols-4 gap-2 text-sm">
          <Info label="Horómetro inicial" value={fmt(verif.horometro_inicial)} />
          <Info label="Horómetro final" value={fmt(verif.horometro_final)} />
          <Info label="Km inicial" value={fmt(verif.km_inicial)} />
          <Info label="Km final" value={fmt(verif.km_final)} />
          <Info label="Duración" value={verif.road_test_minutos ? `${verif.road_test_minutos} min` : '—'} />
          <Info label="Verificado por" value={verif.verificado_por ? 'Técnico firmó' : 'Sin firma'} />
        </CardContent>
        {verif.road_test_observacion && (
          <div className="px-4 pb-4 text-xs text-gray-600 italic">
            "{verif.road_test_observacion}"
          </div>
        )}
      </Card>

      {/* ─── Firma del técnico ─── */}
      {verif.firma_tecnico_url && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <PenTool className="h-4 w-4" />
              Firma del Técnico
            </CardTitle>
          </CardHeader>
          <CardContent>
            <img src={verif.firma_tecnico_url} alt="Firma técnico" className="h-24 object-contain" />
          </CardContent>
        </Card>
      )}

      {/* ─── Items NO OK (foco para aprobador) ─── */}
      {hayNoOks && (
        <Card className="border-red-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-base text-red-700">Items con NO OK ({resumen.no_ok})</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {checklist.filter((x) => x.resultado === 'no_ok').map((it) => (
              <div key={it.id} className="rounded border border-red-200 bg-red-50 p-2 text-sm">
                <div className="flex items-center gap-2">
                  <XCircle className="h-4 w-4 text-red-600" />
                  <strong>#{it.orden}</strong> {it.descripcion}
                </div>
                {it.observacion && (
                  <div className="mt-1 text-xs text-red-800 italic pl-6">"{it.observacion}"</div>
                )}
                {it.foto_url && (
                  <img src={it.foto_url} alt="" className="mt-2 ml-6 h-20 rounded border object-cover" />
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* ─── Checklist completo colapsable ─── */}
      <details className="rounded-lg border border-gray-200 bg-white">
        <summary className="cursor-pointer px-4 py-2 text-sm font-medium text-gray-700">
          Ver checklist completo ({checklist.length} items)
        </summary>
        <div className="max-h-96 overflow-y-auto p-2 space-y-1">
          {checklist.map((it) => (
            <div key={it.id} className="flex items-center gap-2 text-xs border-b py-1">
              {it.resultado === 'ok' && <CheckCircle2 className="h-4 w-4 text-green-600 shrink-0" />}
              {it.resultado === 'no_ok' && <XCircle className="h-4 w-4 text-red-600 shrink-0" />}
              {it.resultado === 'na' && <MinusCircle className="h-4 w-4 text-gray-400 shrink-0" />}
              <span className="w-8 text-gray-400 font-mono">#{it.orden}</span>
              <span className="flex-1">{it.descripcion}</span>
              {it.foto_url && <Camera className="h-3 w-3 text-blue-600" />}
            </div>
          ))}
        </div>
      </details>

      {/* ─── Firma aprobador + acciones ─── */}
      {puedeAprobar && !esMismoTecnico && verif.resultado === 'pendiente' && (
        <>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base flex items-center gap-2">
                <PenTool className="h-4 w-4" />
                Su firma como aprobador
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <SignaturePad onCapture={setFirmaDataUrl} label="Firma Jefe de Taller / Supervisor" />
              <div>
                <label className="text-xs font-medium text-gray-600">Vigencia (días)</label>
                <input
                  type="number" min="1" max="14"
                  className="h-9 w-24 rounded border border-gray-300 px-2 text-sm"
                  value={diasVigencia}
                  onChange={(e) => setDiasVigencia(Number(e.target.value))}
                />
                <span className="ml-2 text-xs text-gray-500">Estándar rental: 3 días (72h)</span>
              </div>
            </CardContent>
          </Card>

          <div className="flex flex-col gap-3">
            <Button
              variant="primary"
              size="lg"
              loading={saving}
              disabled={!verificacionLista || !firmaDataUrl}
              onClick={handleAprobar}
            >
              <ShieldCheck className="h-5 w-5" />
              Aprobar y emitir certificado (vigente {diasVigencia}d)
            </Button>

            {!verificacionLista && (
              <div className="text-xs text-amber-700 text-center">
                {resumen.oblgPend > 0 && `⚠ Hay ${resumen.oblgPend} items obligatorios pendientes. `}
                No se puede aprobar hasta completar el checklist.
              </div>
            )}

            <details className="rounded border border-gray-200 bg-white p-3">
              <summary className="cursor-pointer text-sm text-red-600">Rechazar verificación</summary>
              <div className="mt-2 space-y-2">
                <textarea
                  className="w-full rounded border border-gray-300 p-2 text-sm"
                  placeholder="Motivo del rechazo (obligatorio)"
                  value={motivoRechazo}
                  onChange={(e) => setMotivoRechazo(e.target.value)}
                />
                <Button variant="secondary" onClick={handleRechazar} loading={saving}>
                  Confirmar rechazo
                </Button>
              </div>
            </details>
          </div>
        </>
      )}
    </div>
  )
}

// ─── Subcomponentes ──────────────────────────────────────
function KpiCell({ label, value, color }: { label: string; value: number; color?: string }) {
  return (
    <div className="rounded border bg-white p-3 text-center">
      <div className="text-[10px] uppercase text-gray-500">{label}</div>
      <div className={cn('text-2xl font-bold', color ?? 'text-gray-900')}>{value}</div>
    </div>
  )
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[10px] uppercase text-gray-500">{label}</div>
      <div className="text-sm font-semibold">{value}</div>
    </div>
  )
}

function fmt(v: number | null | undefined): string {
  return v == null ? '—' : String(v)
}
