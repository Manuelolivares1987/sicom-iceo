'use client'

// ============================================================================
// Crear mi clave (22-11-2026) — se llega desde el enlace del correo de acceso
// (Administración → Cuentas). Pública: el enlace trae el usuario y un token de
// un solo uso que vence (ver lib/server/cuentas.ts).
// ============================================================================
import { useEffect, useState } from 'react'
import { Eye, EyeOff, CheckCircle2, Smartphone, Monitor } from 'lucide-react'
import { APK_URL } from '@/lib/app-terreno'

export default function CrearClavePage() {
  const [u, setU] = useState('')
  const [t, setT] = useState('')
  const [clave, setClave] = useState('')
  const [repite, setRepite] = useState('')
  const [ver, setVer] = useState(false)
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [listo, setListo] = useState<string | null>(null)

  useEffect(() => {
    const q = new URLSearchParams(window.location.search)
    setU(q.get('u') ?? ''); setT(q.get('t') ?? '')
  }, [])

  const problema = clave.length > 0 && clave.length < 8 ? 'Mínimo 8 caracteres.'
    : repite.length > 0 && repite !== clave ? 'Las dos claves no coinciden.' : null

  const guardar = async (e: React.FormEvent) => {
    e.preventDefault()
    if (clave.length < 8 || clave !== repite) return
    setEnviando(true); setError(null)
    try {
      const r = await fetch('/api/cuentas/crear-clave', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ u, t, clave }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) { setError(j.error ?? 'No se pudo guardar la clave.'); return }
      setListo(j.email ?? '')
    } catch {
      setError('Sin conexión. Intenta de nuevo cuando tengas señal.')
    } finally { setEnviando(false) }
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-gray-50 px-4 py-10">
      <div className="w-full max-w-sm rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
        <h1 className="text-xl font-bold text-gray-900">Crear mi clave de SICOM</h1>
        {listo !== null ? (
          <div className="mt-4 space-y-4">
            <p className="flex items-start gap-2 text-sm text-green-800">
              <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0" /> Listo, tu clave quedó guardada.
              {listo && <> Tu usuario es <b className="break-all">{listo}</b>.</>}
            </p>
            <a href={APK_URL} className="flex items-center justify-center gap-2 rounded-lg bg-pillado-green-600 px-4 py-3 text-sm font-semibold text-white">
              <Smartphone className="h-4 w-4" /> Teléfono Android: descargar la app SICOM
            </a>
            <p className="text-xs text-gray-600">
              Ábrela, toca «Instalar» (si el teléfono lo pide, permite instalar desde esta fuente; si sale Play Protect,
              «Instalar de todas formas») y entra con tu correo y tu clave.
            </p>
            <a href="/login/" className="flex items-center justify-center gap-2 rounded-lg border border-gray-300 px-4 py-3 text-sm font-medium text-gray-800">
              <Monitor className="h-4 w-4" /> Computador: entrar a SICOM
            </a>
          </div>
        ) : !u || !t ? (
          <p className="mt-4 text-sm text-red-700">Este enlace está incompleto. Ábrelo directamente desde el correo o pide a la oficina que te lo reenvíe.</p>
        ) : (
          <form onSubmit={guardar} className="mt-4 space-y-3">
            <p className="text-sm text-gray-600">Elige una clave de al menos 8 caracteres. Solo tú la vas a conocer.</p>
            <label className="block text-sm font-medium text-gray-700">Nueva clave
              <div className="relative mt-1">
                <input type={ver ? 'text' : 'password'} value={clave} onChange={(e) => setClave(e.target.value)}
                  autoComplete="new-password" required minLength={8}
                  className="w-full rounded-lg border border-gray-300 px-3 py-2.5 pr-10 text-base" />
                <button type="button" onClick={() => setVer((v) => !v)} aria-label={ver ? 'Ocultar clave' : 'Mostrar clave'}
                  className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-gray-500">
                  {ver ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
            </label>
            <label className="block text-sm font-medium text-gray-700">Repite la clave
              <input type={ver ? 'text' : 'password'} value={repite} onChange={(e) => setRepite(e.target.value)}
                autoComplete="new-password" required
                className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2.5 text-base" />
            </label>
            {(problema || error) && <p role="alert" className="text-sm text-red-700">{problema ?? error}</p>}
            <button type="submit" disabled={enviando || clave.length < 8 || clave !== repite}
              className="w-full rounded-lg bg-pillado-green-600 px-4 py-3 text-sm font-semibold text-white disabled:opacity-50">
              {enviando ? 'Guardando…' : 'Guardar mi clave'}
            </button>
          </form>
        )}
      </div>
    </main>
  )
}
