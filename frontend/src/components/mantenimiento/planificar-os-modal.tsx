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

export function PlanificarOsModal({ patente, ncs, preSeleccion, onClose, onDone }: {
  patente: string
  ncs: NcRecepcion[]
  /** NC marcadas con el check de la tabla: el modal parte con esas elegidas. */
  preSeleccion?: string[]
  onClose: () => void
  onDone: () => void
}) {
  const toast = useToast()
  const { data: tecnicos = [] } = useQuery({
    queryKey: ['taller-tecnicos-activos'], queryFn: () => getTallerTecnicos(), staleTime: 300_000,
  })

  // Solo lo que todavía se puede trabajar. Una NC vive en UNA OS: la que ya
  // tiene una no se vuelve a ofrecer (MIG499 expone os_folio en la bandeja).
  const elegibles = useMemo(
    () => ncs.filter((nc) => !['resuelta', 'descartada'].includes(nc.estado_planificacion) && !nc.os_id),
    [ncs],
  )

  const [sel, setSel] = useState<Set<string>>(() => {
    const pre = (preSeleccion ?? []).filter((id) => elegibles.some((n) => n.id === id))
    return new Set(pre.length ? pre : elegibles.map((n) => n.id))
  })
  const [quienes, setQuienes] = useState<string[]>([])
  const [horas, setHoras] = useState('')
  // [MIG507] Planificar ES ponerle día: obligatorio, y no puede ser pasado.
  const [fecha, setFecha] = useState('')
  const hoy = new Date().toISOString().slice(0, 10)
  const [titulo, setTitulo] = useState(`Corrección NC · ${patente}`)
  // [MIG499] «Incluso puede existir una OS para un externo»: sin técnicos
  // nuestros, con proveedor y motivo. La autoriza gerencia y no paga bono.
  const [externo, setExterno] = useState(false)
  const [proveedor, setProveedor] = useState('')
  const [motivoExterno, setMotivoExterno] = useState('')
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
      tecnicoIds: externo ? [] : quienes,
      horas: Number(horas),
      fechaProgramada: fecha,
      titulo: titulo.trim() || null,
      justificacion: justificacion.trim() || null,
      externo,
      proveedor: externo ? proveedor.trim() || null : null,
      motivoExterno: externo ? motivoExterno.trim() || null : null,
    }),
    onSuccess: (r) => {
      if (r.requiere_justificacion) {
        setMotivoTecho(r.motivo ?? 'La suma de OS pasa el techo de horas del planificador: explica por qué.')
        return
      }
      const avisos = (r.avisos ?? []).filter(Boolean)
      toast.success(externo
        ? `OS ${r.folio} creada para ${proveedor.trim()}: falta que gerencia la autorice.`
        : `OS ${r.folio} creada: ${sel.size} NC · ${quienes.length} técnico${quienes.length > 1 ? 's' : ''} · ${horas} h.`
          + ' Le llega al mecánico a su teléfono.')
      for (const a of avisos) toast.success(a)
      onDone()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const puedeCrear = sel.size > 0 && Number(horas) > 0 && fecha >= hoy
    && (externo ? proveedor.trim().length > 1 : quienes.length > 0)
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
          <div className="flex items-center justify-between gap-2">
            <p className="flex items-center gap-1 text-xs font-semibold text-gray-700">
              <Users className="h-3.5 w-3.5" /> Quién la ejecuta (uno, o de a pares)
            </p>
            <label className="flex cursor-pointer items-center gap-1.5 text-[11px] font-medium text-gray-600">
              <input type="checkbox" checked={externo}
                     onChange={(e) => { setExterno(e.target.checked); if (e.target.checked) setQuienes([]) }}
                     className="h-3.5 w-3.5 cursor-pointer" />
              La hace un externo
            </label>
          </div>
          {externo ? (
            <div className="mt-1.5 space-y-1.5 rounded-lg border border-indigo-200 bg-indigo-50/60 p-2">
              <input value={proveedor} onChange={(e) => setProveedor(e.target.value)}
                     placeholder="Proveedor que hace el trabajo (obligatorio)"
                     className="w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
              <input value={motivoExterno} onChange={(e) => setMotivoExterno(e.target.value)}
                     placeholder="Por qué se manda afuera (opcional)"
                     className="w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
              <p className="text-[10px] text-indigo-800">
                La OS externa la autoriza gerencia antes de arrancar, no ocupa técnicos del taller y no paga bono.
              </p>
            </div>
          ) : (
            <>
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
                {/* [MIG500] En terreno el jefe MUEVE a la gente (salió una
                    emergencia): el sistema lo saca de la OS anterior y lo pone
                    acá. Una persona no está en dos OS en paralelo. */}
                Si alguno está en otra OS, se le saca de ahí (su reloj se cierra y queda el motivo escrito).
              </p>
            </>
          )}
        </div>

        {/* ── Qué día y cuánto debe demorar ── */}
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs font-medium">
            {/* [MIG507] Planificar ES ponerle día. */}
            📅 Día programado (obligatorio)
            <input type="date" value={fecha} min={hoy}
                   onChange={(e) => setFecha(e.target.value)}
                   className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
          </label>
          <label className="text-xs font-medium">
            <span className="flex items-center gap-1"><Clock className="h-3.5 w-3.5" /> Tiempo asignado (horas)</span>
            <input type="number" inputMode="decimal" min="0" step="0.5" value={horas}
                   onChange={(e) => setHoras(e.target.value)}
                   placeholder="ej: 4"
                   className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
          </label>
          <label className="col-span-2 text-xs font-medium">
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
