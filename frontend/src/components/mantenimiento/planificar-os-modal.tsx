'use client'

// [MIG498] Planificar la Orden de Servicio desde la bandeja de NC.
//
// El flujo que pidió Manuel (03-09): el jefe analiza las NC del equipo y les
// aprueba los repuestos; DESPUÉS selecciona las NC y arma la OS — quién la
// ejecuta (puede ser de a pares) y cuánto tiempo debe demorar. Esa OS le llega
// al mecánico a su teléfono (/m/taller, «Mi trabajo») con el reloj corriendo
// contra el tiempo asignado.
//
// La OT correctiva del equipo se asegura sola por dentro (se reutiliza la
// abierta): el jefe no tiene que pensar en la OT, piensa en el trabajo.

import { useMemo, useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Clock, ImageOff, Loader2, Users, Wrench } from 'lucide-react'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { useToast } from '@/contexts/toast-context'
import { getTallerTecnicos } from '@/lib/services/taller-plan-semanal'
import { planificarOsDesdeNc } from '@/lib/services/taller-os'
import type { NcRecepcion } from '@/lib/services/no-conformidades'

export function PlanificarOsModal({ patente, ncs, onClose, onDone }: {
  patente: string
  ncs: NcRecepcion[]
  onClose: () => void
  onDone: () => void
}) {
  const toast = useToast()
  const { data: tecnicos = [] } = useQuery({
    queryKey: ['taller-tecnicos-activos'], queryFn: () => getTallerTecnicos(), staleTime: 300_000,
  })

  // Solo lo que todavía se puede trabajar. Si una NC ya vive en otra OS, el
  // servidor lo dice con nombre y apellido al intentar.
  const elegibles = useMemo(
    () => ncs.filter((nc) => !['resuelta', 'descartada'].includes(nc.estado_planificacion)),
    [ncs],
  )

  const [sel, setSel] = useState<Set<string>>(() => new Set(elegibles.map((n) => n.id)))
  const [quienes, setQuienes] = useState<string[]>([])
  const [horas, setHoras] = useState('')
  const [titulo, setTitulo] = useState(`Corrección NC · ${patente}`)
  // [MIG475] Si la suma de OS pasa el techo del planificador, el servidor pide
  // explicar por qué en vez de crear a medias.
  const [motivoTecho, setMotivoTecho] = useState<string | null>(null)
  const [justificacion, setJustificacion] = useState('')

  const toggleNc = (id: string) =>
    setSel((p) => { const n = new Set(p); if (n.has(id)) n.delete(id); else n.add(id); return n })
  const toggleTec = (id: string) =>
    setQuienes((p) => p.includes(id) ? p.filter((x) => x !== id) : [...p, id])

  const crear = useMutation({
    mutationFn: () => planificarOsDesdeNc({
      ncIds: Array.from(sel),
      tecnicoIds: quienes,
      horas: Number(horas),
      titulo: titulo.trim() || null,
      justificacion: justificacion.trim() || null,
    }),
    onSuccess: (r) => {
      if (r.requiere_justificacion) {
        setMotivoTecho(r.motivo ?? 'La suma de OS pasa el techo de horas del planificador: explica por qué.')
        return
      }
      const avisos = (r.avisos ?? []).filter(Boolean)
      toast.success(`OS ${r.folio} creada: ${sel.size} NC · ${quienes.length} técnico${quienes.length > 1 ? 's' : ''} · ${horas} h.`
        + ' Le llega al mecánico a su teléfono.')
      for (const a of avisos) toast.success(a)
      onDone()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const puedeCrear = sel.size > 0 && quienes.length > 0 && Number(horas) > 0
    && (!motivoTecho || justificacion.trim().length >= 10)

  return (
    <Modal open onClose={onClose} title={`Planificar OS · ${patente}`} className="sm:max-w-2xl">
      <div className="space-y-3">
        <p className="text-xs text-gray-500">
          Elige las NC que se resuelven juntas, quién las ejecuta y cuánto debe demorar.
          La OS le llega al mecánico a su teléfono y su reloj corre contra ese tiempo.
        </p>

        {/* ── Qué se va a trabajar ── */}
        <div>
          <p className="text-xs font-semibold text-gray-700">No conformidades ({sel.size} de {elegibles.length} elegidas)</p>
          <div className="mt-1.5 max-h-56 space-y-1 overflow-y-auto pr-1">
            {elegibles.map((nc) => {
              const on = sel.has(nc.id)
              return (
                <label key={nc.id}
                       className={`flex cursor-pointer items-center gap-2 rounded-lg border p-2 ${
                         on ? 'border-orange-300 bg-orange-50/60' : 'border-gray-200 bg-white'}`}>
                  <input type="checkbox" checked={on} onChange={() => toggleNc(nc.id)}
                         className="h-4 w-4 shrink-0 cursor-pointer" />
                  {nc.foto_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={nc.foto_url} alt="Evidencia" loading="lazy"
                         className="h-9 w-9 shrink-0 rounded border object-cover" />
                  ) : (
                    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded border border-dashed border-gray-300 text-gray-300">
                      <ImageOff className="h-3.5 w-3.5" />
                    </span>
                  )}
                  <span className="min-w-0 flex-1 text-xs text-gray-800">{nc.descripcion}</span>
                  <Badge variant={nc.severidad as never} className="shrink-0 text-[10px]">{nc.severidad}</Badge>
                </label>
              )
            })}
            {elegibles.length === 0 && (
              <p className="rounded border border-dashed border-gray-300 p-3 text-center text-xs text-gray-400">
                Este equipo no tiene NC pendientes de trabajar.
              </p>
            )}
          </div>
        </div>

        {/* ── Quién la ejecuta ── */}
        <div>
          <p className="flex items-center gap-1 text-xs font-semibold text-gray-700">
            <Users className="h-3.5 w-3.5" /> Quién la ejecuta (uno, o de a pares)
          </p>
          <div className="mt-1.5 flex flex-wrap gap-1">
            {tecnicos.map((t) => {
              const on = quienes.includes(t.id)
              return (
                <button key={t.id} type="button" onClick={() => toggleTec(t.id)} title={t.especialidad || undefined}
                        className={`rounded border px-2 py-1 text-[11px] ${
                          on ? 'border-blue-500 bg-blue-500 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>
                  {t.nombre}
                  {t.especialidad && <span className={`ml-1 text-[9px] ${on ? 'text-blue-100' : 'text-gray-400'}`}>{t.especialidad}</span>}
                </button>
              )
            })}
          </div>
          <p className="mt-1 text-[10px] text-gray-500">
            Si alguno está en otra OS ahora mismo, se le saca de ahí (su reloj se cierra y queda el motivo escrito).
          </p>
        </div>

        {/* ── Cuánto debe demorar ── */}
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs font-medium">
            <span className="flex items-center gap-1"><Clock className="h-3.5 w-3.5" /> Tiempo asignado (horas)</span>
            <input type="number" inputMode="decimal" min="0" step="0.5" value={horas}
                   onChange={(e) => setHoras(e.target.value)}
                   placeholder="ej: 4"
                   className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
          </label>
          <label className="text-xs font-medium">
            Título (lo lee el mecánico)
            <input value={titulo} onChange={(e) => setTitulo(e.target.value)}
                   className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
          </label>
        </div>

        {/* ── El techo del planificador pide explicación ── */}
        {motivoTecho && (
          <div className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2">
            <p className="text-xs font-medium text-amber-900">{motivoTecho}</p>
            <textarea rows={2} value={justificacion} onChange={(e) => setJustificacion(e.target.value)}
                      placeholder="Por qué esta visita necesita más horas (mínimo 10 caracteres)…"
                      className="mt-1.5 w-full rounded border border-amber-300 px-2 py-1.5 text-sm" />
          </div>
        )}
      </div>

      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={crear.isPending}>Cancelar</Button>
        <Button onClick={() => crear.mutate()} disabled={!puedeCrear || crear.isPending}>
          {crear.isPending ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Wrench className="h-4 w-4 mr-1" />}
          Crear la OS y asignarla
        </Button>
      </ModalFooter>
    </Modal>
  )
}
