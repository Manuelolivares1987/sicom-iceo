// ============================================================================
// Despachador de entregables de prevención (MIG547)
// ----------------------------------------------------------------------------
// Dado un ítem de reportabilidad con plantilla, junta los datos del mes y
// llama al generador que corresponde. Devuelve el archivo listo para
// descargar (y para adjuntar como respaldo al marcar la entrega).
// ============================================================================

import {
  getConsolidadoMes, getFaenaConfig, getIndicadoresAnio, getRegistros,
  type FaenaConfigDatos, type IndicadoresFila, type PrevencionRegistro,
} from '@/lib/services/prevencion-reportabilidad'
import { generarE200Excel } from './prevencion-e200-excel'
import { generarInformeFrankeExcel } from './prevencion-informe-franke-excel'
import { generarPptEvidencias } from './prevencion-ppt-evidencias'

export type PlantillaEntregable = 'e200' | 'grp_cmp' | 'informe_franke' | 'ppt_evidencias'

// Qué tipos de registro alimentan cada PPT de evidencias. Sin entrada = todos
// los registros con evidencia del mes (caso Anexo 10.2 Lomas: lubricante y
// combustible se registran como charlas/inspecciones/HS con foto).
const TIPOS_PPT_POR_ITEM: Record<string, string[]> = {
  'Actividades HS — SAFEWORK': ['HS_SAFEWORK'],
  'Documentación ambiental': ['CHARLA', 'CAMPANA', 'CAPACITACION'],
}

function slug(s: string): string {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 60)
}

export async function generarEntregable(params: {
  plantilla: PlantillaEntregable
  itemNombre: string
  faenaId: string
  faenaNombre: string
  anio: number
  mes: number
  onProgreso?: (msg: string) => void
}): Promise<{ blob: Blob; filename: string }> {
  const { plantilla, itemNombre, faenaId, faenaNombre, anio, mes, onProgreso } = params
  const mm = String(mes).padStart(2, '0')

  onProgreso?.('Cargando configuración de la faena…')
  const { data: cfgRow, error: cfgErr } = await getFaenaConfig(faenaId)
  if (cfgErr) throw cfgErr
  const config: FaenaConfigDatos = (cfgRow?.datos as FaenaConfigDatos) ?? {}

  if (plantilla === 'e200') {
    onProgreso?.('Cargando indicadores del mes…')
    const { data: ind, error } = await getIndicadoresAnio(faenaId, anio)
    if (error) throw error
    const fila = ((ind ?? []) as IndicadoresFila[]).find((f) => f.mes === mes) ?? null
    // Réplica FIEL del formulario estatal (corrección Manuel 2026-09-14:
    // «debe ser el mismo porque es estatal»).
    const blob = await generarE200Excel({ config, indicadores: fila, anio, mes, faenaNombre })
    return { blob, filename: `Formulario_E-200_${slug(faenaNombre)}_${anio}-${mm}.xlsx` }
  }

  // El resto necesita el consolidado + los registros del mes.
  onProgreso?.('Consolidando el mes…')
  const [{ data: consolidado, error: e1 }, { data: registros, error: e2 }] = await Promise.all([
    getConsolidadoMes(faenaId, anio, mes),
    getRegistros({ faenaId, anio, mes }),
  ])
  if (e1) throw e1
  if (e2) throw e2
  const gestion = consolidado?.gestion ?? []
  const indicadores = (consolidado?.indicadores ?? null) as IndicadoresFila | null
  const regs = (registros ?? []) as PrevencionRegistro[]

  if (plantilla === 'grp_cmp') {
    onProgreso?.('Armando el informe GRP (fotos incluidas)…')
    // Import dinámico: el módulo trae @react-pdf/renderer y no tiene por qué
    // cargarse al abrir la página.
    const { generarInformeCmpPdf } = await import('./prevencion-informe-cmp-pdf')
    const blob = await generarInformeCmpPdf({
      config, indicadores, gestion, registros: regs, anio, mes, faenaNombre,
    })
    return { blob, filename: `Informe_GRP_${slug(faenaNombre)}_${anio}-${mm}.pdf` }
  }

  if (plantilla === 'informe_franke') {
    onProgreso?.('Cargando indicadores del año…')
    const { data: ind, error } = await getIndicadoresAnio(faenaId, anio)
    if (error) throw error
    const blob = await generarInformeFrankeExcel({
      config, indicadoresAnio: (ind ?? []) as IndicadoresFila[], gestion, registros: regs, anio, mes,
    })
    return { blob, filename: `Informe_Gestion_${slug(faenaNombre)}_${anio}-${mm}.xlsx` }
  }

  if (plantilla === 'ppt_evidencias') {
    const tipos = TIPOS_PPT_POR_ITEM[itemNombre]
    const filtrados = tipos ? regs.filter((r) => tipos.includes(r.tipo_codigo)) : regs
    onProgreso?.('Armando la presentación con las fotos del mes…')
    const blob = await generarPptEvidencias({
      config, registros: filtrados, titulo: itemNombre, faenaNombre, anio, mes,
      onProgreso: (h, t) => onProgreso?.(`Foto ${h} de ${t}…`),
    })
    return { blob, filename: `${slug(itemNombre)}_${slug(faenaNombre)}_${anio}-${mm}.pptx` }
  }

  throw new Error(`Plantilla desconocida: ${plantilla}`)
}

export function descargarBlob(blob: Blob, filename: string) {
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = filename
  a.click()
  URL.revokeObjectURL(a.href)
}
