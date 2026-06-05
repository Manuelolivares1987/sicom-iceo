'use client'

import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { Button } from '@/components/ui/button'
import FiabilidadPage from '@/app/dashboard/fiabilidad/page'

// Comercial necesita ver el análisis de Fiabilidad de flota completo, pero su rol
// no tiene el módulo 'flota' (donde vive /dashboard/fiabilidad en el sidebar).
// Reutilizamos el MISMO componente del reporte para que siempre quede sincronizado
// (un solo lugar que mantener). FiabilidadPage ya resuelve auth con useRequireAuth.
export default function ComercialFiabilidadPage() {
  return (
    <div>
      <div className="px-4 pt-4 sm:px-6">
        <Link href="/dashboard/comercial">
          <Button variant="ghost" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Comercial
          </Button>
        </Link>
      </div>
      <FiabilidadPage />
    </div>
  )
}
