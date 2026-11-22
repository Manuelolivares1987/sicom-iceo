// /api/cuentas/crear-clave — público: la persona crea su clave con el enlace
// que le llegó por correo (o WhatsApp). Ver lib/server/cuentas.ts.
import { NextResponse } from 'next/server'
import { clienteServicio, usarEnlaceAcceso } from '@/lib/server/cuentas'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: Request) {
  const admin = clienteServicio()
  if (!admin) return NextResponse.json({ error: 'El servidor no está configurado.' }, { status: 500 })
  let b: { u?: string; t?: string; clave?: string }
  try { b = await req.json() } catch { return NextResponse.json({ error: 'Solicitud inválida.' }, { status: 400 }) }
  const clave = b.clave ?? ''
  if (!b.u || !b.t || !/^[0-9a-f-]{36}$/i.test(b.u)) {
    return NextResponse.json({ error: 'El enlace no es válido.' }, { status: 400 })
  }
  if (clave.length < 8) return NextResponse.json({ error: 'La clave debe tener al menos 8 caracteres.' }, { status: 400 })
  try {
    const { email } = await usarEnlaceAcceso(admin, b.u, b.t, clave)
    return NextResponse.json({ ok: true, email })
  } catch (e) {
    const m = (e as Error)?.message
    if (m === 'ENLACE_VENCIDO') return NextResponse.json({ error: 'El enlace venció. Pide a la oficina que te lo reenvíe.' }, { status: 410 })
    if (m === 'ENLACE_INVALIDO') return NextResponse.json({ error: 'El enlace no es válido o ya se usó. Pide a la oficina uno nuevo.' }, { status: 400 })
    return NextResponse.json({ error: 'No se pudo guardar la clave. Intenta de nuevo.' }, { status: 500 })
  }
}
