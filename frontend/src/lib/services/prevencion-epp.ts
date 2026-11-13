import { supabase } from '@/lib/supabase'

// ============================================================================
// Entrega de EPP con firma del trabajador (MIG687)
// ----------------------------------------------------------------------------
// Registro de prevención (DS 44 art. 13): qué se entregó, a quién, cuándo,
// por qué, si se instruyó el uso, y la firma de quien recibe. No descuenta
// stock de bodega.
// ============================================================================

export interface EppCatalogo {
  codigo: string
  nombre: string
  categoria: string
  requiere_talla: boolean
  vida_util_meses: number | null
  orden: number
}

export interface EppItemEntrega {
  epp_codigo: string
  nombre: string
  categoria: string
  cantidad: number
  talla: string | null
  proxima_reposicion: string | null
}

export interface EppEntrega {
  id: string
  personal_id: string
  faena_id: string
  faena_nombre: string
  fecha: string
  motivo: string
  instruccion_uso: boolean
  observacion: string | null
  firma_path: string
  trabajador_nombre: string
  trabajador_rut: string | null
  entregado_por: string
  entregado_por_nombre: string | null
  anulada: boolean
  anulada_motivo: string | null
  created_at: string
  items: EppItemEntrega[]
}

export interface PersonaEpp {
  id: string
  nombre: string
  rut: string
  faena_codigo: string | null
  cargo: string | null
}

export const MOTIVO_EPP: Record<string, string> = {
  ingreso: 'Ingreso / primera entrega',
  reposicion: 'Reposición por vida útil',
  deterioro: 'Deterioro',
  perdida: 'Pérdida',
  cambio_talla: 'Cambio de talla',
  otro: 'Otro',
}

export async function getCatalogoEpp(): Promise<EppCatalogo[]> {
  const { data, error } = await supabase.from('prevencion_epp_catalogo')
    .select('codigo, nombre, categoria, requiere_talla, vida_util_meses, orden')
    .eq('activo', true).order('orden')
  if (error) throw error
  return (data ?? []) as EppCatalogo[]
}

/** Personal vigente del control documental (de todas las faenas). */
export async function getPersonasEpp(): Promise<PersonaEpp[]> {
  const { data, error } = await supabase.from('prevencion_personal')
    .select('id, nombres, apellidos, rut, faena_codigo, cargo')
    .eq('activo', true).order('nombres')
  if (error) throw error
  return (data ?? []).map((p: any) => ({
    id: p.id,
    nombre: `${p.nombres} ${p.apellidos ?? ''}`.trim(),
    rut: p.rut,
    faena_codigo: p.faena_codigo,
    cargo: p.cargo,
  }))
}

export async function getEntregasEpp(params: {
  desde?: string, hasta?: string, faenaId?: string | null, personalId?: string | null, soloMias?: boolean, limit?: number,
} = {}): Promise<EppEntrega[]> {
  let q = supabase.from('v_prevencion_epp_entregas').select('*')
    .order('fecha', { ascending: false }).order('created_at', { ascending: false })
  if (params.desde) q = q.gte('fecha', params.desde)
  if (params.hasta) q = q.lte('fecha', params.hasta)
  if (params.faenaId) q = q.eq('faena_id', params.faenaId)
  if (params.personalId) q = q.eq('personal_id', params.personalId)
  if (params.soloMias) {
    const { data: u } = await supabase.auth.getUser()
    if (u.user) q = q.eq('entregado_por', u.user.id)
  }
  const { data, error } = await q.limit(params.limit ?? 500)
  if (error) throw error
  return (data ?? []) as EppEntrega[]
}

function dataUrlToBlob(dataUrl: string): Blob {
  const bin = atob(dataUrl.split(',')[1] ?? '')
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return new Blob([buf], { type: 'image/png' })
}

/** Sube la firma al bucket privado de prevención y devuelve su ruta. */
export async function subirFirmaEpp(dataUrl: string, faenaId: string, fecha: string): Promise<string> {
  const [anio, mes] = fecha.split('-')
  const path = `${faenaId}/${anio}/${mes}/epp/${Date.now()}-firma.png`
  const { error } = await supabase.storage.from('prevencion-evidencias')
    .upload(path, dataUrlToBlob(dataUrl), { contentType: 'image/png', upsert: false })
  if (error) throw error
  return path
}

export async function registrarEntregaEpp(p: {
  cliente_uuid: string
  personal_id: string
  faena_id: string
  fecha: string
  motivo: string
  instruccion_uso: boolean
  observacion?: string | null
  firma_path: string
  items: { epp_codigo: string, cantidad: number, talla?: string | null }[]
}): Promise<string> {
  const { data, error } = await supabase.rpc('fn_prevencion_epp_registrar', { p })
  if (error) throw new Error(error.message)
  return data as string
}

export async function anularEntregaEpp(id: string, motivo: string) {
  const { error } = await supabase.from('prevencion_epp_entregas')
    .update({ anulada: true, anulada_motivo: motivo }).eq('id', id)
  if (error) throw error
}

export async function urlFirmaEpp(path: string): Promise<string | null> {
  const { data } = await supabase.storage.from('prevencion-evidencias').createSignedUrl(path, 3600)
  return data?.signedUrl ?? null
}
