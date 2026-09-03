'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'
import {
  ArrowLeft, Camera, Check, X, Minus, Play, Pause, CheckCircle2, Loader2, WifiOff, AlertTriangle, Clock,
  Package, Plus, Gauge, ChevronDown, StickyNote,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useAuth } from '@/contexts/auth-context'
import { BLOQUE_LABELS } from '@/lib/services/checklist-v2'
import { useQuery } from '@tanstack/react-query'
import {
  medicionesNeumaticos, respuestaCaptura, getTecnicosActivos,
  type ChecklistV3Item, type RespuestaCaptura, type MedicionItem,
} from '@/lib/services/taller-plan-semanal'
import { RECURSO_ESTADO_LABEL } from '@/lib/services/ot-recursos'
import { buscarProductos } from '@/lib/services/ot-materiales'
import {
  useMecanicoOTs, useMecanicoChecklist, useMarcarItem, useTimingMecanico,
  useAutoSyncTaller, useNetworkStatus, useRecursosOT, useSolicitarRecurso,
  useNotasOT, useAgregarNota,
  useMedidoresOT, useGuardarMedidores,
} from '@/hooks/use-taller-mecanico'

function dataUrlToBlob(dataUrl: string): Blob {
  const [meta, b64] = dataUrl.split(',')
  const mime = meta.match(/:(.*?);/)?.[1] ?? 'image/png'
  const bin = atob(b64)
  const arr = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i)
  return new Blob([arr], { type: mime })
}

function bloqueLabel(b: string): string {
  const known = (BLOQUE_LABELS as Record<string, string>)[b]
  if (known) return known
  const t = b.replace(/^b[0-9]*_?/i, '').replace(/_/g, ' ').trim() || b
  return t.charAt(0).toUpperCase() + t.slice(1)
}

function ResultRadio({ value, disabled, onChange }: {
  value: string | null; disabled?: boolean; onChange: (v: 'ok' | 'no_ok' | 'na') => void
}) {
  const opts = [
    { val: 'ok', label: 'OK', color: 'bg-green-500', icon: Check },
    { val: 'no_ok', label: 'NO OK', color: 'bg-red-500', icon: X },
    { val: 'na', label: 'N/A', color: 'bg-gray-400', icon: Minus },
  ] as const
  return (
    <div className="flex gap-1.5">
      {opts.map((o) => {
        const active = value === o.val
        const Icon = o.icon
        return (
          <button key={o.val} type="button" disabled={disabled} onClick={() => onChange(o.val)}
                  className={`flex h-9 flex-1 items-center justify-center gap-1 rounded-lg border text-xs font-semibold disabled:opacity-50 ${
                    active ? `${o.color} border-transparent text-white` : 'border-gray-200 bg-white text-gray-500'}`}>
            <Icon className="h-3.5 w-3.5" /> {o.label}
          </button>
        )
      })}
    </div>
  )
}

type ProductoLite = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }

export type RecursoPrefill = { instanceItemId: string; texto: string }

type MedicionNeum = { pos: string; mm: number | null }
const esItemNeumaticos = (desc: string) => /neum[aá]tic/i.test(desc)

