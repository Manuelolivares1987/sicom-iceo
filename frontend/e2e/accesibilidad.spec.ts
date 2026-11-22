// Accesibilidad (WCAG 2.1 A/AA, motor axe-core — el mismo de Lighthouse) en las
// pantallas de terreno, con sesión. Falla con violaciones «critical» o
// «serious»; las menores se informan.
import { readFileSync } from 'node:fs'
import { test, expect } from './fixtures'
import { sembrarFranke } from './datos-franke'
import type { FakeSupabase } from './fake-supabase'

const AXE = readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8')
const ROMERAL = { id: '33333333-3333-4333-8333-333333333333', codigo: 'FAE-CMP-ROMERAL', nombre: 'Romeral', app_movil: '/m/romeral', panel_web: false }

const PANTALLAS: Array<{ ruta: string; preparar: (f: FakeSupabase) => void }> = [
  { ruta: '/login/', preparar: () => undefined },
  ...['', 'pauta/', 'despacho/', 'bodega/', 'bitacora/', 'entrega/', 'carga/', 'turno/', 'pendientes/'].map((p) => ({
    ruta: `/m/franke/${p}`, preparar: (f: FakeSupabase) => sembrarFranke(f),
  })),
  ...['', 'inicial/', 'recepcion/', 'trasvasije/', 'cierre/'].map((p) => ({
    ruta: `/m/romeral/${p}`, preparar: (f: FakeSupabase) => f.comoPerfil({ rol: 'operador_combustible', nombre_completo: 'Operador Romeral' }, ROMERAL),
  })),
  ...['', 'insumos/'].map((p) => ({
    ruta: `/m/taller/${p}`, preparar: (f: FakeSupabase) => f.comoPerfil({ rol: 'operador_taller', nombre_completo: 'Mecánico Taller' }, null),
  })),
  { ruta: '/m/enex/', preparar: (f) => f.comoPerfil({ rol: 'supervisor', app_terreno: '/m/enex', nombre_completo: 'Supervisor ENEX' }, null) },
  ...['', 'inspeccion/', 'epp/'].map((p) => ({
    ruta: `/m/prevencion/${p}`, preparar: (f: FakeSupabase) => f.comoPerfil({ rol: 'prevencionista', nombre_completo: 'Prevencionista' }, null),
  })),
  {
    ruta: '/m/calama/', preparar: (f) => {
      f.comoPerfil({ rol: 'tecnico_mantenimiento', nombre_completo: 'Operador Calama' }, null)
      f.tablas.calama_roles_proyecto = [{ usuario_id: f.tablas.usuarios_perfil[0].id, rol_calama: 'operador_calama', activo: true }]
    },
  },
  { ruta: '/dashboard/inventario/scanner/', preparar: (f) => f.comoPerfil({ rol: 'bodeguero', nombre_completo: 'Bodeguero' }, null) },
]

type Violacion = { id: string; impact: string; help: string; nodes: Array<{ target: string[]; html: string }> }

for (const p of PANTALLAS) {
  test(`a11y ${p.ruta}`, async ({ page, fake, conSesion }) => {
    p.preparar(fake)
    if (p.ruta !== '/login/') await conSesion()
    await page.goto(p.ruta)
    await page.waitForLoadState('networkidle').catch(() => undefined)
    await page.waitForTimeout(800)
    await page.addScriptTag({ content: AXE })
    const v = await page.evaluate(async () => {
      const r = await (window as unknown as { axe: { run: (c: unknown, o: unknown) => Promise<{ violations: unknown[] }> } })
        .axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'] } })
      return r.violations
    }) as Violacion[]
    const graves = v.filter((x) => x.impact === 'critical' || x.impact === 'serious')
    for (const x of v) {
      console.log(`[a11y] ${p.ruta} ${x.impact} ${x.id} (${x.nodes.length}) — ${x.help} :: ${x.nodes.slice(0, 2).map((n) => n.html.slice(0, 120)).join(' | ')}`)
    }
    expect(graves.map((x) => `${x.id}: ${x.help} (${x.nodes.length})`)).toEqual([])
  })
}
