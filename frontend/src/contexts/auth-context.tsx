'use client'

import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  useCallback,
  type ReactNode,
} from 'react'
import { useQueryClient } from '@tanstack/react-query'
import type { User } from '@supabase/supabase-js'
import {
  supabase, leerSesionPersistida, guardarIdentidadEquipo, leerIdentidadEquipo, borrarIdentidadEquipo,
} from '@/lib/supabase'
import { EVENTO_CONECTIVIDAD } from '@/lib/conectividad'
import type { UsuarioPerfil } from '@/types/database'

/** Lo que se espera a que la red valide la sesión antes de arrancar con la
 *  guardada en el equipo. En terreno la señal es mala; más que esto es dejar al
 *  operador mirando una pantalla en blanco. */
const ARRANQUE_TIMEOUT_MS = 6000

/** Rol Calama guardado en el teléfono (para el lanzador /m/ sin red). */
export const ROL_CALAMA_KEY = 'sicom-rol-calama'

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
  /** [20-11-2026] La sesión del servidor se perdió (mala señal, token rechazado)
   *  pero el teléfono sigue siendo de esta persona: se trabaja con lo guardado y
   *  las colas esperan. Volver a entrar con señal la restablece. */
  sesionPerdida: boolean
  /** [19-11-2026] Estado del perfil del usuario conectado. 'cargando' mientras
   *  no llega; 'error' si la consulta falló y no hay copia en el equipo (se
   *  reintenta solo); 'sin_perfil' si la cuenta no tiene fila en usuarios_perfil. */
  perfilEstado: 'cargando' | 'listo' | 'error' | 'sin_perfil'
  reintentarPerfil: () => void
  signIn: (email: string, password: string) => Promise<void>
  /** false si el usuario decidió no salir (tenía trabajo sin enviar). */
  signOut: () => Promise<boolean>
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

