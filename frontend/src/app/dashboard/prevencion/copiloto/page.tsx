'use client'

// Copiloto Prevención Centinela en el computador (MIG734): oficina y jefatura.
import { useRequireAuth } from '@/hooks/use-require-auth'
import { ChatCopilotoSso } from '@/components/copiloto-sso/chat'

export default function CopilotoSsoOficina() {
  useRequireAuth()
  return (
    <div className="mx-auto max-w-4xl space-y-3">
      <div>
        <h1 className="text-xl font-bold text-gray-900">Copiloto Prevención · Minera Centinela</h1>
        <p className="text-sm text-gray-500">RECSS AMSA, EDC Altura y Energía Eléctrica, Lecciones Aprendidas, Directriz de contratos y el control documental del personal (solo lectura).</p>
      </div>
      <div className="overflow-hidden rounded-xl border border-gray-200">
        <ChatCopilotoSso />
      </div>
    </div>
  )
}
