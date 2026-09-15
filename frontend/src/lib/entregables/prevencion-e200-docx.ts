// ============================================================================
// Formulario E-200 — RELLENA EL WORD OFICIAL (MIG557)
// ----------------------------------------------------------------------------
// Manuel entregó el formato estatal en Word (E-200_FORMATO-.docx). Ese archivo
// vive como plantilla en /plantillas/e200_plantilla.docx con 49 marcadores
// {{X}} puestos en las celdas de valor SIN tocar el formato. Aquí se descarga,
// se reemplazan los marcadores con los datos del mes y sale el .docx IDÉNTICO
// al del Gobierno, listo para declarar. Reemplaza al Excel de MIG547.
// ============================================================================

import JSZip from 'jszip'
import type { FaenaConfigDatos, IndicadoresFila } from '@/lib/services/prevencion-reportabilidad'

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

function xmlEscape(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

/** "77.316.540-8" → ["77.316.540", "8"] como lo separa el formulario. */
function rutPartes(rut?: string): [string, string] {
  if (!rut) return ['', '']
  const limpio = rut.trim()
  const i = limpio.lastIndexOf('-')
  return i < 0 ? [limpio, ''] : [limpio.slice(0, i), limpio.slice(i + 1)]
}

export async function generarE200Docx(params: {
  config: FaenaConfigDatos
  indicadores: IndicadoresFila | null
  anio: number
  mes: number
  faenaNombre: string
  // [MIG559] E-200 POR LUGAR: cuando la faena declara por instalación
  // (Centinela), estos tres mandan sobre la ficha general — nombre de la
  // faena del mandante, ficha de la instalación y dotación/HH del lugar.
  faenaMandante?: string
  instalacion?: Record<string, string>
  dotacion?: { dot_h: number; hh_h: number; dot_m: number; hh_m: number }
}): Promise<Blob> {
  const { config, indicadores, anio, mes } = params
  const emp = config.empresa ?? {}
  const man = config.mandante ?? {}
  const inst = params.instalacion ?? config.instalacion ?? {}
  const exp = config.experto ?? {}

  const res = await fetch('/plantillas/e200_plantilla.docx')
  if (!res.ok) throw new Error('No se pudo cargar la plantilla oficial del E-200')
  const zip = await JSZip.loadAsync(await res.arrayBuffer())
  let xml = await zip.file('word/document.xml')!.async('string')

  const [rutE, dvE] = rutPartes(emp.rut)
  const [rutR, dvR] = rutPartes(emp.rep_legal_rut)
  const [rutM, dvM] = rutPartes(man.rut)
  const [runX, dvX] = rutPartes(exp.run)
  const num = (v: number | string | null | undefined) =>
    v === null || v === undefined || v === '' ? '' : String(v)

  const valores: Record<string, string> = {
    MES: `${MESES[mes - 1]} de ${anio}`,
    RUT_EMP: rutE, DV_EMP: dvE, RAZON_EMP: emp.razon_social ?? '',
    CATEGORIA: emp.categoria ?? '', FANTASIA_EMP: emp.nombre_fantasia ?? '',
    DIR_CALLE: emp.direccion ?? '', DIR_REGION: emp.region ?? '',
    DIR_PROV: emp.provincia ?? '', DIR_COMUNA: emp.comuna ?? '',
    DIR_FONO: emp.telefono ?? '', DIR_EMAIL: emp.email ?? '',
    REP_LEGAL: emp.rep_legal ?? '', RUT_REP: rutR, DV_REP: dvR,
    FONO_REP: emp.rep_legal_telefono ?? '', EMAIL_REP: emp.rep_legal_email ?? '',
    RUT_MAND: rutM, DV_MAND: dvM, RAZON_MAND: man.razon_social ?? '',
    REGION_MAND: man.region ?? '', FANTASIA_MAND: man.nombre_fantasia ?? '',
    FAENA: params.faenaMandante || config.faena_nombre || params.faenaNombre,
    INSTALACION: inst.nombre ?? '', ESTADO_INST: inst.estado ?? '',
    REGION_INST: inst.region ?? '', PROV_INST: inst.provincia ?? '',
    COMUNA_INST: inst.comuna ?? '', TIPO_INST: inst.tipo ?? '',
    DATUM: inst.datum ?? '', HUSO: inst.huso ?? '', COTA: inst.cota ?? '',
    NORTE: inst.coord_norte ?? '', ESTE: inst.coord_este ?? '',
    DOT_H: params.dotacion ? num(params.dotacion.dot_h) : num(indicadores?.dotacion_hombres),
    HH_H: params.dotacion ? num(params.dotacion.hh_h) : num(indicadores ? Number(indicadores.hh_hombres) : ''),
    DOT_M: params.dotacion ? num(params.dotacion.dot_m) : num(indicadores?.dotacion_mujeres),
    HH_M: params.dotacion ? num(params.dotacion.hh_m) : num(indicadores ? Number(indicadores.hh_mujeres) : ''),
    DOT_SH: '0', HH_SH: '0', DOT_SM: '0', HH_SM: '0',
    RUN_EXP: dvX ? `${runX}-${dvX}` : runX,
    REG_EXP: exp.registro_sngm ?? '',
    NOMBRE_EXP: exp.nombre ?? '', CARGO_EXP: exp.cargo ?? '',
    FECHA_DECL: new Date().toLocaleDateString('es-CL'),
    FONO_EXP: exp.telefono ?? '', EMAIL_EXP: exp.email ?? '',
  }

  for (const [token, valor] of Object.entries(valores)) {
    xml = xml.split(`{{${token}}}`).join(xmlEscape(valor))
  }
  // Ningún marcador puede quedar vivo en el documento final.
  xml = xml.replace(/\{\{[A-Z_]+\}\}/g, '')

  zip.file('word/document.xml', xml)
  return zip.generateAsync({
    type: 'blob',
    mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  })
}
