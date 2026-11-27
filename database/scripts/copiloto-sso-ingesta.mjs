// ============================================================================
// Ingesta del corpus del Copiloto Prevención Centinela (26-11-2026)
// ----------------------------------------------------------------------------
// Lee la base de conocimiento depurada (Markdown) del Campus Centinela y la
// carga en el proyecto copiloto-corpus (tablas sso_*), dividida por sección.
//
//   node copiloto-sso-ingesta.mjs --schema            # crea/actualiza tablas
//   node copiloto-sso-ingesta.mjs --dry-run           # solo muestra los cortes
//   node copiloto-sso-ingesta.mjs                     # carga (idempotente por sha256)
//   node copiloto-sso-ingesta.mjs --dir "<carpeta>"   # otra carpeta
//
// Conexión: database/.env.copiloto.local (COPILOTO_DB_URL).
// ============================================================================

import fs from 'fs'
import path from 'path'
import crypto from 'crypto'
import pg from 'pg'
import { fileURLToPath } from 'url'

const args = process.argv.slice(2)
const flag = (n) => args.includes(n)
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d }

const DIR = opt('--dir', path.join(process.env.USERPROFILE ?? '', 'Downloads', 'Campus Centinela', 'Base_Conocimiento_Agente'))
const MAX = 1800   // caracteres por fragmento (≈ 450 tokens)

// Título y si las cifras vienen de OCR (RECSS y Directriz estaban escaneados).
const META = {
  '01': { titulo: 'Núcleo de exigencias Centinela a EECC (resumen)', escaneado: false },
  '02': { titulo: 'RECSS — Reglamento Especial para Empresas Contratistas en SSO (AMSA v3, 2022)', escaneado: true },
  '03': { titulo: 'Estrategia de Control (EDC) — Trabajos en Altura (17-03-2021)', escaneado: false },
  '04': { titulo: 'Estrategia de Control (EDC) — Interacción con Energía Eléctrica (08-03-2021)', escaneado: false },
  '05': { titulo: 'Lecciones Aprendidas y Boletines (AMSA / Centinela)', escaneado: false },
  '06': { titulo: 'Directriz de Administración de Contratos de Servicios', escaneado: true },
  '07': { titulo: 'Campus Centinela: plataforma, salud y otros', escaneado: false },
  '08': { titulo: 'Manual de usuario SOFI', escaneado: true },
  '09': { titulo: 'Qué se exige al subir a faena y qué se revisa en la tarea', escaneado: false },
  '10': { titulo: 'Cursos que Centinela asigna al equipo de Pillado (Calama) y su estado al 26-11-2026', escaneado: false },
  '11': { titulo: 'EDC adicionales: Fatiga y Somnolencia, Energía Hidráulica, Energía Neumática, Partes Móviles, Soluciones Ácidas y Sustancias Peligrosas, Elementos Combustibles, Espacios Confinados y Libro de Vehículos Livianos', escaneado: false },
  '12': { titulo: 'Cursos Centinela: ART 360, ART Planificado, RECSS e Introducción a las EDC', escaneado: false },
}

