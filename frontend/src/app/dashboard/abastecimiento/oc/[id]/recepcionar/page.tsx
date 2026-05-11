'use client'

import { useParams } from 'next/navigation'
import { RecepcionOCForm } from '@/components/abastecimiento/recepcion-oc-form'

export default function RecepcionarOCPage() {
  const params = useParams<{ id: string }>()
  return (
    <div className="p-6 max-w-5xl mx-auto">
      <RecepcionOCForm ocId={params.id} />
    </div>
  )
}
