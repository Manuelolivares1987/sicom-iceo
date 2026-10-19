// Descarga masiva de los informes ENEX de un mes: todos los PDF guardados en un
// ZIP, una carpeta por faena, nombrados para que se ordenen solos por fecha
// (2026-09-14 - Instalación - Mantención - OT 123.pdf). Va con un índice CSV
// que también lista los servicios SIN PDF, para que la revisión no se salte
// ninguno sin darse cuenta.

import type { EnexPanelRow } from '@/lib/services/enex'

function limpiar(s: string): string {
  return s.replace(/[\\/:*?"<>|]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120)
}

function servicio(r: EnexPanelRow): string {
  return r.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'
}

function estadoFirmas(r: EnexPanelRow): string {
  if (r.cumplida) return r.firma_tecnico_lista ? 'Cumplida' : 'Cumplida (falta firma técnico)'
  return r.firma_tecnico_lista ? 'Falta firma ESM' : 'Faltan las 2 firmas'
}

function csv(v: string | null | undefined): string {
  const s = v ?? ''
  return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

export async function descargarInformesZip(
  filas: EnexPanelRow[],
  nombreZip: string,
  onProgreso?: (hechos: number, total: number) => void,
): Promise<{ incluidos: number; sinPdf: number; fallidos: string[] }> {
  const JSZip = (await import('jszip')).default
  const zip = new JSZip()
  const usados = new Set<string>()
  const fallidos: string[] = []
  const conPdf = filas.filter((r) => r.informe_pdf_url)
  const archivoDe = new Map<EnexPanelRow, string>()

  // Nombres primero (secuencial, para resolver duplicados sin carreras).
  for (const r of conPdf) {
    const partes = [
      (r.fecha_ejecucion ?? '').slice(0, 10) || 'sin-fecha',
      r.instalacion + (r.patente ? ` ${r.patente}` : ''),
      servicio(r),
      r.ot_numero ? `OT ${r.ot_numero}` : '',
    ].filter(Boolean)
    let nombre = `${limpiar(r.faena || 'Sin faena')}/${limpiar(partes.join(' - '))}.pdf`
    for (let i = 2; usados.has(nombre); i++) nombre = nombre.replace(/( \(\d+\))?\.pdf$/, ` (${i}).pdf`)
    usados.add(nombre)
    archivoDe.set(r, nombre)
  }

  // Bajadas de a 4: de una en una un mes completo tarda minutos; todas juntas
  // satura la conexión del teléfono o de la faena.
  let hechos = 0
  const cola = [...conPdf]
  async function trabajador() {
    for (let r = cola.shift(); r; r = cola.shift()) {
      try {
        const res = await fetch(r.informe_pdf_url!)
        if (!res.ok) throw new Error(String(res.status))
        zip.file(archivoDe.get(r)!, await res.blob())
      } catch {
        fallidos.push(`${(r.fecha_ejecucion ?? '').slice(0, 10)} ${r.instalacion}`)
        archivoDe.delete(r)
      }
      onProgreso?.(++hechos, conPdf.length)
    }
  }
  await Promise.all(Array.from({ length: Math.min(4, conPdf.length) }, trabajador))

  // Índice: abre directo en Excel (BOM + punto y coma).
  const cab = ['Fecha', 'Faena', 'Instalación', 'Patente', 'Servicio', 'N° OT', 'Ejecutor', 'Estado firmas', 'Archivo en el ZIP']
  const lineas = [...filas]
    .sort((a, b) => (a.faena ?? '').localeCompare(b.faena ?? '') ||
      (a.fecha_ejecucion ?? '').localeCompare(b.fecha_ejecucion ?? ''))
    .map((r) => [
      (r.fecha_ejecucion ?? '').slice(0, 10), r.faena, r.instalacion, r.patente, servicio(r),
      r.ot_numero, r.ejecutor, estadoFirmas(r),
      archivoDe.get(r) ?? (r.informe_pdf_url ? 'NO SE PUDO DESCARGAR' : 'SIN PDF GENERADO'),
    ].map(csv).join(';'))
  zip.file('Índice.csv', '﻿' + [cab.join(';'), ...lineas].join('\r\n'))

  const blob = await zip.generateAsync({ type: 'blob' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = limpiar(nombreZip) + '.zip'
  a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000)
  return { incluidos: archivoDe.size, sinPdf: filas.length - conPdf.length, fallidos }
}
