// Compila la app para las pruebas E2E con Supabase SIMULADO (Windows y Linux).
import { spawnSync } from 'node:child_process'
const r = spawnSync('npx', ['next', 'build'], {
  stdio: 'inherit', shell: true,
  env: { ...process.env, NEXT_PUBLIC_SUPABASE_URL: 'https://e2e.supabase.co', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'e2e-anon' },
})
process.exit(r.status ?? 1)
