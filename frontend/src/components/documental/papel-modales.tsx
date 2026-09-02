'use client'

/**
 * [MIG486] Corregir y anular un papel del equipo.
 *
 * Vive acá y no dentro de una pantalla porque se usa en los tres lugares donde
 * se mira la documentación de un camión: Control documental, la ficha del activo
 * y la bitácora. Tres copias del mismo modal es la forma más rápida de que tres
 * pantallas terminen aplicando reglas distintas sobre el mismo papel.
 */

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import {
  TIPO_DOC, nombrePapel, getTiposOtrosUsados,
  editarCertificacion, anularCertificacion, restaurarCertificacion, getAnuladosEquipo,
  getCertificacion,
} from '@/lib/services/control-documental'

/**
 * Lo mínimo que hay que saber de un papel para corregirlo o anularlo.
 *
 * A propósito no es `PapelEquipo`: la bitácora y la ficha del activo traen el
 * mismo documento con otra forma, y obligarlas a inventar campos que no usan
 * sería pedirles que mientan.
 */
export type PapelEditable = {
  certificacion_id: string
  patente: string
  /**
   * El tipo, si quien abre el modal lo tiene. La bitácora no: ahí el documento
   * es un evento con título y fecha. Cuando falta, el modal busca el papel.
   */
  tipo?: string
  tipo_otro?: string | null
  etiqueta?: string | null
  fecha_emision?: string | null
  fecha_vencimiento?: string | null
  numero_certificado?: string | null
  entidad_certificadora?: string | null
}

/**
 * [MIG486] Corregir un papel mal cargado.
 *
 * No es lo mismo que renovar: renovar carga la versión SIGUIENTE del documento
 * y deja la anterior en el historial. Esto arregla la fila que ya está — el tipo
 * equivocado, la fecha mal tecleada, el número que faltaba— sin inventar una
 * versión nueva que nunca existió en la realidad.
 *
 * Todo cambio queda en `certificacion_ediciones` con el antes y el después:
 * mover el vencimiento de un papel mueve el semáforo de un camión, y quién lo
 * movió no puede depender de la memoria de nadie.
 */
