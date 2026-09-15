// ============================================================================
// Despachador de entregables de prevención (MIG547)
// ----------------------------------------------------------------------------
// Dado un ítem de reportabilidad con plantilla, junta los datos del mes y
// llama al generador que corresponde. Devuelve el archivo listo para
// descargar (y para adjuntar como respaldo al marcar la entrega).
// ============================================================================

import {
  getAmbientalRegistrosDetalle, getConsolidadoMes, getDotacionInstalacionMes,
  getFaenaConfig, getIndicadoresAnio, getRegistros,
  type DotacionInstalacion, type FaenaConfigDatos, type IndicadoresFila,
  type PrevencionRegistro,
} from '@/lib/services/prevencion-reportabilidad'
import { generarInformeFrankeExcel } from './prevencion-informe-franke-excel'
import { generarPptEvidencias } from './prevencion-ppt-evidencias'

export type PlantillaEntregable =
  | 'e200' | 'grp_cmp' | 'informe_franke' | 'ppt_evidencias'
  | 'estadistica_esm' | 'franke_insumos' | 'franke_residuos' | 'anexo_102'

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
    const { generarE200Docx } = await import('./prevencion-e200-docx')

    // [MIG559] El E-200 va POR LUGAR: si la ficha de la faena declara
    // instalaciones (Centinela), sale UN formulario por cada una — con la
    // faena del mandante, la ficha geográfica del lugar y la dotación/HH que
    // los supervisores subieron para esa instalación — empaquetados en ZIP.
    const instalaciones = config.instalaciones ?? []
    if (instalaciones.length > 0) {
      onProgreso?.('Cargando dotación por instalación…')
      const { data: porInst, error } = await getDotacionInstalacionMes(faenaId, anio, mes)
      if (error) throw error
      const dotPorLugar = new Map(
        ((porInst ?? []) as DotacionInstalacion[]).map((d) => [d.instalacion, d]),
      )
      const detalle = config.instalaciones_detalle ?? {}
      const JSZip = (await import('jszip')).default
      const zip = new JSZip()
      for (const clave of instalaciones) {
        const det = detalle[clave] ?? {}
        // Sin ficha detallada, la clave misma trae «Faena — Instalación».
        const [fParte, iParte] = clave.split('—').map((s) => s.trim())
        const nombreInst = det.nombre ?? iParte ?? clave
        const faenaMandante = det.faena ?? fParte ?? faenaNombre
        const d = dotPorLugar.get(clave)
        onProgreso?.(`Rellenando E-200 de ${nombreInst}…`)
        const blob = await generarE200Docx({
          config, indicadores: null, anio, mes, faenaNombre,
          faenaMandante,
          instalacion: { ...det, nombre: nombreInst },
          dotacion: {
            dot_h: Number(d?.dotacion_max_hombres ?? 0), hh_h: Number(d?.hh_hombres ?? 0),
            dot_m: Number(d?.dotacion_max_mujeres ?? 0), hh_m: Number(d?.hh_mujeres ?? 0),
          },
        })
        zip.file(`Formulario_E-200_${slug(faenaMandante)}_${slug(nombreInst)}_${anio}-${mm}.docx`, blob)
      }
      onProgreso?.('Empaquetando los formularios…')
      const blob = await zip.generateAsync({ type: 'blob' })
      return { blob, filename: `Formularios_E-200_${slug(faenaNombre)}_${anio}-${mm}.zip` }
    }

    onProgreso?.('Cargando indicadores del mes…')
    const { data: ind, error } = await getIndicadoresAnio(faenaId, anio)
    if (error) throw error
    const fila = ((ind ?? []) as IndicadoresFila[]).find((f) => f.mes === mes) ?? null
    // [MIG557] Se RELLENA el Word oficial del Gobierno (plantilla con
    // marcadores en /plantillas/) — sale idéntico al formato estatal.
    onProgreso?.('Rellenando el formulario oficial…')
    const blob = await generarE200Docx({ config, indicadores: fila, anio, mes, faenaNombre })
    return { blob, filename: `Formulario_E-200_${slug(faenaNombre)}_${anio}-${mm}.docx` }
  }

  if (plantilla === 'estadistica_esm') {
    onProgreso?.('Cargando HH por instalación…')
    const [{ data: porInst, error: e1 }, { data: ind, error: e2 }] = await Promise.all([
      getDotacionInstalacionMes(faenaId, anio, mes),
      getIndicadoresAnio(faenaId, anio),
    ])
    if (e1) throw e1
    if (e2) throw e2
    const fila = ((ind ?? []) as IndicadoresFila[]).find((f) => f.mes === mes) ?? null
    const { generarEstadisticaEsmExcel } = await import('./prevencion-reportes-faena-excel')
    const blob = await generarEstadisticaEsmExcel({
      config, porInstalacion: (porInst ?? []) as DotacionInstalacion[],
      indicadores: fila, anio, mes,
    })
    return { blob, filename: `Estadistica_RRHH_ESM_${slug(faenaNombre)}_${anio}-${mm}.xlsx` }
  }

  if (plantilla === 'franke_insumos' || plantilla === 'franke_residuos') {
    onProgreso?.('Cargando lo reportado por el supervisor…')
    const { data: detalle, error } = await getAmbientalRegistrosDetalle(faenaId, anio, mes)
    if (error) throw error
    const mod = await import('./prevencion-reportes-faena-excel')
    if (plantilla === 'franke_insumos') {
      const blob = await mod.generarFrankeInsumosExcel({ config, detalle, anio, mes })
      return { blob, filename: `4.4_Reporte_insumos_${anio}-${mm}.xlsx` }
    }
    const blob = await mod.generarFrankeResiduosExcel({ config, detalle, anio, mes })
    return { blob, filename: `4.5_Gestion_residuos_${anio}-${mm}.xlsx` }
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
    // [MIG557] El formato real de CMP es una PRESENTACIÓN: sale PPTX editable
    // con las 4 láminas del formato (reemplaza al PDF de MIG547).
    onProgreso?.('Armando la presentación GRP (fotos incluidas)…')
    const { generarGrpCmpPptx } = await import('./prevencion-grp-cmp-pptx')
    const blob = await generarGrpCmpPptx({
      config, indicadores, gestion, registros: regs, anio, mes,
    })
    return { blob, filename: `REPORTE_GESTION_MENSUAL_PILLADO_${anio}-${mm}.pptx` }
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

  if (plantilla === 'anexo_102') {
    // [MIG558] La guía manda: estructura exacta del Anexo 10.2, evidencias
    // (fotos y PDF incrustados) en su subsección, constantes donde no hay.
    onProgreso?.('Armando el Anexo 10.2 con su estructura…')
    const { generarAnexo102Pptx } = await import('./prevencion-anexo102-pptx')
    const blob = await generarAnexo102Pptx({
      registros: regs, faenaNombre, anio, mes, onProgreso,
    })
    return { blob, filename: `Anexo_10.2_${slug(faenaNombre)}_${anio}-${mm}.pptx` }
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
