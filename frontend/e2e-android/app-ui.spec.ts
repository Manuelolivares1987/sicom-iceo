// ============================================================================
// La APP SICOM en Android 10 con el visor web de fábrica (WebView 74)
// ----------------------------------------------------------------------------
// Ese visor es tan antiguo que Playwright no puede conectarse a él. Esta prueba
// lo maneja como lo hace Android con sus propias pruebas (uiautomator): lee lo
// que muestra la pantalla y toca/escribe como una persona. Entra con el usuario
// de PRUEBA del Supabase simulado (no es una cuenta real).
// Corre con SICOM_ANDROID_MODO=ui (ver .github/workflows/app-android-e2e.yml).
// ============================================================================
import { execSync } from 'node:child_process'
import { test, expect } from '@playwright/test'
import { FakeSupabase } from '../e2e/fake-supabase'
import { sembrarFranke } from '../e2e/datos-franke'

const MODO_UI = process.env.SICOM_ANDROID_MODO === 'ui'
const PKG = 'cl.pilladoempresas.sicomterreno'
const PUERTO_FAKE = 54321

test.skip(!MODO_UI, 'Solo en el emulador con visor antiguo (SICOM_ANDROID_MODO=ui)')
test.setTimeout(420_000)

const adb = (cmd: string) => execSync(`adb ${cmd}`, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()
const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms))

type Nodo = { texto: string; clase: string; x: number; y: number }
function pantalla(): Nodo[] {
  try {
    adb('shell uiautomator dump /sdcard/ui.xml')
    const xml = adb('shell cat /sdcard/ui.xml')
    const out: Nodo[] = []
    for (const m of xml.matchAll(/<node [^>]*>/g)) {
      const n = m[0]
      const at = (k: string) => (n.match(new RegExp(`${k}="([^"]*)"`))?.[1] ?? '')
      const b = at('bounds').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
      if (!b) continue
      out.push({
        texto: `${at('text')} ${at('content-desc')}`.trim(), clase: at('class'),
        x: Math.round((+b[1] + +b[3]) / 2), y: Math.round((+b[2] + +b[4]) / 2),
      })
    }
    return out
  } catch { return [] }
}
const textoPantalla = () => pantalla().map((n) => n.texto).join(' | ')

async function esperarTexto(re: RegExp, ms = 90_000): Promise<string> {
  const fin = Date.now() + ms
  let ultimo = ''
  while (Date.now() < fin) {
    ultimo = textoPantalla()
    if (re.test(ultimo)) return ultimo
    await esperar(2000)
  }
  throw new Error(`No apareció ${re} en pantalla. Se veía: ${ultimo.slice(0, 600)}`)
}
const tocar = (n: Nodo) => adb(`shell input tap ${n.x} ${n.y}`)
const escribir = (t: string) => adb(`shell input text '${t.replace(/ /g, '%s')}'`)
const enPrimerPlano = () => adb('shell dumpsys activity activities').split('\n')
  .some((l) => /mResumedActivity|topResumedActivity/.test(l) && l.includes(PKG))
const erroresJs = () => adb('logcat -d -s Capacitor:E Capacitor/Console:E').split('\n')
  .filter((l) => /JavaScript Error|SyntaxError|TypeError|ReferenceError/.test(l))

let fake: FakeSupabase
let server: import('node:http').Server
test.beforeAll(async () => {
  fake = new FakeSupabase()
  sembrarFranke(fake)
  fake.rpcs.rpc_faena_comunicacion = () => ({ generado_at: new Date().toISOString(), mi_turno: 'A', ciclo: null,
    novedades: [], por_leer: [], pendientes: [], equipos: [], resumen: null })
  server = await fake.servirHttp(PUERTO_FAKE)
  adb('reverse tcp:3100 tcp:3100'); adb(`reverse tcp:${PUERTO_FAKE} tcp:${PUERTO_FAKE}`)
  adb('logcat -c')
})
test.afterAll(() => { server?.close() })

test('Android 10 con visor antiguo: entrar, y abrir SIN red desde el ícono', async () => {
  await test.step('1. Abre la app y muestra la pantalla de ingreso (sin errores de JavaScript)', async () => {
    adb(`shell am start -W -n ${PKG}/.MainActivity`)
    await esperarTexto(/Iniciar Sesi[oó]n/)
    expect(erroresJs()).toEqual([])
  })

  await test.step('2. Entra con el usuario de prueba y llega a Franke', async () => {
    const campos = pantalla().filter((n) => n.clase === 'android.widget.EditText')
    expect(campos.length).toBeGreaterThanOrEqual(2)
    tocar(campos[0]); await esperar(800); escribir('prueba@e2e.test')
    // Al campo de la clave con TAB, como el «siguiente» del teclado: tocarlo por
    // posición fallaba cuando el teclado movía la pantalla (se escribía todo en
    // el correo).
    adb('shell input keyevent 61'); await esperar(800)
    const correo = pantalla().filter((n) => n.clase === 'android.widget.EditText')[0]
    if (correo && /clave-de-prueba/.test(correo.texto)) throw new Error('La clave quedó en el campo del correo')
    escribir('clave-de-prueba')
    await esperar(500)
    console.log('[android] campos:', JSON.stringify(pantalla().filter((n) => n.clase === 'android.widget.EditText').map((n) => n.texto)))
    // Enviar como el teclado del teléfono («Ir»/Enter); si no, el botón.
    adb('shell input keyevent 66')
    await esperar(4000)
    if (!fake.llamadas.some((l) => l.ruta === 'token')) {
      adb('shell input keyevent 111')
      await esperar(800)
      const boton = pantalla().find((n) => /Iniciar Sesi[oó]n/.test(n.texto))
      expect(boton).toBeTruthy()
      tocar(boton!)
    }
    try {
      await esperarTexto(/Franke/, 120_000)
    } catch (e) {
      console.log('[android] llamadas al servidor:', JSON.stringify(fake.llamadas.map((l) => `${l.metodo} ${l.ruta}`)))
      throw e
    }
    // Dejar que el service worker guarde la app y la precarga baje los datos.
    await expect.poll(() => fake.rpcLlamadas('rpc_faena_comunicacion').length, { timeout: 120_000 }).toBeGreaterThan(0)
    await esperar(45_000)
  })

  await test.step('3. SIN red: se cierra la app y se abre desde el ícono → abre Franke', async () => {
    adb('reverse --remove-all')
    adb('shell svc wifi disable'); adb('shell svc data disable')
    fake.sinRed = true
    await esperar(3000)
    adb(`shell am force-stop ${PKG}`)
    await esperar(1500)
    adb(`shell am start -W -n ${PKG}/.MainActivity`)
    const t = await esperarTexto(/Franke/, 90_000)
    expect(t).not.toMatch(/No se pudo cargar esta pantalla|La app no pudo abrir|Algo falló/)
    expect(erroresJs()).toEqual([])
  })

  await test.step('4. Botón atrás en el inicio: la app queda en segundo plano (no se cierra)', async () => {
    for (let i = 0; i < 6 && enPrimerPlano(); i++) { adb('shell input keyevent 4'); await esperar(1500) }
    expect(enPrimerPlano()).toBe(false)
    expect(adb(`shell pidof ${PKG}`)).not.toBe('')
  })
})
