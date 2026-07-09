// Certificados del equipo (MIG219): la carpeta de la ficha del activo.
// Se habilitan cuando el equipo no tiene NC abiertas; cada uno lo firma el
// operador que hizo el trabajo y el jefe de taller.
import { supabase } from '@/lib/supabase'

const FIRMA_BUCKET = 'calama-firmas'

export type CertificadoCampo = {
  key: string
  label: string
  tipo?: 'text' | 'number' | 'date'
  destacado?: boolean
}

export type CertificadoTipo = {
  codigo: string
  titulo: string
  cuerpo: string
  seccion: string | null
  campos: CertificadoCampo[]
  orden: number
  activo: boolean
}

export type ActivoCertificado = {
  id: string
  activo_id: string
  tipo_codigo: string
  numero: number
  fecha_emision: string
  ciudad: string
  datos: Record<string, string>
  operador_tecnico_id: string | null
  operador_nombre: string
  firma_operador_url: string
  jefe_nombre: string
  firma_jefe_url: string
  ot_id: string | null
  created_at: string
  // vista
  titulo: string
  cuerpo: string
  seccion: string | null
  campos: CertificadoCampo[]
  activo_codigo: string | null
  activo_nombre: string | null
  activo_patente: string | null
  modelo_nombre: string | null
  marca_nombre: string | null
  ot_folio: string | null
}

function dataUrlToBlob(dataUrl: string): Blob {
  const [meta, b64] = dataUrl.split(',')
  const mime = meta.match(/:(.*?);/)?.[1] ?? 'image/png'
  const bin = atob(b64)
  const arr = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i)
  return new Blob([arr], { type: mime })
}

export async function getCertificadoTipos(): Promise<CertificadoTipo[]> {
  const { data, error } = await supabase.from('certificado_tipos')
    .select('*').eq('activo', true).order('orden')
  if (error) throw error
  return (data ?? []) as CertificadoTipo[]
}

export async function getCertificadosActivo(activoId: string): Promise<ActivoCertificado[]> {
  const { data, error } = await supabase.from('v_activo_certificados')
    .select('*').eq('activo_id', activoId).order('numero', { ascending: false })
  if (error) throw error
  return (data ?? []) as ActivoCertificado[]
}

export async function getCertificadoById(id: string): Promise<ActivoCertificado | null> {
  const { data, error } = await supabase.from('v_activo_certificados')
    .select('*').eq('id', id).maybeSingle()
  if (error) throw error
  return (data as ActivoCertificado | null) ?? null
}

/** NC abiertas del equipo — el gate para habilitar la emisión. */
export async function getNcAbiertasActivo(activoId: string): Promise<number> {
  const { count, error } = await supabase.from('no_conformidades')
    .select('id', { count: 'exact', head: true })
    .eq('activo_id', activoId).eq('resuelto', false)
  if (error) throw error
  return count ?? 0
}

async function subirFirmaCertificado(dataUrl: string, quien: 'operador' | 'jefe'): Promise<string> {
  const path = `certificados/${quien}_${Date.now()}_${Math.floor(Math.random() * 1e6)}.png`
  const { error } = await supabase.storage.from(FIRMA_BUCKET)
    .upload(path, dataUrlToBlob(dataUrl), { contentType: 'image/png' })
  if (error) throw error
  return supabase.storage.from(FIRMA_BUCKET).getPublicUrl(path).data.publicUrl
}

export async function emitirCertificado(params: {
  activoId: string
  tipoCodigo: string
  datos: Record<string, string>
  operadorNombre: string
  operadorTecnicoId?: string | null
  firmaOperadorDataUrl: string
  firmaJefeDataUrl: string
  fechaEmision?: string | null
  ciudad?: string | null
  otId?: string | null
}) {
  const firmaOperador = await subirFirmaCertificado(params.firmaOperadorDataUrl, 'operador')
  const firmaJefe = await subirFirmaCertificado(params.firmaJefeDataUrl, 'jefe')
  const { data, error } = await supabase.rpc('rpc_emitir_certificado_activo', {
    p_activo_id: params.activoId,
    p_tipo_codigo: params.tipoCodigo,
    p_datos: params.datos,
    p_operador_nombre: params.operadorNombre,
    p_firma_operador_url: firmaOperador,
    p_firma_jefe_url: firmaJefe,
    p_operador_tecnico_id: params.operadorTecnicoId ?? null,
    p_fecha_emision: params.fechaEmision ?? null,
    p_ciudad: params.ciudad ?? 'Coquimbo',
    p_ot_id: params.otId ?? null,
  })
  if (error) throw error
  return data as { success: boolean; certificado_id: string; numero: number }
}

/** Técnicos del catálogo del taller — para elegir al operador que firmó. */
export async function getTecnicosTaller(): Promise<{ id: string; nombre: string }[]> {
  const { data, error } = await supabase.from('taller_tecnicos')
    .select('id, nombre').eq('activo', true).order('nombre')
  if (error) throw error
  return (data ?? []) as { id: string; nombre: string }[]
}
