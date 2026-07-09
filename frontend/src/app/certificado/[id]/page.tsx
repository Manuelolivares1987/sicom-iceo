'use client'

// Certificado del equipo imprimible (MIG219), formato papel Pillado:
// membrete, ciudad/fecha, título, párrafo de certificación, datos del
// equipo, y firmas del OPERADOR que hizo el trabajo y del JEFE de taller.

import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { Printer } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getCertificadoById, type ActivoCertificado, type CertificadoCampo } from '@/lib/services/certificados-activo'

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']

function fechaLarga(iso: string): string {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number)
  return `${String(d).padStart(2, '0')} de ${MESES[(m ?? 1) - 1]} de ${y}`
}

function valorCampo(v: string | undefined, tipo?: string): string {
  if (!v) return '—'
  if (tipo === 'date' && /^\d{4}-\d{2}-\d{2}/.test(v)) {
    const [y, m, d] = v.slice(0, 10).split('-')
    return `${d}/${m}/${y}`
  }
  return v
}

export default function CertificadoImprimiblePage() {
  const params = useParams()
  const certId = params?.id as string
  const [sesionOk, setSesionOk] = useState<boolean | null>(null)
  const [cert, setCert] = useState<ActivoCertificado | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancel = false
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!cancel) setSesionOk(!!session)
    })
    return () => { cancel = true }
  }, [])

  useEffect(() => {
    if (sesionOk !== true || !certId) return
    let cancel = false
    ;(async () => {
      try {
        const c = await getCertificadoById(certId)
        if (cancel) return
        if (!c) { setError('Certificado no encontrado'); return }
        setCert(c)
      } catch (e) { if (!cancel) setError((e as Error).message) }
    })()
    return () => { cancel = true }
  }, [sesionOk, certId])

  if (sesionOk === null) return <div className="py-20 text-center text-gray-400">Verificando acceso…</div>
  if (sesionOk === false) {
    return (
      <div className="py-20 text-center">
        <p className="text-sm text-gray-600">El certificado requiere iniciar sesión.</p>
        <a href={`/login?next=${encodeURIComponent(`/certificado/${certId}`)}`}
           className="mt-4 inline-block rounded-lg bg-[#0b2a4a] px-5 py-2 text-sm font-semibold text-white">
          Iniciar sesión
        </a>
      </div>
    )
  }
  if (error) return <div className="py-20 text-center text-sm text-red-600">{error}</div>
  if (!cert) return <div className="py-20 text-center text-gray-400">Cargando certificado…</div>

  const datos = cert.datos ?? {}
  const camposBase: CertificadoCampo[] = [
    { key: 'equipo', label: 'Equipo' },
    { key: 'marca', label: 'Marca' },
    { key: 'modelo', label: 'Modelo' },
    { key: 'patente', label: 'Placa patente' },
  ]
  const campos = [...camposBase, ...(cert.campos ?? [])]

  return (
    <div className="mx-auto max-w-2xl bg-white p-6 print:max-w-full print:p-0">
      <style jsx global>{`
        @media print {
          @page { size: letter portrait; margin: 12mm 14mm; }
          html, body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
          .cert-doc { font-size: 13px; }
          .cert-firmas { break-inside: avoid; }
        }
      `}</style>

      {/* Barra de acciones (no se imprime) */}
      <div className="mb-4 flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 print:hidden">
        <p className="text-sm text-gray-600">
          Certificado N° {String(cert.numero).padStart(2, '0')} · {cert.activo_patente ?? cert.activo_codigo} — usa «Guardar como PDF» para archivarlo.
        </p>
        <button onClick={() => window.print()}
                className="flex items-center gap-1.5 rounded-lg bg-[#0b2a4a] px-4 py-2 text-sm font-semibold text-white">
          <Printer className="h-4 w-4" /> Imprimir
        </button>
      </div>

      {/* Certificado */}
      <div className="cert-doc flex min-h-[240mm] flex-col px-2 font-serif text-gray-900">
        {/* Membrete */}
        <div className="flex items-end justify-between">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo.jpg" alt="Pillado Empresas" className="h-16 object-contain print:h-14" />
          <p className="text-sm">{cert.ciudad}, {fechaLarga(cert.fecha_emision)}</p>
        </div>

        {/* Título */}
        <h1 className="mt-8 text-center text-2xl font-semibold tracking-wide print:text-xl">
          {cert.titulo}.
        </h1>

        {/* Párrafo de certificación */}
        <p className="mt-6 text-justify leading-relaxed">{cert.cuerpo}</p>

        {/* Sección + datos */}
        {cert.seccion && <p className="mt-8 underline underline-offset-4">{cert.seccion}:</p>}
        <ul className="mt-6 space-y-2.5 pl-10">
          {campos.map((c) => {
            const v = valorCampo(datos[c.key], c.tipo)
            if (v === '—' && !['equipo', 'marca', 'modelo', 'patente'].includes(c.key)) return null
            return (
              <li key={c.key} className={`list-['▪__'] ${c.destacado ? 'font-semibold' : ''}`}>
                {c.label}: <span className="font-bold">{v}</span>
              </li>
            )
          })}
        </ul>

        {/* Cierre */}
        <p className="mt-10 text-justify">
          Este documento se emite a petición del cliente, para los fines que estime convenientes.
        </p>
        <p className="mt-3">Atte.</p>

        {/* Firmas: operador + jefe de taller */}
        <div className="cert-firmas mt-14 grid grid-cols-2 gap-10">
          <div className="text-center">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={cert.firma_operador_url} alt="firma operador" className="mx-auto h-20 object-contain print:h-16" />
            <div className="mx-6 border-t border-gray-800 pt-2 italic">
              <p>{cert.operador_nombre}</p>
              <p>Operador de Taller</p>
              <p>Pillado y Cía. Ltda.</p>
            </div>
          </div>
          <div className="text-center">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={cert.firma_jefe_url} alt="firma jefe" className="mx-auto h-20 object-contain print:h-16" />
            <div className="mx-6 border-t border-gray-800 pt-2 italic">
              <p>{cert.jefe_nombre}</p>
              <p>Jefe de Mantenimiento</p>
              <p>Pillado y Cía. Ltda.</p>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="mt-auto pt-10">
          <div className="flex justify-between border-t border-gray-300 pt-2 text-xs italic text-gray-700">
            <span>Fono: 051 – 2232159</span>
            <span>contacto@pilladoempresas.cl</span>
            <span>www.pilladoempresas.cl</span>
          </div>
          <div className="mt-1 flex h-1.5">
            <div className="flex-1 bg-orange-500" />
            <div className="flex-1 bg-gray-400" />
            <div className="flex-1 bg-green-600" />
          </div>
        </div>
      </div>
    </div>
  )
}
