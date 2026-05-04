'use client'

import { useEffect, useState } from 'react'
import { CheckCircle2, XCircle, Lock, Unlock, AlertTriangle } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useCalamaPrecheck, useUpsertPrecheck, useLiberarOT } from '@/hooks/use-calama'
import type { CalamaOTConRelaciones } from '@/lib/services/calama'

const GATES: Array<{
  key: keyof BoolFields
  label: string
  descripcion: string
  category: 'personal' | 'equipo' | 'permiso' | 'preparacion'
}> = [
  { key: 'epp_completo',          label: 'EPP completo / Personal acreditado',  descripcion: 'Personal con EPP requerido y acreditaciones vigentes.',            category: 'personal' },
  { key: 'herramientas_ok',       label: 'Herramientas confirmadas',            descripcion: 'Herramientas necesarias verificadas y operativas.',                 category: 'equipo' },
  { key: 'vehiculo_confirmado',   label: 'Vehiculo confirmado',                 descripcion: 'Vehiculo de transporte/operacion disponible y revisado.',            category: 'equipo' },
  { key: 'permisos_trabajo_ok',   label: 'Permiso de ingreso confirmado',       descripcion: 'Permisos de trabajo y/o ingreso a faena emitidos.',                 category: 'permiso' },
  { key: 'charla_ods_realizada',  label: 'Charla ODS / Ventana de trabajo OK',  descripcion: 'Charla operativa diaria realizada y ventana de trabajo coordinada.', category: 'preparacion' },
]

type BoolFields = {
  epp_completo: boolean
  herramientas_ok: boolean
  vehiculo_confirmado: boolean
  requiere_vehiculo_especial: boolean
  vehiculo_especial_confirmado: boolean
  charla_ods_realizada: boolean
  permisos_trabajo_ok: boolean
}

const DEFAULT_FIELDS: BoolFields = {
  epp_completo: false,
  herramientas_ok: false,
  vehiculo_confirmado: false,
  requiere_vehiculo_especial: false,
  vehiculo_especial_confirmado: false,
  charla_ods_realizada: false,
  permisos_trabajo_ok: false,
}

