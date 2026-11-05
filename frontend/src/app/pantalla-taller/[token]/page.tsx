'use client'

// ============================================================================
// El televisor del taller (MIG668)
// ----------------------------------------------------------------------------
// Sin sesión y sin menú: entra con un token revocable y solo puede leer esto. Una
// sesión de Supabase en un PC parado en el taller abriría casi todo el sistema.
//
// SE DIBUJA A 1920×1080 Y SE ESCALA: así se lee igual en 55", 65" o 4K, y el tamaño
// de las letras se decide acá, pensando en quien mira desde lejos.
//
// UNA PANTALLA DESACTUALIZADA QUE PARECE AL DÍA ES PEOR QUE UNA APAGADA
// Si deja de actualizar, lo dice en grande y con la hora del último dato.
// ============================================================================

import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import { getPantallaTaller, type CamionGantt, type PantallaTaller } from '@/lib/services/taller-actividades'
import {
  carrilesDe, colocarBarras, diasVisibles, etiquetaEstadoBarra, papelCorto, textoPapel, type VistaBarra,
} from '@/lib/taller-gantt'

const REFRESCO_MS = 60_000
const AVISO_SIN_DATOS_MS = 5 * 60_000

const ESTADO_CAMION: Record<string, string> = {
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', A: 'Arrendado', C: 'Contrato', D: 'Disponible',
  U: 'Uso interno', L: 'Leasing', H: 'Habilitación', R: 'Recepción', V: 'En venta', S: 'Siniestrado',
}

const ESTILO_BARRA: Record<VistaBarra, React.CSSProperties> = {
  ok: { background: '#00752E', color: '#fff' },
  hoy: { background: '#1C5FD4', color: '#fff' },
  atraso: { background: '#C8141E', color: '#fff' },
  falta: { background: 'repeating-linear-gradient(135deg,#FFC400 0 16px,#FFD84D 16px 32px)', color: '#121111' },
  por_aprobar: { background: '#FFC400', color: '#121111' },
  plan: { background: '#121111', border: '3px solid #BDBBBB', color: '#fff' },
}

const LEYENDA: { v: VistaBarra; t: string }[] = [
  { v: 'ok', t: 'Cerrada con evidencia' },
  { v: 'hoy', t: 'En curso' },
  { v: 'falta', t: 'Falta evidencia' },
  { v: 'por_aprobar', t: 'Por aprobar' },
  { v: 'atraso', t: 'Atrasada' },
  { v: 'plan', t: 'Programada' },
]

const DIAS_SEMANA = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']
const etiquetaDia = (iso: string) => {
  const d = new Date(`${iso}T12:00:00`)
  return `${DIAS_SEMANA[d.getDay()]} ${d.getDate()}`
}
const horaDe = (d: Date) => d.toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit', hour12: false })

