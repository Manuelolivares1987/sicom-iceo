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
import { Infinity as IconoSinVencimiento, Upload } from 'lucide-react'
import { subirDocumentoCert, renovarCertificacion } from '@/lib/services/taller-planificacion'
import { leerDocumento, type LecturaDocumento } from '@/lib/documentos/leer-documento'
// El status y sus colores se toman de donde ya viven: es el mismo vocabulario
// que usa el planificador y que propone Sugerencias GPS. Duplicarlo acá sería
// la forma más rápida de que dos pantallas terminen diciendo cosas distintas.
import { ESTADO_CODIGO_LABELS, ESTADO_CODIGO_COLORS, ESTADO_CODIGO_ORDEN,
         type EstadoCodigo } from '@/lib/services/cierre-diario'
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
  // El papel cuyo archivo se está por reemplazar por uno nuevo.
  const [subiendo, setSubiendo] = useState<PapelEquipo | null>(null)
  // [MIG428] El status va primero porque es la pregunta que se hace primero:
  // «de los que están arrendados, ¿cuáles tienen los papeles al día?».
  const [status, setStatus] = useState<string>('')
  const [zona, setZona] = useState<string>('')

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
      if (status && (e.status_codigo ?? '') !== status) return false
      // 'taller' agrupa a los que no tienen operación asignada: están adentro.
      if (zona === 'taller' ? !!e.zona : zona && e.zona !== zona) return false
      if (soloProblemas && e.vencidos === 0 && e.sin_fecha === 0 && e.por_vencer === 0) return false
      if (!q) return true
      return (e.patente ?? '').toLowerCase().includes(q) ||
             (e.activo_codigo ?? '').toLowerCase().includes(q) ||
             (e.activo_nombre ?? '').toLowerCase().includes(q)
    })
  }, [equipos, busca, soloProblemas, status, zona])

  /** Los status que existen hoy en la flota, en el orden del planificador. */
  const statusDisponibles = useMemo(() => {
    const cuenta = new Map<string, number>()
    for (const e of equipos) {
      const c = e.status_codigo
      if (c) cuenta.set(c, (cuenta.get(c) ?? 0) + 1)
    }
    return ESTADO_CODIGO_ORDEN.filter((c) => cuenta.has(c))
      .map((c) => ({ codigo: c, n: cuenta.get(c)! }))
  }, [equipos])

  const zonasDisponibles = useMemo(() => {
    const z: string[] = []
    let enTaller = 0
    for (const e of equipos) {
      if (!e.zona) { enTaller++; continue }
      if (!z.includes(e.zona)) z.push(e.zona)
    }
    return { zonas: z.sort(), enTaller }
  }, [equipos])

  /** Lo que muestran los recuadros de arriba: sigue al filtro, no a la flota
   *  entera. Un total que no cambia al filtrar confunde más de lo que informa. */
  const totFiltrado = useMemo(() => visibles.reduce((a, e) => ({
    venc: a.venc + e.vencidos, sf: a.sf + e.sin_fecha, pv: a.pv + e.por_vencer,
    prop: a.prop + e.con_propuesta, bloq: a.bloq + e.vencidos_bloqueantes,
  }), { venc: 0, sf: 0, pv: 0, prop: 0, bloq: 0 }), [visibles])

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

      {/* ── El status primero, que es la pregunta que se hace primero ──────── */}
      <div className="rounded-lg border bg-white p-3">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="mr-1 text-[11px] font-semibold uppercase tracking-wide text-gray-500">Status</span>
          <FiltroChip activo={!status} onClick={() => setStatus('')}
                      label="Todos" n={equipos.length} />
          {statusDisponibles.map(({ codigo, n }) => (
            <FiltroChip key={codigo} activo={status === codigo} onClick={() => setStatus(codigo)}
                        label={ESTADO_CODIGO_LABELS[codigo as EstadoCodigo] ?? codigo} n={n}
                        cls={ESTADO_CODIGO_COLORS[codigo as EstadoCodigo]} />
          ))}
        </div>
        <div className="mt-2 flex flex-wrap items-center gap-1.5 border-t pt-2">
          <span className="mr-1 text-[11px] font-semibold uppercase tracking-wide text-gray-500">Zona</span>
          <FiltroChip activo={!zona} onClick={() => setZona('')} label="Todas" n={equipos.length} />
          {zonasDisponibles.zonas.map((z) => (
            <FiltroChip key={z} activo={zona === z} onClick={() => setZona(z)}
                        label={z} n={equipos.filter((e) => e.zona === z).length} />
          ))}
          {zonasDisponibles.enTaller > 0 && (
            <FiltroChip activo={zona === 'taller'} onClick={() => setZona('taller')}
                        label="En taller, sin operación" n={zonasDisponibles.enTaller} />
          )}
          {(status || zona) && (
            <button type="button" onClick={() => { setStatus(''); setZona('') }}
                    className="ml-auto text-[11px] font-medium text-blue-600 hover:underline">
              Limpiar filtros
            </button>
          )}
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        <Tile n={totFiltrado.bloq} label="bloqueantes vencidos" sub="el equipo no debería operar" cls="text-red-700 border-red-700" />
        <Tile n={totFiltrado.venc} label="vencidos" sub="ya caducaron" cls="text-red-600 border-red-500" />
        <Tile n={totFiltrado.sf} label="sin fecha" sub="hay papel, falta la vigencia" cls="text-orange-600 border-orange-500" />
        <Tile n={totFiltrado.pv} label="por vencer" sub="dentro de 30 días" cls="text-amber-600 border-amber-500" />
        <Tile n={totFiltrado.prop} label="con propuesta" sub="el sistema leyó el archivo" cls="text-teal-700 border-teal-600" />
      </div>
      {(status || zona) && (
        <p className="-mt-2 text-[11px] text-gray-500">
          Los números de arriba son de los {visibles.length} equipos que quedaron con el filtro puesto,
          no de la flota completa.
        </p>
      )}

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
                      {e.status_codigo && (
                        <span title={ESTADO_CODIGO_LABELS[e.status_codigo as EstadoCodigo] ?? e.status_codigo}
                              className={`rounded border px-1 text-[9px] font-bold ${
                                ESTADO_CODIGO_COLORS[e.status_codigo as EstadoCodigo] ?? 'bg-gray-100 text-gray-600'}`}>
                          {e.status_codigo}
                        </span>
                      )}
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
                           onSubir={() => setSubiendo(p)}
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
      {subiendo && (
        <ModalSubirPapel p={subiendo} onClose={() => setSubiendo(null)}
                         onListo={() => { setSubiendo(null); refrescar() }} />
      )}
    </div>
  )
}

