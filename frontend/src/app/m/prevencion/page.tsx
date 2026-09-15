'use client'

// ============================================================================
// Prevención en el teléfono — carga directa del supervisor (MIG546)
// ----------------------------------------------------------------------------
// El flujo que pidió prevención en su levantamiento:
//   Supervisor → carga directa del registro → repositorio centralizado →
//   consolidación automática → Informe de Gestión Mensual.
// Sin este canal, cada RIT/VAT/VCT se pide por correo a fin de mes.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { CheckCircle2, ChevronRight, ClipboardList, HardHat, Leaf, Loader2, Paperclip, Plus, ShieldCheck, Trash2, Users } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Modal } from '@/components/ui/modal'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import { RegistroTerrenoForm } from '@/components/prevencion/registro-terreno-form'
import { AmbientalForm } from '@/components/prevencion/ambiental-form'
import {
  useAmbientalConceptos, useCerrarRegistro, useDeleteDotacion, useFaenaConfig,
  useFaenasPrevencion, useMisDotaciones, useMisRegistros,
  useUpsertDotacion,
} from '@/hooks/use-prevencion-reportabilidad'

const ROLES_CREAR = ['administrador', 'prevencionista', 'supervisor',
  'jefe_operaciones', 'jefe_mantenimiento', 'subgerente_operaciones']
// Los que además chequean el mes y generan los documentos (el «portal» tiene
// dos puertas: el supervisor completa, prevención controla).
const ROLES_CONTROL = ['administrador', 'prevencionista', 'jefe_operaciones', 'subgerente_operaciones']

