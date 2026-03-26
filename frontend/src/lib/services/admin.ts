import { supabase } from '@/lib/supabase'

export async function getUsuarios() {
  const { data, error } = await supabase
    .from('usuarios_perfil')
    .select('*, faena:faenas(nombre)')
    .order('nombre_completo')
  return { data, error }
}

export async function updateUsuario(id: string, data: Record<string, any>) {
  const { data: updated, error } = await supabase
    .from('usuarios_perfil')
    .update(data)
    .eq('id', id)
    .select()
    .single()
  return { data: updated, error }
}

export async function getSystemStats() {
  const [contratos, faenas, activos, ots, productos, usuarios] = await Promise.all([
    supabase.from('contratos').select('id', { count: 'exact', head: true }),
    supabase.from('faenas').select('id', { count: 'exact', head: true }),
    supabase.from('activos').select('id', { count: 'exact', head: true }),
    supabase.from('ordenes_trabajo').select('id', { count: 'exact', head: true }),
    supabase.from('productos').select('id', { count: 'exact', head: true }),
    supabase.from('usuarios_perfil').select('id', { count: 'exact', head: true }),
  ])

  return {
    data: {
      contratos: contratos.count ?? 0,
      faenas: faenas.count ?? 0,
      activos: activos.count ?? 0,
      ordenes_trabajo: ots.count ?? 0,
      productos: productos.count ?? 0,
      usuarios: usuarios.count ?? 0,
    },
    error: null,
  }
}
