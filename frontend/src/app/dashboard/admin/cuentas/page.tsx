'use client'

// ============================================================================
// Administración → Cuentas (22-11-2026)
// ----------------------------------------------------------------------------
// Un administrador crea cuentas, decide qué ve cada una (rol, faena, «solo su
// faena», app de terreno, rol en Calama y permisos extra por módulo) y le
// manda el acceso por correo: un enlace para que la persona cree su propia
// clave (vence en 72 h, sirve una vez). El mismo enlace se puede copiar para
// mandarlo por WhatsApp. Todo pasa por /api/admin/cuentas (service role,
// valida que quien llama sea administrador).
// ============================================================================
import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { UserPlus, Send, Copy, Search, ShieldCheck, Pencil } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/contexts/auth-context'
import { useToast } from '@/contexts/toast-context'
import { getFaenas } from '@/lib/services/faenas'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  MODULE_CATALOG, ALL_PERMISSIONS, PERMISSION_LABELS, defaultPermsForRole, useRolPermisosOverrides, type Permission,
} from '@/hooks/use-permissions'
import type { RolUsuario } from '@/types/database'
import { cn } from '@/lib/utils'

const ROL_LABEL: Record<string, string> = {
  administrador: 'Administrador', gerencia: 'Gerencia', subgerente_operaciones: 'Subgerente Ops',
  jefe_operaciones: 'Jefe Operaciones', jefe_mantenimiento: 'Jefe de Taller / Mantenimiento', supervisor: 'Supervisor',
  planificador: 'Planificador', tecnico_mantenimiento: 'Técnico Mantenimiento', bodeguero: 'Bodeguero',
  operador_abastecimiento: 'Operador Abastecimiento', comercial: 'Comercial', prevencionista: 'Prevencionista',
  colaborador: 'Colaborador', auditor: 'Auditor', auditor_calidad: 'Auditor de Calidad',
  rrhh_incentivos: 'RRHH Incentivos', operador_taller: 'Operador de Taller', operador_combustible: 'Operador de Combustible',
}
const APPS: Array<{ v: string; l: string }> = [
  { v: '', l: 'Según su faena (o el panel)' }, { v: '/m/franke', l: 'Franke (faena)' }, { v: '/m/romeral', l: 'Romeral (combustible)' },
  { v: '/m/calama', l: 'Calama (obras civiles)' }, { v: '/m/taller', l: 'Taller' }, { v: '/m/enex', l: 'ENEX' }, { v: '/m/prevencion', l: 'Prevención' },
]
const ROLES_CALAMA = [{ v: '', l: 'Sin rol en Calama' }, { v: 'operador_calama', l: 'Operador Calama' }, { v: 'supervisor_calama', l: 'Supervisor Calama' }, { v: 'jefe_sucursal', l: 'Jefe de sucursal' }]

type Cuenta = {
  id: string; email: string; nombre_completo: string; rol: string; cargo: string | null; faena_id: string | null
  faena_nombre: string | null; activo: boolean; solo_su_faena: boolean | null; app_terreno: string | null
  ultimo_ingreso: string | null; acceso_vence: string | null; permisos_extra: Record<string, string[]>; rol_calama: string | null
}
type Form = {
  email: string; nombre_completo: string; rol: string; cargo: string; faena_id: string; solo_su_faena: boolean
  app_terreno: string; rol_calama: string; activo: boolean; permisos_extra: Record<string, string[]>; enviar_correo: boolean
}
const VACIO: Form = {
  email: '', nombre_completo: '', rol: 'colaborador', cargo: '', faena_id: '', solo_su_faena: false,
  app_terreno: '', rol_calama: '', activo: true, permisos_extra: {}, enviar_correo: true,
}

async function api(method: 'GET' | 'POST', body?: unknown) {
  const { data: { session } } = await supabase.auth.getSession()
  const r = await fetch('/api/admin/cuentas', {
    method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
    body: body ? JSON.stringify(body) : undefined,
  })
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j.error ?? `Error ${r.status}`)
  return j
}

