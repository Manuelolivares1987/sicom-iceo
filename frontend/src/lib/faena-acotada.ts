// [MIG385 + MIG714] Qué puede abrir quien está acotado a su faena (usuarios_perfil.solo_su_faena).
// Lista BLANCA: lo que no está acá no se ve. Una sola fuente para el guard del panel web,
// el guard de las apps de terreno (/m/*) y el menú.
//
// Franke (Manuel, 18-11-2026): «solo pueden ver lo que es de Franke, mi copiloto, el taller y
// sus activos. Nada más, no pueden ver sueldos ni cosas así». Lo de sueldos/bono/costos además
// está cerrado en la BD (MIG714): esto solo recorta la navegación.

export type FaenaAcotada = { codigo: string; nombre: string; app_movil: string | null; panel_web?: string | null }

/** Pantallas del panel web que toda faena acotada ve (filtradas a su faena). */
const WEB_BASE = [
  '/dashboard/activos',
  '/dashboard/ordenes-trabajo',
  '/dashboard/mantenimiento/plan-semanal-taller',
  '/dashboard/prevencion/personal',
]

/** Lo propio de cada faena, además de su panel_web. */
export const EXTRAS_POR_FAENA: Record<string, { label: string; href: string; icono: 'bodega' | 'copiloto' | 'ots' }[]> = {
  'FAE-FRANCKE': [
    { label: 'Bodega Franke', href: '/dashboard/bodega/franke', icono: 'bodega' },
    { label: 'Copiloto del taller', href: '/dashboard/mantenimiento/copiloto', icono: 'copiloto' },
    { label: 'Mis OTs', href: '/dashboard/mis-ots', icono: 'ots' },
  ],
}

/** Apps de terreno (/m/...) extra por faena. La app de la faena y prevención van siempre. */
const MOVIL_EXTRAS_POR_FAENA: Record<string, string[]> = {
  'FAE-FRANCKE': ['/m/taller/copiloto'],
}

const calza = (pathname: string, r: string) => pathname === r || pathname.startsWith(`${r}/`) || pathname.startsWith(`${r}?`)

export function rutaWebPermitida(pathname: string, faena: FaenaAcotada): boolean {
  const permitidas = [
    faena.panel_web ?? null,
    ...WEB_BASE,
    ...(EXTRAS_POR_FAENA[faena.codigo] ?? []).map((x) => x.href),
  ].filter((r): r is string => !!r)
  return permitidas.some((r) => calza(pathname, r))
}

export function rutaMovilPermitida(pathname: string, faena: FaenaAcotada): boolean {
  const permitidas = [
    faena.app_movil ?? null,
    // Los supervisores reportan prevención de SU faena desde el teléfono (MIG546, respeta solo_su_faena).
    '/m/prevencion',
    ...(MOVIL_EXTRAS_POR_FAENA[faena.codigo] ?? []),
  ].filter((r): r is string => !!r)
  // /m/franke también cubre /m/franke-venta: es de la misma faena.
  return permitidas.some((r) => pathname.startsWith(r))
}
