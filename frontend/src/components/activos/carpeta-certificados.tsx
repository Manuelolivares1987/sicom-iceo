'use client'

// Carpeta del equipo (MIG219): certificados que Pillado emite al cliente.
// Se habilitan cuando el equipo no tiene NC abiertas; cada certificado lo
// firma el operador que hizo el trabajo y el jefe de taller.
import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Award, Printer, Plus, AlertTriangle, CheckCircle2 } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/contexts/toast-context'
import { supabase } from '@/lib/supabase'
import { formatDate } from '@/lib/utils'
import {
  getCertificadoTipos, getCertificadosActivo, getNcAbiertasActivo, getTecnicosTaller,
  emitirCertificado, type CertificadoTipo,
} from '@/lib/services/certificados-activo'

type ActivoLite = {
  nombre: string | null
  patente: string | null
  codigo: string
  modelo?: { nombre: string; marca?: { nombre: string } | null } | null
}

async function getActivoLite(activoId: string): Promise<ActivoLite | null> {
  const { data, error } = await supabase.from('activos')
    .select('nombre, patente, codigo, modelo:modelos(nombre, marca:marcas(nombre))')
    .eq('id', activoId).maybeSingle()
  if (error) throw error
  return (data as unknown as ActivoLite | null) ?? null
}

