// ============================================================================
// Supabase simulado para las pruebas E2E de terreno
// ----------------------------------------------------------------------------
// La app de prueba se compila con NEXT_PUBLIC_SUPABASE_URL=https://e2e.supabase.co:
// un host que no existe. Todo lo que la app le pide a «Supabase» (sesión,
// tablas, funciones, fotos) lo contesta esta clase desde memoria. Así las
// pruebas nunca tocan la base real ni usan claves de nadie.
//
// Imita lo que importa del servidor real para terreno:
//   · RPC con identificador del teléfono → el reintento no duplica (23505 /
//     «ya_registrada»), como MIG723 y los client_uuid de las colas.
//   · Se puede «perder la respuesta»: el servidor guarda pero el teléfono no
//     se entera (la falla típica de la señal en faena).
// ============================================================================
import type { BrowserContext, Route, Request } from '@playwright/test'

export const SUPABASE = 'https://e2e.supabase.co'
export const STORAGE_KEY = 'sb-e2e-auth-token'

export const FAENA_ID = '11111111-1111-4111-8111-111111111111'
export const USUARIO_ID = '22222222-2222-4222-8222-222222222222'

type Fila = Record<string, unknown>
type Rpc = (args: Record<string, unknown>, db: FakeSupabase) => unknown

export class FakeSupabase {
  tablas: Record<string, Fila[]> = {}
  rpcs: Record<string, Rpc> = {}
  /** Todo lo que la app pidió: para revisar qué subió y cuántas veces. */
  llamadas: { metodo: string; ruta: string; cuerpo: unknown }[] = []
  /** Pedidos que no tenían respuesta preparada (ayuda a completar el simulador). */
  sinManejar = new Set<string>()
  /** Nombres de RPC cuya PRÓXIMA respuesta se pierde (el servidor sí la procesa). */
  perderRespuesta = new Set<string>()
  /** Tablas donde un UPDATE «pasa» sin tocar filas (como cuando RLS no deja). */
  escrituraBloqueada = new Set<string>()
  /** Si está caído, todo responde 503 (servidor o red con problemas). */
  caido = false
  /** Modo avión: nada llega (ni lo que pide el service worker). */
  sinRed = false
  refrescoFalla = false

  constructor() {
    this.tablas.faenas = [{ id: FAENA_ID, codigo: 'FAE-FRANCKE', nombre: 'Franke', app_movil: '/m/franke/', panel_web: false }]
    this.tablas.usuarios_perfil = [{
      id: USUARIO_ID, nombre_completo: 'Supervisor de Prueba', email: 'prueba@e2e.test', rol: 'supervisor',
      activo: true, faena_id: FAENA_ID, solo_su_faena: true,
      faena: { id: FAENA_ID, codigo: 'FAE-FRANCKE', nombre: 'Franke', app_movil: '/m/franke/', panel_web: false },
    }]
  }

  /** Cambia quién es el usuario de prueba (rol, faena, app de terreno…). */
  comoPerfil(cambios: Fila, faena?: Fila | null) {
    const p = this.tablas.usuarios_perfil[0]
    Object.assign(p, cambios)
    if (faena !== undefined) {
      p.faena = faena
      p.faena_id = faena ? faena.id : null
      if (faena && !this.tablas.faenas.some((f) => f.id === faena.id)) this.tablas.faenas.push(faena)
    }
  }

  usuario() {
    return {
      id: USUARIO_ID, aud: 'authenticated', role: 'authenticated', email: 'prueba@e2e.test',
      app_metadata: { provider: 'email' }, user_metadata: {}, created_at: '2026-01-01T00:00:00Z',
    }
  }

  /** Sesión como la guarda supabase-js en localStorage. */
  sesion(opts: { vencida?: boolean } = {}) {
    const exp = Math.floor(Date.now() / 1000) + (opts.vencida ? -3600 : 3600 * 24 * 30)
    return {
      access_token: jwt({ sub: USUARIO_ID, role: 'authenticated', exp }),
      refresh_token: 'refresh-e2e', token_type: 'bearer', expires_in: 3600, expires_at: exp,
      user: this.usuario(),
    }
  }

  rpcLlamadas(nombre: string) {
    return this.llamadas.filter((l) => l.ruta === `rpc/${nombre}`)
  }

  async instalar(context: BrowserContext) {
    await context.route(`${SUPABASE}/**`, (route) => this.atender(route))
  }

  /**
   * El mismo simulador, pero como servidor HTTP de verdad (para la app nativa
   * en el emulador Android, donde no hay page.route): http://localhost:<puerto>.
   */
  servirHttp(puerto: number): Promise<import('node:http').Server> {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const http = require('node:http') as typeof import('node:http')
    const srv = http.createServer((req, res) => {
      const trozos: Buffer[] = []
      req.on('data', (c: Buffer) => trozos.push(c))
      req.on('end', () => {
        const cuerpo = Buffer.concat(trozos).toString('utf8')
        const ruta = {
          request: () => ({
            url: () => `http://localhost:${puerto}${req.url ?? '/'}`,
            method: () => req.method ?? 'GET',
            headers: () => req.headers as Record<string, string>,
            postData: () => (cuerpo.length ? cuerpo : null),
          }),
          fulfill: async (o: { status?: number; headers?: Record<string, string>; body?: string }) => {
            res.writeHead(o.status ?? 200, o.headers ?? {})
            res.end(o.body ?? '')
          },
          abort: async () => { req.socket.destroy() },
        }
        void this.atender(ruta as unknown as Route)
      })
    })
    return new Promise((ok) => srv.listen(puerto, '0.0.0.0', () => ok(srv)))
  }

