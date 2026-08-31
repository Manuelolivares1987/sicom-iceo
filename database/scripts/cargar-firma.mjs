#!/usr/bin/env node
// ============================================================================
// Cargar la firma de una persona en su perfil
// ----------------------------------------------------------------------------
// POR QUÉ ESTE SCRIPT EXISTE
// Lo normal es que cada uno suba su firma desde la pantalla del certificado: la
// subida al bucket va amarrada a su propia sesión, que es lo que hace que la
// firma valga. Este script es para el caso en que hay que cargarla por fuera
// —una firma escaneada que hubo que limpiar antes, por ejemplo—.
//
// POR QUÉ GUARDA UN data: Y NO UN ARCHIVO EN STORAGE
// Subir al bucket exige una sesión de usuario y acá sólo hay acceso directo a la
// base. Así que la imagen se guarda embebida en `usuarios_perfil.firma_url`.
// Funciona igual en la pantalla y en el PDF —los dos aceptan data URI— y evita
// tener que pedirle la clave a nadie.
//
// LA IMAGEN NO SE VERSIONA
// El archivo se lee del disco y no queda en el repositorio. Una firma
// manuscrita en git es una firma manuscrita al alcance de cualquiera que tenga
// acceso al repositorio; en la base al menos está detrás de la misma puerta que
// el resto de los datos.
//
//   node database/scripts/cargar-firma.mjs "Manuel Olivares" ruta/a/firma.png
// ============================================================================

import pg from 'pg'
import { readFileSync } from 'node:fs'

const [nombre, ruta] = process.argv.slice(2)
if (!nombre || !ruta) {
  console.error('uso: node database/scripts/cargar-firma.mjs "<nombre completo>" <archivo.png>')
  process.exit(1)
}

const env = readFileSync('.env.supabase-admin.local', 'utf8')
const conn = env.match(/SUPABASE_DB_URL=(.+)/)[1].trim()

const bytes = readFileSync(ruta)
const kb = Math.round(bytes.length / 1024)
if (kb > 300) {
  console.error(`La imagen pesa ${kb} KB. Se copia dentro de CADA certificado que se emita: conviene bajarla de 150 KB.`)
  process.exit(1)
}
const ext = ruta.toLowerCase().endsWith('.png') ? 'png' : 'jpeg'
const dataUri = `data:image/${ext};base64,${bytes.toString('base64')}`

const c = new pg.Client({ connectionString: conn, ssl: { rejectUnauthorized: false } })
await c.connect()
const r = await c.query(
  `UPDATE usuarios_perfil
      SET firma_url = $2, firma_actualizada_at = NOW()
    WHERE nombre_completo = $1
    RETURNING id, nombre_completo, cargo, length(firma_url) AS largo`,
  [nombre, dataUri],
)
if (r.rowCount === 0) {
  console.error(`No hay ningún perfil llamado «${nombre}».`)
  process.exit(1)
}
for (const f of r.rows) {
  console.log(`firma cargada · ${f.nombre_completo} · ${f.cargo ?? '(sin cargo)'} · ${Math.round(f.largo / 1024)} KB en el perfil`)
}
await c.end()
