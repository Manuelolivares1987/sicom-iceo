'use client'

import { useState } from 'react'
import ExcelJS from 'exceljs'
import { Upload, Download, CheckCircle2, AlertTriangle, FileSpreadsheet } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { supabase } from '@/lib/supabase'
import { cn } from '@/lib/utils'

type Fila = {
  codigo: string
  codigo_barras?: string | null
  nombre: string
  categoria: string
  subcategoria?: string | null
  unidad_medida: string
  costo_unitario_actual?: number
  stock_minimo?: number
  stock_maximo?: number
  bodega_nombre?: string
  stock_inicial?: number
  error?: string
}

// Columnas esperadas en el Excel (sensibles a nombre, no al orden)
const CAMPOS_OBLIGATORIOS = ['codigo', 'nombre', 'categoria', 'unidad_medida']
const CAMPOS_OPCIONALES = [
  'codigo_barras', 'subcategoria', 'costo_unitario_actual',
  'stock_minimo', 'stock_maximo', 'bodega_nombre', 'stock_inicial',
]

export default function CargarMaestroPage() {
  useRequireAuth()

  const [filas, setFilas] = useState<Fila[]>([])
  const [parsing, setParsing] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [resultado, setResultado] = useState<{ insertados: number; actualizados: number; errores: number } | null>(null)

  const handleFile = async (file: File) => {
    setErrorMsg(null)
    setResultado(null)
    setParsing(true)
    setFilas([])
    try {
      const buffer = await file.arrayBuffer()
      const wb = new ExcelJS.Workbook()
      await wb.xlsx.load(buffer)
      const ws = wb.worksheets[0]
      if (!ws) throw new Error('El archivo no tiene hojas')

      // Leer header (fila 1)
      const headerRow = ws.getRow(1)
      const headerMap: Record<string, number> = {}
      headerRow.eachCell((cell, col) => {
        const name = String(cell.value ?? '').trim().toLowerCase().replace(/\s+/g, '_')
        if (name) headerMap[name] = col
      })

      for (const f of CAMPOS_OBLIGATORIOS) {
        if (!(f in headerMap)) {
          throw new Error(`Falta columna obligatoria: "${f}"`)
        }
      }

      const parsed: Fila[] = []
      const lastRow = ws.actualRowCount
      for (let r = 2; r <= lastRow; r++) {
        const row = ws.getRow(r)
        const get = (name: string) => {
          const col = headerMap[name]
          if (!col) return null
          const v = row.getCell(col).value
          if (v == null || v === '') return null
          // Manejo de formula: { result }
          const vo = v as unknown
          if (typeof vo === 'object' && vo !== null && 'result' in (vo as Record<string, unknown>)) {
            return (vo as { result: unknown }).result
          }
          return v
        }
        const codigo = String(get('codigo') ?? '').trim()
        if (!codigo) continue
        const fila: Fila = {
          codigo,
          codigo_barras: strOrNull(get('codigo_barras')),
          nombre: String(get('nombre') ?? '').trim(),
          categoria: String(get('categoria') ?? '').trim(),
          subcategoria: strOrNull(get('subcategoria')),
          unidad_medida: String(get('unidad_medida') ?? '').trim(),
          costo_unitario_actual: numOrUndef(get('costo_unitario_actual')),
          stock_minimo: numOrUndef(get('stock_minimo')),
          stock_maximo: numOrUndef(get('stock_maximo')),
          bodega_nombre: strOrNull(get('bodega_nombre')) ?? undefined,
          stock_inicial: numOrUndef(get('stock_inicial')),
        }
        // Validación básica
        if (!fila.nombre) fila.error = 'Sin nombre'
        else if (!fila.categoria) fila.error = 'Sin categoría'
        else if (!fila.unidad_medida) fila.error = 'Sin unidad_medida'

        parsed.push(fila)
      }

      setFilas(parsed)
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al parsear el archivo')
    } finally {
      setParsing(false)
    }
  }

  const handleImportar = async () => {
    if (filas.length === 0) return
    const validas = filas.filter((f) => !f.error)
    if (validas.length === 0) {
      setErrorMsg('No hay filas válidas para importar')
      return
    }

    setUploading(true)
    setErrorMsg(null)
    let insertados = 0
    let actualizados = 0
    let errores = 0

    try {
      // Upsert de productos en lotes de 100
      const lotes: Fila[][] = []
      for (let i = 0; i < validas.length; i += 100) {
        lotes.push(validas.slice(i, i + 100))
      }
      for (const lote of lotes) {
        const payload = lote.map((f) => ({
          codigo: f.codigo,
          codigo_barras: f.codigo_barras || null,
          nombre: f.nombre,
          categoria: f.categoria,
          subcategoria: f.subcategoria || null,
          unidad_medida: f.unidad_medida,
          costo_unitario_actual: f.costo_unitario_actual ?? 0,
          stock_minimo: f.stock_minimo ?? 0,
          stock_maximo: f.stock_maximo ?? 0,
        }))
        const { error } = await supabase
          .from('productos')
          .upsert(payload, { onConflict: 'codigo' })
        if (error) {
          errores += lote.length
          setErrorMsg(error.message)
          break
        }
        insertados += lote.length
      }

      // Stock inicial (opcional) — crea/actualiza stock_bodega por bodega_nombre
      for (const f of validas) {
        if (f.stock_inicial == null || !f.bodega_nombre) continue
        // Buscar ids
        const { data: prod } = await supabase
          .from('productos').select('id').eq('codigo', f.codigo).single()
        const { data: bod } = await supabase
          .from('bodegas').select('id').eq('nombre', f.bodega_nombre).single()
        if (!prod?.id || !bod?.id) continue
        const { error: sbErr } = await supabase
          .from('stock_bodega')
          .upsert(
            {
              bodega_id: bod.id,
              producto_id: prod.id,
              cantidad: f.stock_inicial,
              costo_promedio: f.costo_unitario_actual ?? 0,
            },
            { onConflict: 'bodega_id,producto_id' },
          )
        if (!sbErr) actualizados += 1
      }

      setResultado({ insertados, actualizados, errores })
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al importar')
    } finally {
      setUploading(false)
    }
  }

  const descargarTemplate = async () => {
    const wb = new ExcelJS.Workbook()
    const ws = wb.addWorksheet('Productos')
    ws.columns = [
      { header: 'codigo', key: 'codigo', width: 16 },
      { header: 'nombre', key: 'nombre', width: 40 },
      { header: 'categoria', key: 'categoria', width: 18 },
      { header: 'unidad_medida', key: 'unidad_medida', width: 14 },
      { header: 'codigo_barras', key: 'codigo_barras', width: 20 },
      { header: 'subcategoria', key: 'subcategoria', width: 20 },
      { header: 'costo_unitario_actual', key: 'costo_unitario_actual', width: 18 },
      { header: 'stock_minimo', key: 'stock_minimo', width: 12 },
      { header: 'stock_maximo', key: 'stock_maximo', width: 12 },
      { header: 'bodega_nombre', key: 'bodega_nombre', width: 20 },
      { header: 'stock_inicial', key: 'stock_inicial', width: 14 },
    ]
    ws.getRow(1).font = { bold: true }
    ws.getRow(1).fill = {
      type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE0E7FF' },
    }
    // Ejemplo
    ws.addRow({
      codigo: 'FLT-001',
      nombre: 'Filtro aceite motor MB OM457',
      categoria: 'repuesto',
      unidad_medida: 'un',
      codigo_barras: '7801234567890',
      subcategoria: 'Filtros',
      costo_unitario_actual: 45000,
      stock_minimo: 5,
      stock_maximo: 40,
      bodega_nombre: 'Bodega Central',
      stock_inicial: 12,
    })
    const buf = await wb.xlsx.writeBuffer()
    const blob = new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'template_maestro_bodega.xlsx'
    a.click()
    URL.revokeObjectURL(url)
  }

  const validas = filas.filter((f) => !f.error)
  const invalidas = filas.filter((f) => f.error)

  return (
    <div className="space-y-6">
      <div className="rounded-2xl bg-gradient-to-r from-slate-700 to-indigo-700 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <FileSpreadsheet className="h-6 w-6" />
          Cargar Maestro de Bodega
        </h1>
        <p className="text-sm text-white/80 mt-1">
          Sube tu Excel de productos. Las filas existentes (mismo código) se actualizan; las nuevas se crean.
        </p>
      </div>

      {/* Template download */}
      <Card>
        <CardContent className="p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div className="text-sm text-gray-600">
            Primera vez? Descarga el <strong>template</strong> con las columnas y un ejemplo.
          </div>
          <Button variant="secondary" onClick={descargarTemplate}>
            <Download className="h-4 w-4" />
            Descargar Template
          </Button>
        </CardContent>
      </Card>

      {/* Upload */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">1. Cargar archivo Excel</CardTitle>
        </CardHeader>
        <CardContent>
          <label className="block cursor-pointer rounded-lg border-2 border-dashed border-gray-300 bg-gray-50 p-6 text-center transition hover:border-indigo-400 hover:bg-indigo-50">
            <Upload className="mx-auto h-8 w-8 text-gray-400" />
            <div className="mt-2 text-sm">
              {parsing ? (
                <span className="flex items-center justify-center gap-2">
                  <Spinner className="h-4 w-4" />
                  Parseando…
                </span>
              ) : (
                <>Click o arrastra un archivo .xlsx aquí</>
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
          <p className="mt-2 text-xs text-gray-500">
            Columnas obligatorias: codigo, nombre, categoria, unidad_medida.
            Opcionales: codigo_barras, subcategoria, costo_unitario_actual,
            stock_minimo, stock_maximo, bodega_nombre, stock_inicial.
          </p>
        </CardContent>
      </Card>

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{errorMsg}</div>
      )}

      {/* Preview */}
      {filas.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center justify-between">
              <span>2. Vista previa</span>
              <div className="flex gap-2 text-xs">
                <span className="rounded bg-green-100 px-2 py-0.5 text-green-700">{validas.length} válidas</span>
                {invalidas.length > 0 && (
                  <span className="rounded bg-red-100 px-2 py-0.5 text-red-700">{invalidas.length} con error</span>
                )}
              </div>
            </CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                  <th className="px-2 py-2 w-6"></th>
                  <th className="px-2 py-2">Código</th>
                  <th className="px-2 py-2">Nombre</th>
                  <th className="px-2 py-2">Categoría</th>
                  <th className="px-2 py-2">Unidad</th>
                  <th className="px-2 py-2 text-right">Stock inicial</th>
                  <th className="px-2 py-2">Bodega</th>
                  <th className="px-2 py-2">Error</th>
                </tr>
              </thead>
              <tbody>
                {filas.slice(0, 50).map((f, i) => (
                  <tr key={i} className={cn('border-b', f.error && 'bg-red-50')}>
                    <td className="px-2 py-1.5">
                      {f.error ? <AlertTriangle className="h-4 w-4 text-red-600" /> :
                        <CheckCircle2 className="h-4 w-4 text-green-600" />}
                    </td>
                    <td className="px-2 py-1.5 font-mono">{f.codigo}</td>
                    <td className="px-2 py-1.5">{f.nombre}</td>
                    <td className="px-2 py-1.5">{f.categoria}</td>
                    <td className="px-2 py-1.5">{f.unidad_medida}</td>
                    <td className="px-2 py-1.5 text-right">{f.stock_inicial ?? '—'}</td>
                    <td className="px-2 py-1.5">{f.bodega_nombre ?? '—'}</td>
                    <td className="px-2 py-1.5 text-red-600">{f.error ?? ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {filas.length > 50 && (
              <p className="mt-2 text-xs text-gray-400 text-center">
                Mostrando 50 de {filas.length} filas.
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {/* Importar */}
      {validas.length > 0 && !resultado && (
        <Button
          variant="primary"
          size="lg"
          onClick={handleImportar}
          loading={uploading}
        >
          <Upload className="h-4 w-4" />
          Importar {validas.length} productos
        </Button>
      )}

      {resultado && (
        <Card className="border-green-200 bg-green-50">
          <CardContent className="p-4 space-y-1">
            <div className="flex items-center gap-2 text-green-800 font-semibold">
              <CheckCircle2 className="h-5 w-5" />
              Importación terminada
            </div>
            <div className="text-sm text-green-700 pl-7">
              <div>Productos upsertados: <strong>{resultado.insertados}</strong></div>
              <div>Stock bodega actualizado: <strong>{resultado.actualizados}</strong></div>
              {resultado.errores > 0 && (
                <div className="text-red-700">Con error: {resultado.errores}</div>
              )}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

// ─── Helpers ───
function strOrNull(v: unknown): string | null {
  if (v == null || v === '') return null
  return String(v).trim() || null
}
function numOrUndef(v: unknown): number | undefined {
  if (v == null || v === '') return undefined
  const n = Number(v)
  return Number.isFinite(n) ? n : undefined
}
