'use client'

// ============================================================================
// Recobro al cliente, dentro de la OT (MIG576).
//   1. El JEFE DE TALLER arma las partidas (qué se hizo, repuestos, horas, si
//      se cobra) sin precios, y da el OK.
//   2. El PLANIFICADOR revisa, carga los costos y emite. Si algo no cuadra, se
//      lo devuelve al jefe con una nota.
//   3. Emitido = congelado; el Word sale con la tabla de partidas y los totales.
// Funciona aunque la OT ya esté cerrada: el recobro se arma después del trabajo.
// La base valida cada paso (rpc_recobro_*); la pantalla solo esconde lo que no
// corresponde a tu perfil.
// ============================================================================
import { useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/contexts/auth-context'
import {
  getRecobroOT, perfilRecobro, prepararRecobroOT, guardarPartida, eliminarPartida,
  darOkJefe, devolverAlJefe, emitirRecobro, descargarWordRecobroOT, agregarDesdeChecklist,
  type PartidaRecobro, type TipoPartida,
} from '@/lib/services/recobro-ot'
import { getChecklistV3OT, type ChecklistV3Item } from '@/lib/services/taller-plan-semanal'

const TIPOS: { v: TipoPartida; label: string }[] = [
  { v: 'repuesto', label: 'Repuesto' },
  { v: 'mano_obra', label: 'Mano de obra' },
  { v: 'servicio_externo', label: 'Servicio externo' },
  { v: 'otro', label: 'Otro' },
]
const tipoLabel = (t: string) => TIPOS.find((x) => x.v === t)?.label ?? t
const clp = (n: number) => '$' + Math.round(n || 0).toLocaleString('es-CL')
const fecha = (s: string | null) => s
  ? new Date(s).toLocaleString('es-CL', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : ''

type Borrador = {
  id: string | null
  tipo: TipoPartida
  descripcion: string
  cantidad: string
  unidad: string
  cobrable: boolean
  precio: string
}
const vacia = (): Borrador => ({ id: null, tipo: 'repuesto', descripcion: '', cantidad: '1', unidad: '', cobrable: true, precio: '' })
const desde = (p: PartidaRecobro): Borrador => ({
  id: p.id, tipo: p.tipo, descripcion: p.descripcion, cantidad: String(p.cantidad),
  unidad: p.unidad ?? '', cobrable: p.cobrable_cliente, precio: p.precio_unitario ? String(p.precio_unitario) : '',
})

export function RecobroOTSeccion({ otId, otFolio, embebido = false }: {
  otId: string; otFolio: string | null
  /** Dentro de la pestaña «Recobro» de la OT: sin tarjeta propia. */
  embebido?: boolean
}) {
  const qc = useQueryClient()
  const { perfil } = useAuth()
  const quien = perfilRecobro(perfil?.rol)
  const [editando, setEditando] = useState<Borrador | null>(null)
  const [ocupado, setOcupado] = useState(false)
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null)
  const [notaDevolver, setNotaDevolver] = useState<string | null>(null)
  const [borrando, setBorrando] = useState<string | null>(null)
  const [eligiendo, setEligiendo] = useState(false)

  const { data: r, isLoading } = useQuery({
    queryKey: ['recobro-ot', otId],
    queryFn: () => getRecobroOT(otId),
    staleTime: 0,
  })

  const correr = async (f: () => Promise<unknown>, ok?: string) => {
    setOcupado(true); setMsg(null)
    try {
      await f()
      await qc.invalidateQueries({ queryKey: ['recobro-ot', otId] })
      if (ok) setMsg({ ok: true, texto: ok })
      return true
    } catch (e) {
      setMsg({ ok: false, texto: e instanceof Error ? e.message : 'No se pudo completar' })
      return false
    } finally { setOcupado(false) }
  }

  const inf = r?.informe ?? null
  const abierto = inf && inf.estado !== 'emitido'
  const conOk = !!inf?.ok_jefe_at
  const puedeEditar = !!abierto && !!quien && (quien !== 'jefe' || !conOk)
  const vePrecios = quien === 'planificador' || quien === 'admin' || inf?.estado === 'emitido'
  const editaPrecios = puedeEditar && (quien === 'planificador' || quien === 'admin')
  const partidas = r?.partidas ?? []
  const sinPrecio = partidas.filter((p) => p.cobrable_cliente && !(p.precio_unitario > 0)).length

  const guardar = async () => {
    if (!inf || !editando) return
    const cantidad = Number(editando.cantidad.replace(',', '.'))
    const precio = editando.precio.trim() === '' ? null : Number(editando.precio.replace(/\./g, '').replace(',', '.'))
    const ok = await correr(() => guardarPartida(inf.id, {
      id: editando.id, tipo: editando.tipo, descripcion: editando.descripcion, cantidad,
      unidad: editando.unidad, cobrable: editando.cobrable, precio_unitario: editaPrecios ? precio : null,
    }))
    if (ok) setEditando(null)
  }

  if (isLoading) {
    return <Marco embebido={embebido}><p className="text-sm text-gray-400">Cargando recobro…</p></Marco>
  }

  return (
    <Marco embebido={embebido}>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-base font-bold text-gray-900">Recobro al cliente</h3>
          {inf && (
            <span className="text-xs text-gray-500">
              <span className="font-mono font-bold text-violet-900">{inf.folio}</span>
              {' · '}
              {inf.estado === 'emitido' ? `emitido ${fecha(inf.emitido_en)}` : conOk ? 'OK del jefe · falta costear y emitir' : 'jefe armando partidas'}
            </span>
          )}
        </div>

        {/* Pasos del flujo */}
        <ol className="flex flex-wrap gap-2 text-xs">
          {[
            { t: '1. Jefe arma partidas', hecho: conOk || inf?.estado === 'emitido', actual: !!abierto && !conOk },
            { t: '2. Planificador costea y emite', hecho: inf?.estado === 'emitido', actual: !!abierto && conOk },
            { t: '3. Emitido', hecho: inf?.estado === 'emitido', actual: false },
          ].map((s) => (
            <li key={s.t} className={`rounded-full px-2.5 py-1 ${s.hecho ? 'bg-green-100 text-green-800' : s.actual ? 'bg-violet-100 font-semibold text-violet-900' : 'bg-gray-100 text-gray-500'}`}>
              {s.hecho ? '✓ ' : ''}{s.t}
            </li>
          ))}
        </ol>

        {!inf && (
          <div className="rounded-lg border border-violet-200 bg-violet-50/50 px-3 py-3 text-sm text-violet-900">
            {r && r.ncPendientes > 0
              ? <p><b>{r.ncPendientes} NC</b> de esta OT están marcadas como cobrables al cliente.</p>
              : <p>Esta OT todavía no tiene recobro. Puedes empezarlo y agregar las partidas a mano.</p>}
            {quien ? (
              <Button size="sm" className="mt-2" disabled={ocupado}
                      onClick={() => correr(() => prepararRecobroOT(otId), 'Recobro iniciado con las NC cobrables de la OT')}>
                Iniciar recobro de esta OT
              </Button>
            ) : <p className="mt-1 text-xs text-gray-500">Lo inicia el jefe de taller o el planificador.</p>}
          </div>
        )}

        {inf?.devuelto_nota && !conOk && abierto && (
          <div className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
            <b>El planificador lo devolvió:</b> {inf.devuelto_nota}
          </div>
        )}
        {conOk && inf?.ok_jefe_por && (
          <p className="text-xs text-gray-600">
            OK de <b>{r?.nombres[inf.ok_jefe_por] ?? 'jefe de taller'}</b> el {fecha(inf.ok_jefe_at)}
            {inf.ok_jefe_nota ? ` — «${inf.ok_jefe_nota}»` : ''}
          </p>
        )}

        {inf && (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left text-xs text-gray-500">
                  <th className="py-1.5 pr-2">Tipo</th>
                  <th className="py-1.5 pr-2">Descripción</th>
                  <th className="py-1.5 pr-2 text-right">Cant.</th>
                  <th className="py-1.5 pr-2">Se cobra</th>
                  {vePrecios && <th className="py-1.5 pr-2 text-right">P. unitario</th>}
                  {vePrecios && <th className="py-1.5 pr-2 text-right">Total</th>}
                  {puedeEditar && <th />}
                </tr>
              </thead>
              <tbody>
                {partidas.length === 0 && (
                  <tr><td colSpan={7} className="py-3 text-center text-gray-400">Sin partidas todavía.</td></tr>
                )}
                {partidas.map((p) => (
                  <tr key={p.id} className="border-b last:border-0">
                    <td className="py-1.5 pr-2 text-xs text-gray-600">{tipoLabel(p.tipo)}</td>
                    <td className="py-1.5 pr-2">{p.descripcion}</td>
                    <td className="whitespace-nowrap py-1.5 pr-2 text-right">{p.cantidad.toLocaleString('es-CL')} {p.unidad ?? ''}</td>
                    <td className="py-1.5 pr-2 text-xs">{p.cobrable_cliente ? 'Sí' : <span className="text-gray-400">No</span>}</td>
                    {vePrecios && (
                      <td className={`whitespace-nowrap py-1.5 pr-2 text-right ${p.cobrable_cliente && !(p.precio_unitario > 0) ? 'font-semibold text-red-600' : ''}`}>
                        {p.precio_unitario > 0 ? clp(p.precio_unitario) : 'falta'}
                      </td>
                    )}
                    {vePrecios && <td className="whitespace-nowrap py-1.5 pr-2 text-right">{clp(p.total)}</td>}
                    {puedeEditar && (
                      <td className="whitespace-nowrap py-1.5 text-right">
                        <button className="text-xs text-violet-700 underline" onClick={() => setEditando(desde(p))}>
                          {editaPrecios ? 'Editar / precio' : 'Editar'}
                        </button>
                        <button className={`ml-3 text-xs text-red-600 underline ${borrando === p.id ? 'font-bold' : ''}`} disabled={ocupado}
                                onBlur={() => setBorrando(null)}
                                onClick={() => {
                                  if (borrando !== p.id) { setBorrando(p.id); return }
                                  setBorrando(null); void correr(() => eliminarPartida(p.id))
                                }}>
                          {borrando === p.id ? '¿Quitar? Confirmar' : 'Quitar'}
                        </button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
              {vePrecios && partidas.length > 0 && (
                <tfoot className="text-sm">
                  <tr><td colSpan={5} className="pt-2 text-right text-gray-500">Neto cobrable</td><td className="pt-2 text-right">{clp(inf.total_cobrable_cliente)}</td></tr>
                  <tr><td colSpan={5} className="text-right text-gray-500">IVA 19%</td><td className="text-right">{clp(inf.iva)}</td></tr>
                  <tr><td colSpan={5} className="text-right font-bold">Total a recobrar</td><td className="text-right font-bold">{clp(inf.total)}</td></tr>
                </tfoot>
              )}
            </table>
          </div>
        )}

        {/* Formulario de partida */}
        {editando && (
          <div className="space-y-2 rounded-lg border border-violet-200 bg-violet-50/40 p-3">
            <p className="text-sm font-semibold text-violet-900">{editando.id ? 'Editar partida' : 'Nueva partida'}</p>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-6">
              <select className="rounded border px-2 py-1.5 text-sm sm:col-span-2" value={editando.tipo}
                      onChange={(e) => setEditando({ ...editando, tipo: e.target.value as TipoPartida })}>
                {TIPOS.map((t) => <option key={t.v} value={t.v}>{t.label}</option>)}
              </select>
              <input className="rounded border px-2 py-1.5 text-sm sm:col-span-4" placeholder="Descripción (qué se hizo o qué repuesto)"
                     value={editando.descripcion} onChange={(e) => setEditando({ ...editando, descripcion: e.target.value })} />
              <input className="rounded border px-2 py-1.5 text-sm" placeholder="Cantidad" inputMode="decimal"
                     value={editando.cantidad} onChange={(e) => setEditando({ ...editando, cantidad: e.target.value })} />
              <input className="rounded border px-2 py-1.5 text-sm" placeholder="Unidad (un, HH, lt)"
                     value={editando.unidad} onChange={(e) => setEditando({ ...editando, unidad: e.target.value })} />
              <label className="flex items-center gap-2 text-sm sm:col-span-2">
                <input type="checkbox" checked={editando.cobrable}
                       onChange={(e) => setEditando({ ...editando, cobrable: e.target.checked })} />
                Se cobra al cliente
              </label>
              {editaPrecios && (
                <input className="rounded border px-2 py-1.5 text-sm sm:col-span-2" placeholder="Precio unitario neto $" inputMode="numeric"
                       value={editando.precio} onChange={(e) => setEditando({ ...editando, precio: e.target.value })} />
              )}
            </div>
            <div className="flex gap-2">
              <Button size="sm" disabled={ocupado || !editando.descripcion.trim()} onClick={guardar}>Guardar</Button>
              <Button size="sm" variant="secondary" onClick={() => setEditando(null)}>Cancelar</Button>
            </div>
          </div>
        )}

        {/* Acciones */}
        {inf && (
          <div className="flex flex-wrap items-center gap-2">
            {puedeEditar && !editando && (
              <Button size="sm" variant="secondary" onClick={() => setEditando(vacia())}>+ Agregar partida</Button>
            )}
            {puedeEditar && !eligiendo && (
              <Button size="sm" variant="secondary" onClick={() => setEligiendo(true)}>+ Tareas del checklist</Button>
            )}
            {puedeEditar && (r?.ncPendientes ?? 0) > 0 && (
              <Button size="sm" variant="secondary" disabled={ocupado}
                      onClick={() => correr(() => prepararRecobroOT(otId), 'NC cobrables agregadas')}>
                Traer {r?.ncPendientes} NC cobrable{r?.ncPendientes === 1 ? '' : 's'} nueva{r?.ncPendientes === 1 ? '' : 's'}
              </Button>
            )}
            {abierto && !conOk && (quien === 'jefe' || quien === 'admin') && (
              <Button size="sm" disabled={ocupado || partidas.length === 0}
                      onClick={() => correr(() => darOkJefe(inf.id), 'OK enviado: ahora el planificador carga los costos y emite')}>
                Dar OK para costear
              </Button>
            )}
            {abierto && conOk && (quien === 'planificador' || quien === 'admin') && (
              <>
                <Button size="sm" disabled={ocupado || sinPrecio > 0}
                        title={sinPrecio > 0 ? `Faltan precios en ${sinPrecio} partida(s)` : undefined}
                        onClick={() => correr(() => emitirRecobro(inf.id), 'Informe emitido: ya se puede descargar el Word')}>
                  Emitir informe de recobro
                </Button>
                <Button size="sm" variant="secondary" disabled={ocupado} onClick={() => setNotaDevolver('')}>
                  Devolver al jefe
                </Button>
              </>
            )}
            <Button size="sm" variant="secondary" disabled={ocupado}
                    onClick={() => r && correr(() => descargarWordRecobroOT(r, otFolio))}>
              {inf.estado === 'emitido' ? 'Descargar Word' : 'Ver borrador en Word'}
            </Button>
            {abierto && conOk && sinPrecio > 0 && vePrecios && (
              <span className="text-xs text-red-600">Faltan precios en {sinPrecio} partida(s) cobrable(s).</span>
            )}
          </div>
        )}

        {notaDevolver !== null && inf && (
          <div className="space-y-2 rounded-lg border border-amber-300 bg-amber-50 p-3">
            <p className="text-sm font-semibold text-amber-900">¿Qué tiene que corregir el jefe?</p>
            <textarea className="w-full rounded border px-2 py-1.5 text-sm" rows={2} value={notaDevolver}
                      onChange={(e) => setNotaDevolver(e.target.value)} />
            <div className="flex gap-2">
              <Button size="sm" disabled={ocupado || !notaDevolver.trim()}
                      onClick={async () => { if (await correr(() => devolverAlJefe(inf.id, notaDevolver), 'Devuelto al jefe')) setNotaDevolver(null) }}>
                Devolver
              </Button>
              <Button size="sm" variant="secondary" onClick={() => setNotaDevolver(null)}>Cancelar</Button>
            </div>
          </div>
        )}

        {msg && <p className={`text-sm ${msg.ok ? 'text-green-700' : 'text-red-600'}`}>{msg.texto}</p>}

        {(r?.emitidos.length ?? 0) > 0 && abierto && (
          <p className="text-xs text-gray-500">
            Informes ya emitidos de esta OT: {r!.emitidos.map((e) => `${e.folio} (${clp(e.total)})`).join(', ')}
          </p>
        )}
        {!quien && inf && abierto && (
          <p className="text-xs text-gray-500">Las partidas las arma el jefe de taller y las costea el planificador.</p>
        )}

        {eligiendo && inf && (
          <SelectorChecklist
            otId={otId}
            yaEnInforme={new Set(r?.itemsEnInforme ?? [])}
            ocupado={ocupado}
            onCerrar={() => setEligiendo(false)}
            onAgregar={async (ids) => {
              let texto = ''
              const ok = await correr(async () => {
                const res = await agregarDesdeChecklist(inf.id, ids)
                texto = `${res.agregadas} tarea(s) agregada(s) al recobro${res.ya_estaban ? ` · ${res.ya_estaban} ya estaban` : ''}`
              })
              if (ok) { setEligiendo(false); setMsg({ ok: true, texto }) }
            }}
          />
        )}
    </Marco>
  )
}

function Marco({ embebido, children }: { embebido: boolean; children: ReactNode }) {
  return embebido
    ? <div className="space-y-3">{children}</div>
    : <Card className="mt-4"><CardContent className="space-y-3 p-4 sm:p-6">{children}</CardContent></Card>
}

// ── Elegir tareas del checklist de la OT (MIG578) ───────────────────────────
function SelectorChecklist({ otId, yaEnInforme, ocupado, onCerrar, onAgregar }: {
  otId: string
  yaEnInforme: Set<string>
  ocupado: boolean
  onCerrar: () => void
  onAgregar: (ids: string[]) => void
}) {
  const { data: items = [], isLoading } = useQuery({
    queryKey: ['checklist-v3', otId],
    queryFn: () => getChecklistV3OT(otId),
  })
  const [q, setQ] = useState('')
  const [soloConFoto, setSoloConFoto] = useState(false)
  const [soloNoOk, setSoloNoOk] = useState(false)
  const [sel, setSel] = useState<Set<string>>(new Set())

  const norm = (t: string) => t.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
  const fotos = (it: ChecklistV3Item) => (it.foto_urls?.length ?? 0) || (it.foto_url ? 1 : 0)
  const esNoOk = (it: ChecklistV3Item) => (it.resultado ?? '').toLowerCase().replace(/[\s_]/g, '') === 'nook'
  const visibles = items.filter((it) =>
    !it.excluido
    && (!q.trim() || norm(`${it.codigo ?? ''} ${it.descripcion} ${it.observacion ?? ''} ${it.bloque}`).includes(norm(q.trim())))
    && (!soloConFoto || fotos(it) > 0)
    && (!soloNoOk || esNoOk(it)))
  const porBloque = new Map<string, ChecklistV3Item[]>()
  for (const it of visibles) porBloque.set(it.bloque, [...(porBloque.get(it.bloque) ?? []), it])

  const toggle = (id: string) => setSel((s) => {
    const n = new Set(s)
    if (n.has(id)) n.delete(id)
    else n.add(id)
    return n
  })

  return (
    <div className="space-y-2 rounded-lg border border-violet-200 bg-white p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm font-semibold text-violet-900">Tareas del checklist de la OT</p>
        <button className="text-xs text-gray-500 underline" onClick={onCerrar}>Cerrar</button>
      </div>
      <p className="text-xs text-gray-500">
        Marca las tareas que se le cobran al cliente. Cada una entra con su observación y sus fotos (salen en el Word)
        y una partida de mano de obra con el tiempo de la tarea; el precio lo pone el planificador.
      </p>
      <div className="flex flex-wrap items-center gap-3">
        <input className="min-w-[12rem] flex-1 rounded border px-2 py-1.5 text-sm" placeholder="Buscar tarea, código u observación…"
               value={q} onChange={(e) => setQ(e.target.value)} />
        <label className="flex items-center gap-1 text-xs"><input type="checkbox" checked={soloConFoto} onChange={(e) => setSoloConFoto(e.target.checked)} /> Solo con foto</label>
        <label className="flex items-center gap-1 text-xs"><input type="checkbox" checked={soloNoOk} onChange={(e) => setSoloNoOk(e.target.checked)} /> Solo NO OK</label>
      </div>
      {isLoading ? <p className="text-sm text-gray-400">Cargando checklist…</p> : (
        <div className="max-h-[28rem] space-y-3 overflow-y-auto pr-1">
          {porBloque.size === 0 && <p className="text-sm text-gray-400">No hay tareas con ese filtro.</p>}
          {Array.from(porBloque.entries()).map(([bloque, xs]) => (
            <div key={bloque}>
              <p className="sticky top-0 bg-white py-1 text-xs font-bold uppercase text-gray-500">{bloque}</p>
              {xs.map((it) => {
                const ya = yaEnInforme.has(it.instance_item_id)
                return (
                  <label key={it.instance_item_id}
                         className={`flex items-start gap-2 rounded px-2 py-1.5 text-sm ${ya ? 'opacity-60' : 'hover:bg-violet-50'}`}>
                    <input type="checkbox" className="mt-1" disabled={ya}
                           checked={ya || sel.has(it.instance_item_id)} onChange={() => toggle(it.instance_item_id)} />
                    <span className="min-w-0 flex-1">
                      <span className="font-mono text-xs text-gray-400">{it.codigo} </span>
                      {it.descripcion}
                      <span className="ml-2 text-xs text-gray-500">
                        {it.resultado ? `· ${it.resultado}` : ''}{fotos(it) ? ` · 📷 ${fotos(it)}` : ''}{it.tiempo_min ? ` · ${it.tiempo_min} min` : ''}
                        {ya ? ' · ya está en el recobro' : ''}
                      </span>
                      {it.observacion && <span className="block text-xs text-gray-600">«{it.observacion}»</span>}
                    </span>
                  </label>
                )
              })}
            </div>
          ))}
        </div>
      )}
      <div className="flex gap-2">
        <Button size="sm" disabled={ocupado || sel.size === 0} onClick={() => onAgregar(Array.from(sel))}>
          Agregar {sel.size || ''} tarea{sel.size === 1 ? '' : 's'} al recobro
        </Button>
        <Button size="sm" variant="secondary" onClick={onCerrar}>Cancelar</Button>
      </div>
    </div>
  )
}

