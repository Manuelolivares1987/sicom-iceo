'use client'

// ============================================================================
// Control documental de flota. [MIG409/410]
// ----------------------------------------------------------------------------
// Manuel: «un menú exclusivo para tratar todos los papeles no vigentes de la
// flota por camión, con este nuevo escaneo, y actualizar esto».
//
// Camión a la izquierda, sus papeles a la derecha. Cada papel que le falta la
// fecha llega con lo que el lector sacó del PDF —la fecha propuesta, la regla
// que usó y la cita textual— y se acepta con un clic. El enlace al archivo está
// siempre, porque nadie debería tener que creerle a un algoritmo sin poder
// verificar.
//
// Lo que se arregla acá se ve al tiro en el QR del equipo: es la misma vista.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  FileWarning, Search, ExternalLink, Check, X, AlertTriangle, Loader2, ShieldCheck,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
// `Infinity` es un valor global de JavaScript: se importa con alias para no
// sombrearlo dentro de este archivo.
import { Infinity as IconoSinVencimiento } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getEquiposDocumental, getPapelesEquipo, fijarFecha, descartarPropuesta,
  marcarNoCaduca, vuelveACaducar,
  ESTADO_DOC, CONFIANZA, nombreTipo,
  type EquipoDocumental, type PapelEquipo,
} from '@/lib/services/control-documental'

