'use client'

// ============================================================================
// Proveedores (MIG567)
// ----------------------------------------------------------------------------
// El maestro de Softland trae RUT y nombre; el rubro y el giro los puso
// SICOM (reglas de nombre + investigación web) con una confianza. Esta
// pantalla es para VER qué vende cada uno y CORREGIR lo que quedó mal:
// bodega es quien conoce a sus proveedores.
// ============================================================================

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Building2, Search, X, Pencil, Loader2, ArrowLeft, Check, AlertTriangle, Download, Plus } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  listarProveedores, contarProveedoresPorRubro, actualizarProveedor, crearProveedorRapido, rutValido,
  type ProveedorBusqueda,
} from '@/lib/services/bodega-ingreso'
import { RUBROS, TIPOS_PROVEEDOR, rubroCorto, tipoDeRubro } from '@/lib/bodega-rubros'
import { cn } from '@/lib/utils'

const ROLES_EDITAN = ['administrador', 'subgerente_operaciones', 'jefe_mantenimiento', 'supervisor', 'operador_abastecimiento', 'bodeguero']
const PAGE = 50

function useDebounced(value: string, ms = 250) {
  const [v, setV] = useState(value)
  useEffect(() => { const t = setTimeout(() => setV(value), ms); return () => clearTimeout(t) }, [value, ms])
  return v
}

const CONF: Record<string, { t: string; c: string }> = {
  alta:  { t: 'verificado', c: 'bg-emerald-100 text-emerald-800' },
  media: { t: 'probable', c: 'bg-amber-100 text-amber-800' },
  baja:  { t: 'por confirmar', c: 'bg-gray-200 text-gray-700' },
}

