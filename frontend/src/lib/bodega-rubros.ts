// Rubros de proveedor (MIG567). Lista cerrada: la valida fn_rubro_valido en la BD.
// Cada rubro sugiere el `tipo` (enum tipo_proveedor_enum) que se usa en compras.

export type TipoProveedor = 'combustible' | 'repuestos' | 'servicios' | 'lubricantes' | 'filtros' | 'otros'

export const RUBROS: Array<{ rubro: string; tipo: TipoProveedor; corto: string }> = [
  { rubro: 'Repuestos, automotriz y maquinaria',               tipo: 'repuestos',   corto: 'Repuestos' },
  { rubro: 'Ferretería, materiales y eléctricos',              tipo: 'repuestos',   corto: 'Ferretería' },
  { rubro: 'Neumáticos y vulcanización',                       tipo: 'repuestos',   corto: 'Neumáticos' },
  { rubro: 'Lubricantes',                                      tipo: 'lubricantes', corto: 'Lubricantes' },
  { rubro: 'Filtros',                                          tipo: 'filtros',     corto: 'Filtros' },
  { rubro: 'Combustibles y estaciones de servicio',            tipo: 'combustible', corto: 'Combustible' },
  { rubro: 'Seguridad, EPP y ropa de trabajo',                 tipo: 'otros',       corto: 'EPP' },
  { rubro: 'Ingeniería, construcción y servicios industriales', tipo: 'servicios',  corto: 'Serv. industriales' },
  { rubro: 'Transporte, fletes y arriendo de vehículos',       tipo: 'servicios',   corto: 'Transporte' },
  { rubro: 'Hotelería y alojamiento',                          tipo: 'servicios',   corto: 'Hotelería' },
  { rubro: 'Alimentación y supermercado',                      tipo: 'servicios',   corto: 'Alimentación' },
  { rubro: 'Asesorías, capacitación y certificación',          tipo: 'servicios',   corto: 'Asesorías' },
  { rubro: 'Bancos, seguros e instituciones',                  tipo: 'servicios',   corto: 'Bancos/seguros' },
  { rubro: 'Tecnología, telecomunicaciones y retail',          tipo: 'servicios',   corto: 'Tecnología' },
  { rubro: 'Imprenta, publicidad, diseño y oficina',           tipo: 'otros',       corto: 'Oficina/publicidad' },
  { rubro: 'Salud y exámenes',                                 tipo: 'servicios',   corto: 'Salud' },
  { rubro: 'Aseo, residuos y sanitización',                    tipo: 'servicios',   corto: 'Aseo' },
  { rubro: 'Inmobiliaria, arriendos y módulos',                tipo: 'servicios',   corto: 'Arriendos' },
  { rubro: 'Servicios básicos (luz, agua)',                    tipo: 'servicios',   corto: 'Luz/agua' },
  { rubro: 'Agrícola, pesca y veterinaria',                    tipo: 'otros',       corto: 'Agrícola' },
  { rubro: 'Minería y mandantes (posible cliente)',            tipo: 'otros',       corto: 'Minería' },
  { rubro: 'Persona natural (honorarios / servicios)',         tipo: 'servicios',   corto: 'Persona natural' },
  { rubro: 'Otro',                                             tipo: 'otros',       corto: 'Otro' },
]

export const TIPOS_PROVEEDOR: Array<{ v: TipoProveedor; t: string }> = [
  { v: 'repuestos', t: 'Repuestos' }, { v: 'lubricantes', t: 'Lubricantes' }, { v: 'filtros', t: 'Filtros' },
  { v: 'combustible', t: 'Combustible' }, { v: 'servicios', t: 'Servicios' }, { v: 'otros', t: 'Otros' },
]

export function rubroCorto(rubro: string | null | undefined): string {
  if (!rubro) return 'Sin rubro'
  return RUBROS.find((r) => r.rubro === rubro)?.corto ?? rubro
}

export function tipoDeRubro(rubro: string): TipoProveedor {
  return RUBROS.find((r) => r.rubro === rubro)?.tipo ?? 'otros'
}

// Los rubros que de verdad le importan a bodega van primero en los buscadores.
export const RUBROS_BODEGA = new Set([
  'Repuestos, automotriz y maquinaria', 'Ferretería, materiales y eléctricos', 'Neumáticos y vulcanización',
  'Lubricantes', 'Filtros', 'Combustibles y estaciones de servicio', 'Seguridad, EPP y ropa de trabajo',
])
