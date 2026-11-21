import { defineConfig, devices } from '@playwright/test'

// Pruebas E2E de la app de terreno (Franke) en un Android simulado.
// La app se compila con Supabase falso (ver e2e/README.md):
//   NEXT_PUBLIC_SUPABASE_URL=http://supabase.test npm run build
// y se sirve con `next start`. Ninguna prueba toca la base real.
const PUERTO = Number(process.env.E2E_PUERTO ?? 3100)

export default defineConfig({
  testDir: './e2e',
  timeout: 90_000,
  expect: { timeout: 15_000 },
  fullyParallel: true,
  workers: process.env.CI ? 2 : 3,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${PUERTO}`,
    serviceWorkers: 'allow',
    locale: 'es-CL',
    timezoneId: 'America/Santiago',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    // Teléfono Android de gama media, como los de faena.
    { name: 'android', use: { ...devices['Pixel 5'] } },
  ],
  webServer: {
    command: `npx next start -p ${PUERTO}`,
    url: `http://localhost:${PUERTO}/instalar/`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
})
