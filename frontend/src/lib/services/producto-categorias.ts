import { supabase } from '@/lib/supabase'

export type ProductoCategoria = { codigo: string; nombre: string; activo: boolean }

export async function getCategoriasProducto(soloActivas = false): Promise<ProductoCategoria[]> {
  let q = supabase.from('producto_categorias').select('codigo, nombre, activo').order('nombre')
  if (soloActivas) q = q.eq('activo', true)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as ProductoCategoria[]
}

export async function crearCategoria(nombre: string) {
  const codigo = slugCategoria(nombre)
  if (!codigo) throw new Error('Nombre de categoría inválido')
  const { error } = await supabase.from('producto_categorias').insert({ codigo, nombre: nombre.trim() })
  if (error) throw error
  return codigo
}

export async function actualizarCategoria(codigo: string, patch: { nombre?: string; activo?: boolean }) {
  const { error } = await supabase.from('producto_categorias')
    .update({ ...patch, updated_at: new Date().toISOString() }).eq('codigo', codigo)
  if (error) throw error
}

// Slug a partir del nombre: minúsculas, sin acentos, _ entre palabras.
export function slugCategoria(nombre: string): string {
  return nombre.trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40)
}

// Normaliza texto para comparar (minúsculas, sin acentos).
export function normalizar(texto: string): string {
  return texto.trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
}
