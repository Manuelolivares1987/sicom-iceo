/* eslint-disable */
// Runner para ejecutar el parser Calama contra un xlsx local.
// Uso: npx tsx scripts/run-calama-import.ts "<ruta-al-archivo.xlsx>"

import { promises as fs } from 'node:fs'
import path from 'node:path'
import { parseCalamaExcel, type CalamaImportPreview } from '../src/lib/importers/calama-excel-importer'

const DEFAULT_FILE =
  'C:\\Users\\Manuel Olivares\\Desktop\\2026\\PILLADO\\Calama\\Carta Gantt (VA 25_042 Mejoras Centinela) 3003.xlsx'

async function main() {
  const file = process.argv[2] ?? DEFAULT_FILE
  console.log(`Leyendo: ${file}`)
  const buf = await fs.readFile(file)
  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer

  const preview = await parseCalamaExcel(ab, path.basename(file))

  printSection('HOJAS DETECTADAS', preview.hojas_detectadas.join(', '))
  printSection('FAENAS SUGERIDAS', preview.faenas_detectadas
    .map((f) => `${f.codigo} (${f.razon})`).join('\n  ') || '— ninguna —')
  printSection('LINEAS NEGOCIO SUGERIDAS', preview.lineas_negocio_detectadas
    .map((l) => `${l.codigo} (${l.razon})`).join('\n  ') || '— ninguna —')

  printSection('RESUMEN',
    Object.entries(preview.resumen).map(([k, v]) => `${k.padEnd(22)} ${v}`).join('\n'))

  printSamples('ZONAS (primeras 5)', preview.zonas_detectadas.slice(0, 5),
    (z) => `${z.codigo}  ${z.nombre}`)
  printSamples('TAREAS (primeras 8)', preview.tareas_detectadas.slice(0, 8),
    (t) => `${t.codigo}  ${(t.nombre ?? '').slice(0, 50).padEnd(50)} dur ${t.duracion_plan_dias ?? '—'}/${t.duracion_real_dias ?? '—'}d  inicio ${t.fecha_inicio_plan ?? '—'}`)
  printSamples('SUBTAREAS (primeras 8)', preview.subtareas_detectadas.slice(0, 8),
    (s) => `${s.codigo.padEnd(10)} ${(s.descripcion ?? '').slice(0, 50).padEnd(50)} estado: ${s.estado ?? '—'}  fecha: ${s.fecha_real ?? '—'}`)
  printSamples('MATERIALES (primeros 8)', preview.materiales_detectados.slice(0, 8),
    (m) => `[${(m.zona_codigo ?? '——').padEnd(6)}] ${(m.actividad_relacionada ?? '—').slice(0, 25).padEnd(25)} ${(m.descripcion ?? '').slice(0, 30).padEnd(30)} CLP ${m.precio_clp ?? '—'}  UF ${m.valor_uf ?? '—'}`)
  // Cobertura de zona en materiales
  const conZona = preview.materiales_detectados.filter((m) => m.zona_codigo).length
  console.log(`\n=== COBERTURA DE ZONA EN MATERIALES ===\n  Con zona: ${conZona} / ${preview.materiales_detectados.length}`)
  // Conteo por zona
  const porZona = new Map<string, number>()
  for (const m of preview.materiales_detectados) {
    const k = m.zona_codigo ?? '(sin zona)'
    porZona.set(k, (porZona.get(k) ?? 0) + 1)
  }
  console.log('\n=== MATERIALES POR ZONA ===')
  Array.from(porZona.entries()).sort().forEach(([z, n]) => console.log(`  ${z.padEnd(10)} ${n}`))
  printSamples('CONTACTOS (primeros 6)', preview.contactos_detectados.slice(0, 6),
    (c) => `${(c.codigo_actividad ?? '—').padEnd(10)} ${(c.descripcion ?? '').slice(0, 35).padEnd(35)} tel ${c.telefono ?? '—'}  faena: ${c.faena_sugerida ?? '—'}`)
  printSamples('AVANCES (primeros 6)', preview.avances_detectados.slice(0, 6),
    (a) => `${a.codigo.padEnd(10)} ${(a.nombre ?? '').slice(0, 50).padEnd(50)} ${a.avance_pct?.toFixed(1) ?? '—'}%`)
  printSamples('OBSERVACIONES (primeras 6)', preview.observaciones_detectadas.slice(0, 6),
    (o) => `${(o.codigo_relacionado ?? '—').padEnd(10)} ${o.texto.slice(0, 70)}`)

  if (preview.advertencias.length) {
    printSection(`ADVERTENCIAS (${preview.advertencias.length})`,
      preview.advertencias.slice(0, 12).map((a) => `[${a.hoja ?? 'global'}] ${a.detalle}`).join('\n'))
  }
  if (preview.errores_de_mapeo.length) {
    printSection(`ERRORES DE MAPEO (${preview.errores_de_mapeo.length})`,
      preview.errores_de_mapeo.slice(0, 12).map((e) => `[${e.hoja}${e.fila ? ':R' + e.fila : ''}] ${e.detalle}`).join('\n'))
  }
}

function printSection(title: string, body: string) {
  console.log(`\n=== ${title} ===\n${body}`)
}

function printSamples<T>(title: string, items: T[], fmt: (i: T) => string) {
  console.log(`\n=== ${title} ===`)
  if (items.length === 0) {
    console.log('  (vacio)')
    return
  }
  for (const it of items) console.log('  ' + fmt(it))
}

main().catch((e) => {
  console.error('FALLO:', e)
  process.exit(1)
})
