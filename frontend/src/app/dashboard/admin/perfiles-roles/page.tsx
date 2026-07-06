'use client'

import { useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Users, ShieldCheck, Save, RotateCcw, AlertTriangle, CheckCircle2, Lock, UserPlus,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions, useRolPermisosOverrides,
  ALL_ROLES, ALL_PERMISSIONS, PERMISSION_LABELS, MODULE_CATALOG, defaultPermsForRole,
  type PermisosOverrides } from '@/hooks/use-permissions'
import { getUsuarios, updateUsuario, crearUsuarioAdmin, getTecnicosSinCuenta } from '@/lib/services/admin'
import { supabase } from '@/lib/supabase'
import type { RolUsuario } from '@/types/database'
import type { Permission } from '@/hooks/use-permissions'
import { cn } from '@/lib/utils'

const ROL_LABEL: Record<string, string> = {
  administrador: 'Administrador', gerencia: 'Gerencia', subgerente_operaciones: 'Subgerente Ops',
  jefe_operaciones: 'Jefe Operaciones', jefe_mantenimiento: 'Jefe de Taller / Mantenimiento', supervisor: 'Supervisor',
  planificador: 'Planificador', tecnico_mantenimiento: 'Técnico Mantenimiento', bodeguero: 'Bodeguero',
  operador_abastecimiento: 'Operador Abastecimiento', comercial: 'Comercial', prevencionista: 'Prevencionista',
  colaborador: 'Colaborador', auditor: 'Auditor', auditor_calidad: 'Auditor de Calidad',
  rrhh_incentivos: 'RRHH Incentivos', operador_taller: 'Operador de Taller',
}
const rolLabel = (r: string) => ROL_LABEL[r] ?? r

export default function PerfilesRolesPage() {
  useRequireAuth()
  const { isAdmin } = usePermissions()
  const [tab, setTab] = useState<'usuarios' | 'roles'>('usuarios')

  if (!isAdmin()) {
    return (
      <Card><CardContent className="py-10 text-center space-y-2">
        <Lock className="h-10 w-10 text-amber-500 mx-auto" />
        <h3 className="text-lg font-semibold">Solo administradores</h3>
        <p className="text-sm text-muted-foreground">Esta página gestiona perfiles y permisos del sistema.</p>
      </CardContent></Card>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <ShieldCheck className="h-6 w-6 text-purple-600" /> Perfiles y Roles
        </h1>
        <p className="text-sm text-muted-foreground">
          Asigna el rol de cada usuario y configura qué ve y qué puede hacer cada rol en cada módulo.
        </p>
      </div>

      <div className="flex gap-2 border-b">
        <TabBtn active={tab === 'usuarios'} onClick={() => setTab('usuarios')} icon={Users}>Usuarios</TabBtn>
        <TabBtn active={tab === 'roles'} onClick={() => setTab('roles')} icon={ShieldCheck}>Roles y permisos</TabBtn>
      </div>

      {tab === 'usuarios' ? <UsuariosTab /> : <RolesTab />}
    </div>
  )
}

// ── Tab Usuarios ────────────────────────────────────────────────────────────
function UsuariosTab() {
  const qc = useQueryClient()
  const { data: usuarios = [], isLoading } = useQuery({
    queryKey: ['admin-usuarios'],
    queryFn: async () => { const { data, error } = await getUsuarios(); if (error) throw error; return data ?? [] },
  })
  const [savingId, setSavingId] = useState<string | null>(null)
  const [msg, setMsg] = useState<string | null>(null)
  const [filtro, setFiltro] = useState('')
  const [crear, setCrear] = useState(false)

  const cambiarRol = async (id: string, rol: string) => {
    setSavingId(id); setMsg(null)
    try {
      const { error } = await updateUsuario(id, { rol })
      if (error) throw error
      setMsg('Rol actualizado. El usuario lo verá al recargar su sesión.')
      qc.invalidateQueries({ queryKey: ['admin-usuarios'] })
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Error al actualizar')
    } finally { setSavingId(null) }
  }

  const lista = useMemo(() => {
    const f = filtro.toLowerCase()
    return (usuarios as any[]).filter((u) =>
      !f || u.nombre_completo?.toLowerCase().includes(f) || u.email?.toLowerCase().includes(f) || u.rol?.includes(f))
  }, [usuarios, filtro])

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base flex items-center justify-between gap-2">
          <span>Usuarios ({lista.length})</span>
          <div className="flex items-center gap-2">
            <input className="rounded border px-2 py-1 text-sm font-normal" placeholder="Buscar…"
              value={filtro} onChange={(e) => setFiltro(e.target.value)} />
            <Button size="sm" onClick={() => setCrear(true)}>
              <UserPlus className="h-4 w-4 mr-1" /> Crear usuario
            </Button>
          </div>
        </CardTitle>
      </CardHeader>
      <CardContent>
        {msg && <div className="mb-3 flex items-center gap-2 text-sm text-emerald-700"><CheckCircle2 className="h-4 w-4" />{msg}</div>}
        {isLoading && <Spinner className="h-5 w-5" />}
        <div className="space-y-1">
          {lista.map((u) => (
            <div key={u.id} className="flex items-center justify-between gap-3 rounded border p-2 text-sm">
              <div className="min-w-0">
                <div className="font-medium truncate">{u.nombre_completo ?? u.email}</div>
                <div className="text-xs text-muted-foreground truncate">{u.email} · {u.cargo ?? '—'} · {u.faena?.nombre ?? 'sin faena'}</div>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <select className="rounded border px-2 py-1 text-sm" value={u.rol ?? ''}
                  disabled={savingId === u.id}
                  onChange={(e) => cambiarRol(u.id, e.target.value)}>
                  {ALL_ROLES.map((r) => <option key={r} value={r}>{rolLabel(r)}</option>)}
                </select>
                {savingId === u.id && <Spinner className="h-4 w-4" />}
              </div>
            </div>
          ))}
        </div>
      </CardContent>
      {crear && (
        <CrearUsuarioModal
          onClose={() => setCrear(false)}
          onCreated={(m) => { setMsg(m); setCrear(false); qc.invalidateQueries({ queryKey: ['admin-usuarios'] }) }}
        />
      )}
    </Card>
  )
}

