// Cobranza (MIG730-731): la cartera de clientes leída de Softland.
// Datos FICTICIOS (el repositorio es público: nada de clientes ni montos reales).
import { test, expect, sinPantallaDeError } from './fixtures'

const CARTERA = {
  sincronizado_at: '2026-11-26T18:25:00Z',
  resumen: {
    facturado: 1_000_000_000, pagado: 700_000_000, por_vencer: 180_000_000, vencido: 120_000_000,
    n_por_vencer: 6, n_vencido: 5, n_pagada: 40,
    tramos: { '1_30': 50_000_000, '31_60': 30_000_000, '61_90': 25_000_000, mas_90: 15_000_000 },
    credito_a_favor: -1_200_000,
  },
  mensual: [
    { mes: '2026-09', facturado: 300_000_000, cobrado: 280_000_000, pendiente: 20_000_000 },
    { mes: '2026-10', facturado: 350_000_000, cobrado: 250_000_000, pendiente: 100_000_000 },
    { mes: '2026-11', facturado: 350_000_000, cobrado: 170_000_000, pendiente: 180_000_000 },
  ],
  clientes: [
    { cod_aux: '11111111', rut: '11.111.111-1', cliente: 'MINERA EJEMPLO NORTE SPA', deuda: 150_000_000, vencido: 100_000_000,
      abiertas: 3, facturas: 10, facturado: 400_000_000, dias_pago_prom: 75, dias_atraso_prom: 45, pagadas_con_dato: 7, max_dias_vencida: 64 },
    { cod_aux: '22222222', rut: '22.222.222-2', cliente: 'DISTRIBUIDORA DEMO LTDA', deuda: 40_000_000, vencido: null,
      abiertas: 1, facturas: 12, facturado: 200_000_000, dias_pago_prom: 28, dias_atraso_prom: 2, pagadas_con_dato: 11, max_dias_vencida: 0 },
  ],
  documentos: [
    { cod_aux: '11111111', rut: '11.111.111-1', cliente: 'MINERA EJEMPLO NORTE SPA', tipo: 'V1', folio: 9001, emision: '2026-08-24',
      vence: '2026-09-23', monto: 52_000_000, notas_credito: 0, pagado: 0, saldo: 52_000_000, ultimo_pago: null, n_pagos: 0,
      estado: 'vencida', dias_vencida: 64, dias_pago: null, dias_atraso: null, patentes: ['AAAA-11', 'BBBB-22'] },
    { cod_aux: '22222222', rut: '22.222.222-2', cliente: 'DISTRIBUIDORA DEMO LTDA', tipo: 'V1', folio: 9002, emision: '2026-11-10',
      vence: '2026-12-10', monto: 40_000_000, notas_credito: 0, pagado: 0, saldo: 40_000_000, ultimo_pago: null, n_pagos: 0,
      estado: 'por_vencer', dias_vencida: 0, dias_pago: null, dias_atraso: null, patentes: [] },
  ],
}

test('cobranza: tarjetas, antigüedad, clientes, facturas y ficha del cliente', async ({ page, fake, conSesion, erroresJs }) => {
  fake.comoPerfil({ rol: 'administrador', nombre_completo: 'Administración' }, null)
  fake.rpcs.rpc_cxc_cartera = () => CARTERA
  fake.rpcs.rpc_cxc_cliente = () => ({
    cliente: { cod_aux: '11111111', rut: '11.111.111-1', nombre: 'MINERA EJEMPLO NORTE SPA', email: 'pagos@ejemplo.cl', email_dte: null, telefono: null, dia_plazo: 30 },
    documentos: [{ ...CARTERA.documentos[0], equipos: [{ patente: 'AAAA-11', activo_id: null, total: 26_000_000 }], movimientos: [] }],
  })
  await conSesion()

  await page.goto('/dashboard/finanzas/cobranza/')
  await expect(page.getByRole('heading', { name: 'Cobranza' })).toBeVisible()
  await expect(page.getByText('$120.000.000')).toBeVisible()
  await expect(page.getByText('Más de 90 días')).toBeVisible()
  await expect(page.getByText('Moroso', { exact: true })).toBeVisible()
  await expect(page.getByText('Puntual', { exact: true })).toBeVisible()
  await page.screenshot({ path: 'test-results/cobranza-movil.png', fullPage: true })
  await page.setViewportSize({ width: 1366, height: 900 })
  await page.waitForTimeout(800) // el gráfico se re-dibuja al nuevo ancho
  await page.screenshot({ path: 'test-results/cobranza-escritorio.png', fullPage: true })

  // Tabla del gráfico (relevo de accesibilidad del color naranjo).
  await page.getByRole('button', { name: 'Ver tabla' }).click()
  await expect(page.getByRole('cell', { name: 'nov-26' })).toBeVisible()

  // Facturas abiertas con sus patentes, y búsqueda por patente.
  await page.getByRole('button', { name: /Facturas abiertas/ }).click()
  await expect(page.getByText('BBBB-22')).toBeVisible()
  await page.getByPlaceholder('Cliente, RUT, folio o patente').fill('bbbb')
  await expect(page.getByText('9001')).toBeVisible()
  await expect(page.getByText('9002')).toHaveCount(0)

  // Ficha del cliente.
  await page.getByRole('button', { name: 'MINERA EJEMPLO NORTE SPA' }).first().click()
  await expect(page.getByRole('dialog')).toBeVisible()
  await expect(page.getByText('pagos@ejemplo.cl', { exact: false })).toBeVisible()
  await expect(page.getByRole('dialog').getByText('AAAA-11')).toBeVisible()
  await page.screenshot({ path: 'test-results/cobranza-ficha.png' })
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})
