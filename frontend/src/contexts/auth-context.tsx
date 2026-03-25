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

interface AuthContextValue {
  user: User | null
  perfil: UsuarioPerfil | null
  loading: boolean
  error: string | null
  isAuthenticated: boolean
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [perfil, setPerfil] = useState<UsuarioPerfil | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchPerfil = useCallback(async (userId: string) => {
    const { data, error: perfilError } = await supabase
      .from('usuarios_perfil')
      .select('*')
      .eq('id', userId)
      .single()

    if (perfilError) {
      console.error('Error fetching perfil:', perfilError.message)
      setPerfil(null)
      return
    }

    setPerfil(data as UsuarioPerfil)
  }, [])

  useEffect(() => {
    // Check existing session on mount
    supabase.auth.getSession().then(({ data: { session } }) => {
      const currentUser = session?.user ?? null
      setUser(currentUser)

      if (currentUser) {
        fetchPerfil(currentUser.id).finally(() => setLoading(false))
      } else {
        setLoading(false)
      }
    })

    // Subscribe to auth state changes
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      const currentUser = session?.user ?? null
      setUser(currentUser)

      if (currentUser) {
        fetchPerfil(currentUser.id)
      } else {
        setPerfil(null)
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
  }, [])

  return (
    <AuthContext.Provider
      value={{
        user,
        perfil,
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