export function ModalCorregirPapel({ p, onClose, onListo }: {
  p: PapelEditable; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  // Si vino sin tipo (la bitácora), se busca el papel: corregir con un tipo
  // inventado le cambiaría la categoría al documento sin que nadie lo pidiera.
  const { data: real, isLoading: cargando } = useQuery({
    queryKey: ['certificacion', p.certificacion_id],
    queryFn: () => getCertificacion(p.certificacion_id),
    enabled: !p.tipo,
  })

  const [tipo, setTipo] = useState(p.tipo ?? '')
  const [tipoOtro, setTipoOtro] = useState(p.tipo_otro ?? '')
  const [emi, setEmi] = useState(p.fecha_emision ?? '')
  const [venc, setVenc] = useState(
    p.fecha_vencimiento && p.fecha_vencimiento < '2099-01-01' ? p.fecha_vencimiento : '')
  const [numero, setNumero] = useState(p.numero_certificado ?? '')
  const [entidad, setEntidad] = useState(p.entidad_certificadora ?? '')
  const [motivo, setMotivo] = useState('')
  const [busy, setBusy] = useState(false)

  // Una sola vez, cuando llega el papel de la base.
  const [cargado, setCargado] = useState(!!p.tipo)
  if (!cargado && real) {
    setCargado(true)
    setTipo(real.tipo)
    setTipoOtro(real.tipo_otro ?? '')
    setEmi(real.fecha_emision ?? '')
    setVenc(real.fecha_vencimiento && real.fecha_vencimiento < '2099-01-01'
              ? real.fecha_vencimiento : '')
    setNumero(real.numero_certificado ?? '')
    setEntidad(real.entidad_certificadora ?? '')
  }

  const { data: otrosUsados = [] } = useQuery({
    queryKey: ['tipos-otros-usados'], queryFn: getTiposOtrosUsados, staleTime: 5 * 60_000,
  })

  const opciones = useMemo(
    () => Object.entries(TIPO_DOC).map(([value, label]) => ({ value, label }))
      .sort((a, b) => a.label.localeCompare(b.label, 'es')), [])

  const faltaNombre = tipo === 'otra' && tipoOtro.trim().length < 3

  const guardar = async () => {
    setBusy(true)
    try {
      await editarCertificacion({
        certificacionId: p.certificacion_id,
        tipo, tipoOtro: tipo === 'otra' ? tipoOtro.trim() : null,
        fechaEmision: emi || null,
        fechaVencimiento: venc || null,
        numero, entidad, motivo,
      })
      toast.success('Documento corregido')
      onListo()
    } catch (e) {
      toast.error((e as Error).message)
    } finally { setBusy(false) }
  }

  if (cargando || !cargado) {
    return (
      <Modal open onClose={onClose} title={`Corregir · ${p.patente}`}>
        <div className="py-10 text-center"><Spinner /></div>
      </Modal>
    )
  }

  return (
    <Modal open onClose={onClose}
           title={`Corregir · ${nombrePapel({ ...p, tipo })} · ${p.patente}`}>
      <div className="space-y-3">
        <p className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-[11px] text-blue-900">
          Esto arregla el papel que ya está cargado. Si lo que tienes es la versión
          nueva del documento, no lo corrijas: usa <b>«Subir el papel nuevo»</b>, que
          conserva el anterior en el historial.
        </p>

        <div>
          <label className="text-xs font-medium text-gray-600">Tipo de documento</label>
          <select className="mt-1 w-full rounded border px-2 py-1.5 text-sm"
                  value={tipo} onChange={(e) => setTipo(e.target.value)}>
            {opciones.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
        </div>

        {tipo === 'otra' && (
          <div>
            <label className="text-xs font-medium text-gray-600">
              ¿Qué certificado es? <span className="text-red-600">*</span>
            </label>
            <input list="tipos-otros-corregir" value={tipoOtro}
                   onChange={(e) => setTipoOtro(e.target.value)}
                   className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
            <datalist id="tipos-otros-corregir">
              {otrosUsados.map((o: { nombre: string }) => <option key={o.nombre} value={o.nombre} />)}
            </datalist>
          </div>
        )}

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs font-medium text-gray-600">Emisión</label>
            <input type="date" value={emi} onChange={(e) => setEmi(e.target.value)}
                   className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-600">Vencimiento</label>
            <input type="date" value={venc} onChange={(e) => setVenc(e.target.value)}
                   className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-600">N° de certificado</label>
            <input value={numero} onChange={(e) => setNumero(e.target.value)}
                   className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-600">Entidad</label>
            <input value={entidad} onChange={(e) => setEntidad(e.target.value)}
                   className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          </div>
        </div>

        <div>
          <label className="text-xs font-medium text-gray-600">¿Qué estabas corrigiendo?</label>
          <input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                 placeholder="Ej: la fecha venía mal del PDF"
                 className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          <p className="mt-1 text-[11px] text-gray-500">
            Queda guardado junto con lo que decía antes.
          </p>
        </div>
      </div>

      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button onClick={guardar} disabled={busy || faltaNombre}>
          {busy ? 'Guardando…' : 'Guardar la corrección'}
        </Button>
      </ModalFooter>
    </Modal>
  )
}

/**
 * [MIG486] Sacar un papel de circulación.
 *
 * No borra. Estos documentos son la prueba de qué se declaró vigente y cuándo;
 * con contratos que tienen multas de por medio, borrar la fila deja al sistema
 * sin cómo explicar por qué el semáforo estaba verde el mes pasado.
 *
 * Y si había una versión anterior del mismo papel, esa vuelve a ser la vigente:
 * anular el equivocado no deja al equipo sin documento.
 */
export function ModalAnularPapel({ p, onClose, onListo }: {
  p: PapelEditable; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  const [motivo, setMotivo] = useState('')
  const [busy, setBusy] = useState(false)

  const anular = async () => {
    setBusy(true)
    try {
      const r = await anularCertificacion(p.certificacion_id, motivo)
      toast.success(r.vuelve_a_vigente
        ? `Anulado. Vuelve a quedar vigente el anterior (vence ${r.vuelve_a_vigente}).`
        : 'Anulado. El equipo queda sin este documento.')
      onListo()
    } catch (e) {
      toast.error((e as Error).message)
    } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose}
           title={`Anular · ${nombrePapel({ ...p, tipo: p.tipo ?? 'otra' })} · ${p.patente}`}>
      <div className="space-y-3">
        <p className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          El papel sale de la carpeta del equipo, del QR del cliente y de los conteos.
          <b> No se borra</b>: queda registrado quién lo anuló, cuándo y por qué, porque
          es la prueba de lo que se declaró vigente en su momento. Se puede deshacer.
        </p>
        <div>
          <label className="text-xs font-medium text-gray-600">
            ¿Por qué se anula? <span className="text-red-600">*</span>
          </label>
          <textarea rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)}
                    placeholder="Ej: se cargó el archivo del camión equivocado"
                    className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button onClick={anular} disabled={busy || motivo.trim().length < 5}
                className="bg-red-600 hover:bg-red-700">
          {busy ? 'Anulando…' : 'Anular el documento'}
        </Button>
      </ModalFooter>
    </Modal>
  )
}

