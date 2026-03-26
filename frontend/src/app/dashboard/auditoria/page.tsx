'use client'

import { Eye } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'

export default function AuditoriaPage() {
  return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <Card className="max-w-md w-full text-center">
        <CardContent className="pt-8 pb-8">
          <div className="mx-auto w-16 h-16 rounded-full bg-pillado-green-50 flex items-center justify-center mb-4">
            <Eye className="w-8 h-8 text-pillado-green-500" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900 mb-2">Auditoría</h1>
          <p className="text-gray-500 mb-4">Log completo de acciones del sistema: quién, qué, cuándo y dónde.</p>
          <span className="inline-block px-3 py-1 text-sm font-medium text-pillado-orange-500 bg-pillado-orange-50 rounded-full">
            En desarrollo
          </span>
        </CardContent>
      </Card>
    </div>
  )
}