const fecha = (iso: string | null) => iso ? new Date(iso).toLocaleString('es-CL', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }) : ''

function estado(c: Cuenta): { txt: string; cls: string; clave: 'desactivada' | 'activa' | 'pendiente' | 'nunca' } {
  if (!c.activo) return { txt: 'Desactivada', cls: 'bg-gray-200 text-gray-700', clave: 'desactivada' }
  if (c.acceso_vence) {
    const vigente = new Date(c.acceso_vence).getTime() > Date.now()
    return vigente ? { txt: `Enlace enviado · vence ${fecha(c.acceso_vence)}`, cls: 'bg-amber-100 text-amber-900', clave: 'pendiente' }
      : { txt: 'Enlace vencido', cls: 'bg-red-100 text-red-800', clave: 'pendiente' }
  }
  if (c.ultimo_ingreso) return { txt: `Último ingreso ${fecha(c.ultimo_ingreso)}`, cls: 'bg-green-100 text-green-800', clave: 'activa' }
  return { txt: 'Nunca entró', cls: 'bg-orange-100 text-orange-900', clave: 'nunca' }
}

export default function CuentasPage() {
  const { perfil } = useAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const esAdmin = perfil?.rol === 'administrador'
  const { data, isLoading, error } = useQuery({ queryKey: ['admin-cuentas'], queryFn: () => api('GET'), enabled: esAdmin })
  const { data: faenas } = useQuery({ queryKey: ['faenas'], queryFn: async () => (await getFaenas()).data ?? [] })
  const { data: overrides } = useRolPermisosOverrides()

  const [q, setQ] = useState('')
  const [filtroFaena, setFiltroFaena] = useState('')
  const [filtroEstado, setFiltroEstado] = useState('')
  const [editando, setEditando] = useState<Cuenta | 'nueva' | null>(null)
  const [form, setForm] = useState<Form>(VACIO)
  const [guardando, setGuardando] = useState(false)
  const [resultado, setResultado] = useState<{ nombre: string; enlace: string; enviado: boolean; errorCorreo?: string } | null>(null)

  const cuentas = useMemo<Cuenta[]>(() => data?.cuentas ?? [], [data])
  const lista = useMemo(() => cuentas.filter((c) => {
    if (q && !`${c.nombre_completo} ${c.email} ${c.cargo ?? ''}`.toLowerCase().includes(q.toLowerCase())) return false
    if (filtroFaena && c.faena_id !== filtroFaena) return false
    if (filtroEstado && estado(c).clave !== filtroEstado) return false
    return true
  }), [cuentas, q, filtroFaena, filtroEstado])

  const base = (rol: string, modulo: string): Permission[] =>
    (overrides?.[rol]?.[modulo] as Permission[] | undefined) ?? defaultPermsForRole(rol as RolUsuario, modulo)

  const abrir = (c: Cuenta | 'nueva') => {
    setEditando(c); setResultado(null)
    setForm(c === 'nueva' ? VACIO : {
      email: c.email, nombre_completo: c.nombre_completo, rol: c.rol, cargo: c.cargo ?? '', faena_id: c.faena_id ?? '',
      solo_su_faena: !!c.solo_su_faena, app_terreno: c.app_terreno ?? '', rol_calama: c.rol_calama ?? '',
      activo: c.activo, permisos_extra: { ...c.permisos_extra }, enviar_correo: true,
    })
  }
  const setF = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }))
  const toggleExtra = (modulo: string, p: Permission) => setForm((f) => {
    const act = new Set(f.permisos_extra[modulo] ?? [])
    if (act.has(p)) act.delete(p); else act.add(p)
    return { ...f, permisos_extra: { ...f.permisos_extra, [modulo]: Array.from(act) } }
  })

  const guardar = async () => {
    setGuardando(true)
    try {
      const comun = {
        nombre_completo: form.nombre_completo, rol: form.rol, cargo: form.cargo || null, faena_id: form.faena_id || null,
        solo_su_faena: form.solo_su_faena, app_terreno: form.app_terreno || null, rol_calama: form.rol_calama || null,
        permisos_extra: Object.fromEntries(Object.entries(form.permisos_extra).filter(([, v]) => v.length > 0)),
      }
      if (editando === 'nueva') {
        const r = await api('POST', { accion: 'crear', email: form.email, enviar_correo: form.enviar_correo, ...comun })
        setResultado({ nombre: form.nombre_completo, enlace: r.enlace, enviado: r.enviado, errorCorreo: r.errorCorreo })
        toast.success('Cuenta creada')
      } else if (editando) {
        await api('POST', { accion: 'guardar', user_id: editando.id, activo: form.activo, ...comun })
        toast.success('Cambios guardados'); setEditando(null)
      }
      qc.invalidateQueries({ queryKey: ['admin-cuentas'] })
    } catch (e) { toast.error((e as Error).message) } finally { setGuardando(false) }
  }

  const enviarAcceso = async (c: Cuenta, porCorreo: boolean) => {
    try {
      const r = await api('POST', { accion: 'enviar_acceso', user_id: c.id, enviar_correo: porCorreo })
      setResultado({ nombre: c.nombre_completo, enlace: r.enlace, enviado: r.enviado, errorCorreo: r.errorCorreo })
      setEditando(null)
      qc.invalidateQueries({ queryKey: ['admin-cuentas'] })
    } catch (e) { toast.error((e as Error).message) }
  }
  const copiar = async (t: string) => { try { await navigator.clipboard.writeText(t); toast.success('Enlace copiado') } catch { toast.error('No se pudo copiar') } }

  if (!esAdmin) return <div className="p-6 text-sm text-gray-600">Solo un administrador puede ver esta pantalla.</div>

  return (
    <div className="space-y-4 p-4 md:p-6">
      <div className="flex flex-wrap items-center gap-3">
        <ShieldCheck className="h-6 w-6 text-pillado-green-700" />
        <div className="flex-1">
          <h1 className="text-xl font-bold text-gray-900">Cuentas</h1>
          <p className="text-sm text-gray-600">Crea cuentas, decide qué ve cada una y envía el acceso por correo.</p>
        </div>
        <Button onClick={() => abrir('nueva')}><UserPlus className="h-4 w-4" /> Nueva cuenta</Button>
      </div>
      {data && !data.correo_configurado && (
        <p className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          El correo del sistema no está configurado: igual puedes crear cuentas y copiar el enlace para mandarlo por WhatsApp.
        </p>
      )}

      {resultado && (
        <div className="rounded-xl border border-green-300 bg-green-50 p-4 text-sm">
          <p className="font-semibold text-green-900">Acceso para {resultado.nombre}</p>
          <p className="mt-1 text-green-900">
            {resultado.enviado ? 'Se envió el correo con el enlace para crear su clave.' : (resultado.errorCorreo ?? 'No se envió correo.')}
            {' '}También puedes mandarle este enlace por WhatsApp (sirve una vez, vence en 72 h):
          </p>
          <div className="mt-2 flex gap-2">
            <input readOnly value={resultado.enlace} aria-label="Enlace de acceso" className="min-w-0 flex-1 rounded border border-green-300 bg-white px-2 py-1.5 text-xs" />
            <Button size="sm" variant="outline" onClick={() => void copiar(resultado.enlace)}><Copy className="h-3.5 w-3.5" /> Copiar</Button>
          </div>
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        <div className="relative min-w-[220px] flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-500" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar nombre, correo o cargo" aria-label="Buscar"
            className="w-full rounded-lg border border-gray-300 py-2 pl-9 pr-3 text-sm" />
        </div>
        <select value={filtroFaena} onChange={(e) => setFiltroFaena(e.target.value)} aria-label="Faena" className="rounded-lg border border-gray-300 px-3 py-2 text-sm">
          <option value="">Todas las faenas</option>
          {(faenas ?? []).map((f: { id: string; nombre: string }) => <option key={f.id} value={f.id}>{f.nombre}</option>)}
        </select>
        <select value={filtroEstado} onChange={(e) => setFiltroEstado(e.target.value)} aria-label="Estado" className="rounded-lg border border-gray-300 px-3 py-2 text-sm">
          <option value="">Todos los estados</option>
          <option value="nunca">Nunca entró</option>
          <option value="pendiente">Enlace enviado / vencido</option>
          <option value="activa">Activa</option>
          <option value="desactivada">Desactivada</option>
        </select>
      </div>

      {isLoading ? <p className="text-sm text-gray-600">Cargando cuentas…</p>
        : error ? <p className="text-sm text-red-700">{(error as Error).message}</p> : (
        <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs text-gray-600">
              <tr><th className="px-3 py-2">Persona</th><th className="px-3 py-2">Rol</th><th className="px-3 py-2">Faena / app</th><th className="px-3 py-2">Estado</th><th className="px-3 py-2"><span className="sr-only">Acciones</span></th></tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {lista.map((c) => {
                const e = estado(c)
                return (
                  <tr key={c.id}>
                    <td className="px-3 py-2"><div className="font-medium text-gray-900">{c.nombre_completo}</div><div className="text-xs text-gray-600">{c.email}</div></td>
                    <td className="px-3 py-2 text-gray-800">{ROL_LABEL[c.rol] ?? c.rol}{c.rol_calama && <div className="text-xs text-gray-600">{ROLES_CALAMA.find((r) => r.v === c.rol_calama)?.l}</div>}</td>
                    <td className="px-3 py-2 text-gray-800">{c.faena_nombre ?? '—'}{c.solo_su_faena && <span className="text-xs text-gray-600"> · solo su faena</span>}{c.app_terreno && <div className="text-xs text-gray-600">App: {APPS.find((a) => a.v === c.app_terreno)?.l}</div>}</td>
                    <td className="px-3 py-2"><span className={cn('rounded-full px-2 py-0.5 text-xs font-medium', e.cls)}>{e.txt}</span></td>
                    <td className="whitespace-nowrap px-3 py-2 text-right">
                      <Button size="sm" variant="ghost" onClick={() => abrir(c)} aria-label={`Editar ${c.nombre_completo}`}><Pencil className="h-3.5 w-3.5" /></Button>
                      {c.activo && <Button size="sm" variant="outline" onClick={() => void enviarAcceso(c, true)}><Send className="h-3.5 w-3.5" /> Enviar acceso</Button>}
                    </td>
                  </tr>
                )
              })}
              {lista.length === 0 && <tr><td colSpan={5} className="px-3 py-6 text-center text-gray-600">Sin cuentas con ese filtro.</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {editando && (
        <Modal open onClose={() => setEditando(null)} title={editando === 'nueva' ? 'Nueva cuenta' : `Editar: ${editando.nombre_completo}`}
          description="Qué es la persona, qué ve y cómo recibe el acceso.">
          <div className="max-h-[70vh] space-y-4 overflow-y-auto pr-1">
            <section className="grid gap-3 sm:grid-cols-2">
              <Input label="Nombre completo" value={form.nombre_completo} onChange={(e) => setF('nombre_completo', e.target.value)} />
              <Input label="Correo (su usuario)" type="email" value={form.email} disabled={editando !== 'nueva'} onChange={(e) => setF('email', e.target.value)} />
              <Input label="Cargo" value={form.cargo} onChange={(e) => setF('cargo', e.target.value)} />
              <label className="block text-sm font-medium text-gray-700">Rol
                <select aria-label="Rol de la cuenta" value={form.rol} onChange={(e) => setF('rol', e.target.value)} className="mt-1.5 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                  {Object.entries(ROL_LABEL).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                </select>
              </label>
            </section>

            <section className="grid gap-3 rounded-lg border border-gray-200 p-3 sm:grid-cols-2">
              <p className="text-sm font-semibold text-gray-900 sm:col-span-2">Dónde trabaja</p>
              <label className="block text-sm font-medium text-gray-700">Faena
                <select aria-label="Faena de la cuenta" value={form.faena_id} onChange={(e) => setF('faena_id', e.target.value)} className="mt-1.5 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                  <option value="">Sin faena (oficina)</option>
                  {(faenas ?? []).map((f: { id: string; nombre: string }) => <option key={f.id} value={f.id}>{f.nombre}</option>)}
                </select>
              </label>
              <label className="block text-sm font-medium text-gray-700">App al entrar en el teléfono
                <select aria-label="App al entrar en el teléfono" value={form.app_terreno} onChange={(e) => setF('app_terreno', e.target.value)} className="mt-1.5 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                  {APPS.map((a) => <option key={a.v} value={a.v}>{a.l}</option>)}
                </select>
              </label>
              <label className="block text-sm font-medium text-gray-700">Rol en Calama
                <select aria-label="Rol en Calama" value={form.rol_calama} onChange={(e) => setF('rol_calama', e.target.value)} className="mt-1.5 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                  {ROLES_CALAMA.map((r) => <option key={r.v} value={r.v}>{r.l}</option>)}
                </select>
              </label>
              <label className="flex items-center gap-2 self-end pb-2 text-sm text-gray-800">
                <input type="checkbox" checked={form.solo_su_faena} onChange={(e) => setF('solo_su_faena', e.target.checked)} className="h-4 w-4" />
                Ve solo lo de su faena
              </label>
            </section>

            <section className="rounded-lg border border-gray-200 p-3">
              <p className="text-sm font-semibold text-gray-900">Qué puede ver y hacer en el panel</p>
              <p className="text-xs text-gray-600">Lo gris viene con su rol. Marca lo que quieras sumarle solo a esta persona.</p>
              <div className="mt-2 overflow-x-auto">
                <table className="w-full text-xs">
                  <thead><tr className="text-left text-gray-600"><th className="py-1 pr-2">Módulo</th>{ALL_PERMISSIONS.map((p) => <th key={p} className="px-1 py-1 text-center">{PERMISSION_LABELS[p]}</th>)}</tr></thead>
                  <tbody>
                    {MODULE_CATALOG.map((m) => {
                      const delRol = base(form.rol, m.key)
                      const extra = form.permisos_extra[m.key] ?? []
                      return (
                        <tr key={m.key} className="border-t border-gray-100">
                          <td className="py-1 pr-2 text-gray-800">{m.label}</td>
                          {ALL_PERMISSIONS.map((p) => {
                            const porRol = delRol.includes(p)
                            return (
                              <td key={p} className="px-1 py-1 text-center">
                                <input type="checkbox" aria-label={`${m.label}: ${PERMISSION_LABELS[p]}`}
                                  checked={porRol || extra.includes(p)} disabled={porRol}
                                  onChange={() => toggleExtra(m.key, p)} className="h-4 w-4 disabled:opacity-50" />
                              </td>
                            )
                          })}
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </section>

            {editando === 'nueva' ? (
              <label className="flex items-center gap-2 text-sm text-gray-800">
                <input type="checkbox" checked={form.enviar_correo} onChange={(e) => setF('enviar_correo', e.target.checked)} className="h-4 w-4" />
                Enviarle por correo el enlace para crear su clave (también podrás copiarlo para WhatsApp)
              </label>
            ) : (
              <div className="flex flex-wrap items-center gap-2 rounded-lg border border-gray-200 p-3">
                <label className="mr-auto flex items-center gap-2 text-sm text-gray-800">
                  <input type="checkbox" checked={form.activo} onChange={(e) => setF('activo', e.target.checked)} className="h-4 w-4" />
                  Cuenta activa
                </label>
                <Button size="sm" variant="outline" onClick={() => void enviarAcceso(editando, true)}><Send className="h-3.5 w-3.5" /> Enviar acceso por correo</Button>
                <Button size="sm" variant="outline" onClick={() => void enviarAcceso(editando, false)}><Copy className="h-3.5 w-3.5" /> Enlace para WhatsApp</Button>
              </div>
            )}
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setEditando(null)}>Cancelar</Button>
            <Button onClick={() => void guardar()} disabled={guardando || form.nombre_completo.trim().length < 3 || (editando === 'nueva' && !form.email.includes('@'))}>
              {guardando ? 'Guardando…' : editando === 'nueva' ? 'Crear cuenta' : 'Guardar cambios'}
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