/** Un filtro que además dice cuántos equipos hay detrás: elegir a ciegas y
 *  encontrarse con una lista vacía es la forma más rápida de no usar un filtro. */
function FiltroChip({ activo, onClick, label, n, cls }: {
  activo: boolean; onClick: () => void; label: string; n: number; cls?: string
}) {
  return (
    <button type="button" onClick={onClick} disabled={n === 0}
      className={`rounded-full border px-2.5 py-1 text-[11px] font-medium transition-colors disabled:opacity-40 ${
        activo ? 'border-gray-900 bg-gray-900 text-white'
               : cls ? `${cls} hover:brightness-95`
               : 'border-gray-200 bg-white text-gray-700 hover:bg-gray-50'}`}>
      {label} <span className={activo ? 'opacity-70' : 'opacity-50'}>{n}</span>
    </button>
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

function PapelCard({ p, onAceptar, onDescartar, onEditar, onNoCaduca, onVuelveACaducar, onSubir }: {
  p: PapelEquipo; onAceptar: () => void; onDescartar: () => void; onEditar: () => void
  onNoCaduca: () => void; onVuelveACaducar: () => void; onSubir: () => void
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

      {/* [MIG430] El sistema no está de acuerdo con la fecha, pero la escribió
          una persona: se le avisa al lado, sin borrarle el dato. */}
      {p.vigencia_observacion && (
        <p className="mt-1.5 rounded border border-amber-200 bg-amber-50 px-2 py-1 text-[11px] text-amber-800">
          <b>Revisar:</b> {p.vigencia_observacion}
        </p>
      )}
      {p.vigencia_dudosa_nota && (
        <p className="mt-1.5 rounded border border-orange-200 bg-orange-50 px-2 py-1 text-[11px] text-orange-800">
          <b>La fecha que hay no se puede sostener:</b> {p.vigencia_dudosa_nota}
        </p>
      )}

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

        {/* Subir el papel nuevo se puede siempre: renovar no depende de en qué
            estado esté el que hay. Es la salida real de un documento vencido —
            las demás sólo corrigen la fecha del que ya no sirve. */}
        <Button variant="outline" className="h-7 text-xs" onClick={onSubir}>
          <Upload className="mr-1 h-3 w-3" /> Subir el papel nuevo
        </Button>

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
/**
 * Subir el papel nuevo desde Control documental.
 *
 * Antes esto sólo se podía hacer entrando a la ficha del equipo, que es donde
 * NO se está cuando uno descubre que un papel está vencido: se descubre acá.
 *
 * El archivo se revisa en el navegador antes de subirlo (`leerDocumento`):
 * comprueba que sea un archivo de verdad, que hable de ESTE equipo y de este
 * tipo de papel, y saca la fecha si el documento la declara. Los avisos se
 * muestran; sólo los bloqueantes impiden guardar. Un escaneo sin texto no es un
 * error —es la mitad del archivo de la flota— y se guarda igual, con la fecha
 * escrita a mano.
 */
function ModalSubirPapel({ p, onClose, onListo }: {
  p: PapelEquipo; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  const [file, setFile] = useState<File | null>(null)
  const [lectura, setLectura] = useState<LecturaDocumento | null>(null)
  const [leyendo, setLeyendo] = useState(false)
  const [venc, setVenc] = useState('')
  const [emi, setEmi] = useState('')
  const [busy, setBusy] = useState(false)

  const revisar = async (f: File | null) => {
    setFile(f); setLectura(null); setVenc(''); setEmi('')
    if (!f) return
    setLeyendo(true)
    try {
      const r = await leerDocumento(f, { patente: p.patente, tipo: p.tipo })
      setLectura(r)
      if (r.vencimiento) setVenc(r.vencimiento)
      if (r.emision) setEmi(r.emision)
    } catch {
      // Leer es una ayuda, no un requisito: si falla, se carga a mano.
    } finally { setLeyendo(false) }
  }

  const bloqueado = !!lectura?.avisos.some((a) => a.severidad === 'bloqueante')
  const puedeGuardar = !!file && !!venc && !bloqueado && !busy

  const guardar = async () => {
    if (!file) return
    setBusy(true)
    try {
      const url = await subirDocumentoCert(p.activo_id, p.tipo, file)
      await renovarCertificacion({
        activoId: p.activo_id,
        tipo: p.tipo,
        fechaEmision: emi || venc,
        fechaVencimiento: venc,
        archivoUrl: url,
        bloqueante: p.bloqueante,
        notas: lectura?.origen === 'documento'
          ? `Fecha leída del documento al subirlo. ${lectura.evidencia ?? ''}`.slice(0, 400)
          : 'Fecha escrita a mano al subir el papel.',
      })
      toast.success(`${nombreTipo(p.tipo)} del ${p.patente} actualizado — vence ${venc}`)
      onListo()
    } catch (e) {
      toast.error((e as Error).message)
    } finally { setBusy(false) }
  }

  const color = (sev: string) =>
    sev === 'bloqueante' ? 'border-red-300 bg-red-50 text-red-800'
    : sev === 'alto' ? 'border-amber-300 bg-amber-50 text-amber-800'
    : 'border-gray-200 bg-gray-50 text-gray-700'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={onClose}>
      <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-xl bg-white p-5 shadow-xl"
           onClick={(e) => e.stopPropagation()}>
        <h3 className="text-base font-bold">Subir el papel nuevo</h3>
        <p className="mt-0.5 text-xs text-gray-500">{nombreTipo(p.tipo)} · {p.patente}</p>
        <p className="mt-2 rounded bg-gray-50 p-2 text-[11px] text-gray-600">
          El anterior no se borra: queda en el historial del equipo. Desde ahora rige
          el que subas, y el QR del camión lo muestra al toque.
        </p>

        <input type="file" accept=".pdf,image/*"
               onChange={(e) => revisar(e.target.files?.[0] ?? null)}
               className="mt-3 w-full rounded border px-2 py-1.5 text-sm" />

        {leyendo && (
          <p className="mt-2 flex items-center gap-2 text-xs text-gray-500">
            <Loader2 className="h-3 w-3 animate-spin" /> Revisando el archivo…
          </p>
        )}

        {lectura && (
          <div className="mt-3 space-y-1.5">
            {lectura.avisos.map((a, i) => (
              <div key={i} className={`rounded border p-2 text-[11px] ${color(a.severidad)}`}>
                <b>{a.titulo}</b>
                <p className="mt-0.5">{a.detalle}</p>
              </div>
            ))}
            {lectura.vencimiento ? (
              <p className="rounded border border-green-300 bg-green-50 p-2 text-[11px] text-green-800">
                <b>El documento dice que vence el {lectura.vencimiento}.</b>
                {lectura.evidencia && <span className="mt-0.5 block font-mono text-[10px] opacity-80">…{lectura.evidencia.slice(0, 160)}…</span>}
              </p>
            ) : lectura.caracteres === 0 ? (
              <p className="rounded border border-gray-200 bg-gray-50 p-2 text-[11px] text-gray-600">
                Es un escaneo sin texto: hay que escribir la fecha mirando la foto.
              </p>
            ) : null}
          </div>
        )}

        <div className="mt-4 grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs font-medium text-gray-600">Vence el</label>
            <input type="date" value={venc} onChange={(e) => setVenc(e.target.value)}
                   className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-600">Fecha del documento</label>
            <input type="date" value={emi} onChange={(e) => setEmi(e.target.value)}
                   className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          </div>
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button disabled={!puedeGuardar} onClick={guardar}>
            {busy && <Loader2 className="mr-1 h-4 w-4 animate-spin" />}
            Guardar el papel nuevo
          </Button>
        </div>
        {!venc && file && !bloqueado && (
          <p className="mt-2 text-right text-[11px] text-gray-500">Falta la fecha de vencimiento.</p>
        )}
      </div>
    </div>
  )
}

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
