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
import { supabase, leerSesionPersistida } from '@/lib/supabase'
import type { UsuarioPerfil } from '@/types/database'

/** Lo que se espera a que la red valide la sesión antes de arrancar con la
 *  guardada en el equipo. En terreno la señal es mala; más que esto es dejar al
 *  operador mirando una pantalla en blanco. */
const ARRANQUE_TIMEOUT_MS = 6000

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
  /** Hay sesión guardada en el equipo pero no se pudo revalidar contra el
   *  servidor (típicamente, sin señal). Se trabaja con lo descargado. */
  sesionSinValidar: boolean
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
  const [sesionSinValidar, setSesionSinValidar] = useState(false)

  const fetchPerfil = useCallback(async (userId: string) => {
    // Primero lo último conocido: en terreno el perfil (rol, nombre) tiene que
    // estar disponible de inmediato aunque la consulta no llegue nunca.
    const cacheado = leerPerfilCache(userId)
    if (cacheado) setPerfil(cacheado)

    // Se trae la faena junto al perfil porque de ella sale la app de terreno a
    // la que aterriza la gente de faena (MIG361). Sin esto, todo operador de
    // combustible caía en /m/romeral — que era cierto mientras Romeral fuera la
    // única faena con app, y dejó de serlo con Franke.
    const { data, error: perfilError } = await supabase
      .from('usuarios_perfil')
      .select('*, faena:faenas(id, codigo, nombre, app_movil, panel_web)')
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
    // El arranque NO puede depender de que la red conteste. `getSession()`
    // refresca el token si venció, y sin señal esa promesa puede colgarse (o
    // rechazar): antes eso dejaba `loading` en true para siempre y la app de
    // terreno se quedaba en "Cargando…" eterno. Ahora, si no responde a tiempo,
    // se arranca con la sesión guardada en el teléfono.
    let resuelto = false
    const arrancar = (u: User | null, desdeCache: boolean) => {
      setUser(u)
      if (resuelto) return
      resuelto = true
      setSesionSinValidar(desdeCache)
      // El perfil tampoco puede frenar el arranque: si la consulta se cuelga,
      // se sigue con el perfil cacheado y ya se completará cuando responda.
      if (u) {
        Promise.race([
          fetchPerfil(u.id),
          new Promise((r) => setTimeout(r, ARRANQUE_TIMEOUT_MS)),
        ]).catch(() => undefined).finally(() => setLoading(false))
      } else {
        setLoading(false)
      }
    }

    const conCache = () => {
      const local = leerSesionPersistida()
      arrancar(local?.user ?? null, !!local)
    }

    const timer = setTimeout(() => {
      if (resuelto) return
      // eslint-disable-next-line no-console
      console.warn('[auth] la sesión no se pudo validar a tiempo; se usa la guardada en el equipo')
      conCache()
    }, ARRANQUE_TIMEOUT_MS)

    supabase.auth
      .getSession()
      .then(({ data: { session } }) => {
        clearTimeout(timer)
        if (session?.user) arrancar(session.user, false)
        else conCache()
      })
      .catch(() => {
        clearTimeout(timer)
        conCache()
      })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      const currentUser = session?.user ?? null

      // Un TOKEN_REFRESH_FAILED / INITIAL_SESSION sin sesión estando sin señal
      // NO es un cierre de sesión: la sesión guardada sigue siendo válida y el
      // operador debe poder seguir trabajando con lo descargado.
      if (!currentUser && event !== 'SIGNED_OUT') {
        const local = leerSesionPersistida()
        if (local) { setUser(local.user); setSesionSinValidar(true); return }
      }

      setUser(currentUser)
      if (currentUser) {
        setSesionSinValidar(false)
        fetchPerfil(currentUser.id)
      } else {
        setSesionSinValidar(false)
        setPerfil(null)
        setRolCalama(null)
      }
    })

    return () => {
      clearTimeout(timer)
      subscription.unsubscribe()
    }
  }, [fetchPerfil])

  // Sin conexión no se intenta renovar el token. El proyecto tiene rotación de
  // refresh token: si la renovación sale y la respuesta se pierde —lo típico con
  // señal a medias— el teléfono se queda con el token viejo, y reintentarlo
  // puede hacer que el servidor invalide la sesión entera. Estando offline el
  // reintento no aporta nada (la sesión no caduca por tiempo), así que se pausa
  // y se reanuda al recuperar señal. De paso, no gasta batería en faena.
  useEffect(() => {
    const pausar = () => { void supabase.auth.stopAutoRefresh() }
    const reanudar = () => { void supabase.auth.startAutoRefresh() }

    if (typeof navigator !== 'undefined' && !navigator.onLine) pausar()
    window.addEventListener('offline', pausar)
    window.addEventListener('online', reanudar)
    return () => {
      window.removeEventListener('offline', pausar)
      window.removeEventListener('online', reanudar)
    }
  }, [])

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
    setSesionSinValidar(false)

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
        sesionSinValidar,
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
