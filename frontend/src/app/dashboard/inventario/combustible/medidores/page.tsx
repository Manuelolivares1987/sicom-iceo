'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft,
  Plus,
  Gauge,
  Power,
  Trash2,
  AlertCircle,
  CheckCircle2,
  Loader2,
  Camera,
  ImageIcon,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatDate } from '@/lib/utils'
import {
  useEstanques,
  useMedidores,
  useCrearMedidor,
  useUpdateMedidor,
  useDeleteMedidor,
} from '@/hooks/use-combustible'
import {
  uploadEvidenciaCombustible,
  type TipoMedidor,
} from '@/lib/services/combustible'

export default function AdminMedidoresPage() {
  const { data: estanques } = useEstanques()
  const { data: medidores, isLoading } = useMedidores()
  const crear = useCrearMedidor()
  const update = useUpdateMedidor()
  const del = useDeleteMedidor()

  const [formEstanqueId, setFormEstanqueId] = useState<string | null>(null)
  const [tipo, setTipo] = useState<TipoMedidor>('bidireccional')
  const [marca, setMarca] = useState('')
  const [modelo, setModelo] = useState('')
  const [numeroSerie, setNumeroSerie] = useState('')
  const [lectura, setLectura] = useState('')
  const [fotoUrl, setFotoUrl] = useState<string | null>(null)
  const [uploadingFoto, setUploadingFoto] = useState(false)
  const [verFoto, setVerFoto] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [okMsg, setOkMsg] = useState<string | null>(null)

  const porEstanque = useMemo(() => {
    const m = new Map<string, typeof medidores>()
    ;(medidores ?? []).forEach((med) => {
      const arr = m.get(med.estanque_id) ?? []
      arr.push(med)
      m.set(med.estanque_id, arr)
    })
    return m
  }, [medidores])

  function resetForm() {
    setFormEstanqueId(null)
    setTipo('bidireccional')
    setMarca('')
    setModelo('')
    setNumeroSerie('')
    setLectura('')
    setFotoUrl(null)
    setError(null)
  }

  async function handleFoto(file: File) {
    if (!formEstanqueId) {
      setError('Seleccione un estanque primero.')
      return
    }
    setUploadingFoto(true)
    setError(null)
    const { url, error: upErr } = await uploadEvidenciaCombustible(file, {
      tipo: 'medidor',
      estanqueId: formEstanqueId,
    })
    setUploadingFoto(false)
    if (upErr || !url) {
      setError(upErr?.message ?? 'No se pudo subir la foto.')
      return
    }
    setFotoUrl(url)
  }

  async function handleCrear() {
    setError(null)
    if (!formEstanqueId) return setError('Seleccione un estanque.')
    const lect = parseFloat(lectura)
    if (isNaN(lect) || lect < 0)
      return setError('Lectura acumulada actual invalida.')
    if (!fotoUrl)
      return setError('La foto del totalizador es obligatoria al registrar un medidor.')

    try {
      await crear.mutateAsync({
        estanque_id: formEstanqueId,
        tipo,
        marca: marca || null,
        modelo: modelo || null,
        numero_serie: numeroSerie || null,
        lectura_acumulada_actual: lect,
        foto_registro_url: fotoUrl,
      })
      setOkMsg('Medidor creado con evidencia fotografica.')
      setTimeout(() => setOkMsg(null), 3000)
      resetForm()
    } catch (err: any) {
      setError(err?.message ?? 'Error al crear el medidor.')
    }
  }

  async function toggleActivo(id: string, activo: boolean) {
    try {
      await update.mutateAsync({ id, patch: { activo: !activo } })
    } catch (err: any) {
      setError(err?.message ?? 'Error al actualizar.')
    }
  }

  async function eliminar(id: string) {
    setError(null)
    if (!confirm('¿Eliminar este medidor? Solo se puede si no tiene movimientos.')) return
    try {
      await del.mutateAsync(id)
    } catch (err: any) {
      setError(err?.message ?? 'Error al eliminar.')
    }
  }

  return (
    <div className="space-y-4 pb-10">
      <div className="flex items-center gap-3">
        <Link href="/dashboard/inventario/combustible">
          <Button variant="outline" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Volver
          </Button>
        </Link>
        <h1 className="text-xl font-bold text-gray-900">Medidores</h1>
      </div>

      {okMsg && (
        <div className="flex items-center gap-2 rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-700">
          <CheckCircle2 className="h-4 w-4" /> {okMsg}
        </div>
      )}
      {error && (
        <div className="flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          <AlertCircle className="h-4 w-4 flex-shrink-0" />
          <span>{error}</span>
        </div>
      )}

      <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
        <strong>Trazabilidad:</strong> al registrar cualquier medidor se exige una
        foto del totalizador. Esto sella la lectura inicial declarada contra
        adulteraciones posteriores.
      </div>

      {isLoading ? (
        <div className="flex justify-center py-8">
          <Spinner />
        </div>
      ) : (
        <div className="space-y-6">
          {(estanques ?? []).map((e) => {
            const lista = porEstanque.get(e.id) ?? []
            const agregando = formEstanqueId === e.id
            return (
              <div key={e.id} className="space-y-2">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-xs text-gray-500">{e.codigo}</div>
                    <div className="text-base font-semibold text-gray-900">
                      {e.nombre}
                    </div>
                  </div>
                  {!agregando && (
                    <Button
                      size="sm"
                      variant="outline"
                      className="gap-1"
                      onClick={() => {
                        resetForm()
                        setFormEstanqueId(e.id)
                      }}
                    >
                      <Plus className="h-4 w-4" /> Nuevo medidor
                    </Button>
                  )}
                </div>

                {/* Form inline */}
                {agregando && (
                  <Card className="border-blue-200 bg-blue-50/30">
                    <CardContent className="space-y-3 p-4">
                      <div className="grid grid-cols-2 gap-2">
                        <div>
                          <label className="block text-xs font-medium text-gray-600">
                            Marca
                          </label>
                          <Input
                            value={marca}
                            onChange={(ev) => setMarca(ev.target.value)}
                            placeholder="TCS"
                            className="mt-1"
                          />
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-600">
                            Modelo
                          </label>
                          <Input
                            value={modelo}
                            onChange={(ev) => setModelo(ev.target.value)}
                            placeholder="700-20SP4AL"
                            className="mt-1"
                          />
                        </div>
                      </div>
                      <div className="grid grid-cols-2 gap-2">
                        <div>
                          <label className="block text-xs font-medium text-gray-600">
                            N° Serie
                          </label>
                          <Input
                            value={numeroSerie}
                            onChange={(ev) => setNumeroSerie(ev.target.value)}
                            placeholder="855582"
                            className="mt-1"
                          />
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-600">
                            Tipo
                          </label>
                          <select
                            value={tipo}
                            onChange={(ev) => setTipo(ev.target.value as TipoMedidor)}
                            className="mt-1 h-10 w-full rounded-lg border border-gray-300 bg-white px-2 text-sm"
                          >
                            <option value="bidireccional">Bidireccional</option>
                            <option value="ingreso">Solo ingreso</option>
                            <option value="despacho">Solo despacho</option>
                          </select>
                        </div>
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-gray-600">
                          Lectura acumulada actual (totalizador)
                        </label>
                        <Input
                          type="number"
                          step="0.01"
                          value={lectura}
                          onChange={(ev) => setLectura(ev.target.value)}
                          placeholder="3195360"
                          inputMode="decimal"
                          className="mt-1 font-mono text-lg"
                        />
                        <p className="mt-1 text-[11px] text-gray-500">
                          Es el numero grande del totalizador superior del medidor
                          (no el reseteable de abajo). De aqui arrancan las lecturas.
                        </p>
                      </div>

                      {/* Foto obligatoria del totalizador */}
                      <div>
                        <label className="block text-xs font-medium text-gray-600">
                          Foto del totalizador *
                        </label>
                        <p className="mb-2 text-[11px] text-gray-500">
                          Obligatoria: sella la lectura inicial declarada contra
                          adulteraciones posteriores.
                        </p>
                        {fotoUrl ? (
                          <div className="space-y-2">
                            <img
                              src={fotoUrl}
                              alt="Totalizador"
                              className="h-40 w-full rounded-lg border object-cover"
                            />
                            <Button
                              variant="outline"
                              size="sm"
                              className="w-full"
                              onClick={() => setFotoUrl(null)}
                            >
                              Cambiar foto
                            </Button>
                          </div>
                        ) : (
                          <label
                            className={cn(
                              'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed border-gray-300 p-5 text-center',
                              uploadingFoto && 'opacity-60'
                            )}
                          >
                            {uploadingFoto ? (
                              <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
                            ) : (
                              <Camera className="h-6 w-6 text-gray-400" />
                            )}
                            <span className="text-sm font-medium text-gray-700">
                              {uploadingFoto ? 'Subiendo…' : 'Tomar foto'}
                            </span>
                            <span className="text-[11px] text-gray-500">
                              Debe mostrar el totalizador con la lectura declarada
                            </span>
                            <input
                              type="file"
                              accept="image/*"
                              capture="environment"
                              className="hidden"
                              disabled={uploadingFoto}
                              onChange={(ev) => {
                                const f = ev.target.files?.[0]
                                if (f) handleFoto(f)
                              }}
                            />
                          </label>
                        )}
                      </div>

                      <div className="flex gap-2 pt-1">
                        <Button
                          onClick={handleCrear}
                          disabled={crear.isPending || !fotoUrl}
                          className="flex-1"
                        >
                          {crear.isPending ? (
                            <>
                              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                              Creando…
                            </>
                          ) : (
                            'Guardar medidor'
                          )}
                        </Button>
                        <Button
                          variant="outline"
                          className="flex-1"
                          onClick={resetForm}
                        >
                          Cancelar
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                )}

                {/* Lista */}
                {lista.length === 0 && !agregando ? (
                  <Card>
                    <CardContent className="py-4 text-center text-xs text-gray-500">
                      Sin medidores. Agregá uno para habilitar los movimientos de este estanque.
                    </CardContent>
                  </Card>
                ) : (
                  <div className="space-y-2">
                    {lista.map((m) => (
                      <Card key={m.id} className={cn(!m.activo && 'opacity-60')}>
                        <CardContent className="flex items-center gap-3 p-3">
                          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-blue-100">
                            <Gauge className="h-5 w-5 text-blue-600" />
                          </div>
                          <div className="min-w-0 flex-1">
                            <div className="flex flex-wrap items-center gap-2">
                              <span className="text-sm font-semibold text-gray-900">
                                {m.marca ?? 'Medidor'} {m.modelo ?? ''}
                              </span>
                              {m.numero_serie && (
                                <Badge className="bg-gray-100 text-gray-700 hover:bg-gray-100">
                                  S/N {m.numero_serie}
                                </Badge>
                              )}
                              <Badge
                                className={cn(
                                  m.activo
                                    ? 'bg-green-100 text-green-700 hover:bg-green-100'
                                    : 'bg-gray-100 text-gray-600 hover:bg-gray-100'
                                )}
                              >
                                {m.activo ? 'Activo' : 'Inactivo'}
                              </Badge>
                            </div>
                            <div className="mt-0.5 flex flex-wrap gap-3 text-xs text-gray-500">
                              <span>
                                Tipo: <span className="capitalize">{m.tipo}</span>
                              </span>
                              <span>
                                Lectura:{' '}
                                <span className="font-mono font-semibold">
                                  {Number(m.lectura_acumulada_actual).toLocaleString(
                                    'es-CL',
                                    { maximumFractionDigits: 2 }
                                  )}
                                </span>
                              </span>
                              {m.fecha_ultima_lectura && (
                                <span>
                                  Ult. mov.: {formatDate(m.fecha_ultima_lectura)}
                                </span>
                              )}
                            </div>
                          </div>
                          {m.foto_registro_url && (
                            <button
                              onClick={() => setVerFoto(m.foto_registro_url!)}
                              className="rounded p-2 text-blue-500 hover:bg-blue-50"
                              title="Ver foto de registro"
                            >
                              <ImageIcon className="h-4 w-4" />
                            </button>
                          )}
                          <button
                            onClick={() => toggleActivo(m.id, m.activo)}
                            className="rounded p-2 text-gray-500 hover:bg-gray-100"
                            title={m.activo ? 'Desactivar' : 'Activar'}
                          >
                            <Power className="h-4 w-4" />
                          </button>
                          <button
                            onClick={() => eliminar(m.id)}
                            className="rounded p-2 text-red-500 hover:bg-red-50"
                            title="Eliminar"
                          >
                            <Trash2 className="h-4 w-4" />
                          </button>
                        </CardContent>
                      </Card>
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}

      {/* Modal de visualizacion de foto */}
      {verFoto && (
        <div
          onClick={() => setVerFoto(null)}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
        >
          <img
            src={verFoto}
            alt="Foto de registro del medidor"
            className="max-h-[90vh] max-w-full rounded-lg"
          />
          <button
            onClick={() => setVerFoto(null)}
            className="absolute right-4 top-4 rounded-full bg-white/90 px-3 py-1 text-sm font-medium"
          >
            Cerrar
          </button>
        </div>
      )}
    </div>
  )
}
