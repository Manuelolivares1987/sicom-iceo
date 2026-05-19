'use client'

import { useState } from 'react'
import Image from 'next/image'
import { useRouter } from 'next/navigation'
import { AlertTriangle, LogIn, ShieldCheck, BarChart3, Truck, Camera } from 'lucide-react'
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
      if (errLogin) { setError(errLogin.message); return }
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
    <div className="flex min-h-screen flex-col lg:flex-row">
      {/* Hero institucional (izquierda) */}
      <div className="relative flex flex-1 flex-col justify-between bg-gradient-to-br from-pillado-green-700 via-pillado-green-600 to-pillado-green-500 p-8 text-white lg:p-12">
        <div className="absolute inset-0 opacity-10"
             style={{
               backgroundImage: 'radial-gradient(circle at 30% 20%, white 1px, transparent 1px)',
               backgroundSize: '30px 30px',
             }} />
        <div className="relative">
          <div className="flex items-center gap-3">
            <Image src="/images/logo.jpg" alt="Pillado" width={64} height={64}
                   className="rounded-lg shadow-xl" priority />
            <div>
              <div className="text-3xl font-bold tracking-tight">PILLADO</div>
              <div className="text-xs uppercase tracking-widest text-pillado-orange-300">Servicios Mineros</div>
            </div>
          </div>
        </div>

        <div className="relative my-8 max-w-md">
          <h1 className="text-3xl font-bold leading-tight sm:text-4xl">
            Portal Cliente
            <span className="block text-pillado-orange-300">Combustibles</span>
          </h1>
          <p className="mt-4 text-lg text-white/90">
            Acceso seguro a tus transacciones diarias, evidencias fotográficas y
            reportes consolidados de combustible despachado a tu flota.
          </p>

          <div className="mt-8 space-y-3">
            <Feature icon={<BarChart3 className="h-5 w-5" />}
                     titulo="Dashboard en vivo"
                     descripcion="Acumulados por día, semana y mes con gráficos de tendencia." />
            <Feature icon={<Truck className="h-5 w-5" />}
                     titulo="Trazabilidad por patente"
                     descripcion="Filtra por equipo, fecha y empresa autorizada." />
            <Feature icon={<Camera className="h-5 w-5" />}
                     titulo="Evidencia fotográfica"
                     descripcion="Fotos del medidor antes/después, patente del vehículo y firma del receptor." />
            <Feature icon={<ShieldCheck className="h-5 w-5" />}
                     titulo="Acceso seguro"
                     descripcion="Solo ves transacciones autorizadas a tu empresa." />
          </div>
        </div>

        <div className="relative text-xs text-white/60">
          © {new Date().getFullYear()} Pillado Empresas · Todos los derechos reservados
        </div>
      </div>

      {/* Form login (derecha) */}
      <div className="flex flex-1 items-center justify-center bg-white p-6 lg:p-12">
        <div className="w-full max-w-sm space-y-6">
          <div className="lg:hidden">
            <Image src="/images/logo.jpg" alt="Pillado" width={56} height={56}
                   className="mx-auto rounded-lg shadow-sm" />
            <div className="mt-3 text-center">
              <div className="text-xl font-bold text-pillado-green-700">PILLADO</div>
              <div className="text-[10px] uppercase tracking-widest text-gray-500">Portal Cliente</div>
            </div>
          </div>

          <div>
            <h2 className="text-2xl font-bold text-gray-900">Iniciar sesión</h2>
            <p className="mt-1 text-sm text-gray-500">
              Ingresa con las credenciales que te entregó tu administrador en Pillado.
            </p>
          </div>

          <div className="space-y-4">
            <div>
              <label className="text-sm font-semibold text-gray-700">Correo electrónico</label>
              <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                     placeholder="cliente@empresa.cl" autoComplete="email"
                     className="mt-1 h-11" />
            </div>
            <div>
              <label className="text-sm font-semibold text-gray-700">Contraseña</label>
              <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                     onKeyDown={(e) => e.key === 'Enter' && handleLogin()}
                     placeholder="••••••••" autoComplete="current-password"
                     className="mt-1 h-11" />
            </div>
          </div>

          {error && (
            <div className="flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <Button onClick={handleLogin} disabled={loading || !email || !password}
                  className="h-11 w-full gap-2 bg-pillado-green-500 hover:bg-pillado-green-600">
            <LogIn className="h-4 w-4" />
            {loading ? 'Verificando acceso...' : 'Ingresar al portal'}
          </Button>

          <p className="text-center text-xs text-gray-400">
            ¿Problemas para acceder? Contacta a tu ejecutivo de cuenta en Pillado.
          </p>
        </div>
      </div>
    </div>
  )
}

function Feature({ icon, titulo, descripcion }: { icon: React.ReactNode; titulo: string; descripcion: string }) {
  return (
    <div className="flex items-start gap-3">
      <div className="rounded-lg bg-white/10 p-2 text-pillado-orange-300">{icon}</div>
      <div>
        <div className="font-semibold">{titulo}</div>
        <div className="text-sm text-white/80">{descripcion}</div>
      </div>
    </div>
  )
}
