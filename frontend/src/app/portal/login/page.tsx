'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { Fuel, AlertTriangle, LogIn } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { supabase } from '@/lib/supabase'
import { esUsuarioPortal, marcarAccesoPortal } from '@/lib/services/portal-cliente'

export default function PortalLoginPage() {
  const router = useRouter()
  const [email, setEmail]       = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading]   = useState(false)
  const [error, setError]       = useState<string | null>(null)

  const handleLogin = async () => {
    setError(null); setLoading(true)
    try {
      const { error: errLogin } = await supabase.auth.signInWithPassword({
        email: email.trim(), password,
      })
      if (errLogin) {
        setError(errLogin.message); return
      }
      // Validar que es usuario portal (no admin Pillado intentando entrar aquí)
      const esPortal = await esUsuarioPortal()
      if (!esPortal) {
        await supabase.auth.signOut()
        setError('Este usuario no tiene acceso al portal cliente. Si eres usuario de Pillado, entra por /dashboard.')
        return
      }
      await marcarAccesoPortal()
      router.push('/portal/dashboard')
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center p-4">
      <Card className="w-full max-w-sm">
        <CardContent className="space-y-4 p-6">
          <div className="flex items-center justify-center gap-2 text-blue-700">
            <Fuel className="h-8 w-8" />
            <div>
              <div className="text-lg font-bold leading-tight">Portal Cliente</div>
              <div className="text-xs text-gray-500">Combustible — Pillado</div>
            </div>
          </div>

          <div className="space-y-2">
            <div>
              <label className="text-xs font-medium text-gray-700">Email</label>
              <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                     placeholder="cliente@empresa.cl" autoComplete="email" />
            </div>
            <div>
              <label className="text-xs font-medium text-gray-700">Contraseña</label>
              <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                     onKeyDown={(e) => e.key === 'Enter' && handleLogin()}
                     placeholder="••••••••" autoComplete="current-password" />
            </div>
          </div>

          {error && (
            <div className="flex items-start gap-2 rounded border border-red-200 bg-red-50 p-2 text-sm text-red-700">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <Button onClick={handleLogin} disabled={loading || !email || !password}
                  className="w-full bg-blue-600 hover:bg-blue-700 gap-2">
            <LogIn className="h-4 w-4" />
            {loading ? 'Entrando...' : 'Entrar'}
          </Button>

          <p className="text-center text-[10px] text-gray-400">
            Si no tienes acceso, contacta a tu administrador en Pillado.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
