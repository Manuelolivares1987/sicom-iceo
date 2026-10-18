'use client'

// Cuentas del Portal de Flota (MIG609). A diferencia del portal de combustible,
// la cuenta se crea completa desde aquí: no pasa por Supabase Auth, así que no
// hay que ir al dashboard de Supabase a copiar un UUID.

import { useEffect, useState } from 'react'
import {
  AlertTriangle, Check, Copy, ExternalLink, KeyRound, Power, PowerOff, Save, Truck, UserPlus, X,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { formatDateTime } from '@/lib/utils'
import type { ContratoOption } from '@/lib/services/geocercas'
import {
  crearCuentaPortalFlota, editarCuentaPortalFlota, generarPasswordTemporal,
  listarCuentasPortalFlota, resetPasswordPortalFlota, type CuentaPortalFlota,
} from '@/lib/services/portal-flota'

const URL_PORTAL = 'https://pilladoiceo.netlify.app/portal-flota/'

// El texto que se le manda al cliente, listo para pegar en un correo.
const mensajeAcceso = (nombre: string, email: string, password: string) =>
  `Estimado/a ${nombre}:\n\n` +
  `Le damos acceso al Portal de Flota de Pillado Empresas, donde puede revisar y descargar ` +
  `la documentación de nuestros equipos y su registro de mantenciones.\n\n` +
  `Ingreso: ${URL_PORTAL}\nUsuario: ${email}\nContraseña temporal: ${password}\n\n` +
  `Al primer ingreso el portal le pedirá definir una contraseña propia.`

function Credencial({ nombre, email, password, onCerrar }: {
  nombre: string; email: string; password: string; onCerrar: () => void
}) {
  const [copiado, setCopiado] = useState(false)
  const texto = mensajeAcceso(nombre, email, password)
  return (
    <div className="space-y-3">
      <p className="text-sm text-gray-700">
        Esta contraseña <b>no se vuelve a mostrar</b>. Cópiela ahora y envíesela al cliente:
      </p>
      <pre className="whitespace-pre-wrap rounded border bg-gray-50 p-3 text-xs">{texto}</pre>
      <div className="flex justify-end gap-2">
        <Button size="sm" variant="outline" className="gap-1"
                onClick={() => { navigator.clipboard.writeText(texto); setCopiado(true) }}>
          {copiado ? <Check className="h-4 w-4 text-green-600" /> : <Copy className="h-4 w-4" />}
          {copiado ? 'Copiado' : 'Copiar mensaje'}
        </Button>
        <Button size="sm" onClick={onCerrar}>Listo</Button>
      </div>
    </div>
  )
}

export function PortalFlotaCuentas({ contratos }: { contratos: ContratoOption[] }) {
  const [cuentas, setCuentas] = useState<CuentaPortalFlota[]>([])
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [nueva, setNueva] = useState(false)
  const [editando, setEditando] = useState<CuentaPortalFlota | null>(null)
  const [credencial, setCredencial] = useState<{ nombre: string; email: string; password: string } | null>(null)

  const cargar = async () => {
    setCargando(true); setError(null)
    try { setCuentas(await listarCuentasPortalFlota()) }
    catch (e) { setError((e as Error).message) }
    finally { setCargando(false) }
  }
  useEffect(() => { cargar() }, [])

  const accion = async (fn: () => Promise<unknown>) => {
    setError(null)
    try { await fn(); await cargar() } catch (e) { setError((e as Error).message) }
  }

  const resetear = (c: CuentaPortalFlota) => accion(async () => {
    const password = generarPasswordTemporal()
    await resetPasswordPortalFlota(c.id, password)
    setCredencial({ nombre: c.nombre, email: c.email, password })
  })

  return (
    <Card className="border-emerald-200">
      <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 pb-2">
        <div>
          <CardTitle className="flex items-center gap-2 text-base">
            <Truck className="h-5 w-5 text-emerald-600" /> Portal de Flota — documentación y mantenciones
          </CardTitle>
          <p className="mt-0.5 text-xs text-muted-foreground">
            El cliente ve los equipos de los contratos asignados: papeles (ver y descargar) e historial
            de mantenciones, sin costos.{' '}
            <a href={URL_PORTAL} target="_blank" rel="noreferrer" className="inline-flex items-center gap-0.5 text-emerald-700 underline">
              Abrir portal <ExternalLink className="h-3 w-3" />
            </a>
          </p>
        </div>
        <Button size="sm" onClick={() => setNueva(true)} className="gap-1 bg-emerald-600 hover:bg-emerald-700">
          <UserPlus className="h-4 w-4" /> Nueva cuenta
        </Button>
      </CardHeader>
      <CardContent className="p-0">
        {error && (
          <div className="mx-3 mb-2 flex items-center gap-2 rounded border border-red-200 bg-red-50 p-2 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </div>
        )}
        {cargando && cuentas.length === 0 ? (
          <div className="flex h-24 items-center justify-center"><Spinner /></div>
        ) : cuentas.length === 0 ? (
          <p className="p-6 text-center text-sm text-muted-foreground">Sin cuentas. Cree la primera con «Nueva cuenta».</p>
        ) : (
          <div className="divide-y">
            {cuentas.map((c) => (
              <div key={c.id} className={`flex flex-wrap items-start gap-3 p-3 ${!c.activo ? 'opacity-50' : ''}`}>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-semibold">{c.nombre}</span>
                    {c.empresa && <span className="text-xs text-gray-500">· {c.empresa}</span>}
                    {!c.activo && <span className="rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-bold text-red-700">DESACTIVADA</span>}
                    {c.bloqueado && <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-bold text-amber-700">BLOQUEADA 15 MIN</span>}
                    {c.debe_cambiar && c.activo && <span className="rounded bg-slate-100 px-1.5 py-0.5 text-[10px] font-semibold text-slate-600">contraseña temporal</span>}
                  </div>
                  <div className="text-xs text-gray-600">{c.email}</div>
                  <div className="mt-1 flex flex-wrap gap-1.5 text-[11px]">
                    {c.contratos.map((k) => (
                      <span key={k.id} className="rounded bg-blue-100 px-2 py-0.5 text-blue-700">{k.codigo}</span>
                    ))}
                    <span className={`rounded px-2 py-0.5 ${c.n_equipos ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}`}>
                      {c.n_equipos ? `${c.n_equipos} equipos visibles` : '⚠ 0 equipos: asigne equipos al contrato'}
                    </span>
                  </div>
                  <div className="mt-1 text-[10px] text-gray-400">
                    {c.ultimo_acceso_at ? `Último ingreso ${formatDateTime(c.ultimo_acceso_at)}` : 'Nunca ha ingresado'}
                    {` · ${c.n_ingresos} ingresos · ${c.n_descargas} descargas`}
                  </div>
                </div>
                <div className="flex gap-1">
                  <button onClick={() => setEditando(c)} title="Contratos visibles" className="rounded px-2 py-1 text-xs text-gray-600 hover:bg-gray-100">
                    Contratos
                  </button>
                  <button onClick={() => resetear(c)} title="Nueva contraseña temporal" className="rounded p-2 hover:bg-gray-100">
                    <KeyRound className="h-4 w-4 text-gray-600" />
                  </button>
                  <button onClick={() => accion(() => editarCuentaPortalFlota(c.id, { activo: !c.activo }))}
                          title={c.activo ? 'Desactivar (cierra sus sesiones)' : 'Activar'} className="rounded p-2 hover:bg-gray-100">
                    {c.activo ? <Power className="h-4 w-4 text-green-600" /> : <PowerOff className="h-4 w-4 text-gray-400" />}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      <NuevaCuentaModal
        open={nueva} contratos={contratos} onClose={() => setNueva(false)}
        onCreada={(cred) => { setNueva(false); setCredencial(cred); cargar() }}
      />
      {editando && (
        <ContratosModal
          cuenta={editando} contratos={contratos} onClose={() => setEditando(null)}
          onGuardar={(ids) => accion(async () => { await editarCuentaPortalFlota(editando.id, { contratos: ids }); setEditando(null) })}
        />
      )}
      {credencial && (
        <Modal open onClose={() => setCredencial(null)} title="Credenciales del portal">
          <Credencial {...credencial} onCerrar={() => setCredencial(null)} />
        </Modal>
      )}
    </Card>
  )
}

function SelectorContratos({ contratos, sel, onToggle }: {
  contratos: ContratoOption[]; sel: Set<string>; onToggle: (id: string) => void
}) {
  return (
    <div className="max-h-40 space-y-1 overflow-y-auto rounded border bg-gray-50 p-2">
      {contratos.map((c) => (
        <label key={c.id} className="flex cursor-pointer items-center gap-2 rounded px-1 py-0.5 text-xs hover:bg-white">
          <input type="checkbox" checked={sel.has(c.id)} onChange={() => onToggle(c.id)} />
          <span><b>{c.codigo}</b> · {c.cliente}</span>
        </label>
      ))}
    </div>
  )
}

function NuevaCuentaModal({ open, contratos, onClose, onCreada }: {
  open: boolean; contratos: ContratoOption[]; onClose: () => void
  onCreada: (c: { nombre: string; email: string; password: string }) => void
}) {
  const [email, setEmail] = useState('')
  const [nombre, setNombre] = useState('')
  const [empresa, setEmpresa] = useState('')
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (open) { setEmail(''); setNombre(''); setEmpresa(''); setSel(new Set()); setError(null) }
  }, [open])

  const toggle = (id: string) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })

  const guardar = async () => {
    setGuardando(true); setError(null)
    const password = generarPasswordTemporal()
    try {
      await crearCuentaPortalFlota({ email, nombre, empresa, contratos: Array.from(sel), password })
      onCreada({ nombre: nombre.trim(), email: email.trim().toLowerCase(), password })
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setGuardando(false)
    }
  }

  if (!open) return null
  return (
    <Modal open={open} onClose={onClose} title="Nueva cuenta — Portal de Flota">
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium text-gray-700">Correo (será su usuario) *</label>
          <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nombre@esmax.cl" />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs font-medium text-gray-700">Nombre y apellido *</label>
            <Input value={nombre} onChange={(e) => setNombre(e.target.value)} />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-700">Empresa</label>
            <Input value={empresa} onChange={(e) => setEmpresa(e.target.value)} placeholder="ESMAX" />
          </div>
        </div>
        <div>
          <label className="text-xs font-medium text-gray-700">Contratos visibles ({sel.size}) *</label>
          <SelectorContratos contratos={contratos} sel={sel} onToggle={toggle} />
          <p className="mt-1 text-[10px] text-gray-500">
            Ve los equipos asignados a estos contratos. Si un camión cambia de contrato, deja de verlo solo.
          </p>
        </div>
        <p className="text-[11px] text-gray-500">La contraseña temporal se genera sola y se muestra al crear la cuenta.</p>
        {error && (
          <div className="rounded border border-red-200 bg-red-50 p-2 text-sm text-red-700">
            <AlertTriangle className="inline h-4 w-4" /> {error}
          </div>
        )}
        <div className="flex justify-end gap-2 border-t pt-3">
          <Button variant="outline" size="sm" onClick={onClose}><X className="h-4 w-4" /> Cancelar</Button>
          <Button size="sm" onClick={guardar} disabled={guardando} className="bg-emerald-600 hover:bg-emerald-700">
            <Save className="h-4 w-4" /> {guardando ? 'Creando...' : 'Crear cuenta'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}

function ContratosModal({ cuenta, contratos, onClose, onGuardar }: {
  cuenta: CuentaPortalFlota; contratos: ContratoOption[]; onClose: () => void; onGuardar: (ids: string[]) => void
}) {
  const [sel, setSel] = useState<Set<string>>(new Set(cuenta.contratos.map((c) => c.id)))
  const toggle = (id: string) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })
  return (
    <Modal open onClose={onClose} title={`Contratos visibles — ${cuenta.nombre}`}>
      <div className="space-y-3">
        <SelectorContratos contratos={contratos} sel={sel} onToggle={toggle} />
        <div className="flex justify-end gap-2 border-t pt-3">
          <Button variant="outline" size="sm" onClick={onClose}>Cancelar</Button>
          <Button size="sm" disabled={sel.size === 0} onClick={() => onGuardar(Array.from(sel))}
                  className="bg-emerald-600 hover:bg-emerald-700">
            <Save className="h-4 w-4" /> Guardar
          </Button>
        </div>
      </div>
    </Modal>
  )
}
