'use client'

import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import Link from 'next/link'
import { ArrowLeft, Plus, Tag, Check, X, Pencil } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getCategoriasProducto, crearCategoria, actualizarCategoria, slugCategoria, type ProductoCategoria,
} from '@/lib/services/producto-categorias'

export default function CategoriasProductoPage() {
  useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const { data: cats = [], isLoading } = useQuery({ queryKey: ['producto-categorias'], queryFn: () => getCategoriasProducto(false) })
  const [nuevo, setNuevo] = useState('')
  const [saving, setSaving] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [editNombre, setEditNombre] = useState('')

  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ['producto-categorias'] })
    qc.invalidateQueries({ queryKey: ['producto-categorias-activas'] })
  }

  const agregar = async () => {
    if (!nuevo.trim()) return
    setSaving(true)
    try {
      await crearCategoria(nuevo)
      toast.success('Categoría creada')
      setNuevo(''); invalidar()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setSaving(false) }
  }

  const guardarNombre = async (c: ProductoCategoria) => {
    try {
      await actualizarCategoria(c.codigo, { nombre: editNombre.trim() || c.nombre })
      toast.success('Categoría actualizada')
      setEditId(null); invalidar()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') }
  }

  const toggle = async (c: ProductoCategoria) => {
    try {
      await actualizarCategoria(c.codigo, { activo: !c.activo })
      invalidar()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') }
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <Link href="/dashboard/inventario/cargar-maestro" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"><ArrowLeft className="h-4 w-4" /> Volver a cargar maestro</Link>
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2"><Tag className="h-6 w-6 text-indigo-600" /> Categorías de productos</h1>
        <p className="text-sm text-muted-foreground">Catálogo editable. Las categorías se usan al cargar el maestro y al crear productos.</p>
      </div>

      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-sm flex items-center gap-2"><Plus className="h-4 w-4" /> Nueva categoría</CardTitle></CardHeader>
        <CardContent>
          <div className="flex gap-2">
            <input value={nuevo} onChange={(e) => setNuevo(e.target.value)} placeholder="Ej: Artículos de ferretería"
              className="flex-1 rounded border px-3 py-2 text-sm" onKeyDown={(e) => e.key === 'Enter' && agregar()} />
            <Button onClick={agregar} disabled={saving || !nuevo.trim()}>{saving ? 'Creando…' : 'Crear'}</Button>
          </div>
          {nuevo.trim() && <p className="text-[11px] text-muted-foreground mt-1">Código: <code>{slugCategoria(nuevo)}</code></p>}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          {isLoading && <div className="p-4"><Spinner className="h-5 w-5" /></div>}
          <table className="w-full text-sm">
            <thead><tr className="text-xs text-muted-foreground border-b"><th className="text-left p-2">Nombre</th><th className="text-left p-2">Código</th><th className="p-2">Estado</th><th className="p-2"></th></tr></thead>
            <tbody>
              {cats.map((c) => (
                <tr key={c.codigo} className="border-b">
                  <td className="p-2">
                    {editId === c.codigo
                      ? <input autoFocus value={editNombre} onChange={(e) => setEditNombre(e.target.value)} className="rounded border px-2 py-1 text-sm w-full" />
                      : <span className={c.activo ? '' : 'text-muted-foreground line-through'}>{c.nombre}</span>}
                  </td>
                  <td className="p-2"><code className="text-xs text-muted-foreground">{c.codigo}</code></td>
                  <td className="p-2 text-center"><Badge variant={c.activo ? 'operativo' : 'default'} className="text-[10px]">{c.activo ? 'Activa' : 'Inactiva'}</Badge></td>
                  <td className="p-2 text-right whitespace-nowrap">
                    {editId === c.codigo ? (
                      <>
                        <Button size="sm" variant="outline" onClick={() => guardarNombre(c)}><Check className="h-3.5 w-3.5" /></Button>
                        <Button size="sm" variant="outline" className="ml-1" onClick={() => setEditId(null)}><X className="h-3.5 w-3.5" /></Button>
                      </>
                    ) : (
                      <>
                        <Button size="sm" variant="outline" onClick={() => { setEditId(c.codigo); setEditNombre(c.nombre) }}><Pencil className="h-3.5 w-3.5" /></Button>
                        <Button size="sm" variant="outline" className="ml-1" onClick={() => toggle(c)}>{c.activo ? 'Desactivar' : 'Activar'}</Button>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}
