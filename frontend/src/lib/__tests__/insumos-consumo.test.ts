import { describe, expect, it } from 'vitest'
import ExcelJS from 'exceljs'
import { excelInsumos } from '@/lib/export/insumos-excel'
import { armarFilaInsumo, filaParaProveedor, periodosInsumo, type InsumoConsumo } from '@/lib/insumos-consumo'

const base = {
  clave: 'X', cod_prod: 'X', descripcion: 'Aceite', familia: 'Lubricantes', unidad: 'L', acumulado: 240, monto: 480000, movimientos: 3,
  meses_con_consumo: 3, precio_ref: 1500, camiones: 0, con_pauta: false, pauta_12m: null, pauta_2027: null, pauta_2028: null, pauta_2029: null,
  proveedor: 'Proveedor SA', n_proveedores: 1,
} as InsumoConsumo

describe('consumos por insumo', () => {
  it('usa meses cerrados y promedia también los meses sin consumo', () => {
    const [p12] = periodosInsumo('2026-11-09')
    expect(p12).toMatchObject({ desde: '2025-11-01', hasta: '2026-10-31', meses: 12 })
    expect(armarFilaInsumo(base, p12.meses).promedio).toBe(20)
  })

  it('cruza bien el cambio de año', () => {
    const [p12] = periodosInsumo('2027-01-15')
    expect(p12).toMatchObject({ desde: '2026-01-01', hasta: '2026-12-31' })
  })

  it('la pauta manda sobre el promedio aunque proyecte menos', () => {
    const f = armarFilaInsumo({ ...base, con_pauta: true, pauta_12m: 100 }, 12)
    expect(f).toMatchObject({ base: 'pauta', proyeccion: 100, precio: 2000, monto_proyectado: 200000 })
  })

  it('sin pauta sigue el promedio; sin historia usa el precio de referencia', () => {
    expect(armarFilaInsumo(base, 12)).toMatchObject({ base: 'promedio', proyeccion: 240 })
    expect(armarFilaInsumo({ ...base, acumulado: 0, monto: 0, con_pauta: true, pauta_12m: 10 }, 12).precio).toBe(1500)
  })

  it('el Excel para proveedores no trae columnas internas y avisa lo provisorio', async () => {
    const buf = await excelInsumos([armarFilaInsumo({ ...base, con_pauta: true, pauta_12m: 100, provisorio: true }, 12)], true, 'Últimos 12 meses')
    const wb = new ExcelJS.Workbook()
    await wb.xlsx.load(buf as unknown as ArrayBuffer)
    const ws = wb.getWorksheet('Volúmenes')!
    const texto = JSON.stringify([ws.getRow(1).values, ws.getRow(2).values])
    expect(texto).toContain('Proyección 12 meses')
    expect(texto).toContain('Referencial')
    expect(texto).not.toContain('Proveedor SA')
    expect(texto).not.toContain('Precio')
    expect(texto).not.toContain('480000')
  })

  it('al proveedor no le llegan precios, montos ni proveedores actuales', () => {
    const texto = JSON.stringify(filaParaProveedor(armarFilaInsumo(base, 12)))
    expect(texto).not.toContain('Proveedor SA')
    expect(texto).not.toContain('480000')
    expect(texto).not.toContain('2000')
  })
})
