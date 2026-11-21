// Las OTRAS apps de terreno (Romeral, Taller, ENEX, Prevención, Calama,
// vendedor Franke): cada una con su tipo de trabajador, abierta desde el ícono
// y en modo avión en todas sus pantallas.
import { test, expect, prepararSinSenal } from './fixtures'
import type { FakeSupabase } from './fake-supabase'

const ROMERAL = { id: '33333333-3333-4333-8333-333333333333', codigo: 'FAE-CMP-ROMERAL', nombre: 'Romeral', app_movil: '/m/romeral', panel_web: false }

type App = {
  nombre: string
  raiz: string
  pantallas: string[]
  /** El lanzador /m/ la abre directo (sin pasar por el panel). Si no, se entra una vez con señal. */
  desdeIcono: boolean
  preparar: (fake: FakeSupabase) => void
}

const APPS: App[] = [
  {
    nombre: 'Romeral (operador de combustible)', raiz: '/m/romeral/', desdeIcono: true,
    pantallas: ['', 'inicial/', 'recepcion/', 'trasvasije/', 'cierre/'],
    preparar: (f) => f.comoPerfil({ rol: 'operador_combustible', nombre_completo: 'Operador Romeral' }, ROMERAL),
  },
  {
    nombre: 'Taller (operador de taller)', raiz: '/m/taller/', desdeIcono: true,
    pantallas: ['', 'insumos/', 'copiloto/'],
    preparar: (f) => f.comoPerfil({ rol: 'operador_taller', nombre_completo: 'Mecánico Taller' }, null),
  },
  {
    nombre: 'ENEX (supervisor)', raiz: '/m/enex/', desdeIcono: true,
    pantallas: ['', 'servicio/'],
    preparar: (f) => f.comoPerfil({ rol: 'supervisor', app_terreno: '/m/enex', nombre_completo: 'Supervisor ENEX' }, null),
  },
  {
    nombre: 'Prevención (prevencionista)', raiz: '/m/prevencion/', desdeIcono: false,
    pantallas: ['', 'control/', 'epp/', 'inspeccion/', 'inspeccion/editar/'],
    preparar: (f) => f.comoPerfil({ rol: 'prevencionista', nombre_completo: 'Prevencionista' }, null),
  },
  {
    nombre: 'Calama (operador OOCC)', raiz: '/m/calama/', desdeIcono: false,
    pantallas: [''],
    preparar: (f) => {
      f.comoPerfil({ rol: 'tecnico_mantenimiento', nombre_completo: 'Operador Calama' }, null)
      f.tablas.calama_roles_proyecto = [{ usuario_id: f.tablas.usuarios_perfil[0].id, rol_calama: 'operador_calama', activo: true }]
    },
  },
  {
    nombre: 'Vendedor Franke', raiz: '/m/franke-venta/', desdeIcono: false,
    pantallas: [''],
    preparar: (f) => f.comoPerfil({ rol: 'operador_combustible', nombre_completo: 'Vendedor Franke' }),
  },
]

for (const app of APPS) {
  test.describe(app.nombre, () => {
    test.beforeEach(async ({ fake, conSesion }) => {
      app.preparar(fake)
      await conSesion()
    })

    test('abre desde el ícono y todas sus pantallas funcionan en modo avión', async ({ page, modoAvion, erroresJs }) => {
      if (app.desdeIcono) {
        await prepararSinSenal(page, app.raiz)
      } else {
        // Se entra una vez con señal (desde el panel o un link); el ícono la recuerda.
        await page.goto(app.raiz)
        await page.waitForURL(new RegExp(`${app.raiz}?$`))
        await prepararSinSenalDesde(page, app.raiz)
      }
      await modoAvion(true)
      await page.goto('/m/')
      await page.waitForURL(new RegExp(`${app.raiz}?$`))
      for (const p of app.pantallas) {
        await test.step(`${app.raiz}${p}`, async () => {
          await page.goto(`${app.raiz}${p}`)
          await expect(page.locator('body')).not.toBeEmpty()
          await expect(page.getByText(/No se pudo cargar esta pantalla/)).toHaveCount(0)
          await expect(page.getByText(/La app no pudo abrir|Application error|Algo salió mal|Algo falló/i)).toHaveCount(0)
          await expect(page).not.toHaveURL(/\/login\//)
        })
      }
      expect(erroresJs).toEqual([])
    })
  })
}

/** Igual que prepararSinSenal pero sin pasar por el lanzador (ya está en la app). */
async function prepararSinSenalDesde(page: import('@playwright/test').Page, raiz: string) {
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  await page.reload()
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true)
  await expect.poll(() => page.evaluate(async (a) => !!(await caches.match(a)), raiz), { timeout: 30_000 }).toBe(true)
}
