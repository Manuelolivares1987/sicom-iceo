'use client'

// ============================================================================
// Formulario de entrega de EPP (MIG687) — teléfono y panel
// ----------------------------------------------------------------------------
// Trabajador (del control documental) → faena → elementos con talla y
// cantidad → motivo → instrucción de uso → firma del trabajador.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, Loader2, Minus, Plus, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import { useFaenasPrevencion } from '@/hooks/use-prevencion-reportabilidad'
import {
  MOTIVO_EPP, getCatalogoEpp, getPersonasEpp, registrarEntregaEpp, subirFirmaEpp,
} from '@/lib/services/prevencion-epp'

function hoy() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

type Sel = { cantidad: number, talla: string }

export function EppEntregaForm({ faenaIdInicial, onGuardado, onCancelar }: {
  faenaIdInicial?: string | null
  onGuardado?: (id: string) => void
  onCancelar?: () => void
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: catalogo } = useQuery({ queryKey: ['epp-catalogo'], queryFn: getCatalogoEpp, staleTime: 30 * 60_000 })
  const { data: personas, isLoading: cargandoPersonas } = useQuery({ queryKey: ['epp-personas'], queryFn: getPersonasEpp })
  const { data: faenas } = useFaenasPrevencion()

  const [q, setQ] = useState('')
  const [personaId, setPersonaId] = useState('')
  const [faenaId, setFaenaId] = useState(faenaIdInicial ?? '')
  const [fecha, setFecha] = useState(hoy())
  const [motivo, setMotivo] = useState('reposicion')
  const [instruccion, setInstruccion] = useState(true)
  const [obs, setObs] = useState('')
  const [sel, setSel] = useState<Record<string, Sel>>({})
  const [firma, setFirma] = useState<string | null>(null)
  const [guardando, setGuardando] = useState(false)
  const [clienteUuid] = useState(() => crypto.randomUUID())

  const persona = (personas ?? []).find((p) => p.id === personaId)
  const filtradas = useMemo(() => {
    const t = q.trim().toLowerCase()
    return (personas ?? []).filter((p) => !t || p.nombre.toLowerCase().includes(t) || p.rut.toLowerCase().includes(t)).slice(0, 30)
  }, [personas, q])

  const porCategoria = useMemo(() => {
    const m = new Map<string, NonNullable<typeof catalogo>>()
    for (const c of catalogo ?? []) m.set(c.categoria, [...(m.get(c.categoria) ?? []), c])
    return Array.from(m.entries())
  }, [catalogo])

  const toggle = (codigo: string) => setSel((s) => {
    const n = { ...s }
    if (n[codigo]) delete n[codigo]; else n[codigo] = { cantidad: 1, talla: '' }
    return n
  })

  const guardar = async () => {
    if (!persona) return toast.error('Elija al trabajador')
    if (!faenaId) return toast.error('Elija la faena')
    const items = Object.entries(sel)
    if (!items.length) return toast.error('Marque al menos un elemento entregado')
    const faltaTalla = items.find(([c, v]) => catalogo?.find((x) => x.codigo === c)?.requiere_talla && !v.talla.trim())
    if (faltaTalla) return toast.error(`Indique la talla de: ${catalogo?.find((x) => x.codigo === faltaTalla[0])?.nombre}`)
    if (!firma) return toast.error('Falta la firma: el trabajador firma y se toca «Guardar firma»')
    setGuardando(true)
    try {
      const firma_path = await subirFirmaEpp(firma, faenaId, fecha)
      const id = await registrarEntregaEpp({
        cliente_uuid: clienteUuid,
        personal_id: persona.id, faena_id: faenaId, fecha, motivo,
        instruccion_uso: instruccion, observacion: obs || null, firma_path,
        items: items.map(([epp_codigo, v]) => ({ epp_codigo, cantidad: v.cantidad, talla: v.talla || null })),
      })
      toast.success(`Entrega registrada: ${persona.nombre}`)
      qc.invalidateQueries({ queryKey: ['epp-entregas'] })
      onGuardado?.(id)
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo registrar la entrega')
    } finally {
      setGuardando(false)
    }
  }

  return (
    <div className="space-y-4">
      {/* Trabajador */}
      <div>
        <label className="mb-1.5 block text-sm font-medium text-gray-700">Trabajador</label>
        {persona ? (
          <div className="flex items-center gap-2 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-2">
            <Check className="h-4 w-4 text-emerald-600" />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">{persona.nombre}</p>
              <p className="text-[11px] text-gray-500">
                {persona.rut.startsWith('PEND-') ? 'RUT pendiente' : persona.rut}{persona.faena_codigo ? ` · ${persona.faena_codigo}` : ''}
              </p>
            </div>
            <button className="text-xs text-blue-700 underline" onClick={() => setPersonaId('')}>Cambiar</button>
          </div>
        ) : (
          <>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar por nombre o RUT…" className="pl-9" />
            </div>
            <ul className="mt-1 max-h-52 space-y-1 overflow-y-auto">
              {cargandoPersonas && <li className="py-2 text-center text-xs text-gray-400">Cargando personal…</li>}
              {filtradas.map((p) => (
                <li key={p.id}>
                  <button onClick={() => setPersonaId(p.id)}
                          className="flex w-full items-center gap-2 rounded-lg border border-gray-200 bg-white px-3 py-2 text-left text-sm hover:bg-gray-50">
                    <span className="min-w-0 flex-1 truncate font-medium">{p.nombre}</span>
                    <span className="shrink-0 text-[11px] text-gray-500">{p.faena_codigo ?? ''}</span>
                  </button>
                </li>
              ))}
              {!cargandoPersonas && !filtradas.length && (
                <li className="py-2 text-center text-xs text-gray-500">
                  No aparece: hay que darlo de alta en Control documental personal.
                </li>
              )}
            </ul>
          </>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2">
        <Select label="Faena" value={faenaId} onChange={(e) => setFaenaId(e.target.value)} placeholder="Elegir faena…"
                options={(faenas ?? []).map((f: any) => ({ value: f.id, label: f.nombre }))} />
        <Input label="Fecha" type="date" value={fecha} max={hoy()} onChange={(e) => setFecha(e.target.value)} />
      </div>

      <Select label="Motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)}
              options={Object.entries(MOTIVO_EPP).map(([v, l]) => ({ value: v, label: l }))} />

      {/* Elementos */}
      <div>
        <label className="mb-1.5 block text-sm font-medium text-gray-700">
          Elementos entregados ({Object.keys(sel).length})
        </label>
        <div className="space-y-2">
          {porCategoria.map(([cat, items]) => (
            <div key={cat}>
              <p className="mb-1 text-[11px] font-bold uppercase text-gray-500">{cat}</p>
              <div className="space-y-1">
                {items.map((c) => {
                  const s = sel[c.codigo]
                  return (
                    <div key={c.codigo} className={cn('rounded-lg border px-2.5 py-1.5', s ? 'border-pillado-green-500 bg-pillado-green-50' : 'border-gray-200 bg-white')}>
                      <button type="button" onClick={() => toggle(c.codigo)} className="flex w-full items-center gap-2 text-left text-sm">
                        <span className={cn('grid h-5 w-5 shrink-0 place-items-center rounded border-2', s ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-300')}>
                          {s && <Check className="h-3.5 w-3.5" />}
                        </span>
                        <span className="flex-1">{c.nombre}</span>
                      </button>
                      {s && (
                        <div className="mt-1.5 flex items-center gap-2 pl-7">
                          <div className="flex items-center rounded-md border border-gray-300 bg-white">
                            <button type="button" className="p-1" onClick={() => setSel((x) => ({ ...x, [c.codigo]: { ...s, cantidad: Math.max(1, s.cantidad - 1) } }))}><Minus className="h-3.5 w-3.5" /></button>
                            <span className="w-7 text-center text-sm font-semibold">{s.cantidad}</span>
                            <button type="button" className="p-1" onClick={() => setSel((x) => ({ ...x, [c.codigo]: { ...s, cantidad: s.cantidad + 1 } }))}><Plus className="h-3.5 w-3.5" /></button>
                          </div>
                          {c.requiere_talla && (
                            <input value={s.talla} placeholder="Talla"
                                   onChange={(e) => setSel((x) => ({ ...x, [c.codigo]: { ...s, talla: e.target.value } }))}
                                   className="h-8 w-24 rounded-md border border-gray-300 px-2 text-sm" />
                          )}
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
            </div>
          ))}
        </div>
      </div>

      <label className="flex items-start gap-2 rounded-lg border border-blue-200 bg-blue-50 p-3 text-sm text-blue-900">
        <input type="checkbox" className="mt-0.5 h-4 w-4" checked={instruccion} onChange={(e) => setInstruccion(e.target.checked)} />
        Se instruyó al trabajador sobre el uso, cuidado y mantención de los elementos (DS 44 art. 13).
      </label>

      <div>
        <label className="mb-1 block text-sm font-medium text-gray-700">Observación</label>
        <textarea className="min-h-[50px] w-full rounded-lg border border-gray-300 px-2.5 py-1.5 text-sm"
                  value={obs} onChange={(e) => setObs(e.target.value)} />
      </div>

      <div>
        <p className="mb-1 text-[12px] text-gray-600">
          {persona ? <>Firma de <b>{persona.nombre}</b>: declara recibir los elementos en buen estado.</> : 'Firma del trabajador'}
        </p>
        <SignaturePad label="Firma del trabajador" onCapture={(d) => setFirma(d)} />
        {firma && <p className="mt-1 text-[11px] font-medium text-emerald-700">Firma capturada ✓</p>}
      </div>

      <div className="flex gap-2">
        <Button className="flex-1" onClick={guardar} disabled={guardando}>
          {guardando && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Registrar entrega
        </Button>
        {onCancelar && <Button variant="outline" onClick={onCancelar} disabled={guardando}>Cancelar</Button>}
      </div>
    </div>
  )
}
