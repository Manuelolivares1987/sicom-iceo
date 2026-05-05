'use client'

import { useMemo, useState } from 'react'
import {
  Upload, FileSpreadsheet, AlertTriangle, CheckCircle2, Info, MapPin, Layers,
  Hammer, Phone, Calendar, ListChecks, MessageSquare, Database, X,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Select } from '@/components/ui/select'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Input } from '@/components/ui/input'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { supabase } from '@/lib/supabase'
import {
  parseCalamaExcel, type CalamaImportPreview, type LineaNegocioCalama,
} from '@/lib/importers/calama-excel-importer'

type FaenaCalama = 'CENTINELA' | 'LOMAS_BAYAS' | 'SPENCE'

const FAENAS_OPCIONES: Array<{ value: FaenaCalama; label: string }> = [
  { value: 'CENTINELA', label: 'Minera Centinela (AMSA)' },
  { value: 'LOMAS_BAYAS', label: 'Lomas Bayas (Glencore)' },
  { value: 'SPENCE', label: 'Spence (BHP)' },
]

const LINEAS_OPCIONES: Array<{ value: LineaNegocioCalama; label: string }> = [
  { value: 'mejoras_civiles', label: 'Mejoras civiles' },
  { value: 'combustibles', label: 'Combustibles' },
  { value: 'lubricantes', label: 'Lubricantes' },
]

type ImportResult = {
  resultado: string
  plan_codigo: string
  plan_id: string
  faena_usada: string
  linea_negocio_usada: string
  zonas_insertadas: number
  zonas_actualizadas: number
  tareas_insertadas: number
  tareas_actualizadas: number
  ots_insertadas: number
  ots_actualizadas: number
  ots_skipped: number
  subtareas_insertadas: number
  subtareas_actualizadas: number
  materiales_insertados: number
  contactos_insertados: number
  contactos_actualizados: number
  observaciones_insertadas: number
  observaciones_skipped: number
  fechas_insertadas: number
  errores: string[]
  advertencias: string[]
}

function planCodigoFromFile(filename: string, faenaCode: string): string {
  const m = /VA[\s_]*(\d+)[\s_]*(\d+)/i.exec(filename)
  const base = m ? `VA_${m[1]}_${m[2]}` : 'IMPORT'
  return `${base}_${faenaCode}`.toUpperCase().replace(/[^A-Z0-9_]/g, '_')
}

function dateRange(preview: CalamaImportPreview): { inicio: string; termino: string } {
  const hoy = new Date()
  const dflt = hoy.toISOString().slice(0, 10)
  const fechas = [
    ...preview.tareas_detectadas.flatMap((t) => [t.fecha_inicio_plan, t.fecha_fin_plan, t.fecha_inicio_real]),
    ...preview.fechas_planificadas_detectadas.flatMap((f) => [f.fecha_inicio_plan, f.fecha_fin_plan]),
  ].filter((d): d is string => !!d).sort()
  if (fechas.length === 0) {
    const en6m = new Date(hoy)
    en6m.setMonth(en6m.getMonth() + 6)
    return { inicio: dflt, termino: en6m.toISOString().slice(0, 10) }
  }
  return { inicio: fechas[0], termino: fechas[fechas.length - 1] }
}

