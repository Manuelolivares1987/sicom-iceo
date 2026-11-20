'use client'

// «Correo a ESM»: arma el plan de la semana de una faena (resumen + detalle de
// actividades) y lo baja como .eml, que Outlook de escritorio abre como correo
// nuevo con Para, CC y asunto listos. Para Outlook web: copiar y pegar.

import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, Copy, Mail } from 'lucide-react'
import { Modal } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { getPanelVentana, getPlanSemana, getPlanTareas, lunesDe, type EnexFaena } from '@/lib/services/enex'
import { fechaDeIso, sumarDias } from '@/lib/enex-avance'
import {
  armarPlanSemana, asuntoPlanSemana, emlBorrador, esCorreo, htmlPlanSemana, separarCorreos,
} from '@/lib/email/enex-plan-semana'

// Lo que se usó la última vez (por faena) queda en este navegador.
const CLAVE = 'enex-correo-plan'
const POR_DEFECTO = { para: 'sebastian.molina@esm.cl', copia: 'yerko.salazar@esm.cl, hersaly.corey@pilladoempresas.cl' }
type Guardado = { para: string; copia: string; firma?: string }
function leer(faenaId: string): Guardado | null {
  try {
    const t = JSON.parse(localStorage.getItem(CLAVE) ?? '{}') as Record<string, Guardado>
    return t[faenaId] ?? t._ultimo ?? null
  } catch { return null }
}
function guardar(faenaId: string, g: Guardado) {
  try {
    const t = JSON.parse(localStorage.getItem(CLAVE) ?? '{}') as Record<string, Guardado>
    t[faenaId] = g; t._ultimo = g
    localStorage.setItem(CLAVE, JSON.stringify(t))
  } catch { /* sin almacenamiento: no se recuerda, nada más */ }
}

