'use client'

import { useMemo, useState } from 'react'
import {
  ClipboardCheck, AlertTriangle, CheckCircle2, XCircle, MinusCircle,
  ShieldAlert, Users,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import {
  useChequeosCruzadosPendientes, useChequeoCruzadoItems, useResolverChequeoCruzado,
} from '@/hooks/use-control-calidad'
import { subirFirma } from '@/lib/services/verificacion'
import { cn } from '@/lib/utils'

type Res = 'ok' | 'no_ok' | 'na' | 'pendiente'

export default function ChequeoCruzadoPage() {
  useRequireAuth()
  const { user } = useAuth()
  const { data: cola = [], isLoading } = useChequeosCruzadosPendientes(user?.id)
  const [selId, setSelId] = useState<string | null>(null)
  const { data: items = [], isLoading: loadingItems } = useChequeoCruzadoItems(selId ?? undefined)
  const resolver = useResolverChequeoCruzado()

  const [estado, setEstado] = useState<Record<string, { resultado: Res; observacion: string }>>({})
  const [avance, setAvance] = useState<string>('')
  const [obs, setObs] = useState('')
  const [firma, setFirma] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const sel = cola.find((c: any) => c.id === selId)

  const itemState = (id: string): { resultado: Res; observacion: string } =>
    estado[id] ?? { resultado: 'pendiente', observacion: '' }

  const setItem = (id: string, patch: Partial<{ resultado: Res; observacion: string }>) =>
    setEstado((s) => ({ ...s, [id]: { ...itemState(id), ...patch } }))

  const resumen = useMemo(() => {
    let ok = 0, no_ok = 0, na = 0, pendObl = 0
    for (const it of items) {
      const r = itemState(it.id).resultado
      if (r === 'ok') ok++
      else if (r === 'no_ok') no_ok++
      else if (r === 'na') na++
      if (it.obligatorio && r !== 'ok' && r !== 'na') pendObl++
    }
    return { ok, no_ok, na, pendObl, total: items.length }
  }, [items, estado])

  const seleccionar = (id: string) => {
    setSelId(id); setEstado({}); setAvance(''); setObs(''); setFirma(null); setErr(null)
  }

  const enviar = async (resultado: 'aprobado' | 'aprobado_con_obs' | 'rechazado') => {
    if (!selId) return
    if (resultado !== 'rechazado' && resumen.pendObl > 0) {
      setErr('Faltan ítems obligatorios por marcar (OK o N/A).'); return
    }
    setSaving(true); setErr(null)
    try {
      let firmaUrl: string | null = null
      if (firma) {
        const { data, error } = await subirFirma(selId, 'aprobador', firma)
        if (error) throw error
        firmaUrl = data
      }
      await resolver.mutateAsync({
        chequeo_id: selId,
        resultado,
        items: items.map((it) => ({
          id: it.id,
          resultado: itemState(it.id).resultado === 'pendiente' ? 'na' : itemState(it.id).resultado,
          observacion: itemState(it.id).observacion || null,
        })),
        avance_verificado: avance ? Number(avance) : null,
        observaciones: obs || null,
        firma_url: firmaUrl,
      })
      setSelId(null)
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : 'Error al resolver el chequeo')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Users className="h-6 w-6 text-blue-600" /> Chequeo cruzado de fin de turno
        </h1>
        <p className="text-sm text-muted-foreground">
          Verificación independiente del avance del turno. Por segregación de funciones
          (FAA 121.371) no aparecen los trabajos que tú mismo ejecutaste.
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[340px_1fr]">
        {/* Cola */}
        <Card>
          <CardHeader><CardTitle className="text-base">Pendientes ({cola.length})</CardTitle></CardHeader>
          <CardContent className="space-y-2">
            {isLoading && <Spinner className="h-5 w-5" />}
            {!isLoading && cola.length === 0 && (
              <p className="text-sm text-muted-foreground py-6 text-center">
                No hay chequeos cruzados pendientes para ti.
              </p>
            )}
            {cola.map((c: any) => (
              <button
                key={c.id}
                onClick={() => seleccionar(c.id)}
                className={cn(
                  'w-full text-left rounded-lg border p-3 text-sm transition-colors',
                  selId === c.id ? 'border-blue-500 bg-blue-50' : 'hover:bg-muted',
                )}
              >
                <div className="font-semibold">{c.patente ?? c.codigo}</div>
                <div className="text-xs text-muted-foreground">
                  OT {c.folio} · turno {c.turno} · {c.fecha_turno}
                </div>
                <div className="text-xs">Ejecutó: {c.ejecutor_nombre ?? '—'}</div>
                {c.avance_declarado != null && (
                  <div className="text-xs">Avance declarado: {c.avance_declarado}%</div>
                )}
              </button>
            ))}
          </CardContent>
        </Card>

        {/* Detalle */}
        <Card>
          {!sel && (
            <CardContent className="py-16 text-center text-muted-foreground">
              <ClipboardCheck className="h-10 w-10 mx-auto mb-2 opacity-40" />
              Selecciona un chequeo de la cola para verificarlo.
            </CardContent>
          )}
          {sel && (
            <>
              <CardHeader>
                <CardTitle className="text-base flex items-center justify-between">
                  <span>{sel.patente ?? sel.codigo} · OT {sel.folio}</span>
                  <Badge variant="default">
                    {resumen.ok} OK · {resumen.no_ok} NO · {resumen.na} N/A
                  </Badge>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                {loadingItems && <Spinner className="h-5 w-5" />}

                {items.map((it) => {
                  const st = itemState(it.id)
                  return (
                    <div key={it.id} className="rounded-lg border p-3 space-y-2">
                      <div className="flex items-start justify-between gap-3">
                        <div className="text-sm">
                          <span className="font-medium">{it.descripcion}</span>
                          {it.obligatorio && <span className="text-red-500"> *</span>}
                          <Badge variant="default" className="ml-2 text-[10px]">{it.categoria}</Badge>
                        </div>
                        <div className="flex gap-1 shrink-0">
                          <Toggle active={st.resultado === 'ok'} color="green"
                            onClick={() => setItem(it.id, { resultado: 'ok' })}><CheckCircle2 className="h-4 w-4" /></Toggle>
                          <Toggle active={st.resultado === 'no_ok'} color="red"
                            onClick={() => setItem(it.id, { resultado: 'no_ok' })}><XCircle className="h-4 w-4" /></Toggle>
                          <Toggle active={st.resultado === 'na'} color="gray"
                            onClick={() => setItem(it.id, { resultado: 'na' })}><MinusCircle className="h-4 w-4" /></Toggle>
                        </div>
                      </div>
                      {st.resultado === 'no_ok' && (
                        <input
                          className="w-full rounded border px-2 py-1 text-sm"
                          placeholder="Observación / hallazgo (se abrirá No Conformidad)"
                          value={st.observacion}
                          onChange={(e) => setItem(it.id, { observacion: e.target.value })}
                        />
                      )}
                    </div>
                  )
                })}

                <div className="grid gap-3 sm:grid-cols-2">
                  <label className="text-sm">Avance verificado (%)
                    <input type="number" min={0} max={100} value={avance}
                      onChange={(e) => setAvance(e.target.value)}
                      className="mt-1 w-full rounded border px-2 py-1" />
                  </label>
                  <label className="text-sm">Observaciones generales
                    <input value={obs} onChange={(e) => setObs(e.target.value)}
                      className="mt-1 w-full rounded border px-2 py-1" />
                  </label>
                </div>

                <SignaturePad label="Firma del verificador" onCapture={setFirma} />

                {err && (
                  <div className="flex items-center gap-2 text-sm text-red-600">
                    <AlertTriangle className="h-4 w-4" /> {err}
                  </div>
                )}

                <div className="flex flex-wrap gap-2 pt-2">
                  <Button disabled={saving} onClick={() => enviar('aprobado')}>
                    <CheckCircle2 className="h-4 w-4 mr-1" /> Aprobar
                  </Button>
                  <Button variant="outline" disabled={saving} onClick={() => enviar('aprobado_con_obs')}>
                    Aprobar c/observaciones
                  </Button>
                  <Button variant="danger" disabled={saving} onClick={() => enviar('rechazado')}>
                    <ShieldAlert className="h-4 w-4 mr-1" /> Rechazar (abre NCR)
                  </Button>
                </div>
              </CardContent>
            </>
          )}
        </Card>
      </div>
    </div>
  )
}

function Toggle({ active, color, onClick, children }: {
  active: boolean; color: 'green' | 'red' | 'gray'; onClick: () => void; children: React.ReactNode
}) {
  const colors = {
    green: active ? 'bg-green-600 text-white' : 'text-green-600 border-green-300',
    red: active ? 'bg-red-600 text-white' : 'text-red-600 border-red-300',
    gray: active ? 'bg-gray-500 text-white' : 'text-gray-500 border-gray-300',
  }[color]
  return (
    <button type="button" onClick={onClick}
      className={cn('rounded border p-1.5 transition-colors', colors)}>
      {children}
    </button>
  )
}
