// El informe ENEX es el documento con el que el mandante da el trabajo por
// hecho: si react-pdf revienta al armarlo, el técnico se entera en terreno.
// Aquí se renderiza de verdad a PDF con datos como los que deja la app.
import { describe, it, expect, vi } from 'vitest'
import { renderToBuffer } from '@react-pdf/renderer'
import type { EnexReporte, EnexReporteItem } from '@/lib/services/enex'
import { OtMantenimiento, CertificadoCalibracion } from '@/components/enex/pdf-informe-enex'

vi.mock('@/lib/supabase', () => ({ supabase: {} }))

// PNG 1x1 transparente: basta para que react-pdf resuelva la imagen.
const PX = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='

function item(p: Partial<EnexReporteItem> & { codigo: string; descripcion: string }): EnexReporteItem {
  return {
    id: p.codigo, resultado: p.resultado ?? null, valor_medicion: p.valor_medicion ?? null,
    dentro_tolerancia: p.dentro_tolerancia ?? null, foto_url: p.foto_url ?? null,
    fotos_antes: p.fotos_antes ?? null, fotos_despues: p.fotos_despues ?? null,
    observacion: p.observacion ?? null,
    item: {
      id: p.codigo, bloque: (p.item?.bloque ?? '2. Sala de microfiltrado'),
      bloque_orden: 2, orden: 1, codigo: p.codigo, descripcion: p.descripcion,
      tipo_campo: p.item?.tipo_campo ?? 'ok_nook', unidad: null, valor_referencia: null,
      tolerancia_min: null, tolerancia_max: null, periodicidad: 'trimestral',
      critico: false, requiere_foto: true,
    },
  }
}

const reporte: EnexReporte = {
  id: 'e1', estado: 'cumplida', fecha_ejecucion: '2026-08-05', ot_numero: null,
  ejecutor: 'Supervisor Combustible ENEX', observacion: null, evidencia_urls: null,
  firma_tecnico_url: PX, tecnico_nombre: 'Arnold Osandón',
  firma_mandante_url: PX, firmante_mandante_nombre: 'Oscar Campos',
  firmante_mandante_at: '2026-08-05T21:30:00Z',
  inicio_at: '2026-08-05T18:31:30Z', fin_at: '2026-08-05T21:30:24Z', duracion_segundos: 10734,
  pauta_id: 'p1',
  programacion: {
    tipo_servicio: 'mantencion', fecha_programada: '2026-08-05', periodo_anio: 2026, periodo_mes: 8,
    instalacion: {
      nombre: 'Truck Shop Lomas 2 - Rack 1', codigo: null, tipo: 'truck_shop',
      linea: 'lubricante', patente: null, faena: { nombre: 'Lomas Bayas', codigo: 'LB' },
    },
  },
  pauta: { codigo: 'PM-TS', nombre: 'Mantenimiento truck shop', tipo_servicio: 'mantencion', version: 1 },
}

const items: EnexReporteItem[] = [
  item({ codigo: 'DS.MOTIVO', descripcion: 'Motivo del llamado', observacion: 'Mantenimiento sala de microfiltrado', item: { bloque: '0. Datos del servicio', tipo_campo: 'texto' } as EnexReporteItem['item'] }),
  item({ codigo: '2.4', descripcion: 'Inspección de manómetros de presión', resultado: 'ok', fotos_antes: [PX, PX, PX], fotos_despues: [PX, PX] }),
  item({ codigo: '2.5', descripcion: 'Inspección sensores de temperatura', resultado: 'no_ok', observacion: 'Sensor 2 fuera de rango', fotos_antes: [PX], fotos_despues: [] }),
  item({ codigo: '2.6', descripcion: 'Inspección de calefactores', resultado: 'na' }),
]

const sinRegistro = [{
  id: 'x1', bloque: '3. Estanques', bloque_orden: 3, orden: 1, codigo: '3.1',
  descripcion: 'Inspección de estanque de almacenamiento', periodicidad: 'anual', critico: false,
}]

describe('informe ENEX', () => {
  it('arma la OT de mantención con el anexo de antes y después', async () => {
    const buf = await renderToBuffer(
      <OtMantenimiento reporte={reporte} items={items} logoUrl={PX} sinRegistro={sinRegistro} />)
    expect(buf.length).toBeGreaterThan(1000)
  }, 30_000)

  it('arma la OT aunque la visita no traiga ninguna foto', async () => {
    const secos = items.map((i) => ({ ...i, fotos_antes: null, fotos_despues: null }))
    const buf = await renderToBuffer(
      <OtMantenimiento reporte={reporte} items={secos} logoUrl={PX} sinRegistro={[]} />)
    expect(buf.length).toBeGreaterThan(1000)
  }, 30_000)

  it('arma el certificado de calibración', async () => {
    const cal = { ...reporte, programacion: { ...reporte.programacion!, tipo_servicio: 'calibracion' } }
    const buf = await renderToBuffer(
      <CertificadoCalibracion reporte={cal as EnexReporte} items={items} logoUrl={PX} />)
    expect(buf.length).toBeGreaterThan(1000)
  }, 30_000)
})
