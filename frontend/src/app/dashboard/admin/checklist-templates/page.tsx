'use client'

import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import {
  ArrowLeft,
  ClipboardList,
  Plus,
  Trash2,
  Save,
  Camera,
  CheckCircle,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/hooks/use-toast'
import { supabase } from '@/lib/supabase'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
interface ChecklistItem {
  orden: number
  descripcion: string
  obligatorio: boolean
  requiere_foto: boolean
}

interface ChecklistTemplate {
  id: string
  tipo_ot: string
  nombre: string
  descripcion: string | null
  items: ChecklistItem[]
  activo: boolean
  created_at: string
  updated_at: string
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const tipoLabels: Record<string, string> = {
  preventivo: 'Preventivo',
  correctivo: 'Correctivo',
  inspeccion: 'Inspeccion',
  abastecimiento: 'Abastecimiento',
  lubricacion: 'Lubricacion',
  inventario: 'Inventario',
  regularizacion: 'Regularizacion',
}

const tipoBadgeColors: Record<string, string> = {
  preventivo: 'bg-green-100 text-green-700',
  correctivo: 'bg-red-100 text-red-700',
  inspeccion: 'bg-blue-100 text-blue-700',
  abastecimiento: 'bg-amber-100 text-amber-700',
  lubricacion: 'bg-yellow-100 text-yellow-700',
  inventario: 'bg-purple-100 text-purple-700',
  regularizacion: 'bg-orange-100 text-orange-700',
}

// ---------------------------------------------------------------------------
// Template Card Component
// ---------------------------------------------------------------------------
function TemplateCard({
  template,
  onSaved,
}: {
  template: ChecklistTemplate
  onSaved: () => void
}) {
  const [items, setItems] = useState<ChecklistItem[]>(template.items || [])
  const [saving, setSaving] = useState(false)
  const [dirty, setDirty] = useState(false)
  const toast = useToast()

  useEffect(() => {
    setItems(template.items || [])
    setDirty(false)
  }, [template])

  function updateItem(index: number, field: keyof ChecklistItem, value: any) {
    setItems((prev) => {
      const updated = [...prev]
      updated[index] = { ...updated[index], [field]: value }
      return updated
    })
    setDirty(true)
  }

  function addItem() {
    const nextOrden = items.length > 0 ? Math.max(...items.map((i) => i.orden)) + 1 : 1
    setItems((prev) => [
      ...prev,
      { orden: nextOrden, descripcion: '', obligatorio: true, requiere_foto: false },
    ])
    setDirty(true)
  }

  function removeItem(index: number) {
    setItems((prev) => prev.filter((_, i) => i !== index))
    setDirty(true)
  }

  async function handleSave() {
    setSaving(true)
    try {
      // Re-number orden
      const reordered = items.map((item, i) => ({ ...item, orden: i + 1 }))
      const { error } = await supabase
        .from('checklist_templates')
        .update({ items: reordered, updated_at: new Date().toISOString() })
        .eq('id', template.id)

      if (error) throw error
      toast.success('Plantilla guardada correctamente.')
      setDirty(false)
      onSaved()
    } catch (err: any) {
      toast.error(err?.message || 'Error al guardar la plantilla.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Badge className={tipoBadgeColors[template.tipo_ot] || 'bg-gray-100 text-gray-700'}>
              {tipoLabels[template.tipo_ot] || template.tipo_ot}
            </Badge>
            <CardTitle className="text-base">{template.nombre}</CardTitle>
          </div>
          <span className="text-xs text-gray-400">{items.length} items</span>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {items.map((item, index) => (
          <div
            key={index}
            className="flex items-start gap-3 rounded-lg border border-gray-100 p-3"
          >
            <span className="mt-2.5 text-xs font-bold text-gray-400 w-5 shrink-0 text-center">
              {index + 1}
            </span>
            <div className="flex-1 space-y-2">
              <Input
                value={item.descripcion}
                onChange={(e) => updateItem(index, 'descripcion', e.target.value)}
                placeholder="Descripcion del item..."
                className="text-sm"
              />
              <div className="flex items-center gap-4">
                <label className="flex items-center gap-1.5 text-xs text-gray-600 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={item.obligatorio}
                    onChange={(e) => updateItem(index, 'obligatorio', e.target.checked)}
                    className="h-3.5 w-3.5 rounded border-gray-300 text-pillado-green-600 focus:ring-pillado-green-500"
                  />
                  <CheckCircle className="h-3.5 w-3.5" />
                  Obligatorio
                </label>
                <label className="flex items-center gap-1.5 text-xs text-gray-600 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={item.requiere_foto}
                    onChange={(e) => updateItem(index, 'requiere_foto', e.target.checked)}
                    className="h-3.5 w-3.5 rounded border-gray-300 text-pillado-green-600 focus:ring-pillado-green-500"
                  />
                  <Camera className="h-3.5 w-3.5" />
                  Requiere foto
                </label>
              </div>
            </div>
            <button
              onClick={() => removeItem(index)}
              className="mt-2 rounded-md p-1 text-gray-400 hover:bg-red-50 hover:text-red-500"
              title="Eliminar item"
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        ))}

        <div className="flex items-center justify-between pt-2">
          <Button variant="outline" size="sm" onClick={addItem}>
            <Plus className="h-4 w-4 mr-1" />
            Agregar item
          </Button>

          {dirty && (
            <Button size="sm" onClick={handleSave} disabled={saving}>
              {saving ? (
                <Spinner size="sm" className="mr-1" />
              ) : (
                <Save className="h-4 w-4 mr-1" />
              )}
              Guardar cambios
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Main Page
// ---------------------------------------------------------------------------
export default function ChecklistTemplatesPage() {
  const [templates, setTemplates] = useState<ChecklistTemplate[]>([])
  const [loading, setLoading] = useState(true)

  const fetchTemplates = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('checklist_templates')
      .select('*')
      .eq('activo', true)
      .order('tipo_ot')

    if (!error && data) {
      setTemplates(data as ChecklistTemplate[])
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchTemplates()
  }, [fetchTemplates])

  if (loading) {
    return (
      <div className="flex justify-center py-24">
        <Spinner size="lg" className="text-pillado-green-600" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Back link */}
      <Link
        href="/dashboard/admin"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-pillado-green-600"
      >
        <ArrowLeft className="h-4 w-4" />
        Volver a administracion
      </Link>

      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Plantillas de Checklist</h1>
        <p className="mt-1 text-sm text-gray-500">
          Defina los items de checklist por defecto para cada tipo de OT.
          Estos se asignan automaticamente al crear OTs manuales (sin plan PM).
        </p>
      </div>

      {/* Templates */}
      {templates.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <ClipboardList className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <p className="text-gray-500">No hay plantillas de checklist configuradas.</p>
            <p className="text-sm text-gray-400 mt-1">
              Ejecute el script SQL 22_checklist_templates.sql para crear las plantillas iniciales.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-6">
          {templates.map((template) => (
            <TemplateCard key={template.id} template={template} onSaved={fetchTemplates} />
          ))}
        </div>
      )}
    </div>
  )
}
