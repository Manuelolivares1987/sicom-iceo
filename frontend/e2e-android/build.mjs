// Compila la web para la prueba de la app nativa: Supabase simulado en localhost:54321.
import { spawnSync } from 'node:child_process'
const r = spawnSync('npx', ['next', 'build'], {
  stdio: 'inherit', shell: true,
  env: { ...process.env, NEXT_PUBLIC_SUPABASE_URL: 'http://localhost:54321', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'e2e-anon' },
})
process.exit(r.status ?? 1)
