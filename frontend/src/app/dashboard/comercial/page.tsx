'use client'

import Link from 'next/link'
import { Briefcase, DollarSign, Fuel } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { FiabilidadAnalisis } from '@/components/fiabilidad/fiabilidad-analisis'

// La Vista Comercial muestra el análisis de Fiabilidad de flota (solo lectura),
// que es lo único que el equipo comercial necesita ver. Los botones dan acceso a
// las herramientas de combustible (cobranza / consolidado / precios).
// Reutiliza el MISMO componente del reporte para mantener un solo lugar.
export default function ComercialPage() {
  useRequireAuth()

  return (
    <div className="space-y-4 p-4 sm:p-6">
      {/* ── Header + accesos a herramientas de combustible ── */}
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Briefcase className="h-7 w-7 text-purple-600" />
            Vista Comercial
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            Análisis de fiabilidad de flota y herramientas de combustible.
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Link href="/dashboard/comercial/ventas-combustible">
            <Button size="sm" className="bg-pillado-orange-600 hover:bg-pillado-orange-700">
              <DollarSign className="h-4 w-4 mr-1" /> Ventas combustible (cobrar)
            </Button>
          </Link>
          <Link href="/dashboard/comercial/combustible-consolidado">
            <Button variant="outline" size="sm">
              <Fuel className="h-4 w-4 mr-1" /> Consolidado combustible
            </Button>
          </Link>
          <Link href="/dashboard/comercial/precios-combustible">
            <Button variant="outline" size="sm">
              <DollarSign className="h-4 w-4 mr-1" /> Precios combustible
            </Button>
          </Link>
        </div>
      </div>

      {/* ── Análisis de Fiabilidad de flota (solo lectura) ── */}
      <FiabilidadAnalisis readOnly />
    </div>
  )
}
