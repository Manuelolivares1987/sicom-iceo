'use client'

import {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  type ReactNode,
} from 'react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import type { UsuarioPerfil } from '@/types/database'

export type RolCalama =
  | 'jefe_sucursal'
  | 'planificador_calama'
  | 'supervisor_calama'
  | 'operador_calama'
  | 'auditor_calama'

interface AuthContextValue {
  user: User | null
  perfil: UsuarioPerfil | null
  rolCalama: RolCalama | null  // rol especifico del modulo Calama (calama_roles_proyecto)
  loading: boolean
  error: string | null
  isAuthenticated: boolean
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

// Ultimo perfil conocido por usuario: permite recuperar rol/nombre sin conexión
// (apps offline-first /m/taller y /m/calama recargadas sin señal).
const PERFIL_CACHE_KEY = 'sicom-perfil-cache'

function leerPerfilCache(userId: string): UsuarioPerfil | null {
  try {
    const raw = localStorage.getItem(PERFIL_CACHE_KEY)
    if (!raw) return null
    const p = JSON.parse(raw) as UsuarioPerfil
    return p?.id === userId ? p : null
  } catch { return null }
}

function guardarPerfilCache(p: UsuarioPerfil): void {
  try { localStorage.setItem(PERFIL_CACHE_KEY, JSON.stringify(p)) } catch { /* noop */ }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [perfil, setPerfil] = useState<UsuarioPerfil | null>(null)
  const [rolCalama, setRolCalama] = useState<RolCalama | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchPerfil = useCallback(async (userId: string) => {
    const { data, error: perfilError } = await supabase
      .from('usuarios_perfil')
      .select('*')
      .eq('id', userId)
      .maybeSingle()

    if (perfilError) {
      console.error('Error fetching perfil:', perfilError.message)
      // Sin conexión (o error transitorio): usar el último perfil conocido.
      setPerfil(leerPerfilCache(userId))
    } else if (!data) {
      console.warn('No se encontró perfil para el usuario. Cree un registro en usuarios_perfil.')
      setPerfil(null)
    } else {
      setPerfil(data as UsuarioPerfil)
      guardarPerfilCache(data as UsuarioPerfil)
    }

    // Cargar rol Calama desde calama_roles_proyecto (puede no existir tabla en algunos entornos).
    try {
      const { data: rc, error: rcErr } = await supabase
        .from('calama_roles_proyecto')
        .select('rol_calama')
        .eq('usuario_id', userId)
        .eq('activo', true)
        .limit(1)
        .maybeSingle()

      if (rcErr) {
        // 42P01 = tabla no existe, lo silenciamos. Otros errores los logueamos.
        if (rcErr.code !== '42P01') console.warn('rol_calama fetch warning:', rcErr.message)
        setRolCalama(null)
      } else {
        setRolCalama((rc?.rol_calama as RolCalama | undefined) ?? null)
      }
    } catch (e) {
      console.warn('rol_calama lookup failed', e)
      setRolCalama(null)
    }
  }, [])

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      const currentUser = session?.user ?? null
      setUser(currentUser)

      if (currentUser) {
        fetchPerfil(currentUser.id).finally(() => setLoading(false))
      } else {
        setLoading(false)
      }
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      const currentUser = session?.user ?? null
      setUser(currentUser)

      if (currentUser) {
        fetchPerfil(currentUser.id)
      } else {
        setPerfil(null)
        setRolCalama(null)
      }
    })

    return () => {
      subscription.unsubscribe()
    }
  }, [fetchPerfil])

  const signIn = useCallback(async (email: string, password: string) => {
    setError(null)
    const { error: authError } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (authError) {
      setError('Credenciales inválidas. Verifique su correo y contraseña.')
      throw authError
    }
  }, [])

  const signOut = useCallback(async () => {
    setError(null)
    const { error: authError } = await supabase.auth.signOut()

    if (authError) {
      setError('Error al cerrar sesión.')
      throw authError
    }

    setUser(null)
    setPerfil(null)
    setRolCalama(null)

    // Limpia BD offline de Calama y Taller + perfil cacheado: nunca dejar
    // datos del operador en un dispositivo despues del logout.
    try { localStorage.removeItem(PERFIL_CACHE_KEY) } catch { /* noop */ }
    try {
      const { clearCalamaDB } = await import('@/lib/offline/calama-db')
      await clearCalamaDB()
    } catch { /* noop */ }
    try {
      const { clearTallerDB } = await import('@/lib/offline/taller-db')
      await clearTallerDB()
    } catch { /* noop */ }
  }, [])

  return (
    <AuthContext.Provider
      value={{
        user,
        perfil,
        rolCalama,
        loading,
        error,
        isAuthenticated: !!user,
        signIn,
        signOut,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
