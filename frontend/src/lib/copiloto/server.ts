import { createClient, type SupabaseClient } from '@supabase/supabase-js'

// ============================================================================
// Copiloto Técnico — utilidades de servidor compartidas por /api/copiloto/*.
// El corpus (manuales, códigos, fichas, páginas renderizadas) vive en el
// proyecto Supabase paralelo "copiloto-corpus" y se consulta SOLO desde el
// servidor con la service key. SICOM se consulta con el token del usuario
// (RLS manda).
// ============================================================================

export type Autenticado = { sb: SupabaseClient; uid: string }

export async function autenticar(req: Request): Promise<Autenticado | { error: string; status: number }> {
  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!token || !url || !anon) return { error: 'No autorizado.', status: 401 }
  const sb = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } } })
  const { data, error } = await sb.auth.getUser(token)
  if (error || !data?.user) return { error: 'Sesión inválida.', status: 401 }
  return { sb, uid: data.user.id }
}

export function corpusCliente(): SupabaseClient | null {
  const url = process.env.COPILOTO_SUPABASE_URL
  const key = process.env.COPILOTO_SUPABASE_SERVICE_KEY
  if (!url || !key) return null
  return createClient(url, key, { auth: { persistSession: false } })
}

export function slug(v?: string | null): string | null {
  if (!v) return null
  return v.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim().replace(/\s+/g, '-')
}

export function normalizarPatente(p?: string | null): string | null {
  if (!p) return null
  const s = p.toUpperCase().replace(/[^A-Z0-9]/g, '')
  const m = s.match(/^([A-Z]{2,4})(\d{2,4})$/)
  return m ? `${m[1]}-${m[2]}` : s || null
}

export type FichaEquipo = {
  patente: string; marca: string | null; modelo: string | null; anio: number | null
  vin: string | null; numero_motor: string | null; motor: string | null; transmision: string | null
  emisiones: string | null; ecus: string | null; equipamiento: string | null; implemento: string | null
  zona: string | null; fuente_oem: string | null; lectura_codigos: string | null; notas: string | null
  datos: Record<string, unknown> | null
}

export async function fichaEquipo(corpus: SupabaseClient | null, patente?: string | null): Promise<FichaEquipo | null> {
  const p = normalizarPatente(patente)
  if (!corpus || !p) return null
  const { data } = await corpus.from('copiloto_fichas_equipo').select('*').eq('patente', p).maybeSingle()
  return (data as FichaEquipo | null) ?? null
}

export type CodigoFalla = {
  id: number; marca: string | null; aplica: string | null; ecu: string | null; formato: string
  codigo: string; spn: number | null; fmi: number | null; descripcion: string
  causas: string[]; comprobaciones: string[]; sistema: string | null
  confiabilidad: string; fuente: string | null; coincidencia: 'exacta' | 'mismo_spn' | 'texto'
}

export async function buscarCodigo(corpus: SupabaseClient, texto: string, marca: string | null, limit = 8) {
  const { data, error } = await corpus.rpc('buscar_codigo_falla', { p_texto: texto, p_marca: marca, p_limit: limit })
  if (error) throw error
  return (data ?? []) as CodigoFalla[]
}

// Detecta códigos en la pregunta del mecánico: "SPN 3251 FMI 0", "3251-0",
// "P0420", "MID 128 PID 100", "código 4-12"... para buscarlos sin esperar a
// que la IA lo pida.
export function codigosEnTexto(q: string): string[] {
  const out = new Set<string>()
  for (const m of Array.from(q.matchAll(/spn\s*[:#]?\s*(\d{2,7})(?:\D{1,8}fmi\s*[:#]?\s*(\d{1,2}))?/gi))) {
    out.add(m[2] ? `SPN ${m[1]} FMI ${m[2]}` : `SPN ${m[1]}`)
  }
  for (const m of Array.from(q.matchAll(/\b([PBCU][0-9A-F]{4})\b/gi))) out.add(m[1].toUpperCase())
  for (const m of Array.from(q.matchAll(/\bmid\s*(\d{2,3})\s*(pid|sid|psid)\s*(\d{1,4})(?:\D{1,6}fmi\s*(\d{1,2}))?/gi))) {
    out.add(`MID ${m[1]} ${m[2].toUpperCase()} ${m[3]}${m[4] ? ` FMI ${m[4]}` : ''}`)
  }
  if (!out.size && /c[oó]digo|falla|dtc|error/i.test(q)) {
    const m = q.match(/\b(\d{3,6})\s*[-/ ]\s*(\d{1,2})\b/)
    if (m) out.add(`${m[1]} ${m[2]}`)
  }
  return Array.from(out).slice(0, 3)
}

export const BUCKET_PAGINAS = 'paginas'

export async function urlPagina(corpus: SupabaseClient, storagePath: string, segundos = 3600): Promise<string | null> {
  const { data } = await corpus.storage.from(BUCKET_PAGINAS).createSignedUrl(storagePath, segundos)
  return data?.signedUrl ?? null
}

// ── Adjuntos del mecánico (fotos y PDFs) ────────────────────────────────────
export const BUCKET_ADJUNTOS = 'adjuntos'
export const TIPOS_ADJUNTO = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
// 20 MB: el request a Claude tope 32 MB y el base64 infla ~33 %
export const MAX_BYTES_ADJUNTO = 20 * 1024 * 1024
export type AdjuntoRef = { path: string; tipo: string; nombre: string }