export function PrecheckPanel({
  ot,
  puedeEditar,
}: {
  ot: CalamaOTConRelaciones
  puedeEditar: boolean
}) {
  const { data: precheck, isLoading } = useCalamaPrecheck(ot.id)
  const upsert = useUpsertPrecheck()
  const liberar = useLiberarOT()

  const [fields, setFields] = useState<BoolFields>(DEFAULT_FIELDS)
  const [observaciones, setObservaciones] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [okMsg, setOkMsg] = useState<string | null>(null)

  useEffect(() => {
    if (precheck) {
      setFields({
        epp_completo: precheck.epp_completo,
        herramientas_ok: precheck.herramientas_ok,
        vehiculo_confirmado: precheck.vehiculo_confirmado,
        requiere_vehiculo_especial: precheck.requiere_vehiculo_especial,
        vehiculo_especial_confirmado: precheck.vehiculo_especial_confirmado,
        charla_ods_realizada: precheck.charla_ods_realizada,
        permisos_trabajo_ok: precheck.permisos_trabajo_ok,
      })
      setObservaciones(precheck.observaciones ?? '')
    } else {
      setFields({
        ...DEFAULT_FIELDS,
        requiere_vehiculo_especial: ot.requiere_vehiculo_especial,
      })
    }
  }, [precheck, ot.requiere_vehiculo_especial])

  const todosOk = computeLiberacion(fields)
  const otYaLiberada = ot.estado !== 'planificada'

  const toggle = (k: keyof BoolFields) => {
    if (!puedeEditar) return
    setFields((prev) => ({ ...prev, [k]: !prev[k] }))
  }

  const handleGuardar = async () => {
    setError(null); setOkMsg(null)
    try {
      await upsert.mutateAsync({ ot_id: ot.id, ...fields, observaciones: observaciones || null })
      setOkMsg('Precheck actualizado.')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al guardar precheck')
    }
  }

  const handleLiberar = async () => {
    setError(null); setOkMsg(null)
    try {
      // Asegurar que el ultimo estado este guardado antes de liberar.
      await upsert.mutateAsync({ ot_id: ot.id, ...fields, observaciones: observaciones || null })
      await liberar.mutateAsync(ot.id)
      setOkMsg('OT liberada para ejecucion.')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al liberar OT')
    }
  }

  const faltantes = GATES.filter((g) => g.key in fields && !fields[g.key as keyof BoolFields])
  const requiereVehEsp = fields.requiere_vehiculo_especial
  const vehEspFaltante = requiereVehEsp && !fields.vehiculo_especial_confirmado

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center justify-between text-base">
          <span className="flex items-center gap-2">
            {todosOk ? <Unlock className="h-4 w-4 text-green-600" /> : <Lock className="h-4 w-4 text-amber-600" />}
            Precheck / Liberacion
          </span>
          <span
            className={`rounded-full px-3 py-0.5 text-xs font-semibold ${
              todosOk ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'
            }`}
          >
            {todosOk ? 'Liberada' : 'Pendiente'}
          </span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {isLoading ? (
          <div className="text-sm text-gray-400">Cargando precheck…</div>
        ) : (
          <>
            <ul className="space-y-2">
              {GATES.map((g) => (
                <li
                  key={g.key}
                  className={`flex items-start gap-3 rounded-lg border p-3 ${
                    fields[g.key] ? 'border-green-200 bg-green-50' : 'border-gray-200 bg-white'
                  }`}
                >
                  <button
                    onClick={() => toggle(g.key)}
                    disabled={!puedeEditar}
                    className="mt-0.5"
                    aria-label={g.label}
                  >
                    {fields[g.key] ? (
                      <CheckCircle2 className="h-5 w-5 text-green-600" />
                    ) : (
                      <XCircle className="h-5 w-5 text-gray-300" />
                    )}
                  </button>
                  <div className="flex-1">
                    <div className="text-sm font-medium text-gray-900">{g.label}</div>
                    <div className="text-xs text-gray-500">{g.descripcion}</div>
                  </div>
                </li>
              ))}

              {/* Vehiculo especial */}
              <li className="rounded-lg border border-gray-200 bg-white p-3">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={fields.requiere_vehiculo_especial}
                    onChange={() => toggle('requiere_vehiculo_especial')}
                    disabled={!puedeEditar}
                  />
                  <span className="font-medium">Requiere vehiculo especial</span>
                </label>
                {fields.requiere_vehiculo_especial && (
                  <label className="mt-2 flex items-center gap-2 text-sm pl-5">
                    <input
                      type="checkbox"
                      checked={fields.vehiculo_especial_confirmado}
                      onChange={() => toggle('vehiculo_especial_confirmado')}
                      disabled={!puedeEditar}
                    />
                    <span>Vehiculo especial confirmado</span>
                  </label>
                )}
              </li>
            </ul>

            <div>
              <label className="text-xs font-semibold text-gray-600 uppercase">Observaciones</label>
              <textarea
                value={observaciones}
                onChange={(e) => setObservaciones(e.target.value)}
                disabled={!puedeEditar}
                rows={2}
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm disabled:bg-gray-50"
                placeholder="Notas del precheck (opcional)"
              />
            </div>

            {!todosOk && (
              <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
                <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
                <div>
                  <p className="font-semibold">Faltan {faltantes.length + (vehEspFaltante ? 1 : 0)} requisitos:</p>
                  <ul className="mt-1 ml-4 list-disc space-y-0.5">
                    {faltantes.map((g) => <li key={g.key}>{g.label}</li>)}
                    {vehEspFaltante && <li>Vehiculo especial confirmado</li>}
                  </ul>
                </div>
              </div>
            )}

            {error && (
              <div className="rounded-lg border border-red-200 bg-red-50 p-2 text-sm text-red-700">{error}</div>
            )}
            {okMsg && (
              <div className="rounded-lg border border-green-200 bg-green-50 p-2 text-sm text-green-700">{okMsg}</div>
            )}

            <div className="flex flex-wrap gap-2 justify-end">
              {puedeEditar && (
                <Button variant="secondary" onClick={handleGuardar} loading={upsert.isPending}>
                  Guardar precheck
                </Button>
              )}
              {puedeEditar && !otYaLiberada && (
                <Button
                  variant="primary"
                  onClick={handleLiberar}
                  disabled={!todosOk}
                  loading={liberar.isPending || upsert.isPending}
                >
                  <Unlock className="h-4 w-4" />
                  Liberar OT
                </Button>
              )}
              {otYaLiberada && (
                <span className="text-xs text-gray-500 self-center">
                  OT en estado <span className="font-mono">{ot.estado}</span> — no requiere liberacion adicional.
                </span>
              )}
            </div>

            {!puedeEditar && (
              <p className="text-xs text-gray-500 text-right">
                Tu rol no permite editar el precheck.
              </p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}

function computeLiberacion(f: BoolFields): boolean {
  return (
    f.epp_completo &&
    f.herramientas_ok &&
    f.vehiculo_confirmado &&
    f.charla_ods_realizada &&
    f.permisos_trabajo_ok &&
    (!f.requiere_vehiculo_especial || f.vehiculo_especial_confirmado)
  )
}