// ── Modal Crear usuario (via edge function admin-crear-usuario) ─────────────
function CrearUsuarioModal({ onClose, onCreated }: {
  onClose: () => void
  onCreated: (msg: string) => void
}) {
  const [nombre, setNombre] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [rol, setRol] = useState<string>('operador_taller')
  const [cargo, setCargo] = useState('')
  const [tecnicoId, setTecnicoId] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const { data: tecnicos = [] } = useQuery({
    queryKey: ['tecnicos-sin-cuenta'],
    queryFn: getTecnicosSinCuenta,
  })

  const esRolTaller = rol === 'operador_taller' || rol === 'jefe_mantenimiento'
  const valido = nombre.trim().length > 0 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())
    && password.length >= 6

  function generarPassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'
    let p = ''
    const buf = new Uint32Array(10)
    crypto.getRandomValues(buf)
    buf.forEach((n) => { p += chars[n % chars.length] })
    setPassword(p)
  }

  async function guardar() {
    setSaving(true); setError(null)
    try {
      const r = await crearUsuarioAdmin({
        email: email.trim(), password, nombre_completo: nombre.trim(), rol,
        cargo: cargo.trim() || null,
        tecnico_id: esRolTaller && tecnicoId ? tecnicoId : null,
      })
      onCreated(r.warning
        ? `Usuario creado. Aviso: ${r.warning}`
        : `Usuario ${nombre.trim()} creado con rol «${rolLabel(rol)}»${r.tecnico_vinculado ? ` y vinculado al técnico ${r.tecnico_vinculado}` : ''}. Entrégale el correo y la contraseña.`)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al crear usuario')
    } finally { setSaving(false) }
  }

  return (
    <Modal open onClose={onClose} title="Crear usuario">
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium text-muted-foreground">Nombre completo</label>
          <input className="mt-1 w-full rounded border px-3 py-2 text-sm" value={nombre}
            onChange={(e) => setNombre(e.target.value)} placeholder="Ej: Joel Coo" />
        </div>
        <div>
          <label className="text-xs font-medium text-muted-foreground">Correo (será su login)</label>
          <input type="email" className="mt-1 w-full rounded border px-3 py-2 text-sm" value={email}
            onChange={(e) => setEmail(e.target.value)} placeholder="operador@empresa.cl" />
        </div>
        <div>
          <label className="text-xs font-medium text-muted-foreground">Contraseña inicial (mín. 6)</label>
          <div className="mt-1 flex gap-2">
            <input className="w-full rounded border px-3 py-2 text-sm font-mono" value={password}
              onChange={(e) => setPassword(e.target.value)} />
            <Button size="sm" variant="outline" type="button" onClick={generarPassword}>Generar</Button>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs font-medium text-muted-foreground">Rol</label>
            <select className="mt-1 w-full rounded border px-2 py-2 text-sm" value={rol}
              onChange={(e) => setRol(e.target.value)}>
              {ALL_ROLES.map((r) => <option key={r} value={r}>{rolLabel(r)}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Cargo (opcional)</label>
            <input className="mt-1 w-full rounded border px-3 py-2 text-sm" value={cargo}
              onChange={(e) => setCargo(e.target.value)} placeholder="Mecánico" />
          </div>
        </div>
        {esRolTaller && (
          <div>
            <label className="text-xs font-medium text-muted-foreground">
              Vincular a técnico del taller (para que vea las OTs de su cuadrilla)
            </label>
            <select className="mt-1 w-full rounded border px-2 py-2 text-sm" value={tecnicoId}
              onChange={(e) => setTecnicoId(e.target.value)}>
              <option value="">— Sin vincular —</option>
              {(tecnicos as Array<{ id: string; nombre: string; operacion: string | null }>).map((t) => (
                <option key={t.id} value={t.id}>{t.nombre}{t.operacion ? ` (${t.operacion})` : ''}</option>
              ))}
            </select>
          </div>
        )}
        {rol === 'operador_taller' && (
          <p className="text-xs text-muted-foreground">
            El operador entra directo a la app móvil del taller y solo ve las OTs que su jefatura le asigne.
          </p>
        )}
        {error && (
          <div className="flex items-center gap-2 text-sm text-red-600">
            <AlertTriangle className="h-4 w-4 shrink-0" /> {error}
          </div>
        )}
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
        <Button onClick={guardar} disabled={!valido || saving}>
          {saving ? <Spinner className="h-4 w-4 mr-1" /> : <UserPlus className="h-4 w-4 mr-1" />}
          Crear usuario
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// ── Tab Roles y permisos ────────────────────────────────────────────────────
function RolesTab() {
  const qc = useQueryClient()
  const { data: overrides } = useRolPermisosOverrides()
  const [selRole, setSelRole] = useState<RolUsuario>('auditor_calidad')
  const [local, setLocal] = useState<Record<string, Permission[]>>({})
  const [dirty, setDirty] = useState<Set<string>>(new Set())
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)

  const esAdminRole = selRole === 'administrador'

  // (Re)cargar la matriz local cuando cambia el rol o llegan overrides.
  useEffect(() => {
    const next: Record<string, Permission[]> = {}
    for (const m of MODULE_CATALOG) {
      next[m.key] = (overrides?.[selRole]?.[m.key] ?? defaultPermsForRole(selRole, m.key)).slice()
    }
    setLocal(next); setDirty(new Set()); setMsg(null)
  }, [selRole, overrides])

  const esOverride = (mod: string) => !!(overrides as PermisosOverrides | undefined)?.[selRole]?.[mod]

  const toggle = (mod: string, perm: Permission) => {
    setLocal((s) => {
      const cur = new Set(s[mod] ?? [])
      cur.has(perm) ? cur.delete(perm) : cur.add(perm)
      return { ...s, [mod]: ALL_PERMISSIONS.filter((p) => cur.has(p)) }
    })
    setDirty((d) => new Set(d).add(mod))
  }

  const guardar = async () => {
    setSaving(true); setMsg(null)
    try {
      for (const mod of Array.from(dirty)) {
        const ext = MODULE_CATALOG.find((m) => m.key === mod)?.extendido ?? false
        const { error } = await supabase.rpc('fn_set_rol_permisos', {
          p_rol: selRole, p_modulo: mod, p_permisos: local[mod] ?? [], p_es_extendido: ext,
        })
        if (error) throw error
      }
      await qc.invalidateQueries({ queryKey: ['rol-permisos-overrides'] })
      setDirty(new Set())
      setMsg(`Guardado. Los usuarios con rol "${rolLabel(selRole)}" lo verán al recargar.`)
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Error al guardar')
    } finally { setSaving(false) }
  }

  const restaurar = async () => {
    setSaving(true); setMsg(null)
    try {
      const { error } = await supabase.rpc('fn_reset_rol_permisos', { p_rol: selRole })
      if (error) throw error
      await qc.invalidateQueries({ queryKey: ['rol-permisos-overrides'] })
      setMsg('Rol restaurado a los permisos por defecto.')
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Error al restaurar')
    } finally { setSaving(false) }
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[240px_1fr]">
      <Card>
        <CardHeader><CardTitle className="text-base">Roles</CardTitle></CardHeader>
        <CardContent className="space-y-1">
          {ALL_ROLES.map((r) => (
            <button key={r} onClick={() => setSelRole(r)}
              className={cn('w-full text-left rounded px-3 py-2 text-sm transition-colors flex items-center justify-between',
                selRole === r ? 'bg-purple-100 text-purple-800' : 'hover:bg-muted')}>
              <span>{rolLabel(r)}</span>
              {overrides?.[r] && <Badge variant="primary" className="text-[10px]">editado</Badge>}
            </button>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center justify-between">
            <span>Permisos de «{rolLabel(selRole)}»</span>
            {!esAdminRole && (
              <div className="flex gap-2">
                <Button size="sm" variant="outline" disabled={saving} onClick={restaurar}>
                  <RotateCcw className="h-4 w-4 mr-1" /> Restaurar default
                </Button>
                <Button size="sm" disabled={saving || dirty.size === 0} onClick={guardar}>
                  <Save className="h-4 w-4 mr-1" /> Guardar{dirty.size > 0 ? ` (${dirty.size})` : ''}
                </Button>
              </div>
            )}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {esAdminRole ? (
            <div className="flex items-center gap-2 text-sm text-muted-foreground py-6">
              <Lock className="h-4 w-4" /> El rol Administrador tiene acceso total y no es editable (anti-bloqueo).
            </div>
          ) : (
            <>
              {msg && <div className="mb-3 flex items-center gap-2 text-sm text-emerald-700"><CheckCircle2 className="h-4 w-4" />{msg}</div>}
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-xs text-muted-foreground">
                      <th className="text-left py-2 pr-2">Módulo</th>
                      {ALL_PERMISSIONS.map((p) => <th key={p} className="px-1 text-center w-16">{PERMISSION_LABELS[p]}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {MODULE_CATALOG.map((m) => (
                      <tr key={m.key} className="border-t">
                        <td className="py-1.5 pr-2">
                          {m.label}
                          {m.extendido && <Badge variant="default" className="ml-1 text-[9px]">ext</Badge>}
                          {esOverride(m.key) && <Badge variant="primary" className="ml-1 text-[9px]">override</Badge>}
                        </td>
                        {ALL_PERMISSIONS.map((p) => {
                          // Modulos extendidos: solo 'view' es relevante.
                          const aplica = !m.extendido || p === 'view'
                          const checked = (local[m.key] ?? []).includes(p)
                          return (
                            <td key={p} className="text-center">
                              <input type="checkbox" disabled={!aplica} checked={checked}
                                onChange={() => toggle(m.key, p)}
                                className={cn('h-4 w-4', !aplica && 'opacity-20')} />
                            </td>
                          )
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="text-xs text-muted-foreground mt-3">
                «Ver» controla la visibilidad del módulo. Sin override, el rol usa los permisos por defecto del sistema.
              </p>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

function TabBtn({ active, onClick, icon: Icon, children }: { active: boolean; onClick: () => void; icon: any; children: React.ReactNode }) {
  return (
    <button onClick={onClick}
      className={cn('flex items-center gap-2 px-4 py-2 text-sm border-b-2 -mb-px transition-colors',
        active ? 'border-purple-600 text-purple-700 font-medium' : 'border-transparent text-muted-foreground hover:text-foreground')}>
      <Icon className="h-4 w-4" /> {children}
    </button>
  )
}
