// Excel de consumos por insumo. La versión para proveedores lleva solo volúmenes.

import ExcelJS from 'exceljs'
import { filaParaProveedor, type FilaInsumo } from '@/lib/insumos-consumo'

export async function excelInsumos(filas: FilaInsumo[], paraProveedor: boolean, periodo: string) {
  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Volúmenes')
  ws.columns = [
    { header: 'Código', key: 'codigo', width: 16 }, { header: 'Insumo', key: 'insumo', width: 56 }, { header: 'Familia', key: 'familia', width: 22 },
    { header: 'Unidad', key: 'unidad', width: 9 }, { header: `Acumulado (${periodo})`, key: 'acumulado', width: 22 },
    { header: 'Promedio mensual', key: 'promedio', width: 16 }, { header: 'Proyección 12 meses', key: 'proyeccion', width: 18 },
    { header: 'Base proyección', key: 'base', width: 20 }, { header: 'Condición del volumen', key: 'condicion', width: 34 },
    ...(paraProveedor ? [] : [
      { header: 'Pauta 2027', key: 'p27', width: 12 }, { header: 'Pauta 2028', key: 'p28', width: 12 }, { header: 'Pauta 2029', key: 'p29', width: 12 },
      { header: 'Gasto período', key: 'monto', width: 15 }, { header: 'Precio promedio', key: 'precio', width: 15 }, { header: 'Proyección $', key: 'mp', width: 15 },
      { header: 'Proveedor principal', key: 'prov', width: 34 },
    ]),
  ]
  ws.getRow(1).font = { bold: true }
  ws.views = [{ state: 'frozen', ySplit: 1 }]
  for (const f of filas) {
    ws.addRow({
      ...filaParaProveedor(f),
      ...(paraProveedor ? {} : { p27: f.pauta_2027, p28: f.pauta_2028, p29: f.pauta_2029, monto: f.monto, precio: f.precio, mp: f.monto_proyectado, prov: f.proveedor }),
    })
  }
  for (const k of ['acumulado', 'promedio', 'proyeccion']) ws.getColumn(k).numFmt = '#,##0.0'
  return wb.xlsx.writeBuffer()
}