export default function ImportarCalamaPage() {
  useRequireAuth()

  const [parsing, setParsing] = useState(false)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [preview, setPreview] = useState<CalamaImportPreview | null>(null)
  const [validado, setValidado] = useState(false)

  const [faenaSel, setFaenaSel] = useState<FaenaCalama | ''>('')
  const [lineaSel, setLineaSel] = useState<LineaNegocioCalama | ''>('')
  const [planNombreManual, setPlanNombreManual] = useState<string>('')

  const [showConfirm, setShowConfirm] = useState(false)
  const [importing, setImporting] = useState(false)
  const [importResult, setImportResult] = useState<ImportResult | null>(null)

  const handleFile = async (file: File) => {
    setErrorMsg(null)
    setPreview(null)
    setValidado(false)
    setFaenaSel('')
    setLineaSel('')
    setPlanNombreManual('')
    setImportResult(null)
    setParsing(true)
    try {
      const p = await parseCalamaExcel(file)
      setPreview(p)
      const sugFaena = p.faenas_detectadas[0]?.codigo as FaenaCalama | undefined
      const sugLinea = p.lineas_negocio_detectadas[0]?.codigo
      if (sugFaena && FAENAS_OPCIONES.some((o) => o.value === sugFaena)) {
        setFaenaSel(sugFaena)
      }
      if (sugLinea) setLineaSel(sugLinea)
      setPlanNombreManual(p.archivo.replace(/\.xlsx?$/i, ''))
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al parsear el archivo')
    } finally {
      setParsing(false)
    }
  }

  const tieneErroresMapeo = preview ? preview.errores_de_mapeo.length > 0 : false
  const tieneAdvertencias = preview ? preview.advertencias.length > 0 : false
  const seleccionCompleta = !!faenaSel && !!lineaSel

  const planCodigo = useMemo(() => {
    if (!preview || !faenaSel) return ''
    return planCodigoFromFile(preview.archivo, faenaSel)
  }, [preview, faenaSel])

  const handleImportar = async () => {
    if (!preview || !faenaSel || !lineaSel) return
    setImporting(true)
    setErrorMsg(null)
    try {
      const rango = dateRange(preview)
      const payload = {
        archivo: preview.archivo,
        faena_codigo: faenaSel,
        linea_negocio: lineaSel,
        plan_codigo: planCodigo,
        plan_nombre: planNombreManual || preview.archivo,
        plan_fecha_inicio: rango.inicio,
        plan_fecha_termino: rango.termino,
        permitir_advertencias: tieneAdvertencias,
        tiene_errores_mapeo: tieneErroresMapeo,
        zonas: preview.zonas_detectadas.map((z) => ({ codigo: z.codigo, nombre: z.nombre })),
        tareas: preview.tareas_detectadas.map((t) => ({
          codigo: t.codigo,
          nombre: t.nombre,
          zona_codigo: t.zona_codigo,
          duracion_plan_dias: t.duracion_plan_dias,
          duracion_real_dias: t.duracion_real_dias,
          fecha_inicio_plan: t.fecha_inicio_plan,
          fecha_fin_plan: t.fecha_fin_plan,
          fecha_inicio_real: t.fecha_inicio_real,
          fecha_fin_real: t.fecha_fin_real,
          ot_referencia: t.ot_referencia,
          verif: t.verif,
        })),
        subtareas: preview.subtareas_detectadas.map((s) => ({
          codigo: s.codigo,
          descripcion: s.descripcion,
          tarea_codigo: s.tarea_codigo,
          estado: s.estado,
          fecha_real: s.fecha_real,
        })),
        materiales: preview.materiales_detectados.map((m) => ({
          actividad_relacionada: m.actividad_relacionada,
          descripcion: m.descripcion,
          unidad: m.unidad,
          cantidad: m.cantidad,
          precio_clp: m.precio_clp,
          valor_uf: m.valor_uf,
          porcentaje: m.porcentaje,
          bloque: m.observacion,
          zona_codigo: m.zona_codigo,
          zona_nombre: m.zona_nombre,
        })),
        contactos: preview.contactos_detectados.map((c) => ({
          codigo_actividad: c.codigo_actividad,
          descripcion: c.descripcion,
          telefono: c.telefono,
          rol: c.rol,
        })),
        observaciones: preview.observaciones_detectadas.map((o) => ({
          codigo_relacionado: o.codigo_relacionado,
          texto: o.texto,
        })),
      }

      const { data, error } = await supabase.rpc('rpc_calama_importar_excel', { p_payload: payload })
      if (error) throw new Error(error.message)
      setImportResult(data as ImportResult)
      setShowConfirm(false)

      // Segunda llamada: poblar avance_excel_pct desde columna C de
      // "Analisi carta gantt" via rpc_calama_set_avance_excel_lote.
      // El RPC sobreescribe avance_pct salvo que existan eventos reales
      // (operador/supervisor/planificador) o ejecuciones.
      try {
        const items = preview.tareas_detectadas
          .filter((t) => t.avance_excel_pct != null)
          .map((t) => ({
            tarea_codigo_excel: t.codigo,
            avance_excel_pct: t.avance_excel_pct,
          }))
        if (items.length > 0) {
          const { data: avanceResp, error: avanceErr } = await supabase.rpc(
            'rpc_calama_set_avance_excel_lote',
            { p_payload: { plan_codigo: planCodigo, items } },
          )
          if (avanceErr) {
            setErrorMsg(`Avances Excel: ${avanceErr.message}`)
          } else if (avanceResp) {
            // Anexar al resultado del import principal el diagnostico de avance
            const r = data as ImportResult
            const av = avanceResp as {
              total_recibidos?: number
              total_matcheados?: number
              total_no_matcheados?: number
              total_actualizados_excel?: number
              total_actualizados_real?: number
              ejemplos_no_matcheados?: string[]
            }
            const detalleAvance =
              `Avances Excel aplicados: ${av.total_actualizados_excel ?? 0}/${av.total_recibidos ?? 0} ` +
              `| avance_pct refrescado: ${av.total_actualizados_real ?? 0} ` +
              `| no matcheados: ${av.total_no_matcheados ?? 0}` +
              ((av.ejemplos_no_matcheados ?? []).length
                ? ` (ej: ${(av.ejemplos_no_matcheados ?? []).join(', ')})`
                : '')
            r.advertencias = [...(r.advertencias ?? []), detalleAvance]
            setImportResult({ ...r })
          }
        }
      } catch (e) {
        setErrorMsg(e instanceof Error ? `Avances Excel: ${e.message}` : 'Error al aplicar avances Excel')
      }
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al importar')
      setShowConfirm(false)
    } finally {
      setImporting(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <FileSpreadsheet className="h-6 w-6" />
          Operacion Calama — Importar Excel base
        </h1>
        <p className="text-sm text-white/90 mt-1">
          Sube el archivo de Carta Gantt para revisar zonas, tareas, subtareas, materiales y contactos detectados.
        </p>
        <p className="text-xs text-white/80 mt-2 inline-flex items-center gap-1.5 bg-black/20 px-2 py-1 rounded">
          <Info className="h-3.5 w-3.5" />
          La vista previa no inserta datos. La importacion solo ocurre cuando confirmas explicitamente.
        </p>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">1. Cargar archivo Excel</CardTitle>
        </CardHeader>
        <CardContent>
          <label className="block cursor-pointer rounded-lg border-2 border-dashed border-gray-300 bg-gray-50 p-6 text-center transition hover:border-amber-400 hover:bg-amber-50">
            <Upload className="mx-auto h-8 w-8 text-gray-400" />
            <div className="mt-2 text-sm">
              {parsing ? (
                <span className="flex items-center justify-center gap-2">
                  <Spinner className="h-4 w-4" />
                  Parseando…
                </span>
              ) : (
                <>Click o arrastra un archivo .xlsx aqui</>
              )}
            </div>
            <input
              type="file"
              accept=".xlsx,.xls"
              className="hidden"
              disabled={parsing}
              onChange={(e) => {
                const f = e.target.files?.[0]
                if (f) handleFile(f)
              }}
            />
          </label>
        </CardContent>
      </Card>

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {errorMsg}
        </div>
      )}

      {preview && !importResult && (
        <>
          <ResumenCard preview={preview} />
          <SugerenciasCard preview={preview} />
          <HojasCard preview={preview} />
          <ZonasCard preview={preview} />
          <TareasCard preview={preview} />
          <SubtareasCard preview={preview} />
          <MaterialesCard preview={preview} />
          <ContactosCard preview={preview} />
          <AvancesCard preview={preview} />
          <ObservacionesCard preview={preview} />
          <AdvertenciasCard preview={preview} />
          <ErroresCard preview={preview} />

          <Card className="border-amber-200 bg-amber-50">
            <CardContent className="p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div className="text-sm">
                <p className="font-semibold text-amber-900">Validacion de mapeo</p>
                <p className="text-amber-800">
                  Marca como validada cuando hayas revisado los conteos para habilitar la importacion.
                </p>
              </div>
              <Button
                variant={validado ? 'secondary' : 'primary'}
                onClick={() => setValidado(true)}
                disabled={validado}
              >
                <CheckCircle2 className="h-4 w-4" />
                {validado ? 'Mapeo validado' : 'Validar importacion'}
              </Button>
            </CardContent>
          </Card>

          {validado && (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center gap-2">
                  <Database className="h-4 w-4" />
                  3. Configurar importacion a Supabase
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid sm:grid-cols-2 gap-4">
                  <Select
                    label="Faena destino"
                    value={faenaSel}
                    onChange={(e) => setFaenaSel(e.target.value as FaenaCalama)}
                    options={FAENAS_OPCIONES}
                    placeholder="Selecciona una faena…"
                  />
                  <Select
                    label="Linea de negocio principal"
                    value={lineaSel}
                    onChange={(e) => setLineaSel(e.target.value as LineaNegocioCalama)}
                    options={LINEAS_OPCIONES}
                    placeholder="Selecciona una linea…"
                  />
                </div>
                <Input
                  label="Nombre del proyecto / planificacion"
                  value={planNombreManual}
                  onChange={(e) => setPlanNombreManual(e.target.value)}
                  placeholder="Ej: VA 25_042 Mejoras Centinela"
                />
                {planCodigo && (
                  <p className="text-xs text-gray-500">
                    Codigo de planificacion derivado: <span className="font-mono">{planCodigo}</span>
                  </p>
                )}

                {tieneErroresMapeo && (
                  <div className="rounded-lg border border-red-300 bg-red-50 p-3 text-sm text-red-800">
                    <p className="font-semibold flex items-center gap-1">
                      <AlertTriangle className="h-4 w-4" /> Importacion bloqueada
                    </p>
                    <p>El archivo tiene {preview.errores_de_mapeo.length} errores de mapeo. Corrige el Excel y vuelve a subirlo.</p>
                  </div>
                )}

                {!tieneErroresMapeo && tieneAdvertencias && (
                  <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
                    <p className="font-semibold flex items-center gap-1">
                      <AlertTriangle className="h-4 w-4" /> Importacion permitida con advertencias
                    </p>
                    <p>El archivo tiene {preview.advertencias.length} advertencias. Continuar requiere confirmacion explicita.</p>
                  </div>
                )}

                <div className="flex justify-end">
                  <Button
                    variant="primary"
                    size="lg"
                    disabled={!seleccionCompleta || tieneErroresMapeo}
                    onClick={() => setShowConfirm(true)}
                  >
                    <Database className="h-4 w-4" />
                    Importar a Supabase
                  </Button>
                </div>
              </CardContent>
            </Card>
          )}
        </>
      )}

      {importResult && <ImportResultCard result={importResult} onReset={() => {
        setImportResult(null)
        setPreview(null)
        setValidado(false)
        setFaenaSel('')
        setLineaSel('')
      }} />}

      <Modal open={showConfirm} onClose={() => !importing && setShowConfirm(false)} title="Confirmar importacion">
        <div className="space-y-3 text-sm text-gray-700">
          <p>Esta accion cargara las tareas al modulo Operacion Calama. ¿Desea continuar?</p>
          <div className="rounded border border-gray-200 bg-gray-50 p-3 space-y-1 text-xs">
            <div><span className="text-gray-500">Faena:</span> <span className="font-mono">{faenaSel}</span></div>
            <div><span className="text-gray-500">Linea:</span> <span className="font-mono">{lineaSel}</span></div>
            <div><span className="text-gray-500">Planificacion:</span> <span className="font-mono">{planCodigo}</span></div>
            <div><span className="text-gray-500">Nombre:</span> {planNombreManual}</div>
            {preview && (
              <>
                <div className="pt-2 border-t border-gray-200" />
                <div>{preview.zonas_detectadas.length} zonas · {preview.tareas_detectadas.length} tareas · {preview.subtareas_detectadas.length} subtareas</div>
                <div>{preview.materiales_detectados.length} materiales · {preview.contactos_detectados.length} contactos · {preview.observaciones_detectadas.length} observaciones</div>
              </>
            )}
          </div>
          {tieneAdvertencias && (
            <p className="text-amber-700 text-xs">
              ⚠ Se procedera a pesar de {preview?.advertencias.length} advertencias.
            </p>
          )}
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 border-t-0 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setShowConfirm(false)} disabled={importing}>
            <X className="h-4 w-4" />
            Cancelar
          </Button>
          <Button variant="primary" onClick={handleImportar} loading={importing}>
            <Database className="h-4 w-4" />
            Si, importar
          </Button>
        </ModalFooter>
      </Modal>
    </div>
  )
}