// Profundidad por neumático (MIG203): el mecánico registra los mm de cada posición.
function NeumaticosProfundidad({ item, onSave, saving }: {
  item: ChecklistV3Item
  onSave: (m: MedicionNeum[]) => void
  saving: boolean
}) {
  const guardadas = medicionesNeumaticos(item.mediciones)
  const [abierto, setAbierto] = useState(false)
  const [rows, setRows] = useState<MedicionNeum[]>([])

  function abrir() {
    setRows(guardadas.length > 0 ? guardadas : Array.from({ length: 4 }, (_, i) => ({ pos: `Pos ${i + 1}`, mm: null })))
    setAbierto(true)
  }
  function setMm(i: number, v: string) {
    setRows((p) => p.map((r, j) => j === i ? { ...r, mm: v === '' ? null : Number(v) } : r))
  }
  function guardar() {
    const conDato = rows.filter((r) => r.mm != null)
    if (conDato.length === 0) return
    onSave(rows.map((r, i) => ({ pos: `Pos ${i + 1}`, mm: r.mm })))
    setAbierto(false)
  }

  if (!abierto) {
    return (
      <div className="mt-2">
        {guardadas.length > 0 ? (
          <button onClick={abrir} className="flex flex-wrap items-center gap-1.5 rounded-lg border border-blue-200 bg-blue-50 px-2 py-1.5 text-left">
            {guardadas.map((m, i) => (
              <span key={i} className={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                m.mm != null && m.mm < 3 ? 'bg-red-100 text-red-700' : 'bg-white text-blue-800 border border-blue-200'}`}>
                {m.pos}: {m.mm ?? '—'} mm
              </span>
            ))}
            <span className="text-[10px] text-blue-600">editar</span>
          </button>
        ) : (
          <button onClick={abrir}
                  className="flex items-center gap-1 rounded-lg border border-blue-300 bg-blue-50 px-2 py-1.5 text-[11px] font-semibold text-blue-700">
            <Gauge className="h-3.5 w-3.5" /> Registrar profundidad por neumático
          </button>
        )}
      </div>
    )
  }

  return (
    <div className="mt-2 space-y-2 rounded-lg border border-blue-200 bg-blue-50/60 p-2.5">
      <p className="text-[11px] font-semibold text-blue-800">Profundidad de cada neumático (mm)</p>
      <div className="grid grid-cols-2 gap-1.5">
        {rows.map((r, i) => (
          <label key={i} className="flex items-center gap-1.5 text-[11px] text-gray-700">
            <span className="w-11 shrink-0">Pos {i + 1}</span>
            <input type="number" inputMode="decimal" min="0" step="0.5"
                   value={r.mm ?? ''} onChange={(e) => setMm(i, e.target.value)}
                   placeholder="mm"
                   className="w-full rounded-lg border border-gray-200 px-2 py-1.5 text-sm" />
          </label>
        ))}
      </div>
      <div className="flex gap-2">
        <button onClick={() => setRows((p) => [...p, { pos: `Pos ${p.length + 1}`, mm: null }])}
                className="rounded-lg border border-blue-300 bg-white px-2 py-1.5 text-[11px] font-semibold text-blue-700">
          + Neumático
        </button>
        {rows.length > 2 && (
          <button onClick={() => setRows((p) => p.slice(0, -1))}
                  className="rounded-lg border border-gray-300 bg-white px-2 py-1.5 text-[11px] text-gray-600">
            − Quitar
          </button>
        )}
        <button onClick={guardar} disabled={saving || rows.every((r) => r.mm == null)}
                className="ml-auto rounded-lg bg-blue-600 px-3 py-1.5 text-[11px] font-semibold text-white disabled:opacity-50">
          Guardar
        </button>
        <button onClick={() => setAbierto(false)} className="rounded-lg px-2 py-1.5 text-[11px] text-gray-500">
          Cancelar
        </button>
      </div>
    </div>
  )
}

// ── Medidores del equipo (MIG397) ───────────────────────────────────────────
// Con cuánto uso volvió el equipo. Las columnas existían desde siempre, pero el
// mecánico no tenía dónde escribirlas: se llenaban solas arrastrando el último
// valor o quedaban nulas, y 46 de 120 recepciones quedaron sin ningún medidor.
// De este número salen la próxima preventiva y lo que se le cobra al cliente.
/**
 * [MIG444] Los ítems que no son una verificación.
 *
 * El bloque B11 —cierre de recepción— son siete campos de captura: daños,
 * observaciones del operador, trabajos pedidos, próximo horómetro, tipo de OT,
 * tiempo estimado y firmas. Traían el tipo escrito en su propia descripción,
 * entre paréntesis, porque el modelo no tenía cómo declararlo, así que los siete
 * se respondían con OK / NO OK. Marcar «OK» en «Observaciones del operador que
 * entrega» no significa nada.
 */
function CapturaItem({ it, onGuardar, saving }: {
  it: ChecklistV3Item
  onGuardar: (p: {
    observacion?: string | null; valor_numerico?: number | null; mediciones?: MedicionItem
    resultado?: 'ok'
    firmas?: { campo: 'firma_operador_url' | 'firma_taller_url'; blob: Blob }[]
  }) => void
  saving: boolean
}) {
  const cap: RespuestaCaptura = respuestaCaptura(it.mediciones)
  const [texto, setTexto] = useState(it.observacion ?? '')
  const [numero, setNumero] = useState(it.valor_numerico != null ? String(it.valor_numerico) : '')
  const [fecha, setFecha] = useState(cap.fecha ?? '')
  const [opcion, setOpcion] = useState(cap.opcion ?? '')
  // [MIG496] Firmas + RUT del cierre de recepción (B11.07): se firman acá mismo.
  const [rutOp, setRutOp] = useState(cap.rut_operador ?? '')
  const [rutTa, setRutTa] = useState(cap.rut_taller ?? '')
  const [firmaOp, setFirmaOp] = useState('')
  const [firmaTa, setFirmaTa] = useState('')

  // [MIG496] B11.04 se llena solo al guardar los medidores (horómetro + 300 h):
  // cuando el valor llega del servidor, reflejarlo en el input.
  useEffect(() => {
    setNumero(it.valor_numerico != null ? String(it.valor_numerico) : '')
  }, [it.valor_numerico])

  const cls = 'w-full rounded-lg border border-gray-300 px-2 py-1.5 text-sm'
  const esProximaPauta = it.codigo === 'B11.04'

  if (it.tipo_respuesta === 'firma') {
    const firmadoOp = !!cap.firma_operador_url
    const firmadoTa = !!cap.firma_taller_url
    const sucio = !!firmaOp || !!firmaTa
      || rutOp !== (cap.rut_operador ?? '') || rutTa !== (cap.rut_taller ?? '')
    const guardarFirmas = () => {
      const firmas: { campo: 'firma_operador_url' | 'firma_taller_url'; blob: Blob }[] = []
      if (firmaOp) firmas.push({ campo: 'firma_operador_url', blob: dataUrlToBlob(firmaOp) })
      if (firmaTa) firmas.push({ campo: 'firma_taller_url', blob: dataUrlToBlob(firmaTa) })
      const completo = (!!firmaOp || firmadoOp) && (!!firmaTa || firmadoTa)
      onGuardar({
        mediciones: { ...cap, rut_operador: rutOp.trim() || null, rut_taller: rutTa.trim() || null },
        firmas: firmas.length ? firmas : undefined,
        resultado: completo ? 'ok' : undefined,
      })
      setFirmaOp(''); setFirmaTa('')
    }
    return (
      <div className="mt-2 space-y-2.5">
        <div className="rounded-lg border border-gray-200 bg-gray-50/60 p-2.5">
          <p className="flex items-center gap-1.5 text-[11px] font-semibold text-gray-700">
            Operador que entrega el equipo
            {firmadoOp && <span className="flex items-center gap-0.5 text-green-700"><Check className="h-3 w-3" /> firmado</span>}
          </p>
          <input value={rutOp} onChange={(e) => setRutOp(e.target.value)}
                 placeholder="RUT (ej: 12.345.678-9)" inputMode="text"
                 className={cls + ' mt-1.5 max-w-[220px]'} />
          <div className="mt-1.5">
            <SignaturePad label="Firma del operador" onCapture={setFirmaOp} existingUrl={cap.firma_operador_url} />
          </div>
        </div>
        <div className="rounded-lg border border-gray-200 bg-gray-50/60 p-2.5">
          <p className="flex items-center gap-1.5 text-[11px] font-semibold text-gray-700">
            Responsable del taller que recibe
            {firmadoTa && <span className="flex items-center gap-0.5 text-green-700"><Check className="h-3 w-3" /> firmado</span>}
          </p>
          <input value={rutTa} onChange={(e) => setRutTa(e.target.value)}
                 placeholder="RUT (ej: 12.345.678-9)" inputMode="text"
                 className={cls + ' mt-1.5 max-w-[220px]'} />
          <div className="mt-1.5">
            <SignaturePad label="Firma del responsable de taller" onCapture={setFirmaTa} existingUrl={cap.firma_taller_url} />
          </div>
        </div>
        <button type="button" disabled={saving || !sucio} onClick={guardarFirmas}
                className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-40">
          Guardar firmas y RUT
        </button>
      </div>
    )
  }

  if (it.tipo_respuesta === 'numero') {
    const sucio = numero !== (it.valor_numerico != null ? String(it.valor_numerico) : '')
    return (
      <div className="mt-2">
        {esProximaPauta && (
          <p className="mb-1 rounded-lg border border-blue-200 bg-blue-50 px-2 py-1 text-[11px] text-blue-800">
            Se calcula solo al guardar los medidores: horómetro al recibir + 300 h.
            Corrígelo únicamente si esta pauta dice otra cosa.
          </p>
        )}
        <div className="flex items-center gap-2">
          <input type="number" inputMode="decimal" step="0.1" min="0" value={numero}
                 onChange={(e) => setNumero(e.target.value)}
                 placeholder="0" className={cls + ' max-w-[140px] tabular-nums'} />
          <span className="text-xs text-gray-500">h</span>
          <button type="button" disabled={saving || !sucio}
                  onClick={() => onGuardar({
                    valor_numerico: numero.trim() === '' ? null : Number(numero),
                    resultado: numero.trim() === '' ? undefined : 'ok',
                  })}
                  className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-40">
            Guardar
          </button>
        </div>
      </div>
    )
  }

  if (it.tipo_respuesta === 'fecha') {
    const sucio = fecha !== (cap.fecha ?? '')
    return (
      <div className="mt-2 flex items-center gap-2">
        <input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} className={cls + ' max-w-[190px]'} />
        <button type="button" disabled={saving || !sucio}
                onClick={() => onGuardar({ mediciones: { ...cap, fecha: fecha || null }, resultado: fecha ? 'ok' : undefined })}
                className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-40">
          Guardar
        </button>
      </div>
    )
  }

  if (it.tipo_respuesta === 'seleccion') {
    const sucio = opcion !== (cap.opcion ?? '')
    return (
      <div className="mt-2 flex items-center gap-2">
        <input value={opcion} onChange={(e) => setOpcion(e.target.value)}
               placeholder="OT-XX-XX" className={cls + ' max-w-[190px] font-mono'} />
        <button type="button" disabled={saving || !sucio}
                onClick={() => onGuardar({ mediciones: { ...cap, opcion: opcion.trim() || null }, resultado: opcion.trim() ? 'ok' : undefined })}
                className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-40">
          Guardar
        </button>
      </div>
    )
  }

  // texto
  const sucio = texto !== (it.observacion ?? '')
  return (
    <div className="mt-2">
      <textarea rows={2} value={texto} onChange={(e) => setTexto(e.target.value)}
                placeholder="Escribe acá…" className={cls} />
      <button type="button" disabled={saving || !sucio}
              onClick={() => onGuardar({ observacion: texto.trim() || null, resultado: texto.trim() ? 'ok' : undefined })}
              className="mt-1 rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-40">
        Guardar
      </button>
    </div>
  )
}

function MedidoresSection({ otId, online, onGuardado }: {
  otId: string; online: boolean
  /** [MIG496] Avisa cuando la persona guardó los medidores (para partir el reloj). */
  onGuardado?: () => void
}) {
  const { data: med, isLoading } = useMedidoresOT(otId)
  const guardar = useGuardarMedidores(otId)
  const [hm, setHm] = useState('')
  const [km, setKm] = useState('')
  const [cl, setCl] = useState('')
  const [aviso, setAviso] = useState<string | null>(null)
  const [editando, setEditando] = useState(false)

  useEffect(() => {
    if (!med) return
    setHm(med.horometro != null ? String(med.horometro) : '')
    setKm(med.kilometraje != null ? String(med.kilometraje) : '')
    setCl(med.cuenta_litros != null ? String(med.cuenta_litros) : '')
  }, [med])

  if (isLoading || !med) return null

  const exigeKm = med.exige_kilometraje
  // [MIG471] El cuenta litros del aljibe: totalizador que no se reinicia.
  const exigeCl = med.exige_cuenta_litros
  const falta = med.horometro == null
    || (exigeKm && med.kilometraje == null)
    || (exigeCl && med.cuenta_litros == null)
  // [MIG444] Antes bastaba con que el número EXISTIERA para dar la sección por
  // hecha, y el número lo arrastra el sistema del último valor conocido. Por eso
  // en producción hay 83 checklists con medidores y CERO escritos por alguien:
  // la sección se veía cerrada y nadie escribía nunca la lectura real. Ahora se
  // queda abierta hasta que la confirme una persona — y [MIG496] mientras no la
  // confirme, el checklist entero queda bloqueado y el reloj no parte.
  const cerrado = !falta && med.anotado_por_persona && !editando

  const enviar = (confirmado: boolean) => {
    const hmN = hm.trim() === '' ? null : Number(hm)
    const kmN = km.trim() === '' ? null : Number(km)
    if (hmN == null || Number.isNaN(hmN)) { setAviso('Escribe el horómetro.'); return }
    if (exigeKm && (kmN == null || Number.isNaN(kmN))) { setAviso('Escribe el kilometraje.'); return }
    const clN = cl.trim() === '' ? null : Number(cl)
    if (exigeCl && (clN == null || Number.isNaN(clN))) { setAviso('Escribe el cuenta litros.'); return }
    setAviso(null)
    guardar.mutate({ horometro: hmN, kilometraje: kmN, cuentaLitros: clN, confirmado }, {
      onSuccess: (r) => {
        if (r?.requiere_confirmacion) { setAviso(r.motivo ?? 'Revisa el número.'); return }
        setAviso(null); setEditando(false)
        onGuardado?.()
      },
      onError: (e) => setAviso((e as Error).message),
    })
  }

  return (
    <div className={cerrado
      ? 'rounded-xl border border-gray-200 bg-white p-3'
      : 'rounded-xl border-2 border-amber-400 bg-amber-50 p-3'}>
      <div className="flex items-center justify-between gap-2">
        <h2 className="flex items-center gap-1 text-sm font-semibold">
          <Gauge className="h-4 w-4 text-amber-600" /> Medidores del equipo
        </h2>
        {cerrado && (
          <button type="button" onClick={() => setEditando(true)}
                  className="text-[11px] font-semibold text-blue-600 underline">Corregir</button>
        )}
      </div>

      {cerrado ? (
        <p className="mt-1 text-xs text-gray-600">
          <b className="tabular-nums">{med.horometro}</b> h
          {exigeKm && med.kilometraje != null && <> · <b className="tabular-nums">{med.kilometraje}</b> km</>}
          {exigeCl && med.cuenta_litros != null && <> · <b className="tabular-nums">{med.cuenta_litros}</b> L</>}
          {!med.anotado_por_persona && (
            <span className="ml-1 text-amber-700">· lo trajo el sistema, confírmalo</span>
          )}
        </p>
      ) : (
        <>
          <p className="mt-1 text-[11px] text-amber-900">
            {falta
              ? 'Anótalos antes de empezar. De acá sale cuándo toca la próxima mantención.'
              : 'Estos números los trajo el sistema del último dato conocido. Confirma la lectura real del equipo.'}
          </p>
          <div className="mt-2 grid grid-cols-2 gap-2">
            <label className="text-[11px] font-medium text-gray-700">
              Horómetro (h)
              <input type="number" inputMode="decimal" step="0.1" min="0" value={hm}
                     onChange={(e) => setHm(e.target.value)}
                     className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-base tabular-nums"
                     placeholder="0.0" />
            </label>
            {exigeKm && (
              <label className="text-[11px] font-medium text-gray-700">
                Kilometraje (km)
                <input type="number" inputMode="decimal" step="0.1" min="0" value={km}
                       onChange={(e) => setKm(e.target.value)}
                       className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-base tabular-nums"
                       placeholder="0.0" />
              </label>
            )}
            {exigeCl && (
              <label className="col-span-2 text-[11px] font-medium text-gray-700">
                Cuenta litros (L)
                <input type="number" inputMode="decimal" step="1" min="0" value={cl}
                       onChange={(e) => setCl(e.target.value)}
                       className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-base tabular-nums"
                       placeholder="0" />
                <span className="mt-0.5 block font-normal text-[10px] text-gray-500">
                  El totalizador del surtidor, el que no se reinicia. Anota el número tal
                  como aparece.
                </span>
              </label>
            )}
          </div>
          {aviso && (
            <p className="mt-2 rounded-lg bg-white px-2 py-1.5 text-[11px] font-medium text-red-700">
              {aviso}
              {guardar.data?.requiere_confirmacion && (
                <button type="button" onClick={() => enviar(true)}
                        className="ml-2 rounded bg-red-600 px-2 py-0.5 text-white">
                  Es correcto, guardar igual
                </button>
              )}
            </p>
          )}
          <button type="button" disabled={guardar.isPending || !online}
                  onClick={() => enviar(false)}
                  className="mt-2 w-full rounded-lg bg-amber-600 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
            {guardar.isPending ? 'Guardando…' : 'Guardar medidores'}
          </button>
          {!online && (
            <p className="mt-1 text-[11px] text-amber-800">
              Sin señal no se pueden guardar todavía: anótalos cuando vuelva la conexión.
            </p>
          )}
        </>
      )}
    </div>
  )
}

// Repuestos y materiales que el mecánico pide para reparar (los valida el jefe).
function RecursosSection({ otId, online, prefill, onPrefillConsumido }: {
  otId: string; online: boolean
  prefill?: RecursoPrefill | null
  onPrefillConsumido?: () => void
}) {
  const { data: recursos } = useRecursosOT(otId)
  const solicitar = useSolicitarRecurso(otId)
  const [abierto, setAbierto] = useState(false)
  const [q, setQ] = useState('')
  const [resultados, setResultados] = useState<ProductoLite[]>([])
  const [prod, setProd] = useState<ProductoLite | null>(null)
  const [cantidad, setCantidad] = useState('')
  const [comentario, setComentario] = useState('')
  // Hallazgo NO OK que motiva el pedido (amarra el pedido a la NC)
  const [itemRef, setItemRef] = useState<string | null>(null)
  const [itemTexto, setItemTexto] = useState('')
  const seccionRef = useRef<HTMLDivElement | null>(null)

  // "Pedir repuesto" desde un ítem NO OK: abre el formulario amarrado al hallazgo.
  useEffect(() => {
    if (!prefill) return
    setAbierto(true)
    setItemRef(prefill.instanceItemId)
    setItemTexto(prefill.texto)
    seccionRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    onPrefillConsumido?.()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [prefill])
  // Fotos del repuesto (clave cuando la pieza no existe en bodega y hay que comprarla)
  const [fotos, setFotos] = useState<{ file: File; url: string }[]>([])
  const fotoRef = useRef<HTMLInputElement | null>(null)

  function agregarFoto(f: File) {
    setFotos((p) => (p.length >= 3 ? p : [...p, { file: f, url: URL.createObjectURL(f) }]))
  }
  function quitarFoto(i: number) {
    setFotos((p) => { URL.revokeObjectURL(p[i].url); return p.filter((_, j) => j !== i) })
  }

  // Búsqueda en el catálogo de bodega (solo online; sin conexión va texto libre).
  useEffect(() => {
    if (!online || prod || q.trim().length < 2) { setResultados([]); return }
    const t = setTimeout(async () => {
      try {
        const { data } = await buscarProductos(q, 8)
        setResultados((data ?? []) as ProductoLite[])
      } catch { setResultados([]) }
    }, 300)
    return () => clearTimeout(t)
  }, [q, online, prod])

  const puedesPedir = Number(cantidad) > 0 && (prod !== null || q.trim().length >= 3)

  function pedir() {
    if (!puedesPedir) return
    const nombre = typeof window !== 'undefined' ? localStorage.getItem('taller-mecanico') : null
    solicitar.mutate({
      productoId: prod?.id ?? null,
      productoNombre: prod?.nombre ?? null,
      descripcion: prod ? null : q.trim(),
      unidad: prod?.unidad_medida ?? null,
      cantidad: Number(cantidad),
      comentario: comentario.trim() || (itemTexto ? `Hallazgo: ${itemTexto}` : null),
      solicitadoNombre: nombre,
      fotos: fotos.map((f) => f.file),
      instanceItemId: itemRef,
    }, {
      onSuccess: () => {
        fotos.forEach((f) => URL.revokeObjectURL(f.url))
        setQ(''); setProd(null); setCantidad(''); setComentario(''); setFotos([])
        setItemRef(null); setItemTexto(''); setAbierto(false)
      },
    })
  }

  const lista = recursos ?? []

  return (
    <div ref={seccionRef} className="rounded-xl border border-gray-200 bg-white p-3">
      <div className="flex items-center justify-between">
        <h2 className="flex items-center gap-1.5 text-sm font-semibold text-gray-800">
          <Package className="h-4 w-4 text-orange-600" /> Repuestos y materiales
          {lista.length > 0 && <span className="text-xs font-normal text-gray-400">({lista.length})</span>}
        </h2>
        <button onClick={() => setAbierto((v) => !v)}
                className="flex items-center gap-1 rounded-lg bg-orange-600 px-2.5 py-1.5 text-xs font-semibold text-white">
          <Plus className="h-3.5 w-3.5" /> Pedir
        </button>
      </div>

      {lista.length === 0 && !abierto && (
        <p className="mt-2 text-xs text-gray-400">¿Necesitas repuestos para reparar? Pídelos aquí y el jefe los valida.</p>
      )}

      {lista.length > 0 && (
        <div className="mt-2 space-y-1.5">
          {lista.map((r) => {
            const chip = RECURSO_ESTADO_LABEL[r.estado]
            return (
              <div key={r.id} className="rounded-lg border border-gray-100 bg-gray-50 px-2.5 py-2">
                <div className="flex items-center gap-2">
                  <span className="flex-1 text-xs font-medium text-gray-800">
                    {r.producto_nombre ?? r.descripcion}
                  </span>
                  <span className="text-xs text-gray-600 whitespace-nowrap">
                    {r.cantidad_aprobada ?? r.cantidad} {r.unidad ?? 'un'}
                  </span>
                  <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${chip.cls}`}>
                    {chip.label}{r.estado === 'en_vale' && r.ticket_folio ? ` · ${r.ticket_folio}` : ''}
                  </span>
                </div>
                {r.estado === 'aprobado' && r.cantidad_aprobada != null && r.cantidad_aprobada !== r.cantidad && (
                  <p className="mt-0.5 text-[10px] text-gray-500">Pediste {r.cantidad}, el jefe aprobó {r.cantidad_aprobada}</p>
                )}
                {r.nota_jefe && <p className="mt-0.5 text-[10px] italic text-gray-500">Jefe: «{r.nota_jefe}»</p>}
                {(r.fotos?.length ?? 0) > 0 && (
                  <div className="mt-1.5 flex gap-1.5">
                    {(r.fotos ?? []).map((url, i) => (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img key={i} src={url} alt={`foto ${i + 1}`}
                           onClick={() => window.open(url, '_blank')}
                           className="h-12 w-12 rounded-lg border object-cover" />
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}

      {abierto && (
        <div className="mt-3 space-y-2 border-t border-gray-100 pt-3">
          {itemRef && (
            <div className="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-2.5 py-2 text-[11px] text-amber-800">
              <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
              <span className="flex-1">Pedido por hallazgo NO OK: <b>{itemTexto}</b></span>
              <button onClick={() => { setItemRef(null); setItemTexto('') }} className="text-amber-700">
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          )}
          {prod ? (
            <div className="flex items-center gap-2 rounded-lg border border-green-200 bg-green-50 px-2.5 py-2 text-xs">
              <span className="flex-1 font-medium text-green-800">{prod.nombre}</span>
              {prod.unidad_medida && <span className="text-green-700">{prod.unidad_medida}</span>}
              <button onClick={() => { setProd(null); setQ('') }} className="text-green-700"><X className="h-3.5 w-3.5" /></button>
            </div>
          ) : (
            <div>
              <input type="text" value={q} onChange={(e) => setQ(e.target.value)}
                     placeholder={online ? 'Busca en bodega o describe lo que necesitas…' : 'Sin conexión: describe lo que necesitas…'}
                     className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm" />
              {resultados.length > 0 && (
                <div className="mt-1 overflow-hidden rounded-lg border border-gray-200">
                  {resultados.map((p) => (
                    <button key={p.id} onClick={() => { setProd(p); setResultados([]) }}
                            className="flex w-full items-center gap-2 border-b border-gray-100 bg-white px-2.5 py-2 text-left text-xs last:border-0 active:bg-gray-50">
                      <span className="flex-1">{p.nombre}</span>
                      {p.codigo && <span className="font-mono text-[10px] text-gray-400">{p.codigo}</span>}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
          <div className="flex gap-2">
            <input type="number" inputMode="decimal" min="0" value={cantidad}
                   onChange={(e) => setCantidad(e.target.value)} placeholder="Cantidad"
                   className="w-28 rounded-lg border border-gray-200 px-3 py-2 text-sm" />
            <input type="text" value={comentario} onChange={(e) => setComentario(e.target.value)}
                   placeholder="Comentario (opcional)"
                   className="flex-1 rounded-lg border border-gray-200 px-3 py-2 text-sm" />
          </div>

          {/* Fotos del repuesto: sirven cuando la pieza no existe en bodega y hay que comprarla */}
          <div className="flex items-center gap-2">
            {fotos.map((f, i) => (
              <div key={f.url} className="relative">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={f.url} alt={`foto ${i + 1}`} className="h-14 w-14 rounded-lg border object-cover" />
                <button onClick={() => quitarFoto(i)}
                        className="absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-red-600 text-white">
                  <X className="h-3 w-3" />
                </button>
              </div>
            ))}
            {fotos.length < 3 && (
              <button onClick={() => fotoRef.current?.click()}
                      className="flex h-14 w-14 flex-col items-center justify-center gap-0.5 rounded-lg border border-dashed border-gray-300 text-gray-500">
                <Camera className="h-4 w-4" />
                <span className="text-[9px]">Foto</span>
              </button>
            )}
            <input ref={fotoRef} type="file" accept="image/*" capture="environment" className="hidden"
                   onChange={(e) => { const f = e.target.files?.[0]; if (f) agregarFoto(f); e.target.value = '' }} />
            {fotos.length === 0 && (
              <span className="text-[10px] text-gray-400">Foto de la pieza (útil si no existe en bodega)</span>
            )}
          </div>

          <button onClick={pedir} disabled={!puedesPedir || solicitar.isPending}
                  className="flex w-full items-center justify-center gap-1.5 rounded-xl bg-orange-600 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
            {solicitar.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Package className="h-4 w-4" />}
            Pedir al jefe de taller
          </button>
          {solicitar.isError && (
            <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
              No se pudo enviar: {(solicitar.error as Error).message}
            </p>
          )}
        </div>
      )}
    </div>
  )
}

// Notas con foto del operador como anexo de la OT (las ve el jefe). MIG249.
function NotasSection({ otId }: { otId: string }) {
  const { data: notas } = useNotasOT(otId)
  const agregar = useAgregarNota(otId)
  const [abierto, setAbierto] = useState(false)
  const [texto, setTexto] = useState('')
  const [fotos, setFotos] = useState<{ file: File; url: string }[]>([])
  const fotoRef = useRef<HTMLInputElement | null>(null)

  function addFotos(files: File[]) {
    setFotos((p) => [...p, ...files.map((f) => ({ file: f, url: URL.createObjectURL(f) }))].slice(0, 5))
  }
  function quitarFoto(i: number) {
    setFotos((p) => { URL.revokeObjectURL(p[i].url); return p.filter((_, j) => j !== i) })
  }

  function guardar() {
    if (!texto.trim()) return
    const nombre = typeof window !== 'undefined' ? localStorage.getItem('taller-mecanico') : null
    agregar.mutate(
      { texto: texto.trim(), autor: nombre, fotos: fotos.map((f) => f.file) },
      { onSuccess: () => {
          fotos.forEach((f) => URL.revokeObjectURL(f.url))
          setTexto(''); setFotos([]); setAbierto(false)
        } },
    )
  }

  const lista = notas ?? []

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-3">
      <div className="flex items-center justify-between">
        <h2 className="flex items-center gap-1.5 text-sm font-semibold text-gray-800">
          <StickyNote className="h-4 w-4 text-blue-600" /> Notas / anexos
          {lista.length > 0 && <span className="text-xs font-normal text-gray-400">({lista.length})</span>}
        </h2>
        <button onClick={() => setAbierto((v) => !v)}
                className="flex items-center gap-1 rounded-lg bg-blue-600 px-2.5 py-1.5 text-xs font-semibold text-white">
          <Plus className="h-3.5 w-3.5" /> Nota
        </button>
      </div>

      {lista.length === 0 && !abierto && (
        <p className="mt-2 text-xs text-gray-400">¿Se escapó algo del checklist? Deja una nota con foto para el jefe de taller.</p>
      )}

      {abierto && (
        <div className="mt-2 space-y-2 rounded-lg border border-blue-100 bg-blue-50/50 p-2">
          <textarea
            value={texto} onChange={(e) => setTexto(e.target.value)}
            placeholder="Escribe la nota (lo que viste, un detalle, una observación…)"
            className="min-h-[70px] w-full rounded-lg border border-gray-200 px-3 py-2 text-sm" maxLength={1000} />
          {fotos.length > 0 && (
            <div className="flex flex-wrap gap-2">
              {fotos.map((f, i) => (
                <div key={i} className="relative">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={f.url} alt={`foto ${i + 1}`} className="h-16 w-16 rounded-lg border object-cover" />
                  <button onClick={() => quitarFoto(i)}
                          className="absolute -right-1.5 -top-1.5 rounded-full bg-white p-0.5 shadow border">
                    <X className="h-3 w-3 text-gray-600" />
                  </button>
                </div>
              ))}
            </div>
          )}
          <div className="flex items-center gap-2">
            <button type="button" onClick={() => fotoRef.current?.click()}
                    className="flex items-center gap-1 rounded-lg border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-600">
              <Camera className="h-3.5 w-3.5" /> Foto{fotos.length ? ` (${fotos.length})` : ''}
            </button>
            <input ref={fotoRef} type="file" accept="image/*,video/*" multiple className="hidden"
                   onChange={(e) => { const fs = Array.from(e.target.files ?? []) as File[]; if (fs.length) addFotos(fs); e.target.value = '' }} />
            <button onClick={guardar} disabled={!texto.trim() || agregar.isPending}
                    className="ml-auto flex items-center gap-1 rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50">
              {agregar.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
              Guardar
            </button>
          </div>
        </div>
      )}

      {lista.length > 0 && (
        <div className="mt-2 space-y-1.5">
          {lista.map((n) => (
            <div key={n.id} className="rounded-lg border border-gray-100 bg-gray-50 px-2.5 py-2">
              <p className="text-xs text-gray-800 whitespace-pre-wrap">{n.texto}</p>
              {n.fotos.length > 0 && (
                <div className="mt-1.5 flex flex-wrap gap-1.5">
                  {n.fotos.map((url, i) => {
                    const esVideo = /\.(mp4|mov|webm|m4v|3gp)(\?|$)/i.test(url)
                    return esVideo ? (
                      <video key={i} src={url} controls className="h-12 w-12 rounded-lg border object-cover" />
                    ) : (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img key={i} src={url} alt={`foto ${i + 1}`} onClick={() => window.open(url, '_blank')}
                           className="h-12 w-12 rounded-lg border object-cover" />
                    )
                  })}
                </div>
              )}
              <p className="mt-0.5 text-[10px] text-gray-400">
                {n.autor ? `${n.autor} · ` : ''}{new Date(n.created_at).toLocaleString('es-CL')}
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

export default function MecanicoOTPage() {
  useAutoSyncTaller()
  const params = useParams()
  const otId = params?.id as string
  const { user } = useAuth()
  const userId = user?.id ?? ''
  const online = useNetworkStatus()

  const { data: ots } = useMecanicoOTs()
  const ot = useMemo(() => (ots ?? []).find((o) => o.ot_id === otId), [ots, otId])
  const { data: items, isLoading } = useMecanicoChecklist(otId)
  const marcar = useMarcarItem(otId)
  const timing = useTimingMecanico(otId)
  // [MIG496] Sin medidores guardados POR UNA PERSONA no se toca ninguna tarea:
  // de ese número salen la próxima pauta y lo que se cobra. Y al guardarlos,
  // el reloj de la jornada parte solo. (Si la consulta no cargó —p.ej. sin
  // señal— no se bloquea: bloquear a ciegas dejaría inutilizable el offline.)
  const { data: med } = useMedidoresOT(otId)
  const medidoresPendientes = !!med && (
    med.horometro == null
    || (med.exige_kilometraje && med.kilometraje == null)
    || (med.exige_cuenta_litros && med.cuenta_litros == null)
    || !med.anotado_por_persona
  )

  const [observations, setObservations] = useState<Record<string, string>>({})
  const fileRefs = useRef<Record<string, HTMLInputElement | null>>({})
  const [finalizar, setFinalizar] = useState(false)
  // [MIG472] Cerrar con tareas pendientes se puede, explicando por qué.
  const [motivoPend, setMotivoPend] = useState('')
  const [firma, setFirma] = useState('')
  const [conObs, setConObs] = useState(false)
  const [obsFin, setObsFin] = useState('')

  const estado = ot?.ot_estado ?? 'asignada'
  // La vista solo trae OTs activas liberadas: si la lista cargó y esta OT ya
  // no viene, es porque quedó finalizada/cerrada (p.ej. desde otro equipo).
  const otNoDisponible = ots !== undefined && !ot

  const visibles = (items ?? []).filter((i) => !i.excluido)
  const grupos = useMemo(() => {
    const g: { bloque: string; items: ChecklistV3Item[] }[] = []
    for (const it of visibles) {
      let x = g.find((y) => y.bloque === it.bloque)
      if (!x) { x = { bloque: it.bloque, items: [] }; g.push(x) }
      x.items.push(it)
    }
    return g
  }, [visibles])

  // Bloques abiertos (colapsables). Arrancan COLAPSADOS para no mostrar un mar
  // de tareas: el operador abre el bloque que va a trabajar. Al abrir la OT se
  // despliega el primer bloque con tareas pendientes para no partir en blanco.
  const [bloquesAbiertos, setBloquesAbiertos] = useState<Set<string>>(new Set())
  const [autoAbierto, setAutoAbierto] = useState(false)
  useEffect(() => {
    if (autoAbierto || grupos.length === 0) return
    const primerPendiente = grupos.find((g) =>
      g.items.some((i) => !i.resultado || i.resultado === 'pendiente'))
    setBloquesAbiertos(new Set([(primerPendiente ?? grupos[0]).bloque]))
    setAutoAbierto(true)
  }, [grupos, autoAbierto])
  function toggleBloque(bloque: string) {
    setBloquesAbiertos((prev) => {
      const next = new Set(prev)
      if (next.has(bloque)) next.delete(bloque)
      else next.add(bloque)
      return next
    })
  }

  const total = visibles.length
  const hechos = visibles.filter((i) => i.resultado && i.resultado !== 'pendiente').length
  const pendientesOblig = visibles.filter((i) => i.obligatorio && (!i.resultado || i.resultado === 'pendiente')).length
  // Hallazgos NO OK sin foto: bloquean pausar/finalizar (la NC nace con foto).
  const noOkSinFoto = visibles.filter((i) => i.resultado === 'no_ok' && !i.foto_url).length
  const [warnFoto, setWarnFoto] = useState(false)
  const [sinNombre, setSinNombre] = useState(false)
  const [prefillRecurso, setPrefillRecurso] = useState<RecursoPrefill | null>(null)

  /**
   * [MIG448] Quién está poniendo el tiempo.
   *
   * Los nueve técnicos comparten la cuenta del taller, así que el usuario
   * autenticado es el mismo para todos. El nombre que cada uno elige en la
   * portada («Soy: Joel Coo») vive en el localStorage de su teléfono y hasta
   * ahora no llegaba a ninguna parte. Acá se resuelve contra el catálogo y
   * viaja con el reloj: es lo que después permite repartir el bono.
   */
  const { data: tecnicos } = useQuery({
    queryKey: ['taller-tecnicos-activos'],
    queryFn: getTecnicosActivos,
    staleTime: 30 * 60_000,
  })
  const tecnicoId = useMemo(() => {
    if (typeof window === 'undefined') return null
    const elegido = (localStorage.getItem('taller-mecanico') ?? '').trim().toLowerCase()
    if (!elegido || !tecnicos?.length) return null
    const primer = elegido.split(/\s+/)[0] ?? ''
    const t = tecnicos.find((x) => x.nombre.toLowerCase() === elegido)
      ?? tecnicos.find((x) => x.nombre.toLowerCase().split(/\s+/)[0] === primer)
    return t?.id ?? null
  }, [tecnicos])

  function doTiming(accion: 'iniciar' | 'pausar') {
    if (accion === 'pausar' && noOkSinFoto > 0) { setWarnFoto(true); return }
    // [MIG461] El taller entra con una cuenta compartida, así que la sesión no
    // dice quién trabaja. Sin nombre elegido el RPC rechaza el inicio; conviene
    // decirlo acá y no dejar que el mecánico se lleve un error crudo.
    if (accion === 'iniciar' && !tecnicoId) { setSinNombre(true); return }
    setSinNombre(false)
    setWarnFoto(false)
    timing.reset()
    timing.mutate({ accion, userId, tecnicoId })
  }
  // [MIG472] El backend contesta «faltan N tareas» en vez de negarse en seco.
  const pidePendientes = timing.isError && (timing.error as Error).name === 'PENDIENTES'

  function abrirFinalizar() {
    if (noOkSinFoto > 0) { setWarnFoto(true); return }
    setWarnFoto(false)
    if (pendientesOblig > 0 && !confirm(`Quedan ${pendientesOblig} tareas obligatorias sin marcar. ¿Finalizar igual?`)) return
    // Limpiar el error de una acción anterior (p.ej. un pausar fallido) para
    // que no aparezca dentro del modal como "No se pudo finalizar".
    timing.reset()
    setFirma(''); setConObs(false); setObsFin(''); setFinalizar(true)
  }
  function confirmFinalizar() {
    if (!firma) return
    timing.mutate(
      {
        accion: 'finalizar', userId, firma: dataUrlToBlob(firma),
        conObservaciones: conObs, observaciones: obsFin.trim() || null,
        // [MIG472] Sólo viaja si el mecánico ya explicó por qué quedan tareas
        // sin hacer. Sin motivo, el sistema vuelve a preguntar.
        motivoPendientes: motivoPend.trim() || null,
      },
      { onSuccess: () => { setFinalizar(false); setMotivoPend('') } },
    )
  }

  function setResultado(it: ChecklistV3Item, v: 'ok' | 'no_ok' | 'na') {
    marcar.mutate({ instanceItemId: it.instance_item_id, instanceId: it.instance_id, resultado: v })
  }
  function saveObs(it: ChecklistV3Item) {
    const o = observations[it.instance_item_id]
    if (o === undefined || o === (it.observacion ?? '')) return
    marcar.mutate({ instanceItemId: it.instance_item_id, instanceId: it.instance_id, observacion: o })
  }
  function onPhoto(it: ChecklistV3Item, files: File[]) {
    if (files.length) marcar.mutate({ instanceItemId: it.instance_item_id, instanceId: it.instance_id, files })
  }

  return (
    <div className="p-3 space-y-3">
      <Link href="/m/taller" className="inline-flex items-center gap-1 text-sm text-gray-500">
        <ArrowLeft className="h-4 w-4" /> Mis OTs
      </Link>

      {/* Cabecera */}
      <div className="rounded-xl border border-gray-200 bg-white p-3">
        <div className="flex items-center gap-2">
          <span className="font-mono text-sm font-bold">{ot?.ot_folio ?? '…'}</span>
          {!online && <span className="ml-auto flex items-center gap-1 text-[11px] text-amber-700"><WifiOff className="h-3.5 w-3.5" /> sin conexión</span>}
        </div>
        <div className="mt-1 text-sm font-medium text-gray-800">
          {ot?.activo_codigo} {ot?.activo_patente && <span className="text-gray-500">· {ot.activo_patente}</span>}
        </div>
        <div className="text-xs text-gray-500">{ot?.activo_nombre}</div>
        {/* [MIG496] El compromiso del plan es un DATO, no una pregunta del
            checklist: horas de la visita (MIG493) y último día planificado. */}
        {(() => {
          const horas = ot?.horas_planificadas
            ?? (ot?.tiempo_estimado_total_min != null && ot.tiempo_estimado_total_min > 0
                ? Math.round(ot.tiempo_estimado_total_min / 6) / 10 : null)
          const fecha = ot?.fecha_entrega_plan ?? ot?.fecha_programada
          if (horas == null && !fecha) return null
          const fmt = (d: string) =>
            new Date(d.includes('T') ? d : `${d}T00:00:00`).toLocaleDateString('es-CL')
          return (
            <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-0.5 rounded-lg bg-blue-50 px-2 py-1 text-[11px] font-medium text-blue-800">
              {horas != null && (
                <span className="flex items-center gap-1"><Clock className="h-3 w-3" /> {horas} HH comprometidas</span>
              )}
              {fecha && <span>Entrega: {fmt(fecha)}</span>}
            </div>
          )
        })()}
        <div className="mt-2 flex items-center gap-2 text-xs text-gray-600">
          <span className="font-semibold">{hechos}/{total} tareas</span>
          {total > 0 && (
            <div className="h-1.5 flex-1 rounded-full bg-gray-100">
              <div className="h-1.5 rounded-full bg-orange-500" style={{ width: `${Math.min(100, Math.round((hechos / total) * 100))}%` }} />
            </div>
          )}
        </div>
      </div>

      {/* Cronómetro de jornada */}
      {otNoDisponible ? (
        <p className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs font-medium text-blue-700">
          Esta OT ya no está entre tus OTs activas: probablemente ya fue finalizada.
          Vuelve a «Mis OTs» para ver tu trabajo pendiente.
        </p>
      ) : (
      <div className="flex gap-2">
        {estado === 'asignada' && (
          <button onClick={() => doTiming('iniciar')} disabled={timing.isPending || medidoresPendientes}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-green-600 py-3 text-sm font-semibold text-white disabled:opacity-50">
            <Play className="h-4 w-4" /> Iniciar jornada
          </button>
        )}
        {estado === 'pausada' && (
          <button onClick={() => doTiming('iniciar')} disabled={timing.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-green-600 py-3 text-sm font-semibold text-white disabled:opacity-50">
            <Play className="h-4 w-4" /> Reanudar
          </button>
        )}
        {estado === 'en_ejecucion' && (
          <button onClick={() => doTiming('pausar')} disabled={timing.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-amber-500 py-3 text-sm font-semibold text-white disabled:opacity-50">
            <Pause className="h-4 w-4" /> Pausar (fin jornada)
          </button>
        )}
        {(estado === 'en_ejecucion' || estado === 'pausada') && (
          <button onClick={abrirFinalizar} disabled={timing.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-blue-600 py-3 text-sm font-semibold text-white disabled:opacity-50">
            <CheckCircle2 className="h-4 w-4" /> Finalizar
          </button>
        )}
      </div>
      )}
      {sinNombre && (
        <p className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900">
          Antes de empezar, elige tu nombre en la lista de mecánicos (arriba, en «Mis OTs»).
          El taller entra con una cuenta compartida, así que la pantalla no sabe quién eres —
          y el tiempo que se mide es el que después se reparte.
        </p>
      )}
      {warnFoto && noOkSinFoto > 0 && (
        <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
          Hay {noOkSinFoto} hallazgo{noOkSinFoto > 1 ? 's' : ''} NO OK sin foto. Saca la foto de cada
          hallazgo antes de pausar o finalizar — la No Conformidad se reporta con esa foto.
        </p>
      )}
      {timing.isError && (
        <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
          No se pudo registrar la acción: {(timing.error as Error).message}
        </p>
      )}
      <p className="text-[11px] text-gray-500 flex items-center gap-1">
        <AlertTriangle className="h-3 w-3 text-amber-500" />
        Al pausar o finalizar, las tareas NO OK se reportan como No Conformidad al jefe.
      </p>

      {/* [MIG397] Con cuánto uso volvió el equipo. Va antes que todo lo demás
          porque [MIG496] sin medidores no se abre el checklist, y al guardarlos
          el reloj de la jornada parte solo. */}
      <MedidoresSection otId={otId} online={online}
                        onGuardado={() => { if (estado === 'asignada') doTiming('iniciar') }} />
      {medidoresPendientes && (
        <p className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900">
          El checklist está bloqueado hasta que guardes los medidores del equipo.
          Al guardarlos, el reloj de la jornada parte solo.
        </p>
      )}

      {/* Repuestos y materiales para reparar (los valida el jefe) */}
      <RecursosSection otId={otId} online={online}
                       prefill={prefillRecurso} onPrefillConsumido={() => setPrefillRecurso(null)} />

      {/* Notas con foto (anexo para el jefe, por si se escapa algo del checklist) */}
      <NotasSection otId={otId} />

      {/* Este equipo ya se inspeccionó completo: la OT trae solo las NC (MIG270) */}
      {(items ?? [])[0]?.instance_arrastre && total > 0 && (
        <p className="rounded-lg border border-orange-200 bg-orange-50 px-3 py-2 text-[11px] text-orange-800">
          <span className="font-semibold">Solo las no conformidades.</span>{' '}
          El checklist completo ya se hizo en una OT anterior: aquí van las {total} tareas que salieron NO OK.
        </p>
      )}

      {/* Checklist — [MIG496] bloqueado (gris, sin toques) hasta guardar medidores */}
      {isLoading ? (
        <div className="flex justify-center py-8"><Spinner /></div>
      ) : total === 0 ? (
        <p className="py-8 text-center text-sm text-gray-400">Esta OT no tiene checklist (¿se cargó con conexión?).</p>
      ) : (
        <div aria-disabled={medidoresPendientes}
             className={medidoresPendientes ? 'pointer-events-none select-none space-y-3 opacity-50' : 'space-y-3'}>
        {grupos.map((g) => {
          const abierto = bloquesAbiertos.has(g.bloque)
          const nTotal = g.items.length
          const nHechas = g.items.filter((i) => i.resultado && i.resultado !== 'pendiente').length
          const completo = nHechas === nTotal
          return (
          <div key={g.bloque}>
            <button
              type="button"
              onClick={() => toggleBloque(g.bloque)}
              aria-expanded={abierto}
              className="sticky top-0 z-10 flex w-full items-center gap-2 rounded bg-gray-100 px-2 py-2 text-left active:bg-gray-200">
              <ChevronDown className={`h-4 w-4 shrink-0 text-gray-500 transition-transform ${abierto ? '' : '-rotate-90'}`} />
              <span className="text-xs font-semibold text-gray-700">{bloqueLabel(g.bloque)}</span>
              <span className={`ml-auto shrink-0 rounded-full px-2 py-0.5 text-[10px] font-medium ${
                completo ? 'bg-green-100 text-green-700' : 'bg-white text-gray-500'}`}>
                {completo && <Check className="mr-0.5 inline h-2.5 w-2.5" />}{nHechas}/{nTotal}
              </span>
            </button>
            {abierto && (
            <div className="space-y-2 pt-2">
              {g.items.map((it) => (
                <div key={it.instance_item_id} className="rounded-xl border border-gray-200 bg-white p-3">
                  <div className="flex items-start gap-1.5">
                    {it.codigo && <span className="text-[10px] font-mono text-gray-400">{it.codigo}</span>}
                    <p className="flex-1 text-sm text-gray-800">{it.descripcion}</p>
                    {it.tiempo_min != null && (
                      <span className="flex items-center gap-0.5 text-[10px] text-gray-400"><Clock className="h-3 w-3" />{it.tiempo_min}m</span>
                    )}
                  </div>
                  <div className="mt-1 flex flex-wrap gap-1">
                    {it.requiere_foto && <span className="text-[9px] px-1 rounded bg-blue-100 text-blue-700">pide foto</span>}
                    {it.critico && <span className="text-[9px] px-1 rounded bg-red-100 text-red-700">crítica</span>}
                    {it.arrastre && <span className="text-[9px] px-1 rounded bg-orange-100 text-orange-700">no conformidad</span>}
                  </div>
                  {/* Viene NO OK de la inspección anterior (MIG270) */}
                  {it.arrastre && (
                    <p className="mt-1 text-[11px] text-orange-700">
                      Salió NO OK en la inspección anterior
                      {it.arrastre_observacion ? `: ${it.arrastre_observacion}` : '.'}
                    </p>
                  )}

                  {it.tipo_respuesta === 'ok_no_ok' ? (
                    <div className="mt-2"><ResultRadio value={it.resultado} onChange={(v) => setResultado(it, v)} /></div>
                  ) : (
                    <CapturaItem it={it} saving={marcar.isPending}
                      onGuardar={(p) => marcar.mutate({
                        instanceItemId: it.instance_item_id, instanceId: it.instance_id, ...p,
                      })} />
                  )}

                  {/* Neumáticos: profundidad por posición (MIG203) */}
                  {esItemNeumaticos(it.descripcion) && (
                    <NeumaticosProfundidad item={it} saving={marcar.isPending}
                      onSave={(m) => marcar.mutate({ instanceItemId: it.instance_item_id, instanceId: it.instance_id, mediciones: m })} />
                  )}

                  {/* Hallazgo NO OK: foto obligatoria + pedir repuesto ahí mismo */}
                  {it.resultado === 'no_ok' && (
                    <div className="mt-2 flex items-center gap-2">
                      {!it.foto_url ? (
                        <button onClick={() => fileRefs.current[it.instance_item_id]?.click()}
                                className="flex items-center gap-1 rounded-lg border border-red-300 bg-red-50 px-2 py-1.5 text-[11px] font-semibold text-red-700">
                          <Camera className="h-3.5 w-3.5" /> Foto obligatoria
                        </button>
                      ) : (
                        <span className="flex items-center gap-1 text-[11px] text-green-700">
                          <Check className="h-3.5 w-3.5" /> Foto del hallazgo OK
                        </span>
                      )}
                      <button onClick={() => setPrefillRecurso({ instanceItemId: it.instance_item_id, texto: it.descripcion })}
                              className="flex items-center gap-1 rounded-lg border border-orange-300 bg-orange-50 px-2 py-1.5 text-[11px] font-semibold text-orange-700">
                        <Package className="h-3.5 w-3.5" /> Pedir repuesto
                      </button>
                    </div>
                  )}

                  {(() => {
                    const evid = it.foto_urls?.length ? it.foto_urls : (it.foto_url ? [it.foto_url] : [])
                    if (!evid.length) return null
                    return (
                      <div className="mt-2 flex flex-wrap gap-2">
                        {evid.map((u, idx) => {
                          const esVideo = /\.(mp4|mov|webm|m4v|3gp)(\?|$)/i.test(u)
                          return esVideo ? (
                            <video key={idx} src={u} controls className="h-20 w-20 rounded-lg border object-cover" />
                          ) : (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img key={idx} src={u} alt={`evidencia ${idx + 1}`} className="h-20 w-20 rounded-lg border object-cover" />
                          )
                        })}
                      </div>
                    )
                  })()}

                  <div className="mt-2 flex gap-2">
                    <input type="text" placeholder="Observación…"
                           value={observations[it.instance_item_id] ?? it.observacion ?? ''}
                           onChange={(e) => setObservations((p) => ({ ...p, [it.instance_item_id]: e.target.value }))}
                           onBlur={() => saveObs(it)}
                           className="flex-1 rounded-lg border border-gray-200 px-3 py-2 text-sm" />
                    <button type="button" onClick={() => fileRefs.current[it.instance_item_id]?.click()}
                            title="Cámara o galería · varias fotos o video"
                            className={`flex h-10 min-w-10 items-center justify-center gap-1 rounded-lg border px-2 ${
                              it.foto_url ? 'border-green-300 bg-green-50 text-green-600'
                                : it.requiere_foto ? 'border-blue-300 bg-blue-50 text-blue-600' : 'border-gray-200 text-gray-500'}`}>
                      {marcar.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Camera className="h-4 w-4" />}
                      <Plus className="h-3 w-3" />
                    </button>
                    <input ref={(el) => { fileRefs.current[it.instance_item_id] = el }} type="file"
                           accept="image/*,video/*" multiple className="hidden"
                           onChange={(e) => { const fs = Array.from(e.target.files ?? []) as File[]; if (fs.length) onPhoto(it, fs); e.target.value = '' }} />
                  </div>
                </div>
              ))}
            </div>
            )}
          </div>
          )
        })}
        </div>
      )}

      {/* Modal finalizar con firma del técnico */}
      {finalizar && (
        <Modal open onClose={() => setFinalizar(false)} title="Finalizar OT">
          <div className="space-y-3">
            <p className="text-sm text-gray-600">
              Firma para cerrar tu trabajo. Las tareas NO OK ya se reportaron como No Conformidad.
            </p>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={conObs} onChange={(e) => setConObs(e.target.checked)} />
              Finalizar con observaciones
            </label>
            {conObs && (
              <textarea value={obsFin} onChange={(e) => setObsFin(e.target.value)} rows={2}
                        placeholder="Observaciones…" className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
            )}
            <SignaturePad label="Firma del técnico (obligatoria)" onCapture={setFirma} />

            {/* [MIG472] Quedan obligatorias sin hacer. No es un error: es una
                salida que existe y que el jefe de taller revisa después. */}
            {pidePendientes && (
              <div className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2.5">
                <p className="text-xs font-medium text-amber-900">
                  {(timing.error as Error).message}
                </p>
                <label className="mt-2 block text-[11px] font-medium text-amber-900">
                  ¿Por qué quedaron sin hacer?
                  <textarea rows={2} value={motivoPend}
                            onChange={(e) => setMotivoPend(e.target.value)}
                            placeholder="Ej: falta el repuesto del filtro, el cliente se llevó el equipo"
                            className="mt-0.5 w-full rounded-lg border border-amber-300 px-2 py-1.5 text-sm" />
                </label>
                <p className="mt-1 text-[10px] text-amber-800">
                  La OT queda cerrada y marcada para que el jefe de taller la revise. Hasta que
                  la valide, este trabajo no cuenta para el bono.
                </p>
              </div>
            )}

            {timing.isError && !pidePendientes && (
              <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
                No se pudo finalizar: {(timing.error as Error).message}
              </p>
            )}
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setFinalizar(false)}>Cancelar</Button>
            <Button
              disabled={!firma || (conObs && !obsFin.trim()) || timing.isPending
                        || (pidePendientes && motivoPend.trim().length < 10)}
              onClick={confirmFinalizar}>
              {timing.isPending ? <Spinner className="h-4 w-4 mr-1" /> : <CheckCircle2 className="h-4 w-4 mr-1" />}
              {pidePendientes ? 'Cerrar igual — lo revisa el jefe' : 'Finalizar'}
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