export default function ControlDocumentalPage() {
  const { loading: authLoading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()

  const [sel, setSel] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [soloProblemas, setSoloProblemas] = useState(true)
  const [editando, setEditando] = useState<PapelEquipo | null>(null)
  // [MIG427] El papel que se está por marcar como que no caduca.
  const [noCaduca, setNoCaduca] = useState<PapelEquipo | null>(null)

  const { data: equipos = [], isLoading } = useQuery({
    queryKey: ['control-doc-equipos'], queryFn: getEquiposDocumental,
  })
  const activo = sel ?? equipos[0]?.activo_id ?? null
  const { data: papeles = [], isLoading: cargandoPapeles } = useQuery({
    queryKey: ['control-doc-papeles', activo],
    queryFn: () => getPapelesEquipo(activo!),
    enabled: !!activo,
  })

  const visibles = useMemo(() => {
    const q = busca.trim().toLowerCase()
    return equipos.filter((e) => {
      if (soloProblemas && e.vencidos === 0 && e.sin_fecha === 0 && e.por_vencer === 0) return false
      if (!q) return true
      return (e.patente ?? '').toLowerCase().includes(q) ||
             (e.activo_codigo ?? '').toLowerCase().includes(q) ||
             (e.activo_nombre ?? '').toLowerCase().includes(q)
    })
  }, [equipos, busca, soloProblemas])

  const tot = useMemo(() => equipos.reduce((a, e) => ({
    venc: a.venc + e.vencidos, sf: a.sf + e.sin_fecha, pv: a.pv + e.por_vencer,
    prop: a.prop + e.con_propuesta,
  }), { venc: 0, sf: 0, pv: 0, prop: 0 }), [equipos])

  const eqSel = equipos.find((e) => e.activo_id === activo)

  if (authLoading) return <div className="flex justify-center py-20"><Spinner /></div>

  const refrescar = () => {
    qc.invalidateQueries({ queryKey: ['control-doc-equipos'] })
    qc.invalidateQueries({ queryKey: ['control-doc-papeles'] })
  }

  return (
    <div className="space-y-4 p-4 md:p-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold">
          <FileWarning className="h-6 w-6 text-orange-600" /> Control documental de flota
        </h1>
        <p className="mt-1 max-w-3xl text-sm text-gray-600">
          Los papeles de cada camión, con lo que el sistema pudo leer de cada archivo.
          Lo que arregles acá se ve al instante en el QR que escanea el cliente.
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Tile n={tot.venc} label="vencidos" sub="ya caducaron" cls="text-red-600 border-red-500" />
        <Tile n={tot.sf} label="sin fecha" sub="hay papel, falta la vigencia" cls="text-orange-600 border-orange-500" />
        <Tile n={tot.pv} label="por vencer" sub="dentro de 30 días" cls="text-amber-600 border-amber-500" />
        <Tile n={tot.prop} label="con propuesta" sub="el sistema leyó el archivo" cls="text-teal-700 border-teal-600" />
      </div>

      <div className="grid gap-4 lg:grid-cols-[300px_1fr]">
        {/* ── Los camiones ────────────────────────────────────────────────── */}
        <Card className="h-fit">
          <CardContent className="space-y-2 p-3">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-gray-400" />
              <Input value={busca} onChange={(e) => setBusca(e.target.value)} className="pl-8 h-9"
                     placeholder="Buscar patente…" />
            </div>
            <label className="flex items-center gap-1.5 text-[11px] text-gray-600">
              <input type="checkbox" checked={soloProblemas} className="h-3.5 w-3.5"
                     onChange={(e) => setSoloProblemas(e.target.checked)} />
              Sólo los que tienen algo pendiente
            </label>
            {isLoading ? <div className="py-6 text-center"><Spinner className="h-4 w-4" /></div> : (
              <div className="max-h-[70vh] space-y-1 overflow-y-auto">
                {visibles.map((e) => (
                  <button key={e.activo_id} type="button" onClick={() => setSel(e.activo_id)}
                    className={`w-full rounded-lg border p-2 text-left transition-colors ${
                      e.activo_id === activo ? 'border-gray-900 bg-gray-50 ring-1 ring-gray-900' : 'hover:bg-gray-50'}`}>
                    <div className="flex items-center gap-1.5">
                      <span className="text-sm font-bold">{e.patente}</span>
                      {e.vencidos > 0 && <Chip n={e.vencidos} cls="bg-red-600 text-white" t="vencidos" />}
                      {e.sin_fecha > 0 && <Chip n={e.sin_fecha} cls="bg-orange-500 text-white" t="sin fecha" />}
                      {e.vencidos === 0 && e.sin_fecha === 0 && e.por_vencer === 0 && (
                        <ShieldCheck className="ml-auto h-3.5 w-3.5 text-green-600" />
                      )}
                    </div>
                    <div className="truncate text-[11px] text-gray-500">{e.activo_nombre}</div>
                  </button>
                ))}
                {visibles.length === 0 && (
                  <p className="py-6 text-center text-xs text-gray-400">
                    {soloProblemas ? 'Ningún equipo con pendientes.' : 'Sin resultados.'}
                  </p>
                )}
              </div>
            )}
          </CardContent>
        </Card>

        {/* ── Los papeles del camión elegido ──────────────────────────────── */}
        <div className="space-y-2">
          {eqSel && (
            <div className="flex flex-wrap items-baseline gap-2">
              <h2 className="text-lg font-bold">{eqSel.patente}</h2>
              <span className="text-sm text-gray-500">{eqSel.activo_nombre}</span>
              <span className="ml-auto text-[11px] text-gray-500">
                {eqSel.total} documentos · {eqSel.vigentes} al día
              </span>
            </div>
          )}
          {cargandoPapeles ? <div className="py-10 text-center"><Spinner /></div> : (
            <div className="space-y-1.5">
              {papeles.map((p) => (
                <PapelCard key={p.certificacion_id} p={p}
                           onEditar={() => setEditando(p)}
                           onNoCaduca={() => setNoCaduca(p)}
                           onVuelveACaducar={async () => {
                             try {
                               // Si el TIPO estaba marcado, revertir sólo este papel
                               // no sirve: la vista lo volvería a dar por permanente.
                               const alcance = p.tipo_no_caduca ? 'tipo' : 'este'
                               const r = await vuelveACaducar(p.certificacion_id, alcance)
                               toast.success(alcance === 'tipo'
                                 ? `${nombreTipo(p.tipo)} vuelve a caducar — ${r.papeles_afectados} papeles piden fecha otra vez`
                                 : 'Este papel vuelve a pedir fecha')
                               refrescar()
                             } catch (e) { toast.error((e as Error).message) }
                           }}
                           onAceptar={async () => {
                             try {
                               const r = await fijarFecha({
                                 certificacionId: p.certificacion_id,
                                 vencimiento: p.vencimiento_propuesto!,
                                 emision: p.emision_propuesta,
                                 origen: p.propuesta_confianza === 'alta' ? 'documento' : 'regla_2_anios',
                               })
                               toast.success(r.vencido
                                 ? `Registrado: venció el ${r.vencimiento}`
                                 : `Registrado: vence el ${r.vencimiento}`)
                               refrescar()
                             } catch (e) { toast.error((e as Error).message) }
                           }}
                           onDescartar={async () => {
                             try {
                               await descartarPropuesta(p.certificacion_id, 'La fecha propuesta no corresponde')
                               toast.success('Propuesta descartada')
                               refrescar()
                             } catch (e) { toast.error((e as Error).message) }
                           }} />
              ))}
              {papeles.length === 0 && (
                <p className="py-10 text-center text-sm text-gray-400">Este equipo no tiene documentos cargados.</p>
              )}
            </div>
          )}
        </div>
      </div>

      {editando && (
        <ModalFecha p={editando} onClose={() => setEditando(null)}
                    onListo={() => { setEditando(null); refrescar() }} />
      )}
      {noCaduca && (
        <ModalNoCaduca p={noCaduca} onClose={() => setNoCaduca(null)}
                       onListo={() => { setNoCaduca(null); refrescar() }} />
      )}
    </div>
  )
}

function Tile({ n, label, sub, cls }: { n: number; label: string; sub: string; cls: string }) {
  return (
    <div className={`rounded-lg border border-l-4 bg-white p-3 ${cls}`}>
      <div className={`text-2xl font-bold tabular-nums ${cls.split(' ')[0]}`}>{n}</div>
      <div className="text-xs font-medium text-gray-700">{label}</div>
      <div className="text-[11px] text-gray-400">{sub}</div>
    </div>
  )
}

function Chip({ n, cls, t }: { n: number; cls: string; t: string }) {
  return <span title={t} className={`rounded-full px-1.5 text-[10px] font-bold ${cls}`}>{n}</span>
}

function PapelCard({ p, onAceptar, onDescartar, onEditar, onNoCaduca, onVuelveACaducar }: {
  p: PapelEquipo; onAceptar: () => void; onDescartar: () => void; onEditar: () => void
  onNoCaduca: () => void; onVuelveACaducar: () => void
}) {
  const [busy, setBusy] = useState(false)
  const est = ESTADO_DOC[p.estado] ?? ESTADO_DOC.no_aplica
  const conf = p.propuesta_confianza ? CONFIANZA[p.propuesta_confianza] : null
  const puedeAceptar = !!p.vencimiento_propuesto && p.estado !== 'vigente'
  // Marcado a mano en este papel, o el tipo entero declarado permanente.
  const yaNoCaduca = p.fecha_origen === 'documento_sin_vencimiento' || !!p.tipo_no_caduca

  const correr = async (fn: () => Promise<void> | void) => {
    setBusy(true); try { await fn() } finally { setBusy(false) }
  }

  return (
    <div className={`rounded-lg border bg-white p-3 ${
      p.estado === 'vencido' ? 'border-l-4 border-l-red-500'
      : p.estado === 'sin_fecha' ? 'border-l-4 border-l-orange-500'
      : p.estado === 'por_vencer' ? 'border-l-4 border-l-amber-500' : ''}`}>
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-semibold text-gray-800">{nombreTipo(p.tipo)}</span>
        <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${est.cls}`}>{est.label}</span>
        {p.bloqueante && (
          <span className="flex items-center gap-0.5 text-[10px] font-semibold text-red-600">
            <AlertTriangle className="h-3 w-3" /> Bloqueante
          </span>
        )}
        {p.archivo_url && (
          <a href={p.archivo_url} target="_blank" rel="noreferrer"
             className="ml-auto flex items-center gap-1 text-[11px] font-medium text-blue-600 hover:underline">
            Ver el archivo <ExternalLink className="h-3 w-3" />
          </a>
        )}
      </div>

      <div className="mt-0.5 text-[11px] text-gray-500">
        {yaNoCaduca ? 'Este documento no vence'
          : p.fecha_vencimiento
          ? <>Vence {p.fecha_vencimiento}{p.dias_restantes != null && ` · ${p.dias_restantes} días`}</>
          : 'Sin fecha de vencimiento registrada'}
        {p.fecha_origen && p.fecha_origen !== 'documento_sin_vencimiento' && (
          <span className="ml-1 text-gray-400">· fecha {
            p.fecha_origen === 'documento' ? 'leída del documento'
            : p.fecha_origen === 'regla_2_anios' ? 'por regla de 2 años'
            : p.fecha_origen === 'carga_inicial' ? 'de la carga de abril'
            : 'escrita a mano'}</span>
        )}
      </div>

      {/* Lo que el lector sacó del archivo */}
      {conf && p.estado !== 'vigente' && (
        <div className="mt-2 rounded-lg bg-gray-50 p-2">
          <div className="flex flex-wrap items-center gap-2">
            <span className={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${conf.cls}`}>{conf.label}</span>
            {p.vencimiento_propuesto ? (
              <span className="text-xs">
                propone <b className={p.propuesta_vencida ? 'text-red-600' : ''}>{p.vencimiento_propuesto}</b>
                {p.propuesta_vencida && <span className="text-red-600"> — ya vencido</span>}
              </span>
            ) : <span className="text-xs text-gray-500">no pudo sacar la fecha</span>}
          </div>
          <p className="mt-1 text-[11px] text-gray-500">{conf.detalle}</p>
          {p.propuesta_evidencia && (
            <details className="mt-1">
              <summary className="cursor-pointer text-[11px] font-medium text-gray-500">Lo que dice el archivo</summary>
              <p className="mt-1 rounded bg-white p-1.5 font-mono text-[10px] leading-relaxed text-gray-600">
                …{p.propuesta_evidencia.slice(0, 300)}…
              </p>
            </details>
          )}
        </div>
      )}

      {/* ── Qué se puede hacer con este papel ────────────────────────────────
          La botonera vivía DENTRO del bloque de la propuesta, así que un papel
          del que el lector no sacó nada —que son la mayoría— no tenía ninguna
          acción: se veía el problema y no se podía resolver. Ahora está afuera. */}
      <div className="mt-2 flex flex-wrap items-center gap-1.5">
        {puedeAceptar && (
          <Button className="h-7 text-xs" disabled={busy} onClick={() => correr(onAceptar)}>
            {busy ? <Loader2 className="mr-1 h-3 w-3 animate-spin" /> : <Check className="mr-1 h-3 w-3" />}
            Aceptar {p.vencimiento_propuesto}
          </Button>
        )}

        {yaNoCaduca ? (
          <>
            <span className="flex items-center gap-1 rounded-full bg-gray-100 px-2 py-0.5 text-[11px] font-medium text-gray-600">
              <IconoSinVencimiento className="h-3 w-3" />
              {p.tipo_no_caduca ? 'Este tipo de documento no caduca' : 'Este papel no caduca'}
            </span>
            <Button variant="ghost" className="h-7 text-xs text-gray-500" disabled={busy}
                    onClick={() => correr(onVuelveACaducar)}>
              {p.tipo_no_caduca ? 'Sí caduca, revertir para todo el tipo' : 'Sí caduca'}
            </Button>
          </>
        ) : (
          <>
            <Button variant="outline" className="h-7 text-xs" onClick={onEditar}>
              {p.fecha_vencimiento ? 'Escribir otra fecha' : 'Escribir la fecha'}
            </Button>
            <Button variant="outline" className="h-7 text-xs" onClick={onNoCaduca}>
              <IconoSinVencimiento className="mr-1 h-3 w-3" /> No caduca
            </Button>
          </>
        )}

        {p.propuesta_id && !yaNoCaduca && (
          <Button variant="ghost" className="h-7 text-xs text-gray-500" disabled={busy}
                  onClick={() => correr(onDescartar)}>
            <X className="mr-1 h-3 w-3" /> Descartar la propuesta
          </Button>
        )}
      </div>
    </div>
  )
}

