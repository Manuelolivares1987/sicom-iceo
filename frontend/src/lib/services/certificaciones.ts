import { supabase } from '@/lib/supabase'
import { todayISO } from '@/lib/utils'
import type { Certificacion } from '@/types/database'

export async function getCertificaciones(activoId?: string) {
  let query = supabase
    .from('certificaciones')
    .select('*, activo:activos(id, codigo, nombre, tipo)')

  if (activoId) {
    query = query.eq('activo_id', activoId)
  }

  const { data, error } = await query.order('fecha_vencimiento', { ascending: true })

  return { data: data as Certificacion[] | null, error }
}

export async function getCertificacionesVencidas() {
  const { data, error } = await supabase
    .from('certificaciones')
    .select('*, activo:activos(id, codigo, nombre, tipo)')
    .in('estado', ['vencido', 'por_vencer'])
    .order('fecha_vencimiento', { ascending: true })

  return { data: data as Certificacion[] | null, error }
}

// NOTA: crear/renovar documentación va SIEMPRE por `renovarCertificacion`
// (RPC rpc_renovar_certificacion, MIG272) + `subirDocumentoCert` en
// lib/services/taller-planificacion.ts. La versión anterior de este archivo
// insertaba directo y subía el archivo a un bucket 'certificaciones' que no
// existe, así que ningún papel se podía cargar desde /dashboard/cumplimiento.

// Get all certifications with activo info
export async function getAllCertificaciones(filters?: {
  estado?: string
  tipo?: string
  faena_id?: string
}) {
  let query = supabase
    .from('certificaciones')
    .select('*, activo:activos(id, codigo, nombre, tipo, faena_id, faena:faenas(nombre))')
    .order('fecha_vencimiento', { ascending: true })

  if (filters?.estado) query = query.eq('estado', filters.estado)
  if (filters?.tipo) query = query.eq('tipo', filters.tipo)
  if (filters?.faena_id) query = query.eq('activo.faena_id', filters.faena_id)

  const { data, error } = await query
  return { data, error }
}

// Get certification stats
export async function getCertificacionStats() {
  const { data, error } = await supabase
    .from('certificaciones')
    .select('estado')

  if (error || !data) return { data: null, error }

  const stats = {
    total: data.length,
    vigentes: data.filter(c => c.estado === 'vigente').length,
    por_vencer: data.filter(c => c.estado === 'por_vencer').length,
    vencidas: data.filter(c => c.estado === 'vencido').length,
  }
  return { data: stats, error: null }
}

export async function getProximosVencimientos(dias: number = 30) {
  const hoy = todayISO()
  const limite = new Date()
  limite.setDate(limite.getDate() + dias)
  const limiteFecha = limite.toISOString().split('T')[0]

  const { data, error } = await supabase
    .from('certificaciones')
    .select('*, activo:activos(id, codigo, nombre, tipo)')
    .gte('fecha_vencimiento', hoy)
    .lte('fecha_vencimiento', limiteFecha)
    .order('fecha_vencimiento', { ascending: true })

  return { data: data as Certificacion[] | null, error }
}
