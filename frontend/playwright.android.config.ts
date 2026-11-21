import { defineConfig, devices } from '@playwright/test'

// La app SICOM nativa en un emulador Android (ver e2e-android/app-nativa.spec.ts).
// La web se compila con Supabase simulado en http://localhost:54321:
//   node e2e-android/build.mjs && npx playwright test -c playwright.android.config.ts
// En CI corre con SICOM_ANDROID=1 dentro del emulador; sin esa variable, en Chromium.
export default defineConfig({
  testDir: './e2e-android',
  timeout: 240_000,
  workers: 1,
  retries: 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never', outputFolder: 'playwright-report-android' }]] : 'list',
  use: { ...devices['Pixel 5'], trace: 'retain-on-failure', screenshot: 'only-on-failure' },
  outputDir: 'test-results-android',
  webServer: {
    command: 'npx next start -p 3100',
    url: 'http://localhost:3100/instalar/',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
})
