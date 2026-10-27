import { describe, expect, it, vi } from 'vitest'
import ExcelJS from 'exceljs'

vi.mock('@/lib/supabase', () => ({ supabase: {} }))
import { leerAramco } from '@/lib/services/combustible-tarjeta'

// Encabezados tal como los exporta Aramco Fleet (portaltarjetas.cl), con tildes.
// Los valores son inventados.
const ENC = ['Fecha transacción', 'Cliente', 'Centro de costo', 'Tarjeta', 'Tipo tarjeta', 'Patente', 'Tipo de vehiculo',
  'Tipo de venta', 'Guia despacho', 'Cód. autorización', 'Factura', 'RUT Chofer', 'Odometro', 'Odometro anterior',
  'Rendimiento del vehiculo', 'Producto', 'ES', 'Comuna ES', 'Pizarra ($/L)', 'Volumen (L)', 'Total pizarra ($)',
  'Total descuento ($)', 'IE ($)', 'IVA ($)', 'FEPP ($)', 'Total pago ($)', 'Tipo de Contrato', 'Grupo de Tarjetas ']

function libro(filas: unknown[][]) {
  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('transacciones')
  ws.addRow(ENC)
  filas.forEach((f) => ws.addRow(f))
  return wb
}
const fila = (cod: string | null, litros: number | null) => [
  new Date(Date.UTC(2026, 9, 27, 7, 15, 56)), 'CLIENTE DE PRUEBA', null, '0000 0001', 'Pospago', 'TE ST 01', 'Camionetas',
  'AUTOMÁTICA', 111, cod, null, '1-9', null, null, null, 'Diesel B', 'ESTACION DE PRUEBA', 'CALAMA', 1600, litros,
  40000, 1000, 0, 0, 0, 39000, '', null]

describe('leerAramco', () => {
  it('lee una carga con la hora local tal como la muestra el portal', () => {
    const { filas, descartadas } = leerAramco(libro([fila('AUT-1', 25.5)]))
    expect(descartadas).toBe(0)
    expect(filas).toHaveLength(1)
    expect(filas[0]).toMatchObject({
      fecha_hora: '2026-10-27T07:15:56', patente: 'TE ST 01', cod_autorizacion: 'AUT-1', litros: 25.5,
      total_pago: 39000, estacion: 'ESTACION DE PRUEBA', guia_despacho: '111', odometro: null,
    })
  })

  it('descarta filas sin código de autorización o sin litros', () => {
    const { filas, descartadas } = leerAramco(libro([fila('A1', 30), fila(null, 30), fila('A3', null)]))
    expect(filas.map((f) => f.cod_autorizacion)).toEqual(['A1'])
    expect(descartadas).toBe(2)
  })

  it('rechaza un Excel que no es el de transacciones', () => {
    const wb = new ExcelJS.Workbook()
    wb.addWorksheet('x').addRow(['Factura', 'Monto'])
    expect(() => leerAramco(wb)).toThrow(/Aramco Fleet/)
  })
})
