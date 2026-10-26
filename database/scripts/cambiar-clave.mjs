#!/usr/bin/env node
// Cambia la contraseña de una cuenta y comprueba con un login real que entra.
//
//   node database/scripts/cambiar-clave.mjs <correo> <clave-nueva>
//
// Existe porque la app no tiene pantalla de cambio de clave y la edge function
// admin-crear-usuario no está desplegada (ver reference_crear_usuario_sql).
// De paso arregla lo que deja una cuenta sin poder entrar aunque la clave esté
// bien: columnas de token en NULL (GoTrue las lee como texto no nulo), falta
// de la fila en auth.identities, correo sin confirmar o cuenta bloqueada.
//
// La clave no se imprime ni se guarda en ningún archivo.

import pg from 'pg'
import dotenv from 'dotenv'
import { readFileSync } from 'fs'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const [correo, clave] = process.argv.slice(2)
if (!correo || !clave) {
  console.error('Uso: node database/scripts/cambiar-clave.mjs <correo> <clave-nueva>')
  process.exit(2)
}
if (clave.length < 8) {
  console.error('La clave debe tener al menos 8 caracteres.')
  process.exit(2)
}

const e = process.env
const db = new pg.Client(e.SUPABASE_DB_URL
  ? { connectionString: e.SUPABASE_DB_URL.trim(), ssl: { rejectUnauthorized: false } }
  : { host: e.SUPABASE_DB_HOST, port: Number(e.SUPABASE_DB_PORT || 5432), user: e.SUPABASE_DB_USER,
      password: e.SUPABASE_DB_PASSWORD, database: e.SUPABASE_DB_NAME || 'postgres', ssl: { rejectUnauthorized: false } })

await db.connect()
try {
  await db.query('BEGIN')
  const u = await db.query(
    `UPDATE auth.users SET
        encrypted_password = extensions.crypt($2, extensions.gen_salt('bf')),
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        banned_until = NULL,
        confirmation_token = COALESCE(confirmation_token, ''),
        recovery_token = COALESCE(recovery_token, ''),
        email_change = COALESCE(email_change, ''),
        email_change_token_new = COALESCE(email_change_token_new, ''),
        email_change_token_current = COALESCE(email_change_token_current, ''),
        phone_change = COALESCE(phone_change, ''),
        phone_change_token = COALESCE(phone_change_token, ''),
        reauthentication_token = COALESCE(reauthentication_token, ''),
        updated_at = now()
      WHERE lower(email) = lower($1) AND deleted_at IS NULL
      RETURNING id, email`, [correo, clave])
  if (u.rowCount !== 1) throw new Error(`No existe una cuenta activa con el correo ${correo}`)
  const { id, email } = u.rows[0]
  await db.query(
    `INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
     SELECT $1::text, $1::uuid,
            jsonb_build_object('sub', $1::text, 'email', $2::text, 'email_verified', true, 'phone_verified', false),
            'email', now(), now(), now()
      WHERE NOT EXISTS (SELECT 1 FROM auth.identities WHERE user_id = $1::uuid AND provider = 'email')`,
    [id, email])
  await db.query('COMMIT')
  console.log(`Clave cambiada para ${email}.`)
} catch (err) {
  await db.query('ROLLBACK').catch(() => {})
  console.error('No se cambió nada:', err.message)
  process.exit(1)
} finally {
  await db.end()
}

// Prueba de verdad: el mismo login que hace la app.
const envFront = readFileSync(resolve(__dirname, '../../frontend/.env.local'), 'utf8')
const leer = (k) => envFront.match(new RegExp(`^${k}=(.*)$`, 'm'))?.[1]?.trim().replace(/^['"]|['"]$/g, '')
const url = leer('NEXT_PUBLIC_SUPABASE_URL')
const anon = leer('NEXT_PUBLIC_SUPABASE_ANON_KEY')
const r = await fetch(`${url}/auth/v1/token?grant_type=password`, {
  method: 'POST',
  headers: { apikey: anon, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: correo, password: clave }),
})
if (r.ok) {
  console.log('Login verificado: la cuenta entra con la clave nueva.')
} else {
  console.error(`El login de prueba falló (${r.status}): ${(await r.text()).slice(0, 200)}`)
  process.exit(1)
}