export default function ProveedoresPage() {
  const { perfil, loading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const puedeEditar = !!perfil && ROLES_EDITAN.includes(perfil.rol)

  const [q, setQ] = useState('')
  const [rubro, setRubro] = useState<string | null>(null)
  const [soloRevisar, setSoloRevisar] = useState(false)
  const [incluirInactivos, setIncluirInactivos] = useState(false)
  const [pagina, setPagina] = useState(0)
  const [editando, setEditando] = useState<ProveedorBusqueda | null>(null)
  const [creando, setCreando] = useState(false)
  const dq = useDebounced(q)

  useEffect(() => { setPagina(0) }, [dq, rubro, soloRevisar, incluirInactivos])

  const { data: conteos = {} } = useQuery({ queryKey: ['proveedores-conteo'], queryFn: contarProveedoresPorRubro, staleTime: 60_000 })
  const { data, isFetching } = useQuery({
    queryKey: ['proveedores-lista', dq, rubro, soloRevisar, incluirInactivos, pagina],
    queryFn: () => listarProveedores({ q: dq, rubro, soloRevisar, soloActivos: !incluirInactivos, limit: PAGE, offset: pagina * PAGE }),
    placeholderData: (prev) => prev,
  })
  const rows = data?.rows ?? []
  const total = data?.total ?? 0
  const totalActivos = useMemo(() => Object.values(conteos).reduce((s, n) => s + n, 0), [conteos])

  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ['proveedores-lista'] })
    qc.invalidateQueries({ queryKey: ['proveedores-conteo'] })
    qc.invalidateQueries({ queryKey: ['prov-busqueda'] })
  }

  const exportarCsv = async () => {
    const { rows: todos } = await listarProveedores({ q: dq, rubro, soloRevisar, soloActivos: !incluirInactivos, limit: 5000, offset: 0 })
    const esc = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`
    const csv = ['codigo;rut;nombre;rubro;giro;tipo;confianza;activo',
      ...todos.map((p) => [p.codigo, p.rut, p.nombre, p.rubro, p.giro, p.tipo, p.rubro_confianza, p.activo ? 'si' : 'no'].map(esc).join(';'))].join('\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }))
    a.download = `proveedores_${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
  }

  if (loading) return <div className="flex justify-center py-16"><Loader2 className="h-6 w-6 animate-spin text-gray-400" /></div>

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-4 md:p-6">
      <div className="flex flex-wrap items-center gap-2">
        <Link href="/dashboard/inventario" className="rounded-md border border-gray-300 p-1.5 text-gray-600 hover:bg-gray-50" aria-label="Volver">
          <ArrowLeft className="h-4 w-4" />
        </Link>
        <h1 className="flex items-center gap-2 text-xl font-bold text-gray-900">
          <Building2 className="h-6 w-6 text-sky-700" /> Proveedores
        </h1>
        <span className="text-sm text-gray-500">{totalActivos.toLocaleString('es-CL')} activos · a qué se dedica cada uno</span>
        <div className="ml-auto flex gap-2">
          <Button type="button" variant="outline" size="sm" onClick={exportarCsv}><Download className="mr-1 h-4 w-4" /> CSV</Button>
          {puedeEditar && <Button type="button" size="sm" onClick={() => setCreando(true)}><Plus className="mr-1 h-4 w-4" /> Nuevo</Button>}
        </div>
      </div>

      {/* Rubros como chips con conteo */}
      <div className="flex flex-wrap gap-1.5">
        <button type="button" onClick={() => setRubro(null)}
                className={cn('rounded-full border px-2.5 py-1 text-xs font-semibold', !rubro ? 'border-sky-600 bg-sky-600 text-white' : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-50')}>
          Todos {totalActivos}
        </button>
        {RUBROS.filter((r) => (conteos[r.rubro] ?? 0) > 0).map((r) => (
          <button key={r.rubro} type="button" onClick={() => setRubro(rubro === r.rubro ? null : r.rubro)} title={r.rubro}
                  className={cn('rounded-full border px-2.5 py-1 text-xs font-semibold', rubro === r.rubro ? 'border-sky-600 bg-sky-600 text-white' : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-50')}>
            {r.corto} <span className="opacity-70">{conteos[r.rubro]}</span>
          </button>
        ))}
        {(conteos['Sin rubro'] ?? 0) > 0 && <span className="rounded-full bg-gray-100 px-2.5 py-1 text-xs text-gray-600">Sin rubro {conteos['Sin rubro']}</span>}
      </div>

      <Card>
        <CardContent className="space-y-3 p-4">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative min-w-[260px] flex-1">
              <Search className="pointer-events-none absolute left-3 top-3 h-4 w-4 text-gray-400" />
              <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nombre, RUT o giro (ej: neumáticos, soldadura, Copiapó)" className="pl-9" />
              {q && <button type="button" onClick={() => setQ('')} className="absolute right-3 top-3 text-gray-400" aria-label="Limpiar"><X className="h-4 w-4" /></button>}
            </div>
            <label className="flex items-center gap-1.5 text-xs text-gray-700">
              <input type="checkbox" checked={soloRevisar} onChange={(e) => setSoloRevisar(e.target.checked)} className="h-4 w-4" />
              Solo por confirmar
            </label>
            <label className="flex items-center gap-1.5 text-xs text-gray-700">
              <input type="checkbox" checked={incluirInactivos} onChange={(e) => setIncluirInactivos(e.target.checked)} className="h-4 w-4" />
              Incluir inactivos
            </label>
            <span className="text-xs text-gray-500">{total.toLocaleString('es-CL')} resultado(s){isFetching ? '…' : ''}</span>
          </div>

          <div className="overflow-x-auto rounded-lg border border-gray-200">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-[11px] uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="px-3 py-2 text-left">Proveedor</th>
                  <th className="px-3 py-2 text-left">Rubro</th>
                  <th className="px-3 py-2 text-left">A qué se dedica</th>
                  <th className="px-3 py-2 text-left">Dato</th>
                  <th className="px-2 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {rows.map((p) => {
                  const c = CONF[p.rubro_confianza ?? ''] ?? null
                  return (
                    <tr key={p.id} className={cn('hover:bg-gray-50', !p.activo && 'opacity-50')}>
                      <td className="px-3 py-2">
                        <div className="font-medium text-gray-800">{p.nombre}</div>
                        <div className="font-mono text-[11px] text-gray-500">{p.rut ?? p.codigo}{p.es_persona_natural ? ' · persona natural' : ''}</div>
                      </td>
                      <td className="px-3 py-2 text-xs text-gray-700">{rubroCorto(p.rubro)}</td>
                      <td className="max-w-md px-3 py-2 text-xs text-gray-600">{p.giro ?? <span className="italic text-gray-400">sin información</span>}</td>
                      <td className="px-3 py-2">
                        {c && <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-semibold', c.c)}>{c.t}</span>}
                        {p.rubro_fuente === 'manual' && <span className="ml-1 rounded-full bg-sky-100 px-2 py-0.5 text-[10px] font-semibold text-sky-800">corregido</span>}
                      </td>
                      <td className="px-2 py-2 text-right">
                        {puedeEditar && (
                          <button type="button" onClick={() => setEditando(p)} className="rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-800" aria-label="Editar">
                            <Pencil className="h-4 w-4" />
                          </button>
                        )}
                      </td>
                    </tr>
                  )
                })}
                {rows.length === 0 && !isFetching && (
                  <tr><td colSpan={5} className="px-3 py-8 text-center text-sm text-gray-500">Nada con esos filtros.</td></tr>
                )}
              </tbody>
            </table>
          </div>

          {total > PAGE && (
            <div className="flex items-center justify-between text-xs text-gray-600">
              <span>Página {pagina + 1} de {Math.ceil(total / PAGE)}</span>
              <div className="flex gap-2">
                <Button type="button" variant="outline" size="sm" disabled={pagina === 0} onClick={() => setPagina((p) => p - 1)}>Anterior</Button>
                <Button type="button" variant="outline" size="sm" disabled={(pagina + 1) * PAGE >= total} onClick={() => setPagina((p) => p + 1)}>Siguiente</Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {editando && (
        <EditarProveedorModal proveedor={editando} onClose={() => setEditando(null)}
          onSaved={() => { setEditando(null); invalidar(); toast.success('Proveedor actualizado') }} />
      )}
      {creando && (
        <CrearProveedorModal onClose={() => setCreando(false)}
          onSaved={(existia) => { setCreando(false); invalidar(); toast.success(existia ? 'Ese proveedor ya existía' : 'Proveedor creado') }} />
      )}
    </div>
  )
}

function Campo({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="block"><span className="text-xs font-semibold text-gray-700">{label}</span><div className="mt-1">{children}</div></label>
}

function EditarProveedorModal({ proveedor, onClose, onSaved }: { proveedor: ProveedorBusqueda; onClose: () => void; onSaved: () => void }) {
  const toast = useToast()
  const [nombre, setNombre] = useState(proveedor.nombre)
  const [rut, setRut] = useState(proveedor.rut ?? '')
  const [rubro, setRubro] = useState(proveedor.rubro ?? 'Otro')
  const [tipo, setTipo] = useState(proveedor.tipo)
  const [giro, setGiro] = useState(proveedor.giro ?? '')
  const [contacto, setContacto] = useState(proveedor.contacto ?? '')
  const [telefono, setTelefono] = useState(proveedor.telefono ?? '')
  const [email, setEmail] = useState(proveedor.email ?? '')
  const [activo, setActivo] = useState(proveedor.activo !== false)
  const [busy, setBusy] = useState(false)

  const guardar = async () => {
    if (rut.trim() && !rutValido(rut)) { toast.error('El RUT no cuadra (dígito verificador)'); return }
    setBusy(true)
    try {
      await actualizarProveedor(proveedor.id, {
        nombre: nombre.trim() !== proveedor.nombre ? nombre.trim() : undefined,
        rut: rut.trim() !== (proveedor.rut ?? '') ? (rut.trim() || null) : undefined,
        rubro: rubro !== proveedor.rubro ? rubro : undefined,
        tipo: tipo !== proveedor.tipo ? tipo : undefined,
        giro: giro.trim() !== (proveedor.giro ?? '') ? giro.trim() : undefined,
        contacto: contacto.trim() !== (proveedor.contacto ?? '') ? contacto.trim() : undefined,
        telefono: telefono.trim() !== (proveedor.telefono ?? '') ? telefono.trim() : undefined,
        email: email.trim() !== (proveedor.email ?? '') ? email.trim() : undefined,
        activo: activo !== (proveedor.activo !== false) ? activo : undefined,
      })
      onSaved()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'No se pudo guardar') }
    finally { setBusy(false) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-0 md:items-center md:p-4" onClick={onClose}>
      <div className="max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-t-2xl bg-white p-5 shadow-xl md:rounded-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-base font-bold text-gray-900">Editar proveedor</h2>
          <button type="button" onClick={onClose} aria-label="Cerrar"><X className="h-5 w-5 text-gray-500" /></button>
        </div>
        <div className="space-y-3">
          <Campo label="Nombre"><Input value={nombre} onChange={(e) => setNombre(e.target.value)} /></Campo>
          <div className="grid grid-cols-2 gap-3">
            <Campo label="RUT"><Input value={rut} onChange={(e) => setRut(e.target.value)} className={cn(rut.trim() && !rutValido(rut) && 'border-red-400')} /></Campo>
            <Campo label="Tipo (compras)">
              <select value={tipo} onChange={(e) => setTipo(e.target.value)} className="h-10 w-full rounded-md border border-gray-300 bg-white px-2 text-sm">
                {TIPOS_PROVEEDOR.map((t) => <option key={t.v} value={t.v}>{t.t}</option>)}
              </select>
            </Campo>
          </div>
          <Campo label="Rubro">
            <select value={rubro} onChange={(e) => { setRubro(e.target.value); setTipo(tipoDeRubro(e.target.value)) }} className="h-10 w-full rounded-md border border-gray-300 bg-white px-2 text-sm">
              {RUBROS.map((r) => <option key={r.rubro} value={r.rubro}>{r.rubro}</option>)}
            </select>
          </Campo>
          <Campo label="A qué se dedica (giro)"><Input value={giro} onChange={(e) => setGiro(e.target.value)} placeholder="ej: venta de repuestos Mercedes-Benz y Scania" maxLength={160} /></Campo>
          <div className="grid grid-cols-3 gap-3">
            <Campo label="Contacto"><Input value={contacto} onChange={(e) => setContacto(e.target.value)} /></Campo>
            <Campo label="Teléfono"><Input value={telefono} onChange={(e) => setTelefono(e.target.value)} /></Campo>
            <Campo label="Correo"><Input value={email} onChange={(e) => setEmail(e.target.value)} /></Campo>
          </div>
          <label className="flex items-center gap-2 text-sm text-gray-700">
            <input type="checkbox" checked={activo} onChange={(e) => setActivo(e.target.checked)} className="h-4 w-4" /> Activo (aparece en el buscador de ingreso)
          </label>
          {(proveedor.rubro_confianza === 'baja' || proveedor.rubro_confianza === 'media') && (
            <div className="flex items-start gap-2 rounded-lg bg-amber-50 p-2 text-xs text-amber-900">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              El rubro se dedujo {proveedor.rubro_fuente === 'web' ? 'de la web' : 'del nombre'} con confianza {proveedor.rubro_confianza}. Si lo conoces, corrígelo: lo que guardes queda como definitivo.
            </div>
          )}
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose} disabled={busy}>Cancelar</Button>
          <Button type="button" onClick={guardar} disabled={busy}>{busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Check className="mr-1 h-4 w-4" />} Guardar</Button>
        </div>
      </div>
    </div>
  )
}

function CrearProveedorModal({ onClose, onSaved }: { onClose: () => void; onSaved: (existia: boolean) => void }) {
  const toast = useToast()
  const [nombre, setNombre] = useState('')
  const [rut, setRut] = useState('')
  const [rubro, setRubro] = useState('Repuestos, automotriz y maquinaria')
  const [giro, setGiro] = useState('')
  const [busy, setBusy] = useState(false)

  const crear = async () => {
    if (nombre.trim().length < 3) { toast.error('Escribe el nombre'); return }
    if (rut.trim() && !rutValido(rut)) { toast.error('El RUT no cuadra (dígito verificador)'); return }
    setBusy(true)
    try {
      const r = await crearProveedorRapido(nombre.trim(), rut.trim() || null, tipoDeRubro(rubro), rubro, giro.trim() || null)
      onSaved(r.existia)
    } catch (e) { toast.error(e instanceof Error ? e.message : 'No se pudo crear') }
    finally { setBusy(false) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-0 md:items-center md:p-4" onClick={onClose}>
      <div className="w-full max-w-lg rounded-t-2xl bg-white p-5 shadow-xl md:rounded-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-base font-bold text-gray-900">Nuevo proveedor</h2>
          <button type="button" onClick={onClose} aria-label="Cerrar"><X className="h-5 w-5 text-gray-500" /></button>
        </div>
        <div className="space-y-3">
          <Campo label="Razón social (como en la factura)"><Input value={nombre} onChange={(e) => setNombre(e.target.value)} autoFocus /></Campo>
          <Campo label="RUT"><Input value={rut} onChange={(e) => setRut(e.target.value)} placeholder="76.123.456-7" className={cn(rut.trim() && !rutValido(rut) && 'border-red-400')} /></Campo>
          <Campo label="Rubro">
            <select value={rubro} onChange={(e) => setRubro(e.target.value)} className="h-10 w-full rounded-md border border-gray-300 bg-white px-2 text-sm">
              {RUBROS.map((r) => <option key={r.rubro} value={r.rubro}>{r.rubro}</option>)}
            </select>
          </Campo>
          <Campo label="A qué se dedica"><Input value={giro} onChange={(e) => setGiro(e.target.value)} placeholder="opcional" maxLength={160} /></Campo>
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose} disabled={busy}>Cancelar</Button>
          <Button type="button" onClick={crear} disabled={busy}>{busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Check className="mr-1 h-4 w-4" />} Crear</Button>
        </div>
      </div>
    </div>
  )
}