  private async atender(route: Route) {
    const req = route.request()
    const url = new URL(req.url())
    const ruta = url.pathname.replace(/^\/(rest|auth|storage)\/v1\//, '')
    const cuerpo = leerCuerpo(req)
    if (req.method() !== 'OPTIONS') this.llamadas.push({ metodo: req.method(), ruta, cuerpo })
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
    const json = (status: number, body: unknown, extra: Record<string, string> = {}) =>
      route.fulfill({ status, headers: { ...cors, 'content-type': 'application/json', ...extra }, body: JSON.stringify(body) })

    if (this.sinRed) { this.llamadas.pop(); return route.abort('internetdisconnected') }
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })
    if (this.caido) return json(503, { message: 'Service Unavailable' })

    // ── Auth ────────────────────────────────────────────────────────────
    if (url.pathname.startsWith('/auth/v1/')) {
      if (ruta === 'user') return json(200, this.usuario())
      if (ruta === 'token') {
        if (this.refrescoFalla) return json(400, { error: 'invalid_grant', error_description: 'Refresh Token Not Found' })
        return json(200, this.sesion())
      }
      if (ruta === 'logout') return route.fulfill({ status: 204, headers: cors })
      this.sinManejar.add(`AUTH ${ruta}`)
      return json(200, {})
    }

    // ── Storage (fotos y firmas) ───────────────────────────────────────
    if (url.pathname.startsWith('/storage/v1/')) {
      const path = ruta.replace(/^object\/(public\/)?/, '')
      const ya = this.tablas.__storage?.some((f) => f.path === path)
      if (req.method() === 'POST' && ya) return json(400, { statusCode: '409', error: 'Duplicate', message: 'The resource already exists' })
      if (req.method() === 'POST') (this.tablas.__storage ??= []).push({ path })
      return json(200, { Key: path, Id: path })
    }

    // ── RPC ─────────────────────────────────────────────────────────────
    if (ruta.startsWith('rpc/')) {
      const nombre = ruta.slice(4)
      const h = this.rpcs[nombre]
      if (!h) { this.sinManejar.add(`RPC ${nombre}`); return json(200, null) }
      let res: unknown
      try { res = h((cuerpo ?? {}) as Record<string, unknown>, this) } catch (e) {
        const err = e as { code?: string; message?: string; status?: number }
        return json(err.status ?? 400, { code: err.code ?? 'P0001', message: err.message ?? String(e), details: null, hint: null })
      }
      if (this.perderRespuesta.delete(nombre)) return route.abort('connectionreset')
      return json(200, res ?? null)
    }

    // ── Tablas / vistas (PostgREST) ────────────────────────────────────
    const tabla = ruta.split('/')[0]
    const filas = this.tablas[tabla]
    if (req.method() === 'GET' || req.method() === 'HEAD') {
      if (!filas) this.sinManejar.add(`GET ${tabla}`)
      const res = filtrar(filas ?? [], url.searchParams)
      const unObjeto = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
      if (unObjeto) {
        if (!res.length) return json(406, { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned', details: 'The result contains 0 rows', hint: null })
        return json(200, res[0])
      }
      return json(200, res, { 'content-range': `0-${Math.max(res.length - 1, 0)}/${res.length}` })
    }
    // PATCH como PostgREST: cambia las filas que calzan y devuelve SOLO esas.
    // Con la tabla en «escrituraBloqueada» imita a RLS: ningún error, cero filas.
    if (req.method() === 'PATCH' && filas) {
      if (this.escrituraBloqueada.has(tabla)) return json(200, [])
      const tocadas = filtrar(filas, url.searchParams)
      for (const f of tocadas) Object.assign(f, (cuerpo ?? {}) as object)
      return json(200, tocadas)
    }
    // Escrituras directas a tablas: se guardan tal cual.
    const nuevas = (Array.isArray(cuerpo) ? cuerpo : [cuerpo]).filter(Boolean) as Fila[]
    if (req.method() === 'POST') (this.tablas[tabla] ??= []).push(...nuevas)
    return json(201, nuevas)
  }
}

function leerCuerpo(req: Request): unknown {
  const t = req.postData()
  if (!t) return null
  try { return JSON.parse(t) } catch { return t }
}

/** Filtros simples de PostgREST: col=eq.valor (los demás se ignoran). */
function filtrar(filas: Fila[], q: URLSearchParams): Fila[] {
  let r = filas
  q.forEach((v, k) => {
    if (['select', 'order', 'limit', 'offset'].includes(k)) return
    const m = /^eq\.(.*)$/.exec(v)
    if (m) r = r.filter((f) => String(f[k]) === decodeURIComponent(m[1]))
    const il = /^ilike\.(.*)$/.exec(v)
    if (il) {
      const patron = decodeURIComponent(il[1]).split('%').map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*')
      const re = new RegExp('^' + patron + '$', 'i')
      r = r.filter((f) => re.test(String(f[k] ?? '')))
    }
  })
  const lim = Number(q.get('limit'))
  return lim > 0 ? r.slice(0, lim) : r
}

function jwt(payload: Record<string, unknown>) {
  const b = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url')
  return `${b({ alg: 'HS256', typ: 'JWT' })}.${b(payload)}.firma-e2e`
}
