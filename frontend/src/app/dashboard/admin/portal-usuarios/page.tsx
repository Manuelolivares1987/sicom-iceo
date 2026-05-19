'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, UserPlus, RefreshCw, Power, PowerOff, AlertTriangle,
  ExternalLink, Building2, Check, X, Save, Users,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  cargarPerfilesPortal, crearPerfilPortal, togglePerfilPortal,
  cargarEmpresasExternasDistintas,
  type PerfilPortalAdmin,
} from '@/lib/services/portal-cliente'
import { cargarContratosActivos, type ContratoOption } from '@/lib/services/geocercas'

export default function PortalUsuariosAdminPage() {
  useRequireAuth()
  const [perfiles, setPerfiles]     = useState<PerfilPortalAdmin[]>([])
  const [contratos, setContratos]   = useState<ContratoOption[]>([])
  const [empresas, setEmpresas]     = useState<string[]>([])
  const [loading, setLoading]       = useState(true)
  const [error, setError]           = useState<string | null>(null)
  const [showModal, setShowModal]   = useState(false)

  const cargar = async () => {
    setLoading(true); setError(null)
    try {
      const [p, c, e] = await Promise.all([
        cargarPerfilesPortal(),
        cargarContratosActivos(),
        cargarEmpresasExternasDistintas(),
      ])
      setPerfiles(p); setContratos(c); setEmpresas(e)
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { cargar() }, [])

  const handleToggle = async (p: PerfilPortalAdmin) => {
    try {
      await togglePerfilPortal(p.user_id, !p.activo)
      await cargar()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/dashboard/admin">
            <Button variant="ghost" size="sm" className="gap-1">
              <ArrowLeft className="h-4 w-4" /> Admin
            </Button>
          </Link>
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold">
              <Users className="h-6 w-6 text-blue-600" />
              Usuarios Portal Cliente
            </h1>
            <p className="text-sm text-muted-foreground">
              Gestiona accesos externos al portal de combustible (/portal/login).
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button onClick={cargar} variant="outline" size="sm" className="gap-1" disabled={loading}>
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </Button>
          <Button onClick={() => setShowModal(true)} size="sm" className="gap-1 bg-blue-600 hover:bg-blue-700">
            <UserPlus className="h-4 w-4" /> Nuevo perfil
          </Button>
        </div>
      </div>

      {/* Aviso de proceso */}
      <Card className="border-amber-200 bg-amber-50">
        <CardContent className="space-y-1 p-3 text-sm text-amber-900">
          <div className="font-semibold">Proceso de creación:</div>
          <ol className="ml-4 list-decimal space-y-0.5 text-xs">
            <li>Crea el usuario en Supabase Dashboard → Authentication → Users con email + password</li>
            <li>Copia el <b>user_id</b> (UUID) del usuario creado</li>
            <li>Aquí abajo click "Nuevo perfil" → pega el user_id + define qué puede ver</li>
            <li>Envía al cliente el link <code className="rounded bg-white px-1">https://pilladoiceo.netlify.app/portal/login</code> + credenciales</li>
          </ol>
        </CardContent>
      </Card>

      {error && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Perfiles ({perfiles.length})</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {loading && perfiles.length === 0 ? (
            <div className="flex h-32 items-center justify-center"><Spinner /></div>
          ) : perfiles.length === 0 ? (
            <div className="p-6 text-center text-sm text-muted-foreground">
              Sin perfiles del portal creados. Click "Nuevo perfil" arriba.
            </div>
          ) : (
            <div className="divide-y">
              {perfiles.map((p) => (
                <div key={p.id} className={`flex items-start gap-3 p-3 ${!p.activo ? 'opacity-50' : ''}`}>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold">{p.nombre_visible}</span>
                      {!p.activo && <span className="rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-bold text-red-700">DESACTIVADO</span>}
                    </div>
                    <div className="text-xs text-gray-600">{p.email ?? '(sin email)'}</div>
                    {p.empresa && <div className="text-xs text-gray-500">{p.empresa}{p.rut_empresa ? ` · ${p.rut_empresa}` : ''}</div>}
                    <div className="mt-1 flex flex-wrap gap-2 text-[11px]">
                      {p.n_contratos ? (
                        <span className="rounded bg-blue-100 px-2 py-0.5 text-blue-700">{p.n_contratos} contratos</span>
                      ) : null}
                      {p.n_empresas ? (
                        <span className="rounded bg-purple-100 px-2 py-0.5 text-purple-700">{p.n_empresas} empresas externas</span>
                      ) : null}
                      {!p.n_contratos && !p.n_empresas && (
                        <span className="rounded bg-amber-100 px-2 py-0.5 text-amber-700">⚠ Sin filtros — no verá nada</span>
                      )}
                    </div>
                    {p.ultimo_acceso_at && (
                      <div className="mt-1 text-[10px] text-gray-400">
                        Último acceso: {new Date(p.ultimo_acceso_at).toLocaleString('es-CL')}
                      </div>
                    )}
                  </div>
                  <button onClick={() => handleToggle(p)}
                          title={p.activo ? 'Desactivar acceso' : 'Activar acceso'}
                          className="rounded p-2 hover:bg-gray-100">
                    {p.activo
                      ? <Power className="h-4 w-4 text-green-600" />
                      : <PowerOff className="h-4 w-4 text-gray-400" />}
                  </button>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <NuevoPerfilModal
        open={showModal}
        onClose={() => setShowModal(false)}
        contratos={contratos}
        empresas={empresas}
        onCreado={() => { setShowModal(false); cargar() }}
      />
    </div>
  )
}

function NuevoPerfilModal({ open, onClose, contratos, empresas, onCreado }: {
  open: boolean; onClose: () => void
  contratos: ContratoOption[]; empresas: string[]
  onCreado: () => void
}) {
  const [userId, setUserId]             = useState('')
  const [nombreVisible, setNombreVisible] = useState('')
  const [empresa, setEmpresa]           = useState('')
  const [rutEmpresa, setRutEmpresa]     = useState('')
  const [contratosSel, setContratosSel] = useState<Set<string>>(new Set<string>())
  const [empresasSel, setEmpresasSel]   = useState<Set<string>>(new Set<string>())
  const [notas, setNotas]               = useState('')
  const [saving, setSaving]             = useState(false)
  const [error, setError]               = useState<string | null>(null)

  useEffect(() => {
    if (open) {
      setUserId(''); setNombreVisible(''); setEmpresa(''); setRutEmpresa('')
      setContratosSel(new Set<string>()); setEmpresasSel(new Set<string>())
      setNotas(''); setError(null)
    }
  }, [open])

  const toggleContrato = (id: string) => {
    const n = new Set(contratosSel); if (n.has(id)) n.delete(id); else n.add(id); setContratosSel(n)
  }
  const toggleEmpresa = (e: string) => {
    const n = new Set(empresasSel); if (n.has(e)) n.delete(e); else n.add(e); setEmpresasSel(n)
  }

  const handleGuardar = async () => {
    setError(null)
    if (!/^[0-9a-f-]{36}$/i.test(userId.trim())) {
      setError('user_id inválido. Debe ser un UUID de auth.users (Supabase Dashboard → Users).')
      return
    }
    if (!nombreVisible.trim()) { setError('Nombre visible es obligatorio'); return }
    if (contratosSel.size === 0 && empresasSel.size === 0) {
      setError('Selecciona al menos un contrato O una empresa externa, sino el cliente no verá nada.')
      return
    }
    setSaving(true)
    try {
      await crearPerfilPortal({
        userId:           userId.trim(),
        nombreVisible:    nombreVisible.trim(),
        empresa:          empresa.trim() || undefined,
        rutEmpresa:       rutEmpresa.trim() || undefined,
        contratosIds:     Array.from(contratosSel),
        empresasExternas: Array.from(empresasSel),
        notas:            notas.trim() || undefined,
      })
      onCreado()
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setSaving(false)
    }
  }

  if (!open) return null

  return (
    <Modal open={open} onClose={onClose} title="Nuevo perfil — Portal Cliente">
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium text-gray-700">User ID (UUID de auth.users) *</label>
          <Input value={userId} onChange={(e) => setUserId(e.target.value)}
                 placeholder="abc12345-6789-..." className="font-mono text-xs" />
          <p className="mt-1 text-[10px] text-gray-500">
            <ExternalLink className="inline h-3 w-3" /> Crea primero el usuario en Supabase Dashboard → Authentication → Users con email + password, luego copia su UUID aquí.
          </p>
        </div>
        <div>
          <label className="text-xs font-medium text-gray-700">Nombre visible *</label>
          <Input value={nombreVisible} onChange={(e) => setNombreVisible(e.target.value)}
                 placeholder="Codelco Norte - Juan Pérez" />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs font-medium text-gray-700">Empresa</label>
            <Input value={empresa} onChange={(e) => setEmpresa(e.target.value)} placeholder="Codelco" />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-700">RUT empresa</label>
            <Input value={rutEmpresa} onChange={(e) => setRutEmpresa(e.target.value)} placeholder="76.xxx.xxx-x" />
          </div>
        </div>

        <div>
          <label className="text-xs font-medium text-gray-700">
            Contratos visibles ({contratosSel.size})
          </label>
          <div className="max-h-32 overflow-y-auto rounded border bg-gray-50 p-2 space-y-1">
            {contratos.length === 0 ? (
              <div className="text-xs text-gray-500">Sin contratos activos en BD.</div>
            ) : contratos.map((c) => (
              <label key={c.id} className="flex items-center gap-2 text-xs cursor-pointer hover:bg-white px-1 py-0.5 rounded">
                <input type="checkbox" checked={contratosSel.has(c.id)} onChange={() => toggleContrato(c.id)} />
                <span><b>{c.codigo}</b> · {c.cliente}</span>
              </label>
            ))}
          </div>
        </div>

        <div>
          <label className="text-xs font-medium text-gray-700">
            Empresas externas autorizadas visibles ({empresasSel.size})
          </label>
          <div className="max-h-32 overflow-y-auto rounded border bg-gray-50 p-2 space-y-1">
            {empresas.length === 0 ? (
              <div className="text-xs text-gray-500">Sin empresas externas registradas.</div>
            ) : empresas.map((e) => (
              <label key={e} className="flex items-center gap-2 text-xs cursor-pointer hover:bg-white px-1 py-0.5 rounded">
                <input type="checkbox" checked={empresasSel.has(e)} onChange={() => toggleEmpresa(e)} />
                <span>{e}</span>
              </label>
            ))}
          </div>
        </div>

        <div>
          <label className="text-xs font-medium text-gray-700">Notas</label>
          <textarea value={notas} onChange={(e) => setNotas(e.target.value)} rows={2}
                    className="w-full rounded border border-gray-200 px-2 py-1 text-sm" />
        </div>

        {error && (
          <div className="rounded border border-red-200 bg-red-50 p-2 text-sm text-red-700">
            <AlertTriangle className="inline h-4 w-4" /> {error}
          </div>
        )}

        <div className="flex justify-end gap-2 border-t pt-3">
          <Button variant="outline" size="sm" onClick={onClose}><X className="h-4 w-4" /> Cancelar</Button>
          <Button size="sm" onClick={handleGuardar} disabled={saving} className="bg-green-600 hover:bg-green-700">
            <Save className="h-4 w-4" /> {saving ? 'Guardando...' : 'Crear perfil'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