// Texto de la interfaz del e-learning (cursos 12): no aporta y ensucia la búsqueda.
const BASURA = /^(Paralelogramo \d+|Punto caliente.*|Multiplicar \d+|arrow ícono \d+|check ícono \d+|Haz clic.*|Desplazar hasta abajo|Debes .* antes de enviar\.|Respuesta no válida|Aceptar|Continuar|Ingresar nombre|Escribe tu nombre.*|¿Quieres continuar donde te quedaste\?|Advertencia|Mensaje de advertencia|```(text)?)$/
const ESCENA = /^(MsgScene_\w+|PromptScene|[0-9A-Za-z]{11})$/

function cortar(texto) {
  const lineas = texto.split(/\r?\n/)
  const ruta = []          // títulos vigentes por nivel
  const piezas = []
  let buf = []
  const seccionActual = () => ruta.filter(Boolean).join(' › ')
  const volcar = () => {
    const contenido = buf.join('\n').trim()
    buf = []
    if (contenido.length < 40) return
    const seccion = seccionActual()
    // Secciones largas: en párrafos, sin pasar de MAX.
    if (contenido.length <= MAX) { piezas.push({ seccion, contenido }); return }
    let actual = ''
    for (const p of contenido.split(/\n{2,}/)) {
      if ((actual + '\n\n' + p).length > MAX && actual) { piezas.push({ seccion, contenido: actual.trim() }); actual = '' }
      if (p.length > MAX) {
        for (let i = 0; i < p.length; i += MAX) piezas.push({ seccion, contenido: p.slice(i, i + MAX) })
      } else actual += (actual ? '\n\n' : '') + p
    }
    if (actual.trim()) piezas.push({ seccion, contenido: actual.trim() })
  }
  for (const l of lineas) {
    if (BASURA.test(l.trim())) continue
    const m = /^(#{1,4})\s+(.*)$/.exec(l)
    if (m && ESCENA.test(m[2].trim())) continue
    if (m) {
      volcar()
      const nivel = m[1].length
      ruta.length = nivel - 1
      ruta[nivel - 1] = m[2].replace(/\*\*/g, '').trim()
      continue
    }
    buf.push(l)
  }
  volcar()
  return piezas
}

function leerEnv() {
  const f = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '.env.copiloto.local')
  const e = fs.readFileSync(f, 'utf8')
  return Object.fromEntries(e.split(/\r?\n/).filter((l) => /^[A-Z_]+=/.test(l)).map((l) => {
    const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).trim().replace(/^"|"$/g, '')]
  }))
}

const archivos = fs.readdirSync(DIR).filter((f) => /^(0[1-9]|1[0-9])_.*\.md$/.test(f)).sort()
const docs = archivos.map((archivo) => {
  const codigo = archivo.slice(0, 2)
  const texto = fs.readFileSync(path.join(DIR, archivo), 'utf8')
  return { codigo, archivo, ...META[codigo], sha256: crypto.createHash('sha256').update(texto).digest('hex'), piezas: cortar(texto) }
})

if (flag('--dry-run')) {
  for (const d of docs) {
    console.log(`${d.codigo} ${d.titulo}: ${d.piezas.length} fragmentos (máx ${Math.max(...d.piezas.map((p) => p.contenido.length))} car.)`)
    console.log('   ej.:', d.piezas[Math.min(3, d.piezas.length - 1)]?.seccion)
  }
  process.exit(0)
}

const env = leerEnv()
const c = new pg.Client({ connectionString: env.COPILOTO_DB_URL, ssl: { rejectUnauthorized: false } })
await c.connect()
try {
  if (flag('--schema')) {
    const sql = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'copiloto', 'sso_schema.sql'), 'utf8')
    await c.query(sql)
    console.log('Esquema sso_* listo.')
    process.exit(0)
  }
  let cargados = 0, iguales = 0, fragmentos = 0
  for (const d of docs) {
    const ya = (await c.query('select id, sha256 from sso_documentos where codigo = $1', [d.codigo])).rows[0]
    if (ya?.sha256 === d.sha256) { iguales++; continue }
    await c.query('begin')
    if (ya) await c.query('delete from sso_documentos where id = $1', [ya.id])
    const id = (await c.query(
      'insert into sso_documentos (codigo, titulo, archivo, escaneado, sha256) values ($1,$2,$3,$4,$5) returning id',
      [d.codigo, d.titulo, d.archivo, d.escaneado, d.sha256])).rows[0].id
    for (let i = 0; i < d.piezas.length; i += 200) {
      const lote = d.piezas.slice(i, i + 200)
      const vals = [], params = []
      lote.forEach((p, j) => {
        params.push(id, i + j, p.seccion || null, p.contenido)
        vals.push(`($${params.length - 3},$${params.length - 2},$${params.length - 1},$${params.length})`)
      })
      await c.query(`insert into sso_chunks (documento_id, orden, seccion, contenido) values ${vals.join(',')}`, params)
    }
    await c.query('commit')
    cargados++; fragmentos += d.piezas.length
    console.log(`  ${d.codigo} ${d.titulo}: ${d.piezas.length} fragmentos`)
  }
  const tot = (await c.query('select count(distinct documento_id)::int docs, count(*)::int chunks from sso_chunks')).rows[0]
  console.log(`Cargados ${cargados} (${fragmentos} fragmentos), sin cambios ${iguales}. Corpus SSO: ${tot.docs} documentos, ${tot.chunks} fragmentos.`)
} finally {
  await c.end()
}