/** [MIG486] Lo que se sacó de circulación, para poder devolverlo. */
export function ModalAnulados({ activoId, patente, onClose, onListo }: {
  activoId: string; patente: string; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const { data: lista = [], isLoading } = useQuery({
    queryKey: ['papeles-anulados', activoId],
    queryFn: () => getAnuladosEquipo(activoId),
  })

  const devolver = async (id: string) => {
    try {
      await restaurarCertificacion(id)
      toast.success('El documento vuelve a la carpeta del equipo')
      qc.invalidateQueries({ queryKey: ['papeles-anulados', activoId] })
      onListo()
    } catch (e) { toast.error((e as Error).message) }
  }

  return (
    <Modal open onClose={onClose} title={`Documentos anulados · ${patente}`}>
      {isLoading ? <div className="py-8 text-center"><Spinner /></div>
        : lista.length === 0 ? (
          <p className="py-6 text-center text-sm text-gray-500">
            Este equipo no tiene documentos anulados.
          </p>
        ) : (
          <div className="space-y-2">
            {lista.map((a) => (
              <div key={a.id} className="rounded-lg border border-gray-200 bg-gray-50 p-2.5">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-semibold text-gray-800">{a.etiqueta}</span>
                  {a.fecha_vencimiento && (
                    <span className="text-[11px] text-gray-500">vencía {a.fecha_vencimiento}</span>
                  )}
                  {a.archivo_url && (
                    <a href={a.archivo_url} target="_blank" rel="noreferrer"
                       className="text-[11px] font-medium text-blue-600 hover:underline">
                      Ver el archivo
                    </a>
                  )}
                  <Button size="sm" variant="outline" className="ml-auto h-7 text-xs"
                          onClick={() => devolver(a.id)}>
                    <RotateCcw className="mr-1 h-3 w-3" /> Devolver
                  </Button>
                </div>
                <p className="mt-1 text-[11px] text-gray-600">
                  {a.anulado_motivo}
                  <span className="text-gray-400">
                    {' · '}{a.anulado_por ?? 'alguien'}, {a.anulado_at.slice(0, 10)}
                  </span>
                </p>
              </div>
            ))}
          </div>
        )}
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
      </ModalFooter>
    </Modal>
  )
}