/**
 * Marcar que un papel no caduca. [MIG427]
 *
 * Lo único que este modal decide es el ALCANCE, y por eso es lo primero que se
 * ve. «Este papel» y «todos los de este tipo» no son la misma afirmación: la
 * segunda vale también para los documentos que lleguen mañana, y es la que
 * corresponde al certificado de cabina.
 */
function ModalNoCaduca({ p, onClose, onListo }: {
  p: PapelEquipo; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  const [alcance, setAlcance] = useState<'este' | 'tipo'>('tipo')
  const [motivo, setMotivo] = useState('')
  const [busy, setBusy] = useState(false)

  // La base lo exige para un bloqueante; el aviso va acá para no chocar contra
  // un error del servidor después de haber apretado el botón.
  const faltaMotivo = !!p.bloqueante && !motivo.trim()

  const guardar = async () => {
    setBusy(true)
    try {
      const r = await marcarNoCaduca({ certificacionId: p.certificacion_id, alcance, motivo })
      toast.success(alcance === 'tipo'
        ? `${nombreTipo(p.tipo)}: no caduca. Se resolvieron ${r.papeles_resueltos} papeles de la flota.`
        : `${nombreTipo(p.tipo)} del ${p.patente}: no caduca.`)
      onListo()
    } catch (e) {
      toast.error((e as Error).message)
    } finally { setBusy(false) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={onClose}>
      <div className="w-full max-w-lg rounded-xl bg-white p-5 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="text-base font-bold">Este documento no caduca</h3>
        <p className="mt-0.5 text-xs text-gray-500">
          {nombreTipo(p.tipo)} · {p.patente}
        </p>

        <div className="mt-4 space-y-2">
          <label className={`flex cursor-pointer gap-3 rounded-lg border p-3 ${
            alcance === 'tipo' ? 'border-blue-500 bg-blue-50' : 'hover:bg-gray-50'}`}>
            <input type="radio" className="mt-1" checked={alcance === 'tipo'}
                   onChange={() => setAlcance('tipo')} />
            <span>
              <span className="block text-sm font-semibold">Ningún «{nombreTipo(p.tipo)}» caduca</span>
              <span className="block text-xs text-gray-500">
                Vale para toda la flota y para los que se carguen más adelante. Es el caso
                del certificado de cabina: no vence en ningún equipo.
              </span>
            </span>
          </label>

          <label className={`flex cursor-pointer gap-3 rounded-lg border p-3 ${
            alcance === 'este' ? 'border-blue-500 bg-blue-50' : 'hover:bg-gray-50'}`}>
            <input type="radio" className="mt-1" checked={alcance === 'este'}
                   onChange={() => setAlcance('este')} />
            <span>
              <span className="block text-sm font-semibold">Sólo este papel del {p.patente}</span>
              <span className="block text-xs text-gray-500">
                Este documento en particular no declara vencimiento. Los demás del
                mismo tipo siguen pidiendo fecha.
              </span>
            </span>
          </label>
        </div>

        <div className="mt-4">
          <label className="text-xs font-medium text-gray-600">
            Por qué no caduca {p.bloqueante && <span className="text-red-600">· obligatorio</span>}
          </label>
          <textarea rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)}
                    placeholder="Ej: certifica una condición del equipo, no una autorización con plazo."
                    className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          {p.bloqueante && (
            <p className="mt-1 text-[11px] text-red-600">
              Es un certificado bloqueante: autoriza a operar. Decir que no vence tiene
              que quedar explicado y firmado.
            </p>
          )}
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button disabled={busy || faltaMotivo} onClick={guardar}>
            {busy && <Loader2 className="mr-1 h-4 w-4 animate-spin" />}
            {alcance === 'tipo' ? 'Marcar todo el tipo' : 'Marcar este papel'}
          </Button>
        </div>
      </div>
    </div>
  )
}