export default function PrevencionMobileHome() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const toast = useToast()
  const { data: registros, isLoading } = useMisRegistros(30)
  const cerrar = useCerrarRegistro()

  const [nuevoOpen, setNuevoOpen] = useState(false)
  const [cerrandoId, setCerrandoId] = useState<string | null>(null)
  const [obsCierre, setObsCierre] = useState('')

  // [MIG553] Subidas a faena: personas que subieron → HH = 8 × personas.
  const { data: faenas } = useFaenasPrevencion()
  const { data: subidas } = useMisDotaciones(7)
  const guardarSubida = useUpsertDotacion()
  const borrarSubida = useDeleteDotacion()
  const [subidaOpen, setSubidaOpen] = useState(false)
  // [MIG554] Ambiental: el botón aparece solo si alguna faena tiene catálogo.
  const { data: ambConceptos } = useAmbientalConceptos()
  const [ambientalOpen, setAmbientalOpen] = useState(false)
  const [subFaena, setSubFaena] = useState('')
  const [subFecha, setSubFecha] = useState(() => new Date().toISOString().slice(0, 10))
  const [subHombres, setSubHombres] = useState('')
  const [subMujeres, setSubMujeres] = useState('0')
  // [MIG556] La subida es conteo simple TAL CUAL en todas las faenas: el
  // supervisor indica la cantidad y esa manda para las HH. La nómina de
  // Calama se usa en los ASISTENTES de las actividades (charlas), no aquí.
  const totalPersonas = (Number(subHombres) || 0) + (Number(subMujeres) || 0)
  // [MIG557] Centinela declara HH POR INSTALACIÓN: si la ficha de la faena
  // define instalaciones, la subida pide en cuál se trabajó.
  // [MIG559] El E-200 va POR LUGAR: primero la faena del mandante (Centinela
  // Sulfuros / Oxido / Encuentro) y después la instalación. Lo guardado sigue
  // siendo la clave «Faena — Instalación» (así la lee la dotación y el E-200).
  const { data: subConfig } = useFaenaConfig(subFaena || null)
  const instalaciones: string[] = ((subConfig as any)?.instalaciones ?? [])
  const detalleInst = ((subConfig as any)?.instalaciones_detalle ?? {}) as Record<string, Record<string, string>>
  const lugares = instalaciones.map((clave) => {
    const det = detalleInst[clave] ?? {}
    const [f, i] = clave.split('—').map((s) => s.trim())
    return { clave, faena: det.faena ?? f ?? clave, instalacion: det.nombre ?? i ?? clave }
  })
  const faenasMandante = Array.from(new Set(lugares.map((l) => l.faena)))
  const [subFaenaMandante, setSubFaenaMandante] = useState('')
  const [subInstalacion, setSubInstalacion] = useState('')
  const instalacionesDelMandante = lugares.filter((l) => l.faena === subFaenaMandante)

  const nombreFaena = (id: string) =>
    (faenas ?? []).find((f: any) => f.id === id)?.nombre ?? '—'

  const confirmarSubida = async () => {
    if (!subFaena) return toast.error('Elija la faena')
    if (lugares.length > 0 && (!subFaenaMandante || !subInstalacion)) {
      return toast.error('Elija la faena del mandante y la instalación (el E-200 se declara por lugar)')
    }
    if (totalPersonas < 1) return toast.error('Indique cuántas personas subieron (usted incluido)')
    try {
      await guardarSubida.mutateAsync({
        faena_id: subFaena,
        fecha: subFecha,
        hombres: Number(subHombres) || 0,
        mujeres: Number(subMujeres) || 0,
        instalacion: lugares.length > 0 ? subInstalacion : null,
      })
      toast.success(`Subida guardada: ${totalPersonas} personas = ${totalPersonas * 8} HH`)
      setSubidaOpen(false)
      setSubHombres(''); setSubMujeres('0')
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo guardar la subida')
    }
  }

  const puedeCrear = !!perfil?.rol && ROLES_CREAR.includes(perfil.rol)

  const abiertos = useMemo(
    () => (registros ?? []).filter((r) => r.estado === 'abierto'),
    [registros],
  )

  // Mi avance del mes: lo que YO llevo cargado, por tipo. Es lo que el
  // prevencionista ve en su monitoreo — así el supervisor sabe si va corto
  // antes de que se lo pidan.
  const avanceMes = useMemo(() => {
    const ahora = new Date()
    const prefijo = `${ahora.getFullYear()}-${String(ahora.getMonth() + 1).padStart(2, '0')}`
    const delMes = (registros ?? []).filter((r) => r.fecha_actividad.startsWith(prefijo))
    const porTipo = new Map<string, number>()
    for (const r of delMes) porTipo.set(r.tipo_codigo, (porTipo.get(r.tipo_codigo) ?? 0) + 1)
    return { total: delMes.length, porTipo: Array.from(porTipo.entries()) }
  }, [registros])

  if (verificando) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }
  if (sinSesionOffline) return <SinSesionOffline />

  const confirmarCierre = async () => {
    if (!cerrandoId) return
    try {
      await cerrar.mutateAsync({ id: cerrandoId, observacion: obsCierre.trim() || undefined })
      toast.success('Registro cerrado')
      setCerrandoId(null)
      setObsCierre('')
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo cerrar el registro')
    }
  }

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      <header className="border-b border-gray-200 bg-white px-4 pb-5 pt-[max(1.25rem,env(safe-area-inset-top))]">
        <p className="flex items-center gap-2 text-lg font-bold leading-tight text-gray-900">
          <HardHat className="h-5 w-5 text-pillado-green-500" />
          Prevención — registro de terreno
        </p>
        <p className="text-xs text-gray-500">
          RIT · VAT · VCT · charlas · inspecciones
          {perfil?.nombre_completo ? ` · ${perfil.nombre_completo}` : ''}
        </p>
      </header>

      <main className="space-y-4 px-4 py-5">
        {!puedeCrear && (
          <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
            Su cuenta no tiene el rol para cargar registros de prevención.
            Avise a quien administra el sistema.
          </p>
        )}

        {!!perfil?.rol && ROLES_CONTROL.includes(perfil.rol) && (
          <Link href="/m/prevencion/control"
                className="flex w-full items-center gap-3 rounded-xl border-2 border-gray-900 bg-gray-900 p-4 text-white active:scale-[0.99]">
            <ShieldCheck className="h-6 w-6 shrink-0" />
            <div className="min-w-0 flex-1 text-left">
              <p className="text-base font-bold">Control del mes</p>
              <p className="text-xs opacity-70">Quién cargó, qué falta y generar los documentos</p>
            </div>
            <ChevronRight className="h-5 w-5 shrink-0 opacity-60" />
          </Link>
        )}

        {puedeCrear && (
          <button
            onClick={() => setNuevoOpen(true)}
            className="flex w-full items-center gap-3 rounded-xl border-2 border-pillado-green-500 bg-white p-4 active:scale-[0.99]"
          >
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-pillado-green-500 text-white">
              <Plus className="h-6 w-6" />
            </div>
            <div className="min-w-0 flex-1 text-left">
              <p className="text-base font-bold text-gray-900">Nuevo registro</p>
              <p className="text-xs text-gray-500">
                Con foto queda respaldado para el informe mensual
              </p>
            </div>
          </button>
        )}

        {puedeCrear && (
          <button
            onClick={() => setSubidaOpen(true)}
            className="flex w-full items-center gap-3 rounded-xl border-2 border-blue-500 bg-white p-4 active:scale-[0.99]"
          >
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-blue-500 text-white">
              <Users className="h-6 w-6" />
            </div>
            <div className="min-w-0 flex-1 text-left">
              <p className="text-base font-bold text-gray-900">Subida a faena</p>
              <p className="text-xs text-gray-500">
                Cuántos subieron hoy (usted incluido) — alimenta las HH del E-200
              </p>
            </div>
          </button>
        )}

        {puedeCrear && (ambConceptos?.length ?? 0) > 0 && (
          <button
            onClick={() => setAmbientalOpen(true)}
            className="flex w-full items-center gap-3 rounded-xl border-2 border-emerald-500 bg-white p-4 active:scale-[0.99]"
          >
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-emerald-500 text-white">
              <Leaf className="h-6 w-6" />
            </div>
            <div className="min-w-0 flex-1 text-left">
              <p className="text-base font-bold text-gray-900">Residuos e insumos (Franke)</p>
              <p className="text-xs text-gray-500">
                Retiro semanal de residuos e insumos del mes — doc. ambiental
              </p>
            </div>
          </button>
        )}

        {puedeCrear && (subidas?.length ?? 0) > 0 && (
          <div className="rounded-xl border border-blue-200 bg-white p-3">
            <p className="mb-1.5 text-xs font-bold uppercase text-gray-500">
              Mis subidas — últimos 7 días
            </p>
            <ul className="space-y-1">
              {(subidas ?? []).map((s) => (
                <li key={s.id} className="flex items-center gap-2 text-sm">
                  <span className="w-20 shrink-0 text-xs text-gray-500">{s.fecha}</span>
                  <span className="min-w-0 flex-1 truncate font-medium">{nombreFaena(s.faena_id)}</span>
                  <span className="shrink-0 rounded bg-blue-50 px-1.5 py-0.5 text-xs font-bold text-blue-700">
                    {s.hombres + s.mujeres} pers · {(s.hombres + s.mujeres) * 8} HH
                  </span>
                  <button className="text-gray-300 hover:text-red-500"
                          onClick={async () => {
                            try {
                              await borrarSubida.mutateAsync(s.id)
                              toast.success('Subida borrada')
                            } catch (e: any) { toast.error(e?.message ?? 'No se pudo borrar') }
                          }}>
                    <Trash2 className="h-4 w-4" />
                  </button>
                </li>
              ))}
            </ul>
            <p className="mt-1 text-[11px] text-gray-400">
              ¿Se equivocó? Vuelva a registrar el mismo día y faena: se corrige solo.
            </p>
          </div>
        )}

        {puedeCrear && avanceMes.total > 0 && (
          <div className="rounded-xl border border-gray-200 bg-white p-3">
            <p className="mb-1.5 text-xs font-bold uppercase text-gray-500">
              Mi avance del mes · {avanceMes.total} registros
            </p>
            <div className="flex flex-wrap gap-1.5">
              {avanceMes.porTipo.map(([t, n]) => (
                <span key={t} className="rounded-full bg-gray-100 px-2.5 py-1 text-xs font-medium text-gray-700">
                  {t}: <b>{n}</b>
                </span>
              ))}
            </div>
          </div>
        )}

        {abiertos.length > 0 && (
          <section>
            <h2 className="mb-2 text-sm font-bold text-amber-700">
              Mis abiertos ({abiertos.length}) — ciérrelos cuando la medida esté lista
            </h2>
            <ul className="space-y-2">
              {abiertos.map((r) => (
                <li key={r.id} className="rounded-xl border border-amber-200 bg-white p-3">
                  <div className="flex items-center gap-2">
                    <span className="rounded bg-gray-100 px-1.5 py-0.5 text-xs font-bold">{r.tipo_codigo}</span>
                    <span className="min-w-0 flex-1 truncate text-sm font-medium">{r.titulo}</span>
                  </div>
                  <div className="mt-2 flex items-center justify-between">
                    <span className="text-xs text-gray-500">{r.fecha_actividad}</span>
                    <Button size="sm" variant="outline" onClick={() => setCerrandoId(r.id)}>
                      <CheckCircle2 className="mr-1 h-4 w-4" /> Cerrar
                    </Button>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        )}

        <section>
          <h2 className="mb-2 flex items-center gap-1.5 text-sm font-bold text-gray-700">
            <ClipboardList className="h-4 w-4" /> Mis últimos registros
          </h2>
          {isLoading ? (
            <div className="flex justify-center py-8"><Spinner className="h-6 w-6" /></div>
          ) : !registros?.length ? (
            <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
              Todavía no carga registros desde este teléfono.
            </p>
          ) : (
            <ul className="space-y-1.5">
              {registros.map((r) => (
                <li key={r.id} className="flex items-center gap-2 rounded-lg border border-gray-200 bg-white px-3 py-2">
                  <span className="w-20 shrink-0 rounded bg-gray-100 px-1.5 py-0.5 text-center text-xs font-bold">
                    {r.tipo_codigo}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-gray-900">{r.titulo}</p>
                    <p className="text-[11px] text-gray-500">{r.fecha_actividad}</p>
                  </div>
                  {(r.evidencias?.length ?? 0) > 0 && (
                    <span className="flex items-center gap-0.5 text-xs text-gray-400">
                      <Paperclip className="h-3 w-3" />{r.evidencias.length}
                    </span>
                  )}
                  <span className={cn(
                    'shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold',
                    r.estado === 'abierto' ? 'bg-amber-100 text-amber-700' : 'bg-green-100 text-green-700',
                  )}>
                    {r.estado}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </main>

      <Modal open={nuevoOpen} onClose={() => setNuevoOpen(false)}
             title="Nuevo registro" className="max-w-[480px]">
        <RegistroTerrenoForm
          faenaIdInicial={(perfil as any)?.faena_id ?? null}
          onGuardado={() => setNuevoOpen(false)}
          onCancelar={() => setNuevoOpen(false)}
        />
      </Modal>

      <Modal open={ambientalOpen} onClose={() => setAmbientalOpen(false)}
             title="Residuos e insumos" className="max-w-[480px]">
        <AmbientalForm onGuardado={() => setAmbientalOpen(false)}
                       onCancelar={() => setAmbientalOpen(false)} />
      </Modal>

      <Modal open={subidaOpen} onClose={() => setSubidaOpen(false)}
             title="Subida a faena" className="max-w-[480px]">
        <div className="space-y-3">
          <Select
            label="Faena que visitó"
            value={subFaena}
            onChange={(e) => {
              setSubFaena(e.target.value)
              // Las instalaciones son de cada faena: al cambiarla se limpian.
              setSubFaenaMandante('')
              setSubInstalacion('')
            }}
            placeholder="Elegir faena…"
            options={(faenas ?? []).map((f: any) => ({ value: f.id, label: f.nombre }))}
          />
          {lugares.length > 0 && (
            <>
              <Select
                label="Faena del mandante"
                value={subFaenaMandante}
                onChange={(e) => {
                  setSubFaenaMandante(e.target.value)
                  setSubInstalacion('')
                }}
                placeholder="Elegir faena del mandante…"
                options={faenasMandante.map((f) => ({ value: f, label: f }))}
              />
              <Select
                label="Instalación donde trabajaron"
                value={subInstalacion}
                onChange={(e) => setSubInstalacion(e.target.value)}
                placeholder={subFaenaMandante ? 'Elegir instalación…' : 'Elija primero la faena del mandante'}
                disabled={!subFaenaMandante}
                options={instalacionesDelMandante.map((l) => ({ value: l.clave, label: l.instalacion }))}
              />
            </>
          )}
          {/* [MIG559] Sin tope: el E-200 también se declara hacia adelante,
              la dotación de días futuros se puede dejar registrada. */}
          <Input label="Fecha de la subida" type="date" value={subFecha}
                 onChange={(e) => setSubFecha(e.target.value)} />
          <div className="grid grid-cols-2 gap-3">
            <Input label="Hombres (usted incluido)" type="number" min={0} inputMode="numeric"
                   value={subHombres} onChange={(e) => setSubHombres(e.target.value)} />
            <Input label="Mujeres" type="number" min={0} inputMode="numeric"
                   value={subMujeres} onChange={(e) => setSubMujeres(e.target.value)} />
          </div>
          <div className={cn(
            'rounded-lg border p-3 text-center',
            totalPersonas > 0 ? 'border-blue-200 bg-blue-50' : 'border-gray-200 bg-gray-50',
          )}>
            <p className="text-xs text-gray-500">HH del día para el E-200 (8 × personas)</p>
            <p className="text-2xl font-bold text-blue-700">
              {totalPersonas > 0 ? `${totalPersonas} × 8 = ${totalPersonas * 8} HH` : '—'}
            </p>
          </div>
          <div className="flex gap-2">
            <Button className="flex-1" onClick={confirmarSubida} disabled={guardarSubida.isPending}>
              {guardarSubida.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Guardar subida
            </Button>
            <Button variant="outline" onClick={() => setSubidaOpen(false)}>Cancelar</Button>
          </div>
        </div>
      </Modal>

      <Modal open={!!cerrandoId} onClose={() => setCerrandoId(null)}
             title="Cerrar registro" className="max-w-[480px]">
        <div className="space-y-3">
          <label className="block text-sm font-medium text-gray-700">
            ¿Qué se hizo? (observación de cierre)
          </label>
          <textarea
            className="min-h-[80px] w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            value={obsCierre}
            onChange={(e) => setObsCierre(e.target.value)}
          />
          <div className="flex gap-2">
            <Button className="flex-1" onClick={confirmarCierre} disabled={cerrar.isPending}>
              {cerrar.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Cerrar registro
            </Button>
            <Button variant="outline" onClick={() => setCerrandoId(null)}>Cancelar</Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