export function CarpetaCertificados({ activoId }: { activoId: string }) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: certs, isLoading } = useQuery({
    queryKey: ['activo-certificados', activoId],
    queryFn: () => getCertificadosActivo(activoId),
  })
  const { data: ncAbiertas } = useQuery({
    queryKey: ['activo-nc-abiertas', activoId],
    queryFn: () => getNcAbiertasActivo(activoId),
  })
  const { data: tipos } = useQuery({ queryKey: ['certificado-tipos'], queryFn: getCertificadoTipos, staleTime: 300_000 })
  const { data: tecnicos } = useQuery({ queryKey: ['taller-tecnicos-cert'], queryFn: getTecnicosTaller, staleTime: 300_000 })
  const { data: activo } = useQuery({ queryKey: ['activo-lite-cert', activoId], queryFn: () => getActivoLite(activoId) })

  const [abierto, setAbierto] = useState(false)
  const [tipoCodigo, setTipoCodigo] = useState('')
  const tipo: CertificadoTipo | undefined = useMemo(
    () => (tipos ?? []).find((t) => t.codigo === tipoCodigo), [tipos, tipoCodigo])

  const [datos, setDatos] = useState<Record<string, string>>({})
  const [fecha, setFecha] = useState('')
  const [operadorId, setOperadorId] = useState('')
  const [operadorNombre, setOperadorNombre] = useState('')
  const [firmaOperador, setFirmaOperador] = useState('')
  const [firmaJefe, setFirmaJefe] = useState('')

  const bloqueado = (ncAbiertas ?? 0) > 0

  function abrirModal() {
    const hoy = new Date().toISOString().slice(0, 10)
    setTipoCodigo(''); setFecha(hoy)
    setDatos({
      equipo: activo?.nombre ?? '',
      marca: activo?.modelo?.marca?.nombre ?? '',
      modelo: activo?.modelo?.nombre ?? '',
      patente: activo?.patente ?? activo?.codigo ?? '',
    })
    setOperadorId(''); setOperadorNombre(''); setFirmaOperador(''); setFirmaJefe('')
    setAbierto(true)
  }

  const emitir = useMutation({
    mutationFn: emitirCertificado,
    onSuccess: (r) => {
      toast.success(`Certificado N° ${String(r.numero).padStart(2, '0')} emitido`)
      qc.invalidateQueries({ queryKey: ['activo-certificados', activoId] })
      setAbierto(false)
      window.open(`/certificado/${r.certificado_id}`, '_blank')
    },
    onError: (e) => toast.error((e as Error).message),
  })

  function confirmarEmision() {
    if (!tipo) { toast.error('Elige el tipo de certificado'); return }
    const nombreOp = operadorId
      ? (tecnicos ?? []).find((t) => t.id === operadorId)?.nombre ?? operadorNombre
      : operadorNombre
    if (!nombreOp.trim()) { toast.error('Indica el operador que realizó el trabajo'); return }
    if (!firmaOperador || !firmaJefe) { toast.error('Faltan firmas: el certificado lo firman el operador Y el jefe de taller'); return }
    emitir.mutate({
      activoId, tipoCodigo: tipo.codigo, datos,
      operadorNombre: nombreOp.trim(), operadorTecnicoId: operadorId || null,
      firmaOperadorDataUrl: firmaOperador, firmaJefeDataUrl: firmaJefe,
      fechaEmision: fecha || null,
    })
  }

  const camposBase = [
    { key: 'equipo', label: 'Equipo' },
    { key: 'marca', label: 'Marca' },
    { key: 'modelo', label: 'Modelo' },
    { key: 'patente', label: 'Placa patente' },
  ]

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="flex items-center gap-1.5 text-base font-semibold">
            <Award className="h-4 w-4 text-emerald-600" /> Carpeta del equipo — certificados
          </h3>
          <p className="text-xs text-muted-foreground">
            Certificados Pillado firmados por el operador y el jefe de taller. Se habilitan al resolver todas las NC.
          </p>
        </div>
        <Button size="sm" onClick={abrirModal} disabled={bloqueado}
                title={bloqueado ? 'El equipo tiene NC abiertas' : 'Emitir un certificado del equipo'}>
          <Plus className="h-4 w-4 mr-1" /> Emitir certificado
        </Button>
      </div>

      {bloqueado ? (
        <div className="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          El equipo tiene <b>{ncAbiertas}</b> No Conformidad{(ncAbiertas ?? 0) > 1 ? 'es' : ''} abierta{(ncAbiertas ?? 0) > 1 ? 's' : ''} —
          los certificados se habilitan cuando se resuelvan todas.
        </div>
      ) : (
        <div className="flex items-center gap-2 rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-2 text-xs text-emerald-800">
          <CheckCircle2 className="h-4 w-4 shrink-0" />
          Sin NC abiertas: el equipo puede certificarse.
        </div>
      )}

      {isLoading ? (
        <div className="flex justify-center py-6"><Spinner /></div>
      ) : (certs ?? []).length === 0 ? (
        <p className="py-4 text-center text-sm text-gray-400">Aún no hay certificados emitidos para este equipo.</p>
      ) : (
        <div className="space-y-2">
          {(certs ?? []).map((c) => (
            <Card key={c.id}>
              <CardContent className="flex items-center gap-3 p-3">
                <span className="font-mono text-xs font-bold text-gray-500">
                  {String(c.numero).padStart(2, '0')}
                </span>
                <div className="flex-1 min-w-0">
                  <div className="truncate text-sm font-semibold text-gray-900">{c.titulo}</div>
                  <div className="text-[11px] text-gray-500">
                    {formatDate(c.fecha_emision)} · operador {c.operador_nombre} · jefe {c.jefe_nombre}
                    {c.ot_folio && <> · OT {c.ot_folio}</>}
                  </div>
                </div>
                <Button variant="outline" size="sm" onClick={() => window.open(`/certificado/${c.id}`, '_blank')}>
                  <Printer className="h-4 w-4 mr-1" /> Ver / Imprimir
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Modal de emisión */}
      {abierto && (
        <Modal open onClose={() => setAbierto(false)} title="Emitir certificado del equipo">
          <div className="space-y-3">
            <div>
              <label className="text-xs font-medium">Tipo de certificado</label>
              <select value={tipoCodigo} onChange={(e) => setTipoCodigo(e.target.value)}
                      className="w-full rounded border px-2 py-1.5 text-sm">
                <option value="">— Elegir —</option>
                {(tipos ?? []).map((t) => <option key={t.codigo} value={t.codigo}>{t.titulo}</option>)}
              </select>
            </div>

            {tipo && (
              <>
                <div className="grid grid-cols-2 gap-2">
                  {camposBase.map((c) => (
                    <div key={c.key}>
                      <label className="text-xs font-medium text-gray-600">{c.label}</label>
                      <input className="w-full rounded border px-2 py-1.5 text-sm"
                             value={datos[c.key] ?? ''}
                             onChange={(e) => setDatos((p) => ({ ...p, [c.key]: e.target.value }))} />
                    </div>
                  ))}
                  {(tipo.campos ?? []).map((c) => (
                    <div key={c.key}>
                      <label className="text-xs font-medium text-gray-600">{c.label}</label>
                      <input className="w-full rounded border px-2 py-1.5 text-sm"
                             type={c.tipo === 'date' ? 'date' : c.tipo === 'number' ? 'number' : 'text'}
                             value={datos[c.key] ?? ''}
                             onChange={(e) => setDatos((p) => ({ ...p, [c.key]: e.target.value }))} />
                    </div>
                  ))}
                  <div>
                    <label className="text-xs font-medium text-gray-600">Fecha de emisión</label>
                    <input type="date" className="w-full rounded border px-2 py-1.5 text-sm"
                           value={fecha} onChange={(e) => setFecha(e.target.value)} />
                  </div>
                  <div>
                    <label className="text-xs font-medium text-gray-600">Operador que realizó el trabajo</label>
                    <select value={operadorId} onChange={(e) => setOperadorId(e.target.value)}
                            className="w-full rounded border px-2 py-1.5 text-sm">
                      <option value="">Otro (escribir abajo)</option>
                      {(tecnicos ?? []).map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}
                    </select>
                    {!operadorId && (
                      <input className="mt-1 w-full rounded border px-2 py-1.5 text-sm" placeholder="Nombre del operador"
                             value={operadorNombre} onChange={(e) => setOperadorNombre(e.target.value)} />
                    )}
                  </div>
                </div>

                <SignaturePad label="Firma del operador (obligatoria)" onCapture={setFirmaOperador} />
                <SignaturePad label="Firma del jefe de taller (obligatoria)" onCapture={setFirmaJefe} />
              </>
            )}
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setAbierto(false)}>Cancelar</Button>
            <Button disabled={!tipo || !firmaOperador || !firmaJefe || emitir.isPending} onClick={confirmarEmision}>
              {emitir.isPending ? <Spinner className="h-4 w-4 mr-1" /> : <Award className="h-4 w-4 mr-1" />}
              Emitir y ver certificado
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
