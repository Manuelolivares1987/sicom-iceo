'use client'

import { useState, useEffect } from 'react'
import { useForm } from 'react-hook-form'
import Image from 'next/image'
import { useRouter } from 'next/navigation'
import { Eye, EyeOff, LogIn } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'

interface LoginForm {
  email: string
  password: string
}

export default function LoginPage() {
  const router = useRouter()
  const { signIn, isAuthenticated, loading: authLoading } = useAuth()
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginForm>()

  // Redirect if already authenticated
  useEffect(() => {
    if (!authLoading && isAuthenticated) {
      router.replace('/dashboard')
    }
  }, [authLoading, isAuthenticated, router])

  const onSubmit = async (data: LoginForm) => {
    setError(null)
    try {
      await signIn(data.email, data.password)
      router.push('/dashboard')
    } catch {
      setError('Credenciales inválidas. Verifique su correo y contraseña.')
    }
  }

  // Don't render form while checking auth state
  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-pillado-green-700 via-pillado-green-800 to-gray-900">
        <div className="h-10 w-10 animate-spin rounded-full border-4 border-white border-t-transparent" />
      </div>
    )
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-pillado-green-700 via-pillado-green-800 to-gray-900 px-4 py-8">
      {/* Background pattern */}
      <div className="pointer-events-none absolute inset-0 opacity-5">
        <div
          className="h-full w-full"
          style={{
            backgroundImage:
              'radial-gradient(circle at 1px 1px, white 1px, transparent 0)',
            backgroundSize: '40px 40px',
          }}
        />
      </div>

      <div className="relative w-full max-w-md">
        {/* Card */}
        <div className="rounded-2xl bg-white/95 px-8 py-10 shadow-2xl backdrop-blur-sm sm:px-10">
          {/* Logo */}
          <div className="mb-6 flex justify-center">
            <Image
              src="/images/logo_empresa_2.png"
              alt="Pillado Empresas"
              width={200}
              height={80}
              className="h-auto w-[200px] object-contain"
              priority
            />
          </div>

          {/* Title */}
          <h1 className="text-center text-2xl font-bold tracking-tight text-gray-900">
            SICOM-ICEO
          </h1>
          <p className="mb-8 text-center text-sm text-gray-500">
            Sistema Integral de Control Operacional
          </p>

          {/* Error Message */}
          {error && (
            <div className="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          )}

          {/* Form */}
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
            {/* Email */}
            <div>
              <label
                htmlFor="email"
                className="mb-1.5 block text-sm font-medium text-gray-700"
              >
                Correo electrónico
              </label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                placeholder="usuario@pilladoempresas.cl"
                className="block w-full rounded-lg border border-gray-300 bg-white px-4 py-2.5 text-sm text-gray-900 placeholder-gray-400 transition-colors focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                {...register('email', {
                  required: 'El correo es obligatorio',
                  pattern: {
                    value: /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i,
                    message: 'Correo electrónico inválido',
                  },
                })}
              />
              {errors.email && (
                <p className="mt-1 text-xs text-red-600">
                  {errors.email.message}
                </p>
              )}
            </div>

            {/* Password */}
            <div>
              <label
                htmlFor="password"
                className="mb-1.5 block text-sm font-medium text-gray-700"
              >
                Contraseña
              </label>
              <div className="relative">
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  placeholder="••••••••"
                  className="block w-full rounded-lg border border-gray-300 bg-white px-4 py-2.5 pr-10 text-sm text-gray-900 placeholder-gray-400 transition-colors focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                  {...register('password', {
                    required: 'La contraseña es obligatoria',
                    minLength: {
                      value: 6,
                      message: 'Mínimo 6 caracteres',
                    },
                  })}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                  tabIndex={-1}
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              </div>
              {errors.password && (
                <p className="mt-1 text-xs text-red-600">
                  {errors.password.message}
                </p>
              )}
            </div>

            {/* Submit */}
            <button
              type="submit"
              disabled={isSubmitting}
              className="flex w-full items-center justify-center gap-2 rounded-lg bg-pillado-green-500 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-pillado-green-600 focus:outline-none focus:ring-2 focus:ring-pillado-green-500 focus:ring-offset-2 active:bg-pillado-green-700 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? (
                <div className="h-5 w-5 animate-spin rounded-full border-2 border-white border-t-transparent" />
              ) : (
                <LogIn className="h-4 w-4" />
              )}
              {isSubmitting ? 'Ingresando...' : 'Iniciar Sesión'}
            </button>
          </form>
        </div>

        {/* Footer */}
        <p className="mt-6 text-center text-xs text-white/60">
          Pillado Empresas &copy; 2026 &mdash; Trayectoria y Compromiso
        </p>
      </div>
    </div>
  )
}
