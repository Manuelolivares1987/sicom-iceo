import { defineConfig, devices } from '@playwright/test'

// Lo que pide el service worker (sondeo de conexión, GET a la base) también
// pasa por el Supabase simulado; sin esto se escapaba a la red real.
process.env.PW_EXPERIMENTAL_SERVICE_WORKER_NETWORK_EVENTS = '1'

// Pruebas E2E de la app de terreno (Franke) en un Android simulado.
// La app se compila con Supabase falso (ver e2e/README.md):
//   NEXT_PUBLIC_SUPABASE_URL=https://e2e.supabase.co npm run build
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
    { name: 'android', use: { ...devices['Pixel 5'] }, testIgnore: /actualizacion\.spec\.ts/ },
    // Cambia el sw.js servido: va sola y al final.
    { name: 'actualizacion', use: { ...devices['Pixel 5'] }, testMatch: /actualizacion\.spec\.ts/, dependencies: ['android'] },
  ],
  webServer: {
    command: `npx next start -p ${PUERTO}`,
    url: `http://localhost:${PUERTO}/instalar/`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
})