/** Registros sin enviar en las bases offline que el logout borra (Calama y Taller). */
async function contarPendientesOffline(): Promise<number> {
  if (typeof window === 'undefined') return 0
  let total = 0
  try {
    const { calamaDB } = await import('@/lib/offline/calama-db')
    const db = calamaDB()
    total += await db.sync_queue.where('status').anyOf('pending', 'error').count()
  } catch { /* sin base o ilegible */ }
  try {
    const { tallerDB } = await import('@/lib/offline/taller-db')
    const db = tallerDB()
    total += await db.pending.count()
    total += await db.pendingPlan.count()
  } catch { /* sin base o ilegible */ }
  // [20-11-2026] Franke y ENEX también: antes «Cerrar sesión» no avisaba de lo
  // que quedaba sin subir en la faena y el siguiente usuario lo heredaba.
  const contadores: Array<() => Promise<number>> = [
    async () => (await import('@/lib/offline/faena-pauta-offline')).pendientesCount(),
    async () => (await import('@/lib/offline/combustible-faena-offline')).pendientesCount(),
    async () => (await import('@/lib/offline/bodega-faena-offline')).pendientesCount(),
    async () => (await import('@/lib/offline/faena-bitacora-offline')).pendientesCount(),
    async () => (await import('@/lib/offline/faena-entrega-offline')).pendientesCount(),
    async () => (await import('@/lib/offline/enex-offline')).getEnexPendingCount(),
  ]
  for (const c of contadores) { try { total += await c() } catch { /* sin base */ } }
  return total
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [perfil, setPerfil] = useState<UsuarioPerfil | null>(null)
  const [rolCalama, setRolCalama] = useState<RolCalama | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [sesionSinValidar, setSesionSinValidar] = useState(false)
  const [sesionPerdida, setSesionPerdida] = useState(false)
  // true mientras corre «Cerrar sesión»: ese SIGNED_OUT sí es una salida real.
  const cerrando = useRef(false)
  const [perfilEstado, setPerfilEstado] = useState<'cargando' | 'listo' | 'error' | 'sin_perfil'>('cargando')

  // Cuando cambia QUIÉN está conectado, lo consultado antes no vale. Las
  // consultas de React Query viven 5 minutos como "frescas" y sobreviven al
  // cierre de sesión y al login siguiente (todo ocurre sin recargar la página):
  // el supervisor de Calama entraba, abría «Nuevo registro» y la lista de
  // faenas era la que se había pedido sin sesión —vacía— hasta apretar F5.
  // Lo mismo aplica al arranque: la página dispara sus consultas antes de que
  // la sesión guardada termine de cargar. Al aparecer el usuario se reinician
  // y se vuelven a pedir con su token; al salir se borran, para que el
  // siguiente que entre en el mismo equipo no vea nada del anterior.
  const queryClient = useQueryClient()
  const usuarioAnterior = useRef<string | null | undefined>(undefined)
  useEffect(() => {
    const actual = user?.id ?? null
    if (usuarioAnterior.current !== undefined && usuarioAnterior.current !== actual) {
      if (actual) void queryClient.resetQueries()
      else queryClient.clear()
    }
    usuarioAnterior.current = actual
  }, [user?.id, queryClient])

  const fetchPerfil = useCallback(async (userId: string) => {
    // Primero lo último conocido: en terreno el perfil (rol, nombre) tiene que
    // estar disponible de inmediato aunque la consulta no llegue nunca.
    const cacheado = leerPerfilCache(userId)
    if (cacheado) { setPerfil(cacheado); setPerfilEstado('listo') }
    else setPerfilEstado('cargando')

    // Se trae la faena junto al perfil porque de ella sale la app de terreno a
    // la que aterriza la gente de faena (MIG361). Sin esto, todo operador de
    // combustible caía en /m/romeral — que era cierto mientras Romeral fuera la
    // única faena con app, y dejó de serlo con Franke.
    let data: unknown = null
    let perfilError: { message: string } | null = null
    try {
      const r = await supabase
        .from('usuarios_perfil')
        .select('*, faena:faenas!usuarios_perfil_faena_id_fkey(id, codigo, nombre, app_movil, panel_web)')
        .eq('id', userId)
        .maybeSingle()
      data = r.data
      perfilError = r.error
    } catch (e) {
      // Red cortada / límite de tiempo: mismo camino que un error de la consulta.
      perfilError = { message: e instanceof Error ? e.message : String(e) }
    }

    if (perfilError) {
      console.error('Error fetching perfil:', perfilError.message)
      // Sin conexión (o error transitorio): usar el último perfil conocido.
      // Sin copia en el equipo queda en 'error' y se reintenta (ver abajo):
      // antes quedaba en null para siempre y el panel mostraba el menú
      // general sin filtrar por faena (Yohan, Franke, 19-11-2026).
      const c = leerPerfilCache(userId)
      setPerfil(c)
      setPerfilEstado(c ? 'listo' : 'error')
    } else if (!data) {
      console.warn('No se encontró perfil para el usuario. Cree un registro en usuarios_perfil.')
      setPerfil(null)
      setPerfilEstado('sin_perfil')
    } else {
      setPerfil(data as UsuarioPerfil)
      guardarPerfilCache(data as UsuarioPerfil)
      setPerfilEstado('listo')
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
        const r = (rc?.rol_calama as RolCalama | undefined) ?? null
        setRolCalama(r)
        // El lanzador /m/ lo lee sin red para abrir /m/calama directo.
        try { localStorage.setItem(ROL_CALAMA_KEY, JSON.stringify({ id: userId, rol: r })) } catch { /* sin storage */ }
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

    // [20-11-2026] Como WhatsApp: si el teléfono ya conoce a la persona (sesión
    // guardada o identidad del equipo) y su perfil, la app se abre YA, sin
    // esperar a la red. La validación con el servidor sigue por detrás.
    {
      const local = leerSesionPersistida()
      const u0 = local?.user ?? leerIdentidadEquipo()
      const p0 = u0 ? leerPerfilCache(u0.id) : null
      if (u0 && p0) {
        setUser(u0); setPerfil(p0); setPerfilEstado('listo')
        setSesionSinValidar(true); setSesionPerdida(!local)
        setLoading(false)
      }
    }

    const arrancar = (u: User | null, desdeCache: boolean) => {
      setUser(u)
      if (resuelto) return
      resuelto = true
      setSesionSinValidar(desdeCache)
      if (u) guardarIdentidadEquipo(u)
      if (u && !desdeCache) setSesionPerdida(false)
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
      if (local) { arrancar(local.user, true); return }
      // Sin sesión guardada pero con identidad del equipo: la sesión se perdió,
      // no la persona. Se sigue con lo guardado y se pide volver a entrar.
      const respaldo = leerIdentidadEquipo()
      if (respaldo) setSesionPerdida(true)
      arrancar(respaldo, !!respaldo)
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

      // [20-11-2026] Un SIGNED_OUT que nadie pidió (auth-js borró la sesión porque
      // el servidor rechazó la renovación: respuesta perdida, portal cautivo…)
      // NO saca a la persona de la app: sigue trabajando con lo guardado.
      if (!currentUser && !cerrando.current) {
        const respaldo = leerIdentidadEquipo()
        if (respaldo) { setUser(respaldo); setSesionSinValidar(true); setSesionPerdida(true); return }
      }

      setUser(currentUser)
      if (currentUser) {
        setSesionSinValidar(false)
        setSesionPerdida(false)
        guardarIdentidadEquipo(currentUser)
        fetchPerfil(currentUser.id)
      } else {
        setSesionSinValidar(false)
        setPerfil(null)
        setRolCalama(null)
        setPerfilEstado('cargando')
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

  // [19-11-2026] Perfil que no llegó: reintentar solo (3 s, 6 s, 12 s… hasta
  // 30 s) y apenas vuelva la conexión real. Sin esto, una sola consulta
  // perdida con mala señal dejaba la sesión sin perfil hasta cerrar y volver.
  const [intentoPerfil, setIntentoPerfil] = useState(0)
  const reintentarPerfil = useCallback(() => {
    if (user?.id) void fetchPerfil(user.id)
  }, [user?.id, fetchPerfil])
  useEffect(() => {
    if (!user?.id || perfilEstado !== 'error') return
    const espera = Math.min(3000 * 2 ** intentoPerfil, 30_000)
    const t = setTimeout(() => {
      setIntentoPerfil((n) => n + 1)
      void fetchPerfil(user.id)
    }, espera)
    const alVolver = (e: Event) => {
      if ((e as CustomEvent<{ enLinea: boolean }>).detail?.enLinea) void fetchPerfil(user.id)
    }
    window.addEventListener(EVENTO_CONECTIVIDAD, alVolver)
    return () => { clearTimeout(t); window.removeEventListener(EVENTO_CONECTIVIDAD, alVolver) }
  }, [user?.id, perfilEstado, intentoPerfil, fetchPerfil])
  useEffect(() => { if (perfilEstado === 'listo') setIntentoPerfil(0) }, [perfilEstado])

  const signIn = useCallback(async (email: string, password: string) => {
    setError(null)
    const { error: authError } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (authError) {
      // [20-11-2026] Sin red no es «credenciales inválidas»: decirlo así hacía
      // que la gente cambiara la clave o creyera que la habían bloqueado.
      const sinRed = authError.name === 'AuthRetryableFetchError' || !authError.status || authError.status >= 500
      setError(sinRed
        ? 'No hay conexión con el servidor. Busque señal o wifi e intente de nuevo; su clave está bien.'
        : 'Credenciales inválidas. Verifique su correo y contraseña.')
      throw authError
    }
  }, [])

  // [19-11-2026] Cerrar sesión = SOLO este teléfono (scope 'local').
  //  - Antes era 'global': salir en un equipo mataba la sesión en todos (el
  //    supervisor que cerraba en el PC dejaba al mismo usuario fuera en el
  //    teléfono de faena), y cada «Cerrar sesión» de alguien pegado en la
  //    ruedita lo dejaba peor.
  //  - Sin señal tampoco falla: auth-js borra la sesión local antes de avisar
  //    al servidor, y ese aviso no puede frenar la salida (se corta a los 4 s).
  //  - Si hay trabajo sin enviar en las bases offline, se pregunta antes de
  //    borrarlo: perder una jornada entera por un toque es peor que preguntar.
  const signOut = useCallback(async () => {
    setError(null)

    const pendientes = await contarPendientesOffline()
    if (pendientes > 0 && typeof window !== 'undefined') {
      const seguir = window.confirm(
        `Hay ${pendientes} registro(s) guardados sin señal que todavía no se envían.\n\n` +
        'Si cierra sesión ahora se pierden. Conéctese a la red y espere a que se envíen.\n\n' +
        '¿Cerrar sesión igual?',
      )
      if (!seguir) return false
    }

    cerrando.current = true
    borrarIdentidadEquipo()
    try {
      await Promise.race([
        supabase.auth.signOut({ scope: 'local' }),
        new Promise((r) => setTimeout(r, 4000)),
      ])
    } catch (e) {
      // La sesión local ya se borró; lo que falló es avisar al servidor.
      console.warn('[auth] signOut: no se pudo avisar al servidor', e)
    }
    // Por si el aviso quedó colgado antes de borrar: nunca dejar sesión guardada.
    try {
      for (let i = localStorage.length - 1; i >= 0; i--) {
        const k = localStorage.key(i)
        if (k && k.startsWith('sb-') && k.includes('-auth-token')) localStorage.removeItem(k)
      }
    } catch { /* noop */ }

    setUser(null)
    setPerfil(null)
    setRolCalama(null)
    setSesionSinValidar(false)
    setSesionPerdida(false)
    setPerfilEstado('cargando')
    cerrando.current = false

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
    return true
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
        sesionPerdida,
        perfilEstado,
        reintentarPerfil,
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