function Fila({ c, dias, hoyIdx, compacta }: { c: CamionGantt; dias: string[]; hoyIdx: number; compacta: boolean }) {
  const colocadas = useMemo(() => colocarBarras(c.barras, dias), [c.barras, dias])
  const carriles = carrilesDe(colocadas)
  const sinPlan = colocadas.length === 0
  const detenido = c.estado_codigo === 'F'
  const papeles = compacta ? c.papeles.slice(0, 1) : c.papeles.slice(0, 2)
  const restantes = c.papeles.length - papeles.length
  const estado = c.estado_codigo ? (ESTADO_CAMION[c.estado_codigo] ?? c.estado_codigo) : 'Sin estado'
  const apretada = compacta || carriles > 1
  // Con 10 camiones y dos barras topadas, el texto va en una línea o no cabe.
  const enLinea = compacta && carriles > 1
  const fsBarra = enLinea ? 22 : apretada ? 27 : 34
  return (
    <section style={{ flex: '1 1 0', minHeight: 0, display: 'grid', gridTemplateColumns: '400px minmax(0,1fr)', background: '#232121', borderRadius: 6, overflow: 'hidden', opacity: detenido && sinPlan ? 0.72 : 1 }}>
      <div style={{ padding: '4px 16px', display: 'flex', flexDirection: 'column', justifyContent: 'center', minHeight: 0, overflow: 'hidden' }}>
        <div style={{ display: compacta ? 'flex' : 'block', alignItems: 'baseline', gap: 10, whiteSpace: 'nowrap' }}>
          <div style={{ fontSize: compacta ? 44 : 80, fontWeight: 800, lineHeight: compacta ? 1 : 0.95, letterSpacing: 1 }}>{c.patente}</div>
          <div style={{ fontSize: compacta ? 20 : 28, fontWeight: 600, color: '#D8D6D6', margin: compacta ? 0 : '1px 0 4px', overflow: 'hidden' }}>
            {compacta ? c.estado_codigo : estado}{c.dias != null ? ` · ${c.dias} d` : ''}
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
          {papeles.map((p) => {
            // Fuera de servicio sin plan no alarma: no va a salir a la calle.
            const color = detenido && sinPlan
              ? { background: '#3A3838', color: '#D8D6D6' }
              : p.estado === 'vencido' ? { background: '#C8141E', color: '#fff' } : { background: '#FFC400', color: '#121111' }
            return (
              <div key={p.tipo} style={{ ...color, padding: '1px 10px', borderRadius: 3, fontSize: compacta ? 21 : 27, fontWeight: 800, lineHeight: 1.15, whiteSpace: 'nowrap', overflow: 'hidden' }}>
                {textoPapel(papelCorto(p.tipo, p.etiqueta), p.estado, p.dias)}{restantes > 0 ? ` · +${restantes}` : ''}
              </div>
            )
          })}
        </div>
      </div>
      <div style={{ position: 'relative', minHeight: 0 }}>
        <div style={{ position: 'absolute', inset: 0, display: 'grid', gridTemplateColumns: `repeat(${dias.length},minmax(0,1fr))` }}>
          {dias.map((d, i) => (
            <div key={d} style={i === hoyIdx
              ? { background: '#3C2A1C', borderLeft: '3px solid #FF6A00', borderRight: '3px solid #FF6A00' }
              : { borderLeft: i === 6 ? '4px solid #6A6868' : '1px solid #3A3838' }} />
          ))}
        </div>
        {sinPlan ? (
          <div style={{ position: 'absolute', inset: compacta ? 6 : 16, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 28, borderRadius: 6, background: 'rgba(18,17,17,.72)', border: detenido ? '3px dashed #6A6868' : '4px dashed #FF8A8A' }}>
            <span style={{ fontSize: compacta ? 38 : 54, fontWeight: 800, color: detenido ? '#D8D6D6' : '#FF8A8A' }}>SIN PLAN</span>
            {!detenido && <span style={{ fontSize: compacta ? 26 : 34, fontWeight: 600 }}>El planificador debe definir qué se hace</span>}
          </div>
        ) : (
          <div style={{ position: 'absolute', inset: 0, padding: '6px 2px', display: 'grid', gap: 4, gridTemplateColumns: `repeat(${dias.length},minmax(0,1fr))`, gridTemplateRows: `repeat(${carriles},minmax(0,1fr))` }}>
            {colocadas.map(({ barra, col, largo, carril, cortadaInicio }) => {
              const estadoTxt = etiquetaEstadoBarra(barra.vista, barra.evidencia, barra.origen)
              return (
                <div key={`${barra.origen}-${barra.id}`} style={{ ...ESTILO_BARRA[barra.vista], gridColumn: `${col + 1} / span ${largo}`, gridRow: carril + 1, margin: '0 3px', padding: '0 2px', borderRadius: 6, display: 'flex', flexDirection: enLinea ? 'row' : 'column', gap: enLinea ? 6 : 0, alignItems: 'center', justifyContent: 'center', textAlign: 'center', minWidth: 0, overflow: 'hidden', alignSelf: apretada ? 'stretch' : 'center', height: apretada ? 'auto' : 124 }}>
                  <b style={{ fontSize: fsBarra, fontWeight: 800, lineHeight: 1.05, whiteSpace: 'nowrap' }}>
                    {cortadaInicio ? '◄ ' : ''}{largo > 1 ? barra.titulo : barra.corto}
                  </b>
                  {estadoTxt && (
                    <span style={{ fontSize: enLinea ? 18 : apretada ? 21 : 25, fontWeight: 700, lineHeight: 1.1, whiteSpace: 'nowrap' }}>{estadoTxt}</span>
                  )}
                  {largo > 1 && barra.responsable && !compacta && carriles === 1 && (
                    <span style={{ fontSize: 24, fontWeight: 600, lineHeight: 1.1, whiteSpace: 'nowrap' }}>{barra.responsable}</span>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>
    </section>
  )
}

export default function PantallaTallerPage() {
  const token = useParams()?.token as string
  const [datos, setDatos] = useState<PantallaTaller | null>(null)
  const [ultimo, setUltimo] = useState<Date | null>(null)
  const [ahora, setAhora] = useState(() => new Date())
  const [escala, setEscala] = useState(0)

  useEffect(() => {
    let vivo = true
    const cargar = async () => {
      try {
        const d = await getPantallaTaller(token)
        if (!vivo) return
        setDatos(d)
        setUltimo(new Date())
      } catch {
        // Se queda con lo último y el aviso grande avisa si dura mucho.
      }
    }
    void cargar()
    const t = setInterval(cargar, REFRESCO_MS)
    return () => { vivo = false; clearInterval(t) }
  }, [token])

  useEffect(() => {
    const t = setInterval(() => setAhora(new Date()), 15_000)
    // Recarga en la madrugada para tomar versiones nuevas de la página sin que nadie toque el PC.
    const recarga = new Date()
    recarga.setDate(recarga.getDate() + (recarga.getHours() >= 4 ? 1 : 0))
    recarga.setHours(4, 0, 0, 0)
    const r = setTimeout(() => window.location.reload(), recarga.getTime() - Date.now())
    return () => { clearInterval(t); clearTimeout(r) }
  }, [])

  useEffect(() => {
    const ajustar = () => setEscala(Math.min(window.innerWidth / 1920, window.innerHeight / 1080))
    ajustar()
    window.addEventListener('resize', ajustar)
    return () => window.removeEventListener('resize', ajustar)
  }, [])

  const dias = useMemo(() => (datos?.desde && datos?.hasta ? diasVisibles(datos.desde, datos.hasta) : []), [datos?.desde, datos?.hasta])
  const camiones = useMemo(() => datos?.camiones ?? [], [datos?.camiones])
  const hoyIdx = datos?.hoy ? dias.indexOf(datos.hoy) : -1
  const sinDatos = !ultimo || ahora.getTime() - ultimo.getTime() > AVISO_SIN_DATOS_MS

  const conteo = useMemo(() => {
    const todas = camiones.flatMap((c) => c.barras)
    return {
      taller: camiones.filter((c) => c.en_taller).length,
      falta: todas.filter((b) => b.vista === 'falta' || b.vista === 'por_aprobar').length,
      atraso: todas.filter((b) => b.vista === 'atraso').length,
      sinPlan: camiones.filter((c) => c.barras.length === 0 && c.estado_codigo !== 'F').length,
    }
  }, [camiones])

  // Antes de conocer el tamaño de la pantalla no se dibuja: evita el salto y que
  // la hora del servidor no calce con la del PC.
  if (escala === 0) return <div style={{ position: 'fixed', inset: 0, background: '#121111' }} />

  if (datos && !datos.valido) {
    return (
      <div style={{ position: 'fixed', inset: 0, background: '#121111', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 'min(5vw, 64px)', fontWeight: 700, textAlign: 'center', padding: 40 }}>
        Este enlace de pantalla ya no es válido.
      </div>
    )
  }

  const compacta = camiones.length > 5
  const hoyLargo = ahora.toLocaleDateString('es-CL', { weekday: 'long', day: 'numeric', month: 'short' })

  return (
    <div style={{ position: 'fixed', inset: 0, background: '#000', overflow: 'hidden', cursor: 'none' }}>
      <style>{`@import url('https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@500;600;700;800&display=swap');`}</style>
      <div style={{ width: 1920, height: 1080, transform: `scale(${escala})`, transformOrigin: '0 0', background: '#121111', color: '#fff', fontFamily: "'Barlow Semi Condensed', Calibri, sans-serif", display: 'flex', flexDirection: 'column', overflow: 'hidden', position: 'relative' }}>
        <header style={{ height: 92, flex: 'none', display: 'flex', alignItems: 'center', gap: 40, padding: '0 32px', background: '#232121', borderBottom: '6px solid #FF6A00' }}>
          <h1 style={{ margin: 0, flex: 1, fontSize: 54, fontWeight: 800, letterSpacing: 0.5, textTransform: 'uppercase' }}>{datos?.nombre ?? 'Taller'}</h1>
          {[
            { n: conteo.taller, t: 'en taller', c: '#fff' },
            { n: conteo.falta, t: 'por evidencia', c: conteo.falta ? '#FFC400' : '#fff' },
            { n: conteo.atraso, t: 'atrasadas', c: conteo.atraso ? '#FF6B6B' : '#fff' },
            { n: conteo.sinPlan, t: 'sin plan', c: conteo.sinPlan ? '#FF6B6B' : '#fff' },
          ].map((k) => (
            <div key={k.t} style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
              <b style={{ fontSize: 58, fontWeight: 800, color: k.c }}>{k.n}</b>
              <span style={{ fontSize: 30, fontWeight: 600, color: '#D8D6D6' }}>{k.t}</span>
            </div>
          ))}
          <div style={{ textAlign: 'right', fontSize: 28, fontWeight: 600, color: '#D8D6D6', lineHeight: 1.15, paddingLeft: 16, textTransform: 'capitalize' }}>
            {hoyLargo}<br />{horaDe(ahora)}
          </div>
        </header>

        <div style={{ height: 58, flex: 'none', display: 'grid', gridTemplateColumns: '400px minmax(0,1fr)', padding: '0 16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', paddingLeft: 16, fontSize: 25, fontWeight: 700, color: '#BDBBBB', letterSpacing: 1 }}>CAMIÓN Y PAPELES</div>
          <div style={{ display: 'grid', gridTemplateColumns: `repeat(${dias.length || 12},minmax(0,1fr))` }}>
            {dias.map((d, i) => (
              <div key={d} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontSize: 29, fontWeight: i === hoyIdx ? 800 : 700, color: i === hoyIdx ? '#121111' : '#D8D6D6', background: i === hoyIdx ? '#FF6A00' : undefined, borderRadius: '4px 4px 0 0' }}>
                {etiquetaDia(d)}{i === hoyIdx && <b style={{ fontSize: 22 }}>HOY</b>}
              </div>
            ))}
          </div>
        </div>

        <main style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', gap: compacta ? 4 : 8, padding: '0 16px' }}>
          {camiones.map((c) => <Fila key={c.activo_id} c={c} dias={dias} hoyIdx={hoyIdx} compacta={compacta} />)}
          {datos && camiones.length === 0 && (
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 64, fontWeight: 700, color: '#D8D6D6' }}>No hay camiones en taller.</div>
          )}
        </main>

        <footer style={{ height: 68, flex: 'none', marginTop: 8, display: 'flex', alignItems: 'center', gap: 20, padding: '0 32px', background: '#232121', borderTop: '2px solid #4A4848' }}>
          {LEYENDA.map((l) => (
            <div key={l.v} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 23, fontWeight: 600, whiteSpace: 'nowrap' }}>
              <i style={{ ...ESTILO_BARRA[l.v], display: 'block', width: 30, height: 24, borderRadius: 3, boxSizing: 'border-box' }} />{l.t}
            </div>
          ))}
          <div style={{ marginLeft: 'auto', fontSize: 27, fontWeight: 800, whiteSpace: 'nowrap', overflow: 'hidden' }}>
            {(datos?.sin_agendar?.length ?? 0) > 0 ? (
              <><span style={{ color: '#FF8A8A' }}>RT sin agendar:</span> {datos!.sin_agendar!.map((s) => s.patente).join(' · ')}</>
            ) : 'Ninguna RT sin agendar'}
          </div>
        </footer>

        {sinDatos && (
          <div style={{ position: 'absolute', left: 0, right: 0, top: 92, padding: '22px 32px', background: '#C8141E', color: '#fff', fontSize: 58, fontWeight: 800, textAlign: 'center', zIndex: 5 }}>
            {ultimo ? `SIN CONEXIÓN: estos datos son de las ${horaDe(ultimo)}` : 'Conectando con SICOM…'}
          </div>
        )}
      </div>
    </div>
  )
}