// ─── Subcomponentes ──────────────────────────────────────────────────────────

function ResumenCard({ preview }: { preview: CalamaImportPreview }) {
  const r = preview.resumen
  const items: Array<[string, number]> = [
    ['Zonas', r.total_zonas],
    ['Tareas', r.total_tareas],
    ['Subtareas', r.total_subtareas],
    ['Materiales', r.total_materiales],
    ['Contactos', r.total_contactos],
    ['Fechas plan', r.total_fechas],
    ['Observaciones', r.total_observaciones],
    ['Advertencias', r.total_advertencias],
    ['Errores mapeo', r.total_errores],
  ]
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">2. Resumen del archivo</CardTitle>
      </CardHeader>
      <CardContent className="grid grid-cols-3 sm:grid-cols-5 lg:grid-cols-9 gap-2">
        {items.map(([label, n]) => (
          <div key={label} className="rounded-lg border bg-white p-3 text-center">
            <div className="text-xs text-gray-500">{label}</div>
            <div className="text-xl font-bold text-gray-900">{n}</div>
          </div>
        ))}
      </CardContent>
      <CardContent className="pt-0 text-xs text-gray-500">
        Archivo: <span className="font-mono">{preview.archivo}</span>
      </CardContent>
    </Card>
  )
}

function SugerenciasCard({ preview }: { preview: CalamaImportPreview }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <MapPin className="h-4 w-4" /> Sugerencias automaticas
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        <div>
          <div className="text-xs uppercase text-gray-500 mb-1">Faenas detectadas</div>
          {preview.faenas_detectadas.length === 0 ? (
            <span className="text-gray-400 italic">Sin sugerencia</span>
          ) : (
            <ul className="space-y-1">
              {preview.faenas_detectadas.map((f) => (
                <li key={f.codigo} className="flex items-center gap-2">
                  <span className="font-mono text-xs rounded bg-amber-100 px-2 py-0.5 text-amber-800">{f.codigo}</span>
                  <span>{f.nombre}</span>
                  <span className="text-xs text-gray-400">— {f.razon}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
        <div>
          <div className="text-xs uppercase text-gray-500 mb-1">Lineas de negocio detectadas</div>
          {preview.lineas_negocio_detectadas.length === 0 ? (
            <span className="text-gray-400 italic">Sin sugerencia</span>
          ) : (
            <ul className="space-y-1">
              {preview.lineas_negocio_detectadas.map((l) => (
                <li key={l.codigo} className="flex items-center gap-2">
                  <span className="font-mono text-xs rounded bg-indigo-100 px-2 py-0.5 text-indigo-800">{l.codigo}</span>
                  <span className="text-xs text-gray-400">— {l.razon}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

function HojasCard({ preview }: { preview: CalamaImportPreview }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Layers className="h-4 w-4" /> Hojas detectadas
        </CardTitle>
      </CardHeader>
      <CardContent className="text-sm">
        <ul className="flex flex-wrap gap-2">
          {preview.hojas_detectadas.map((h) => (
            <li key={h} className="rounded bg-slate-100 px-2 py-1 text-slate-700 text-xs font-mono">{h}</li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}

function ZonasCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.zonas_detectadas.length === 0) return null
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Zonas ({preview.zonas_detectadas.length})</CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
              <th className="px-2 py-2">Codigo</th>
              <th className="px-2 py-2">Nombre</th>
              <th className="px-2 py-2">Hoja</th>
            </tr>
          </thead>
          <tbody>
            {preview.zonas_detectadas.slice(0, 50).map((z, i) => (
              <tr key={i} className="border-b">
                <td className="px-2 py-1.5 font-mono">{z.codigo}</td>
                <td className="px-2 py-1.5">{z.nombre}</td>
                <td className="px-2 py-1.5 text-gray-400">{z.origen_hoja}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}

function TareasCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.tareas_detectadas.length === 0) return null
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <ListChecks className="h-4 w-4" />
          Tareas ({preview.tareas_detectadas.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
              <th className="px-2 py-2">Codigo</th>
              <th className="px-2 py-2">Nombre</th>
              <th className="px-2 py-2">Zona</th>
              <th className="px-2 py-2 text-right">Dur. plan</th>
              <th className="px-2 py-2 text-right">Dur. real</th>
              <th className="px-2 py-2 text-right">% Excel</th>
              <th className="px-2 py-2">Inicio plan</th>
              <th className="px-2 py-2">Fin plan</th>
              <th className="px-2 py-2">Inicio real</th>
              <th className="px-2 py-2">Verif</th>
            </tr>
          </thead>
          <tbody>
            {preview.tareas_detectadas.slice(0, 100).map((t, i) => (
              <tr key={i} className="border-b">
                <td className="px-2 py-1.5 font-mono">{t.codigo}</td>
                <td className="px-2 py-1.5">{t.nombre}</td>
                <td className="px-2 py-1.5 font-mono text-gray-500">{t.zona_codigo ?? '—'}</td>
                <td className="px-2 py-1.5 text-right">{t.duracion_plan_dias ?? '—'}</td>
                <td className="px-2 py-1.5 text-right">{t.duracion_real_dias ?? '—'}</td>
                <td className="px-2 py-1.5 text-right">{t.avance_excel_pct != null ? `${t.avance_excel_pct.toFixed(0)}%` : '—'}</td>
                <td className="px-2 py-1.5">{t.fecha_inicio_plan ?? '—'}</td>
                <td className="px-2 py-1.5">{t.fecha_fin_plan ?? '—'}</td>
                <td className="px-2 py-1.5">{t.fecha_inicio_real ?? '—'}</td>
                <td className="px-2 py-1.5">{t.verif ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {preview.tareas_detectadas.length > 100 && (
          <p className="mt-2 text-xs text-gray-400 text-center">
            Mostrando 100 de {preview.tareas_detectadas.length} tareas.
          </p>
        )}
      </CardContent>
    </Card>
  )
}

function SubtareasCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.subtareas_detectadas.length === 0) return null
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Subtareas ({preview.subtareas_detectadas.length})</CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
              <th className="px-2 py-2">Codigo</th>
              <th className="px-2 py-2">Descripcion</th>
              <th className="px-2 py-2">Tarea</th>
              <th className="px-2 py-2">Estado</th>
              <th className="px-2 py-2">Fecha real</th>
            </tr>
          </thead>
          <tbody>
            {preview.subtareas_detectadas.slice(0, 100).map((s, i) => (
              <tr key={i} className="border-b">
                <td className="px-2 py-1.5 font-mono">{s.codigo}</td>
                <td className="px-2 py-1.5">{s.descripcion}</td>
                <td className="px-2 py-1.5 font-mono text-gray-500">{s.tarea_codigo ?? '—'}</td>
                <td className="px-2 py-1.5">{s.estado ?? '—'}</td>
                <td className="px-2 py-1.5">{s.fecha_real ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {preview.subtareas_detectadas.length > 100 && (
          <p className="mt-2 text-xs text-gray-400 text-center">
            Mostrando 100 de {preview.subtareas_detectadas.length} subtareas.
          </p>
        )}
      </CardContent>
    </Card>
  )
}

function MaterialesCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.materiales_detectados.length === 0) return null
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Hammer className="h-4 w-4" />
          Materiales ({preview.materiales_detectados.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
              <th className="px-2 py-2">Zona</th>
              <th className="px-2 py-2">Actividad</th>
              <th className="px-2 py-2">Descripcion</th>
              <th className="px-2 py-2 text-right">% </th>
              <th className="px-2 py-2 text-right">CLP</th>
              <th className="px-2 py-2 text-right">UF</th>
              <th className="px-2 py-2">Bloque</th>
            </tr>
          </thead>
          <tbody>
            {preview.materiales_detectados.slice(0, 100).map((m, i) => (
              <tr key={i} className="border-b">
                <td className="px-2 py-1.5 font-mono text-gray-500">{m.zona_codigo ?? '—'}</td>
                <td className="px-2 py-1.5">{m.actividad_relacionada ?? '—'}</td>
                <td className="px-2 py-1.5">{m.descripcion}</td>
                <td className="px-2 py-1.5 text-right">{m.porcentaje != null ? m.porcentaje.toFixed(2) : '—'}</td>
                <td className="px-2 py-1.5 text-right">
                  {m.precio_clp != null ? Math.round(m.precio_clp).toLocaleString('es-CL') : '—'}
                </td>
                <td className="px-2 py-1.5 text-right">{m.valor_uf != null ? m.valor_uf.toFixed(2) : '—'}</td>
                <td className="px-2 py-1.5 text-gray-500">{m.observacion ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {preview.materiales_detectados.length > 100 && (
          <p className="mt-2 text-xs text-gray-400 text-center">
            Mostrando 100 de {preview.materiales_detectados.length} materiales.
          </p>
        )}
      </CardContent>
    </Card>
  )
}

function ContactosCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.contactos_detectados.length === 0) return null
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Phone className="h-4 w-4" />
          Contactos ({preview.contactos_detectados.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
              <th className="px-2 py-2">Cod.</th>
              <th className="px-2 py-2">Descripcion</th>
              <th className="px-2 py-2">Telefono</th>
              <th className="px-2 py-2">Rol</th>
              <th className="px-2 py-2">Faena sugerida</th>
            </tr>
          </thead>
          <tbody>
            {preview.contactos_detectados.map((c, i) => (
              <tr key={i} className="border-b">
                <td className="px-2 py-1.5 font-mono">{c.codigo_actividad ?? '—'}</td>
                <td className="px-2 py-1.5">{c.descripcion}</td>
                <td className="px-2 py-1.5 font-mono">{c.telefono ?? '—'}</td>
                <td className="px-2 py-1.5">{c.rol ?? '—'}</td>
                <td className="px-2 py-1.5">{c.faena_sugerida ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}

function AvancesCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.avances_detectados.length === 0) return null
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Calendar className="h-4 w-4" />
          Avances reportados ({preview.avances_detectados.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
              <th className="px-2 py-2">Codigo</th>
              <th className="px-2 py-2">Nombre</th>
              <th className="px-2 py-2 text-right">Avance %</th>
            </tr>
          </thead>
          <tbody>
            {preview.avances_detectados.slice(0, 100).map((a, i) => (
              <tr key={i} className="border-b">
                <td className="px-2 py-1.5 font-mono">{a.codigo}</td>
                <td className="px-2 py-1.5">{a.nombre}</td>
                <td className="px-2 py-1.5 text-right">{a.avance_pct != null ? a.avance_pct.toFixed(1) : '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}

function ObservacionesCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.observaciones_detectadas.length === 0) return null
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <MessageSquare className="h-4 w-4" />
          Observaciones ({preview.observaciones_detectadas.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
              <th className="px-2 py-2">Codigo</th>
              <th className="px-2 py-2">Texto</th>
              <th className="px-2 py-2">Hoja</th>
            </tr>
          </thead>
          <tbody>
            {preview.observaciones_detectadas.slice(0, 100).map((o, i) => (
              <tr key={i} className="border-b">
                <td className="px-2 py-1.5 font-mono">{o.codigo_relacionado ?? '—'}</td>
                <td className="px-2 py-1.5">{o.texto}</td>
                <td className="px-2 py-1.5 text-gray-400">{o.origen_hoja}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}

function AdvertenciasCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.advertencias.length === 0) return null
  return (
    <Card className="border-amber-200">
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2 text-amber-700">
          <AlertTriangle className="h-4 w-4" />
          Advertencias ({preview.advertencias.length})
        </CardTitle>
      </CardHeader>
      <CardContent>
        <ul className="space-y-1 text-sm text-amber-900">
          {preview.advertencias.map((a, i) => (
            <li key={i} className="flex gap-2">
              <span className="text-amber-500">•</span>
              <span>
                {a.hoja && <span className="font-mono text-xs text-amber-700 mr-2">[{a.hoja}]</span>}
                {a.detalle}
              </span>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}

function ErroresCard({ preview }: { preview: CalamaImportPreview }) {
  if (preview.errores_de_mapeo.length === 0) return null
  return (
    <Card className="border-red-200">
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2 text-red-700">
          <AlertTriangle className="h-4 w-4" />
          Errores de mapeo ({preview.errores_de_mapeo.length})
        </CardTitle>
      </CardHeader>
      <CardContent>
        <ul className="space-y-1 text-sm text-red-900">
          {preview.errores_de_mapeo.map((e, i) => (
            <li key={i} className="flex gap-2">
              <span className="text-red-500">•</span>
              <span>
                <span className="font-mono text-xs text-red-700 mr-2">
                  [{e.hoja}{e.fila ? `:R${e.fila}` : ''}]
                </span>
                {e.detalle}
              </span>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}

function ImportResultCard({ result, onReset }: { result: ImportResult; onReset: () => void }) {
  const ok = result.resultado === 'OK_IMPORTACION_CALAMA'
  return (
    <Card className={ok ? 'border-green-200 bg-green-50' : 'border-amber-200 bg-amber-50'}>
      <CardHeader className="pb-2">
        <CardTitle className={`text-base flex items-center gap-2 ${ok ? 'text-green-800' : 'text-amber-800'}`}>
          <CheckCircle2 className="h-5 w-5" />
          Importacion completada — {result.resultado}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        <div className="rounded bg-white p-3 grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
          <Stat label="Plan" value={result.plan_codigo} mono />
          <Stat label="Faena" value={result.faena_usada} mono />
          <Stat label="Linea" value={result.linea_negocio_usada} mono />
          <Stat label="Plan ID" value={result.plan_id.slice(0, 8) + '…'} mono />
          <Stat label="Zonas ins / upd" value={`${result.zonas_insertadas} / ${result.zonas_actualizadas}`} />
          <Stat label="Tareas ins / upd" value={`${result.tareas_insertadas} / ${result.tareas_actualizadas}`} />
          <Stat label="OTs ins / upd / skip" value={`${result.ots_insertadas} / ${result.ots_actualizadas} / ${result.ots_skipped}`} />
          <Stat label="Subtareas ins / upd" value={`${result.subtareas_insertadas} / ${result.subtareas_actualizadas}`} />
          <Stat label="Materiales ins" value={result.materiales_insertados} />
          <Stat label="Contactos ins / upd" value={`${result.contactos_insertados} / ${result.contactos_actualizados}`} />
          <Stat label="Observaciones ins / skip" value={`${result.observaciones_insertadas} / ${result.observaciones_skipped}`} />
          <Stat label="Fechas ins" value={result.fechas_insertadas} />
        </div>

        {result.advertencias.length > 0 && (
          <div className="rounded border border-amber-300 bg-white p-3">
            <p className="font-semibold text-amber-800 text-xs mb-2">Advertencias del servidor ({result.advertencias.length})</p>
            <ul className="space-y-1 text-xs text-amber-900 max-h-40 overflow-y-auto">
              {result.advertencias.slice(0, 30).map((a, i) => <li key={i}>• {a}</li>)}
            </ul>
          </div>
        )}

        {result.errores.length > 0 && (
          <div className="rounded border border-red-300 bg-white p-3">
            <p className="font-semibold text-red-800 text-xs mb-2">Errores ({result.errores.length})</p>
            <ul className="space-y-1 text-xs text-red-900 max-h-40 overflow-y-auto">
              {result.errores.map((e, i) => <li key={i}>• {e}</li>)}
            </ul>
          </div>
        )}

        <Button variant="secondary" onClick={onReset}>
          <Upload className="h-4 w-4" />
          Importar otro archivo
        </Button>
      </CardContent>
    </Card>
  )
}

function Stat({ label, value, mono }: { label: string; value: string | number; mono?: boolean }) {
  return (
    <div>
      <div className="text-gray-500">{label}</div>
      <div className={`font-semibold text-gray-900 ${mono ? 'font-mono text-xs' : ''}`}>{value}</div>
    </div>
  )
}