export function CorreoPlanModal({ faenas, faenaInicial, hoy, firmaInicial, onClose }: {
  faenas: EnexFaena[]; faenaInicial: string | null; hoy: string; firmaInicial: string; onClose: () => void
}) {
  const toast = useToast()
  const [faenaId, setFaenaId] = useState(faenaInicial ?? faenas[0]?.id ?? '')
  // Por defecto la semana que viene (el plan se envía antes de empezarla).
  const [lunes, setLunes] = useState(() => sumarDias(lunesDe(hoy), 7))
  const [para, setPara] = useState('')
  const [copia, setCopia] = useState('')
  const [firma, setFirma] = useState(firmaInicial)
  useEffect(() => {
    const g = leer(faenaId)
    setPara(g?.para ?? POR_DEFECTO.para)
    setCopia(g?.copia ?? POR_DEFECTO.copia)
    if (g?.firma) setFirma(g.firma)
  }, [faenaId])

  const faena = faenas.find((f) => f.id === faenaId)
  const domingo = sumarDias(lunes, 6)
  const meses = useMemo(() => {
    const m = new Map<string, { anio: number; mes: number }>()
    for (const f of [lunes, domingo]) { const d = fechaDeIso(f); m.set(`${d.getFullYear()}-${d.getMonth()}`, { anio: d.getFullYear(), mes: d.getMonth() + 1 }) }
    return Array.from(m.values())
  }, [lunes, domingo])

  const { data, isLoading, error } = useQuery({
    queryKey: ['enex-correo-plan', faenaId, lunes],
    enabled: !!faenaId,
    staleTime: 10_000,
    queryFn: async () => {
      const [plan, programaciones] = await Promise.all([getPlanSemana(faenaId, lunes), getPanelVentana(meses, faenaId)])
      const tareas = plan ? await getPlanTareas(plan.id) : []
      return { plan, tareas, programaciones }
    },
  })

  const armado = useMemo(() => (data && faena
    ? armarPlanSemana({ faena: faena.nombre, lunes, tareas: data.tareas, programaciones: data.programaciones })
    : null), [data, faena, lunes])
  const asunto = armado ? asuntoPlanSemana(armado) : ''
  const html = useMemo(() => (armado ? htmlPlanSemana(armado, firma) : ''), [armado, firma])

  const listaPara = separarCorreos(para), listaCopia = separarCorreos(copia)
  const malos = [...listaPara, ...listaCopia].filter((x) => !esCorreo(x))
  const listo = !!armado && listaPara.length > 0 && malos.length === 0

  function abrirEnOutlook() {
    if (!armado || !listo) return
    guardar(faenaId, { para, copia, firma })
    const eml = emlBorrador({ para: listaPara, copia: listaCopia, asunto, html })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob([eml], { type: 'message/rfc822' }))
    a.download = `Plan_semana_${armado.numero}_${faena?.codigo ?? 'ENEX'}.eml`
    a.click()
    setTimeout(() => URL.revokeObjectURL(a.href), 5_000)
    toast.success('Correo descargado. Ábrelo: Outlook lo muestra como mensaje nuevo, listo para enviar.')
  }

  async function copiarCorreo() {
    guardar(faenaId, { para, copia, firma })
    const caja = document.createElement('div')
    caja.innerHTML = html
    try {
      await navigator.clipboard.write([new ClipboardItem({
        'text/html': new Blob([html], { type: 'text/html' }),
        'text/plain': new Blob([caja.innerText || caja.textContent || ''], { type: 'text/plain' }),
      })])
      toast.success('Correo copiado. Pégalo en Outlook con Ctrl+V.')
    } catch { toast.error('No se pudo copiar. Usa «Abrir en Outlook».') }
  }
  async function copiarAsunto() {
    try { await navigator.clipboard.writeText(asunto); toast.success('Asunto copiado') }
    catch { toast.error('No se pudo copiar el asunto') }
  }

  const rangoTxt = `${lunes.slice(8, 10)}-${lunes.slice(5, 7)} al ${domingo.slice(8, 10)}-${domingo.slice(5, 7)}`
  const sinPublicar = data?.plan && data.plan.estado === 'borrador'

  return (
    <Modal open onClose={onClose} title="Correo a ESM · plan de la semana" className="max-w-4xl">
      <div className="space-y-3 text-sm">
        <div className="flex flex-wrap items-center gap-2">
          <select value={faenaId} onChange={(e) => setFaenaId(e.target.value)} className="rounded-lg border px-2 py-1.5 text-sm">
            {faenas.map((f) => <option key={f.id} value={f.id}>{f.nombre}</option>)}
          </select>
          <button onClick={() => setLunes(sumarDias(lunes, -7))} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Semana anterior"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[190px] text-center font-semibold">Semana {armado?.numero ?? ''} · {rangoTxt}</span>
          <button onClick={() => setLunes(sumarDias(lunes, 7))} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Semana siguiente"><ChevronRight className="h-4 w-4" /></button>
          {isLoading && <Spinner className="h-4 w-4" />}
        </div>

        <div className="grid gap-2 md:grid-cols-2">
          <label className="block"><span className="text-xs text-gray-500">Para</span>
            <input value={para} onChange={(e) => setPara(e.target.value)} className="mt-0.5 w-full rounded-lg border px-2 py-1.5 text-sm" /></label>
          <label className="block"><span className="text-xs text-gray-500">CC (AdC y jefes de operaciones del contrato)</span>
            <input value={copia} onChange={(e) => setCopia(e.target.value)} className="mt-0.5 w-full rounded-lg border px-2 py-1.5 text-sm" /></label>
        </div>
        {malos.length > 0 && <p className="text-xs text-red-600">Correo no válido: {malos.join(', ')}</p>}
        <label className="block"><span className="text-xs text-gray-500">Firma</span>
          <textarea value={firma} onChange={(e) => setFirma(e.target.value)} rows={3} className="mt-0.5 w-full rounded-lg border px-2 py-1.5 text-sm" /></label>

        {error && <p className="text-xs text-red-600">No se pudo cargar el plan: {(error as Error).message}</p>}
        {sinPublicar && <p className="rounded bg-amber-50 px-2 py-1 text-xs text-amber-800">El plan semanal de esta semana está en borrador (aún no publicado al mantenedor).</p>}
        {armado && armado.jornadas === 0 && <p className="rounded bg-gray-50 px-2 py-1 text-xs text-gray-600">No hay nada programado esta semana para {faena?.nombre}.</p>}

        <div>
          <p className="text-xs text-gray-500">Asunto: <b className="text-gray-800">{asunto}</b></p>
          <div className="mt-1 max-h-[45vh] overflow-y-auto rounded-lg border bg-white p-3" dangerouslySetInnerHTML={{ __html: html }} />
        </div>

        <div className="flex flex-wrap items-center justify-end gap-2 border-t pt-3">
          <Button variant="outline" disabled={!armado} onClick={copiarAsunto}><Copy className="mr-1 h-4 w-4" /> Copiar asunto</Button>
          <Button variant="outline" disabled={!armado} onClick={copiarCorreo}><Copy className="mr-1 h-4 w-4" /> Copiar correo</Button>
          <Button disabled={!listo} onClick={abrirEnOutlook}><Mail className="mr-1 h-4 w-4" /> Abrir en Outlook</Button>
        </div>
        <p className="text-right text-[11px] text-gray-400">«Abrir en Outlook» baja un archivo .eml: ábrelo y Outlook de escritorio lo muestra como correo nuevo. En Outlook web usa «Copiar».</p>
      </div>
    </Modal>
  )
}
