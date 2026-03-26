'use client'

import { Wrench } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'

export default function MantenimientoPage() {
  return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <Card className="max-w-md w-full text-center">
        <CardContent className="pt-8 pb-8">
          <div className="mx-auto w-16 h-16 rounded-full bg-pillado-green-50 flex items-center justify-center mb-4">
            <Wrench className="w-8 h-8 text-pillado-green-500" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900 mb-2">Mantenimiento</h1>
          <p className="text-gray-500 mb-4">Planes de mantenimiento preventivo y correctivo, pautas del fabricante y calendario de vencimientos.</p>
          <span className="inline-block px-3 py-1 text-sm font-medium text-pillado-orange-500 bg-pillado-orange-50 rounded-full">
            En desarrollo
          </span>
        </CardContent>
      </Card>
    </div>
  )
}