function ModalFecha({ p, onClose, onListo }: {
  p: PapelEquipo; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  const [venc, setVenc] = useState(p.vencimiento_propuesto ?? '')
  const [emi, setEmi] = useState(p.emision_propuesta ?? '')
  const [nota, setNota] = useState('')
  const [busy, setBusy] = useState(false)

  const guardar = async () => {
    setBusy(true)
    try {
      const r = await fijarFecha({
        certificacionId: p.certificacion_id, vencimiento: venc,
        emision: emi || null, origen: 'manual', nota: nota || null,
      })
      toast.success(r.vencido ? `Registrado: venció el ${r.vencimiento}` : `Registrado: vence el ${r.vencimiento}`)
      onListo()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={`${nombreTipo(p.tipo)} · ${p.patente}`}>
      <div className="space-y-3">
        {p.archivo_url && (
          <a href={p.archivo_url} target="_blank" rel="noreferrer"
             className="inline-flex items-center gap-1 text-sm font-medium text-blue-600 hover:underline">
            Abrir el archivo para verificar <ExternalLink className="h-3.5 w-3.5" />
          </a>
        )}
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs font-medium text-gray-700">
            Vence el
            <Input type="date" value={venc} onChange={(e) => setVenc(e.target.value)} className="mt-1" />
          </label>
          <label className="text-xs font-medium text-gray-700">
            Emitido el (opcional)
            <Input type="date" value={emi} onChange={(e) => setEmi(e.target.value)} className="mt-1" />
          </label>
        </div>
        <label className="block text-xs font-medium text-gray-700">
          Nota (opcional)
          <Input value={nota} onChange={(e) => setNota(e.target.value)} className="mt-1"
                 placeholder="De dónde sacaste la fecha" />
        </label>
        <p className="text-[11px] text-gray-400">
          Queda registrado que la fecha la escribió una persona, con tu nombre y la fecha de hoy.
        </p>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy || !venc} onClick={guardar}>
          {busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Check className="mr-1 h-4 w-4" />}
          Guardar
        </Button>
      </ModalFooter>
    </Modal>
  )
}
