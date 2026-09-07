'use client'

// Plan de acción Gemba — la bandeja de GESTIÓN de los hallazgos de terreno.
//
// Manuel: «las NC que levantan en terreno, ¿dónde las pueden ver? La idea es
// hacer gestión». Los hallazgos ya vivían en gemba_hallazgos y por diseño
// siguen editables después de cerrar el recorrido (MIG288: el plan de acción
// SIGUE VIVO), pero solo se podían trabajar entrando recorrido por recorrido.
// La lista con su gestión vive en components/gemba/plan-accion-lista y se
// muestra también dentro del reporte de avance.

import Link from 'next/link'
import { ArrowLeft, AlertTriangle } from 'lucide-react'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { PlanAccionLista } from '@/components/gemba/plan-accion-lista'

export default function GembaHallazgosPage() {
  useRequireAuth()
  return (
    <div className="space-y-4 pb-6">
      <div>
        <Link href="/dashboard/gemba"
              className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
          <ArrowLeft className="h-4 w-4" /> Volver a recorridos
        </Link>
        <h1 className="mt-2 flex items-center gap-2 text-xl font-bold text-gray-900 sm:text-2xl">
          <AlertTriangle className="h-6 w-6 text-amber-500" />
          Plan de acción — hallazgos de terreno
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          Todo lo levantado en los recorridos, en un solo lugar: asigna responsable y plazo,
          avanza el estado y cierra la acción cuando esté resuelta.
        </p>
      </div>
      <PlanAccionLista />
    </div>
  )
}
