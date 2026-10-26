'use client'

// Importar la planilla "Planificación diaria" (una hoja por faena) a la Gantt
// (MIG590). Nada se escribe hasta confirmar: primero se ve qué fila de la
// planilla cae en qué instalación y cuántos servicios se crean.
//
// Camiones: la planilla dice "CP2" (2 camiones ese día) sin patente. [MIG651]
// Van al «camión por asignar» de la faena: la patente la anota el supervisor en
// terreno, con el camión que la operación entregue ese día. Sin camión por
// asignar (faena sin migrar) se usa lo de antes: los camiones sin calibración
// en el período, los de calibración más antigua primero.

import { useMemo, useState } from 'react'
import { FileSpreadsheet, Loader2, AlertTriangle, Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import {
  programarLote, crearInstalacion, getPanelVentana,
  type EnexFaena, type EnexInstalacion, type EnexPanelRow, type TipoServicio,
} from '@/lib/services/enex'
import { leerHojaPlanilla, emparejar, normalizarNombre, type HojaPlanilla } from '@/lib/enex-avance'
import { hojaAMatriz } from '@/lib/enex-planilla-excel'

type Hoja = HojaPlanilla & { nombre: string; faenaIds: string[] }
type Item = { instalacion_id: string; tipo_servicio: TipoServicio; fecha: string; observacion: string | null; cantidad?: number }

function faenasDeHoja(nombre: string, faenas: EnexFaena[]): string[] {
  const n = normalizarNombre(nombre)
  const por = (cods: string[]) => cods.map((c) => faenas.find((f) => f.codigo === c)?.id).filter(Boolean) as string[]
  if (n.includes('centinela')) return por(['CENTINELA', 'NCEN_DES'])
  if (n.includes('spence')) return por(['SPENCE'])
  if (n.includes('lomas')) return por(['LB_COMB', 'LB_LUB'])
  const f = faenas.find((x) => n.includes(normalizarNombre(x.nombre)) || n.includes(x.codigo.toLowerCase()))
  return f ? [f.id] : []
}

function tipoDeNombre(n: string): EnexInstalacion['tipo'] {
  const t = normalizarNombre(n)
  if (/\beess\b/.test(t)) return 'eess'
  if (/semimovil/.test(t)) return 'semimovil'
  if (/truck|rack|microfiltr/.test(t)) return 'truck_shop'
  if (/petroler|\btk\b|brazo|enaex|orica|estanque/.test(t)) return 'petrolera'
  return 'otro'
}

export function ImportarPlanillaModal({ faenas, instalaciones, hoy, onClose, onDone, onInstalacionCreada }: {
  faenas: EnexFaena[]; instalaciones: EnexInstalacion[]; hoy: string
  onClose: () => void; onDone: () => void; onInstalacionCreada: () => Promise<unknown>
}) {
  const toast = useToast()
  const [leyendo, setLeyendo] = useState(false)
  const [hojas, setHojas] = useState<Hoja[]>([])
  const [mapa, setMapa] = useState<Record<string, string>>({})          // `${hoja}|${fila}` → instalacion_id ('' = no importar)
  const [faenaCam, setFaenaCam] = useState<Record<string, string>>({})  // `${hoja}|${fila}` → faena de los camiones
  const [existentes, setExistentes] = useState<EnexPanelRow[]>([])
  const [desdeHoy, setDesdeHoy] = useState(true)
  const [busy, setBusy] = useState(false)
  const [archivo, setArchivo] = useState('')

  async function leer(file: File) {
    setLeyendo(true)
    try {
      const ExcelJS = (await import('exceljs')).default
      const wb = new ExcelJS.Workbook()
      await wb.xlsx.load(await file.arrayBuffer())
      const out: Hoja[] = []
      wb.eachSheet((ws) => {
        const h = leerHojaPlanilla(hojaAMatriz(ws), Number(hoy.slice(0, 4)))
        if (h.filas.some((f) => f.entradas.length > 0)) out.push({ ...h, nombre: ws.name, faenaIds: faenasDeHoja(ws.name, faenas) })
      })
      if (out.length === 0) { toast.error('No encontré hojas con el formato de la planificación diaria'); return }
      // Emparejamiento automático por nombre.
      const m: Record<string, string> = {}, fc: Record<string, string> = {}
      for (const h of out) {
        const cands = instalaciones.filter((i) => i.tipo !== 'camion' && (h.faenaIds.length === 0 || h.faenaIds.includes(i.faena_id)))
        for (const f of h.filas) {
          const k = `${h.nombre}|${f.fila}`
          if (f.esCamiones) fc[k] = h.faenaIds[0] ?? ''
          else m[k] = emparejar(f.nombre, cands)?.id ?? ''
        }
      }
      setMapa(m); setFaenaCam(fc); setHojas(out); setArchivo(file.name)
      // Lo ya programado en esos meses: para no repetir camiones ni días.
      const fechas = out.flatMap((h) => [h.desde!, h.hasta!]).sort()
      const meses: { anio: number; mes: number }[] = []
      for (let [a, mm] = fechas[0].split('-').map(Number); `${a}-${String(mm).padStart(2, '0')}` <= fechas[fechas.length - 1].slice(0, 7);) {
        meses.push({ anio: a, mes: mm }); mm++; if (mm > 12) { mm = 1; a++ }
      }
      setExistentes(await getPanelVentana(meses))
    } catch (e) { toast.error(`No se pudo leer el archivo: ${(e as Error).message}`) } finally { setLeyendo(false) }
  }

  // Lo que se va a crear, con los avisos.
  const plan = useMemo(() => {
    const items: Item[] = []
    let pasadas = 0, sinCamion = 0
    const porFila: Record<string, number> = {}
    const yaExiste = new Set(existentes.map((r) => `${r.instalacion_id}|${r.tipo_servicio}|${r.fecha_programada?.slice(0, 10)}`))
    const camionesUsados = new Set(existentes.filter((r) => r.instalacion_tipo === 'camion' && r.tipo_servicio === 'calibracion').map((r) => r.instalacion_id))
    for (const h of hojas) {
      for (const f of h.filas) {
        const k = `${h.nombre}|${f.fila}`
        let n = 0
        if (f.esCamiones) {
          const fid = faenaCam[k]
          if (!fid) continue
          const comodin = instalaciones.find((i) => i.es_comodin && i.faena_id === fid)
          if (comodin) {
            for (const e of f.entradas) {
              if (desdeHoy && e.fecha < hoy) { pasadas += e.camiones; continue }
              // cantidad = total del día: reimportar no duplica.
              items.push({ instalacion_id: comodin.id, tipo_servicio: 'calibracion', fecha: e.fecha, observacion: `Planilla ${e.codigo}`, cantidad: e.camiones })
              n += e.camiones
            }
            porFila[k] = n
            continue
          }
          const cola = instalaciones.filter((i) => i.tipo === 'camion' && !i.es_comodin && i.faena_id === fid && !camionesUsados.has(i.id))
            .sort((a, b) => (a.ultima_calibracion ?? '').localeCompare(b.ultima_calibracion ?? ''))
          for (const e of f.entradas) {
            if (desdeHoy && e.fecha < hoy) { pasadas += e.camiones; continue }
            for (let j = 0; j < e.camiones; j++) {
              const c = cola.shift()
              if (!c) { sinCamion++; continue }
              camionesUsados.add(c.id)
              items.push({ instalacion_id: c.id, tipo_servicio: 'calibracion', fecha: e.fecha, observacion: `Planilla ${e.codigo}` })
              n++
            }
          }
        } else {
          const iid = mapa[k]
          if (!iid) continue
          for (const e of f.entradas) {
            if (desdeHoy && e.fecha < hoy) { pasadas += e.servicios.length; continue }
            for (const s of e.servicios) {
              if (yaExiste.has(`${iid}|${s}|${e.fecha}`)) continue
              items.push({ instalacion_id: iid, tipo_servicio: s, fecha: e.fecha, observacion: `Planilla ${e.codigo}` })
              n++
            }
          }
        }
        porFila[k] = n
      }
    }
    return { items, pasadas, sinCamion, porFila }
  }, [hojas, mapa, faenaCam, instalaciones, existentes, desdeHoy, hoy])

  async function crearFaltante(h: Hoja, fila: number, nombre: string) {
    const faenaId = h.faenaIds[0]
    if (!faenaId) { toast.error('Elige primero a qué faena pertenece la hoja'); return }
    const tipo = tipoDeNombre(nombre)
    try {
      const r = await crearInstalacion({ faenaId, nombre: nombre.replace(/\s+/g, ' ').trim(), tipo, linea: tipo === 'truck_shop' ? 'lubricante' : 'combustible' })
      await onInstalacionCreada()
      setMapa((p) => ({ ...p, [`${h.nombre}|${fila}`]: r.id }))
      toast.success(`Instalación «${nombre}» creada en ${faenas.find((f) => f.id === faenaId)?.nombre}`)
    } catch (e) { toast.error((e as Error).message) }
  }

  async function confirmar() {
    if (plan.items.length === 0) return
    setBusy(true)
    try {
      let creadas = 0, omitidas = 0
      for (let i = 0; i < plan.items.length; i += 200) {
        const r = await programarLote(plan.items.slice(i, i + 200))
        creadas += r.creadas; omitidas += r.omitidas
      }
      toast.success(`${creadas} servicios programados${omitidas ? ` · ${omitidas} ya estaban` : ''}. El mantenedor los ve en su día.`)
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  const ignorados = hojas.flatMap((h) => h.ignorados.map((x) => `${x.codigo} ×${x.n} (${h.nombre})`))

  return (
    <Modal open onClose={onClose} title="Importar planilla de planificación diaria" className="sm:max-w-4xl">
      <div className="space-y-3">
        <p className="text-sm text-gray-600">
          Sube la planilla Excel (una hoja por faena, instalación × día con códigos <b>CMP</b>, <b>C</b>, <b>MP</b>, <b>CP</b>/<b>CP2</b>/<b>CP3</b>, <b>AG</b>).
          Los códigos <b>R</b> (respaldo), <b>RP</b> y <b>D</b> no se programan. Revisa la vista previa antes de confirmar.
        </p>
        <label className="flex cursor-pointer items-center gap-2 rounded-lg border border-dashed border-gray-300 p-3 text-sm text-gray-600 hover:bg-gray-50">
          {leyendo ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileSpreadsheet className="h-4 w-4" />}
          {archivo || 'Elegir archivo .xlsx'}
          <input type="file" accept=".xlsx" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) void leer(f); e.target.value = '' }} />
        </label>

        {hojas.length > 0 && (
          <>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={desdeHoy} onChange={(e) => setDesdeHoy(e.target.checked)} />
              Programar solo desde hoy en adelante <span className="text-xs text-gray-500">(lo pasado quedaría como atrasado)</span>
            </label>
            <div className="max-h-[50vh] space-y-3 overflow-y-auto">
              {hojas.map((h) => {
                const cands = instalaciones.filter((i) => i.tipo !== 'camion')
                return (
                  <div key={h.nombre} className="rounded-lg border">
                    <div className="flex flex-wrap items-center justify-between gap-2 border-b bg-gray-50 px-3 py-1.5">
                      <span className="text-sm font-semibold">Hoja {h.nombre}</span>
                      <span className="text-[11px] text-gray-500">{h.desde} → {h.hasta}</span>
                    </div>
                    <table className="w-full text-xs">
                      <tbody>
                        {h.filas.filter((f) => f.entradas.length > 0).map((f) => {
                          const k = `${h.nombre}|${f.fila}`
                          return (
                            <tr key={k} className="border-b last:border-0">
                              <td className="w-[38%] p-1.5">
                                <div className="font-medium text-gray-800">{f.nombre}</div>
                                <div className="text-[10px] text-gray-500">{f.entradas.map((e) => `${e.fecha.slice(8, 10)}/${e.fecha.slice(5, 7)} ${e.codigo}`).join(' · ')}</div>
                              </td>
                              <td className="p-1.5">
                                {f.esCamiones ? (
                                  <select value={faenaCam[k] ?? ''} onChange={(e) => setFaenaCam((p) => ({ ...p, [k]: e.target.value }))}
                                          className="w-full rounded border px-1.5 py-1">
                                    <option value="">— no importar —</option>
                                    {faenas.map((fa) => <option key={fa.id} value={fa.id}>Camiones de {fa.nombre} ({instalaciones.filter((i) => i.tipo === 'camion' && !i.es_comodin && i.faena_id === fa.id).length})</option>)}
                                  </select>
                                ) : (
                                  <div className="flex items-center gap-1">
                                    <select value={mapa[k] ?? ''} onChange={(e) => setMapa((p) => ({ ...p, [k]: e.target.value }))}
                                            className={`w-full rounded border px-1.5 py-1 ${mapa[k] ? '' : 'border-amber-400 bg-amber-50'}`}>
                                      <option value="">— no importar —</option>
                                      {faenas.map((fa) => (
                                        <optgroup key={fa.id} label={fa.nombre}>
                                          {cands.filter((i) => i.faena_id === fa.id).map((i) => <option key={i.id} value={i.id}>{i.nombre}</option>)}
                                        </optgroup>
                                      ))}
                                    </select>
                                    {!mapa[k] && (
                                      <button onClick={() => crearFaltante(h, f.fila, f.nombre)} title="Crear esta instalación en la faena de la hoja"
                                              className="flex shrink-0 items-center gap-0.5 rounded border px-1.5 py-1 text-[11px] text-blue-700 hover:bg-blue-50">
                                        <Plus className="h-3 w-3" /> Crear
                                      </button>
                                    )}
                                  </div>
                                )}
                              </td>
                              <td className="w-20 p-1.5 text-right tabular-nums text-gray-600">{plan.porFila[k] ?? 0} serv.</td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                )
              })}
            </div>
            <div className="rounded-lg border border-blue-200 bg-blue-50/60 px-3 py-2 text-sm text-blue-900">
              Se programarán <b>{plan.items.length}</b> servicios.
              {plan.pasadas > 0 && <> {plan.pasadas} con fecha pasada quedan fuera.</>}
            </div>
            {(plan.sinCamion > 0 || ignorados.length > 0) && (
              <div className="flex gap-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                <div>
                  {plan.sinCamion > 0 && <p>{plan.sinCamion} calibraciones de camión sin patente disponible: la faena no tiene más camiones cargados sin calibración en el período.</p>}
                  {ignorados.length > 0 && <p>Códigos no programados: {ignorados.join(', ')}.</p>}
                </div>
              </div>
            )}
          </>
        )}
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy || plan.items.length === 0} onClick={confirmar}>
          {busy && <Loader2 className="mr-1 h-4 w-4 animate-spin" />} Programar {plan.items.length || ''} servicios
        </Button>
      </ModalFooter>
    </Modal>
  )
}
