import { supabase } from '@/lib/supabase'

// Lecturas del portal del mandante (MIG688). Todo pasa por funciones de la
// base que validan link + ingreso vigente; el portal no tiene usuario.

export interface ConfigPortal {
  ver_prevencion: boolean
  ver_operaciones: boolean
  faenas: { id: string, nombre: string }[]
  faenas_enex: { codigo: string, nombre: string }[]
}

export interface InspeccionPortal {
  id: string; fecha: string; faena: string; trabajo: string
  instalacion: string | null; area_sector: string | null; inspector: string | null
  estado: 'en_curso' | 'pendiente_cierre_art' | 'cerrada'
  resultado: 'conforme' | 'con_desviaciones' | 'critico'
  pct_cumplimiento: number | null; items_cumple: number; items_no_cumple: number
  personas_no_habilitadas: number; desviaciones: number; desviaciones_abiertas: number
}

export interface DesviacionPortal {
  id: string; fecha: string; faena: string; trabajo: string; item_codigo: string | null
  criticidad: 'alta' | 'media' | 'baja'; descripcion: string; accion: string | null
  responsable: string | null; fecha_compromiso: string | null; vencida: boolean | null
}

export interface ActividadPortal {
  id: string; fecha: string; faena: string; tipo: string; tipo_codigo: string
  titulo: string; descripcion: string | null; area_sector: string | null
  estado: 'abierto' | 'cerrado'; responsable: string | null
  asistentes: number | null; duracion_minutos: number | null; fotos: string[]
}

export interface PrevencionPortal {
  inspecciones: InspeccionPortal[]
  desviaciones_abiertas: DesviacionPortal[]
  actividades: ActividadPortal[]
  resumen_actividades: { tipo: string, realizados: number, abiertos: number }[]
  indicadores: {
    faena: string; dotacion: number | null; hh: number | null; accidentes_ctp: number | null
    dias_perdidos: number | null; incidentes_alto_potencial: number | null
    if: number | null; ig: number | null; acum_if: number | null; acum_ig: number | null
  }[]
}

export interface ServicioPortal {
  programacion_id: string; faena: string; instalacion: string; instalacion_tipo: string | null
  patente: string | null; linea: string | null; tipo_servicio: 'mantencion' | 'calibracion'
  periodo_mes: number; fecha_programada: string | null; estado: string; cumplida: boolean | null
  fecha_ejecucion: string | null; ot_numero: string | null; tecnico: string | null
  firmante_mandante: string | null; informe_pdf_url: string | null
}

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(error.message)
  return data as T
}

export const getConfigPortal = (token: string, acceso: string) =>
  rpc<ConfigPortal>('fn_portal_mandante_config', { p_token: token, p_acceso_id: acceso })

export const getPrevencionPortal = (token: string, acceso: string, anio: number, mes: number) =>
  rpc<PrevencionPortal>('fn_portal_mandante_prevencion', { p_token: token, p_acceso_id: acceso, p_anio: anio, p_mes: mes })

export const getOperacionesPortal = (token: string, acceso: string, anio: number, mes: number | null) =>
  rpc<{ servicios: ServicioPortal[] }>('fn_portal_mandante_operaciones', { p_token: token, p_acceso_id: acceso, p_anio: anio, p_mes: mes })

export const getInspeccionPortal = (token: string, acceso: string, id: string) =>
  rpc<any>('fn_portal_mandante_inspeccion', { p_token: token, p_acceso_id: acceso, p_id: id })

/** Firma fotos a través del servidor (que valida el alcance en la base). */
export async function urlsFotosPortal(token: string, acceso: string, paths: string[]): Promise<Record<string, string>> {
  const r = await fetch('/api/prevencion/portal-evidencia/', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ token, acceso_id: acceso, paths }),
  })
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j.error ?? 'No se pudieron cargar las fotos')
  return j.urls ?? {}
}

export const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']
