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

// Crea un usuario de la plataforma (auth + perfil) via edge function con
// service role. Solo funciona para el rol administrador (validado server-side).
export type CrearUsuarioParams = {
  email: string
  password: string
  nombre_completo: string
  rol: string
  cargo?: string | null
  tecnico_id?: string | null   // vincular a taller_tecnicos (operador de taller)
}

export async function crearUsuarioAdmin(params: CrearUsuarioParams): Promise<{
  user_id: string
  tecnico_vinculado?: string | null
  warning?: string
}> {
  const { data, error } = await supabase.functions.invoke('admin-crear-usuario', {
    body: params,
  })
  if (error) {
    // FunctionsHttpError: el mensaje real viene en el body de la respuesta.
    const ctx = (error as { context?: Response }).context
    if (ctx && typeof ctx.json === 'function') {
      const body = await ctx.json().catch(() => null)
      throw new Error(body?.error ?? error.message ?? 'Error al crear usuario')
    }
    throw new Error(error.message ?? 'Error al crear usuario')
  }
  return data as { user_id: string; tecnico_vinculado?: string | null; warning?: string }
}

// Técnicos de taller sin cuenta vinculada (para el modal de crear usuario).
export async function getTecnicosSinCuenta() {
  const { data, error } = await supabase
    .from('taller_tecnicos')
    .select('id, nombre, especialidad, operacion')
    .is('usuario_perfil_id', null)
    .eq('activo', true)
    .order('nombre')
  if (error) throw error
  return data ?? []
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
