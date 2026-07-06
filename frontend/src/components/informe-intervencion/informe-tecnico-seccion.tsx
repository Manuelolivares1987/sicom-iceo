'use client'

import { useEffect, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  FileText, Plus, Send, CheckCircle2, XCircle, AlertTriangle, Eye,
  Pencil, FileCheck, Lock, GitBranch, Loader2,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { usePermissions } from '@/hooks/use-permissions'
import {
  getInformePorOt, crearDesdeOt, actualizarBorrador, enviarRevision, observar,
  aprobar, cerrar, crearNuevaVersion, generarYSubirPDF, getSignedPdfUrl,
  type InformeIntervencion, type EstadoInformeIntervencion, type CamposBorradorInforme,
} from '@/lib/services/informe-intervencion'

// Roles que pueden crear/editar el informe (espejo del backend fn_ii_puede('edit')).
const ROLES_EDIT = new Set([
  'administrador', 'subgerente_operaciones', 'jefe_operaciones', 'jefe_mantenimiento',
  'supervisor', 'tecnico_mantenimiento',
])
// Roles que pueden aprobar/observar/cerrar/registrar PDF (fn_ii_puede('approve')).
const ROLES_APPROVE = new Set(['administrador', 'subgerente_operaciones', 'jefe_mantenimiento'])

const ESTADO_META: Record<EstadoInformeIntervencion, { label: string; className: string }> = {
  borrador: { label: 'Borrador', className: 'bg-gray-100 text-gray-700' },
  pendiente_revision: { label: 'Pendiente de revisión', className: 'bg-amber-100 text-amber-800' },
  observado: { label: 'Observado', className: 'bg-orange-100 text-orange-800' },
  aprobado: { label: 'Aprobado', className: 'bg-blue-100 text-blue-800' },
  cerrado: { label: 'Cerrado', className: 'bg-green-100 text-green-800' },
  anulado: { label: 'Anulado', className: 'bg-red-100 text-red-700' },
}

const OT_EJECUTADA_ESTADOS = new Set([
  'ejecutada_ok', 'ejecutada_con_observaciones', 'cerrada',
])

interface Props {
  otId: string
  activoId?: string
  otEstado?: string
}

export function InformeTecnicoSeccion({ otId, otEstado }: Props) {
  const qc = useQueryClient()
  const { rol } = usePermissions()
  const puedeEditar = !!rol && ROLES_EDIT.has(rol)
  const puedeAprobar = !!rol && ROLES_APPROVE.has(rol)

  const { data: informe, isLoading } = useQuery({
    queryKey: ['informe-intervencion', otId],
    queryFn: async () => {
      const { data, error } = await getInformePorOt(otId)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })

  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [ok, setOk] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)
  const [motivoObs, setMotivoObs] = useState('')
  const [showObs, setShowObs] = useState(false)

  function invalidate() {
    qc.invalidateQueries({ queryKey: ['informe-intervencion', otId] })
  }
  function flashOk(msg: string) {
    setOk(msg)
    setTimeout(() => setOk(null), 4000)
  }

  async function run(tag: string, fn: () => Promise<{ error: unknown }>, successMsg: string) {
    setBusy(tag); setError(null); setOk(null)
    try {
      const { error: e } = await fn()
      if (e) throw e
      invalidate()
      flashOk(successMsg)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ocurrió un error')
    } finally {
      setBusy(null)
    }
  }

  async function handleCrear() {
    setBusy('crear'); setError(null)
    try {
      const { data, error: e } = await crearDesdeOt(otId)
      if (e || !data) throw e ?? new Error('No se pudo crear el informe')
      invalidate()
      flashOk('Informe técnico creado desde la OT')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al crear el informe')
    } finally {
      setBusy(null)
    }
  }

  async function handleVerPDF() {
    if (!informe?.pdf_url) return
    setBusy('ver-pdf'); setError(null)
    try {
      const { data, error: e } = await getSignedPdfUrl(informe.pdf_url)
      if (e || !data) throw e ?? new Error('No se pudo obtener el PDF')
      window.open(data, '_blank')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al abrir el PDF')
    } finally {
      setBusy(null)
    }
  }

  async function handleGenerarPDF() {
    if (!informe) return
    setBusy('gen-pdf'); setError(null); setOk(null)
    try {
      const { signedUrl, error: e } = await generarYSubirPDF(informe)
      if (e) throw e
      invalidate()
      flashOk('PDF generado y registrado')
      if (signedUrl) window.open(signedUrl, '_blank')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al generar el PDF')
    } finally {
      setBusy(null)
    }
  }

  async function handleNuevaVersion() {
    if (!informe) return
    const motivo = window.prompt('Motivo de la corrección (obligatorio):')?.trim()
    if (!motivo) return
    setBusy('nueva-version'); setError(null)
    try {
      const { data, error: e } = await crearNuevaVersion(informe.id, motivo)
      if (e || !data) throw e ?? new Error('No se pudo crear la nueva versión')
      invalidate()
      flashOk('Nueva versión creada (borrador)')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al crear la nueva versión')
    } finally {
      setBusy(null)
    }
  }

  return (
    <Card className="mt-4">
      <CardContent className="p-4 sm:p-6">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <FileText className="h-5 w-5 text-pillado-green-600" />
            <h3 className="text-base font-bold text-gray-900">Informe técnico de intervención</h3>
          </div>
          {informe && (
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500">{informe.folio} · v{informe.version}</span>
              <Badge className={ESTADO_META[informe.estado].className}>{ESTADO_META[informe.estado].label}</Badge>
            </div>
          )}
        </div>

        {/* Feedback */}
        {error && (
          <div className="mb-3 flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
            <XCircle className="mt-0.5 h-4 w-4 shrink-0" /> {error}
          </div>
        )}
        {ok && (
          <div className="mb-3 flex items-center gap-2 rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-700">
            <CheckCircle2 className="h-4 w-4 shrink-0" /> {ok}
          </div>
        )}

        {isLoading ? (
          <div className="flex justify-center py-6"><Spinner size="md" className="text-pillado-green-500" /></div>
        ) : !informe ? (
          // ── Inexistente ──────────────────────────────────
          <div className="space-y-3">
            {otEstado && OT_EJECUTADA_ESTADOS.has(otEstado) && (
              <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-700">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                Esta OT está ejecutada y aún no tiene informe técnico. Se recomienda generarlo.
              </div>
            )}
            <p className="text-sm text-gray-500">
              Aún no existe informe técnico para esta orden de trabajo.
            </p>
            {puedeEditar ? (
              <Button variant="primary" onClick={handleCrear} loading={busy === 'crear'}>
                <Plus className="h-4 w-4" /> Crear informe desde la OT
              </Button>
            ) : (
              <p className="text-xs text-gray-400">No tienes permiso para crear el informe técnico.</p>
            )}
          </div>
        ) : (
          // ── Existe ───────────────────────────────────────
          <div className="space-y-4">
            {informe.estado === 'observado' && informe.motivo_correccion && (
              <div className="flex items-start gap-2 rounded-lg border border-orange-200 bg-orange-50 p-3 text-sm text-orange-800">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                <span><strong>Observaciones del revisor:</strong> {informe.motivo_correccion}</span>
              </div>
            )}

            {/* Editor de borrador */}
            {(informe.estado === 'borrador' || informe.estado === 'observado') && puedeEditar && (
              editing ? (
                <BorradorForm
                  informe={informe}
                  saving={busy === 'guardar'}
                  onCancel={() => setEditing(false)}
                  onSave={async (campos) => {
                    await run('guardar', () => actualizarBorrador(informe.id, campos), 'Cambios guardados')
                    setEditing(false)
                  }}
                />
              ) : (
                <Button variant="outline" size="sm" onClick={() => setEditing(true)}>
                  <Pencil className="h-4 w-4" /> Editar borrador
                </Button>
              )
            )}

            {/* Acciones por estado */}
            <div className="flex flex-wrap gap-2">
              {(informe.estado === 'borrador' || informe.estado === 'observado') && puedeEditar && !editing && (
                <Button
                  variant="primary" size="sm"
                  onClick={() => run('enviar', () => enviarRevision(informe.id), 'Enviado a revisión')}
                  loading={busy === 'enviar'}
                >
                  <Send className="h-4 w-4" /> Enviar a revisión
                </Button>
              )}

              {informe.estado === 'pendiente_revision' && puedeAprobar && (
                <>
                  <Button
                    variant="primary" size="sm"
                    onClick={() => run('aprobar', () => aprobar(informe.id), 'Informe aprobado')}
                    loading={busy === 'aprobar'}
                  >
                    <FileCheck className="h-4 w-4" /> Aprobar
                  </Button>
                  <Button variant="secondary" size="sm" onClick={() => setShowObs((v) => !v)}>
                    <Pencil className="h-4 w-4" /> Observar
                  </Button>
                </>
              )}

              {informe.estado === 'pendiente_revision' && !puedeAprobar && (
                <span className="text-xs text-gray-500">En revisión por el jefe de taller.</span>
              )}

              {informe.estado === 'aprobado' && puedeAprobar && (
                <>
                  <Button
                    variant="primary" size="sm"
                    onClick={handleGenerarPDF}
                    loading={busy === 'gen-pdf'}
                  >
                    <FileText className="h-4 w-4" /> {informe.pdf_url ? 'Regenerar PDF' : 'Generar PDF'}
                  </Button>
                  <Button
                    variant="secondary" size="sm"
                    onClick={() => run('cerrar', () => cerrar(informe.id), 'Informe cerrado')}
                    loading={busy === 'cerrar'}
                    disabled={!informe.pdf_url}
                  >
                    <Lock className="h-4 w-4" /> Cerrar informe
                  </Button>
                </>
              )}

              {informe.pdf_url && (
                <Button variant="outline" size="sm" onClick={handleVerPDF} loading={busy === 'ver-pdf'}>
                  <Eye className="h-4 w-4" /> Ver PDF
                </Button>
              )}

              {(informe.estado === 'aprobado' || informe.estado === 'cerrado') && puedeEditar && (
                <Button variant="ghost" size="sm" onClick={handleNuevaVersion} loading={busy === 'nueva-version'}>
                  <GitBranch className="h-4 w-4" /> Crear nueva versión
                </Button>
              )}
            </div>

            {/* Panel de observación */}
            {showObs && informe.estado === 'pendiente_revision' && puedeAprobar && (
              <div className="space-y-2 rounded-lg border border-orange-200 bg-orange-50 p-3">
                <label className="block text-xs font-medium text-orange-800">Motivo de la observación</label>
                <textarea
                  value={motivoObs}
                  onChange={(e) => setMotivoObs(e.target.value)}
                  rows={2}
                  placeholder="Indica qué debe corregirse…"
                  className="w-full rounded-lg border border-orange-300 px-3 py-2 text-sm focus:outline-none"
                />
                <div className="flex gap-2">
                  <Button
                    variant="secondary" size="sm"
                    disabled={!motivoObs.trim()}
                    loading={busy === 'observar'}
                    onClick={async () => {
                      await run('observar', () => observar(informe.id, motivoObs.trim()), 'Informe observado')
                      setMotivoObs(''); setShowObs(false)
                    }}
                  >
                    Devolver con observaciones
                  </Button>
                  <Button variant="ghost" size="sm" onClick={() => setShowObs(false)}>Cancelar</Button>
                </div>
              </div>
            )}

            {busy === 'gen-pdf' && (
              <p className="flex items-center gap-1 text-xs text-gray-500">
                <Loader2 className="h-3 w-3 animate-spin" /> Generando y subiendo el PDF…
              </p>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ── Formulario de borrador ───────────────────────────────

const TEXT_FIELDS: { key: keyof CamposBorradorInforme; label: string; area?: boolean }[] = [
  { key: 'tipo_intervencion', label: 'Tipo de intervención' },
  { key: 'motivo_ingreso', label: 'Motivo de ingreso', area: true },
  { key: 'condicion_ingreso', label: 'Condición de ingreso', area: true },
  { key: 'diagnostico_resumen', label: 'Diagnóstico', area: true },
  { key: 'trabajo_planificado_resumen', label: 'Trabajo planificado', area: true },
  { key: 'trabajo_realizado_resumen', label: 'Trabajo realizado', area: true },
  { key: 'trabajos_pendientes_resumen', label: 'Trabajos pendientes', area: true },
  { key: 'pruebas_resumen', label: 'Pruebas', area: true },
  { key: 'resultado_pruebas', label: 'Resultado de pruebas' },
  { key: 'estado_salida', label: 'Estado de salida' },
  { key: 'restricciones_operacionales', label: 'Restricciones operacionales', area: true },
  { key: 'recomendaciones', label: 'Recomendaciones', area: true },
]

const NUM_FIELDS: { key: keyof CamposBorradorInforme; label: string }[] = [
  { key: 'kilometraje_ingreso', label: 'Km ingreso' },
  { key: 'kilometraje_salida', label: 'Km salida' },
  { key: 'horometro_ingreso', label: 'Horómetro ingreso' },
  { key: 'horometro_salida', label: 'Horómetro salida' },
]

function BorradorForm({
  informe, saving, onSave, onCancel,
}: {
  informe: InformeIntervencion
  saving: boolean
  onSave: (campos: CamposBorradorInforme) => void
  onCancel: () => void
}) {
  const [text, setText] = useState<Record<string, string>>({})
  const [nums, setNums] = useState<Record<string, string>>({})

  useEffect(() => {
    const t: Record<string, string> = {}
    for (const f of TEXT_FIELDS) t[f.key] = (informe[f.key as keyof InformeIntervencion] as string | null) ?? ''
    setText(t)
    const n: Record<string, string> = {}
    for (const f of NUM_FIELDS) {
      const v = informe[f.key as keyof InformeIntervencion] as number | null
      n[f.key] = v == null ? '' : String(v)
    }
    setNums(n)
  }, [informe])

  function handleSubmit() {
    const campos: CamposBorradorInforme = {}
    for (const f of TEXT_FIELDS) {
      ;(campos as Record<string, unknown>)[f.key] = text[f.key] ?? ''
    }
    for (const f of NUM_FIELDS) {
      const raw = nums[f.key]
      if (raw !== undefined && raw !== '') {
        ;(campos as Record<string, unknown>)[f.key] = Number(raw)
      }
    }
    onSave(campos)
  }

  return (
    <div className="space-y-3 rounded-lg border border-gray-200 bg-gray-50 p-3">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        {TEXT_FIELDS.map((f) => (
          <div key={f.key} className={f.area ? 'sm:col-span-2' : ''}>
            <label className="mb-1 block text-xs font-medium text-gray-500">{f.label}</label>
            {f.area ? (
              <textarea
                rows={2}
                value={text[f.key] ?? ''}
                onChange={(e) => setText((p) => ({ ...p, [f.key]: e.target.value }))}
                className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none"
              />
            ) : (
              <input
                type="text"
                value={text[f.key] ?? ''}
                onChange={(e) => setText((p) => ({ ...p, [f.key]: e.target.value }))}
                className="h-9 w-full rounded-lg border border-gray-300 px-3 text-sm focus:border-pillado-green-500 focus:outline-none"
              />
            )}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {NUM_FIELDS.map((f) => (
          <div key={f.key}>
            <label className="mb-1 block text-xs font-medium text-gray-500">{f.label}</label>
            <input
              type="number"
              value={nums[f.key] ?? ''}
              onChange={(e) => setNums((p) => ({ ...p, [f.key]: e.target.value }))}
              className="h-9 w-full rounded-lg border border-gray-300 px-3 text-sm focus:border-pillado-green-500 focus:outline-none"
            />
          </div>
        ))}
      </div>
      <div className="flex gap-2">
        <Button variant="primary" size="sm" onClick={handleSubmit} loading={saving}>
          Guardar cambios
        </Button>
        <Button variant="ghost" size="sm" onClick={onCancel} disabled={saving}>Cancelar</Button>
      </div>
    </div>
  )
}
