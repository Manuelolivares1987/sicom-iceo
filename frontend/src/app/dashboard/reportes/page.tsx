'use client'

import { FileSpreadsheet } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'

export default function ReportesPage() {
  return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <Card className="max-w-md w-full text-center">
        <CardContent className="pt-8 pb-8">
          <div className="mx-auto w-16 h-16 rounded-full bg-pillado-green-50 flex items-center justify-center mb-4">
            <FileSpreadsheet className="w-8 h-8 text-pillado-green-500" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900 mb-2">Reportes</h1>
          <p className="text-gray-500 mb-4">Reportes exportables en PDF y Excel: cumplimiento, OTs, inventario, KPI, ICEO e incentivos.</p>
          <span className="inline-block px-3 py-1 text-sm font-medium text-pillado-orange-500 bg-pillado-orange-50 rounded-full">
            En desarrollo
          </span>
        </CardContent>
      </Card>
    </div>
  )
}
