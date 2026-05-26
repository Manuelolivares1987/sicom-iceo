# Informe de Gestión de Flota — Pillado / SICOM-ICEO
### Reporte al Directorio · Mayo 2026

> **Fuente para NotebookLM.** Cada sección incluye un enlace directo al módulo del
> sistema donde se puede ver el dato en vivo. Base del sistema:
> **https://pilladoiceo.netlify.app**

---

## 1. Resumen ejecutivo

Pillado opera una flota industrial de **68 activos** (55 vehículos/equipos operativos)
arrendados a la minería en dos macrozonas: **Coquimbo (36 equipos)** y **Calama (19
equipos)**. La gestión —antes dispersa en planillas Excel— hoy está unificada en una
plataforma única (SICOM-ICEO) que integra operación, mantención, combustible, flota,
GPS y reportabilidad, con datos reales y trazabilidad de punta a punta.

Hito del período: el **estado diario de cada equipo** se controla con datos reales
(enero–mayo 2026, 7.512 estados cargados) y la flota está **rastreada por GPS en tiempo
real** con **geocercas** que detectan en qué faena/taller se encuentra cada equipo.

🔗 **Panel principal:** https://pilladoiceo.netlify.app/dashboard/flota/dashboard

---

## 2. Reporte diario de flota (automático)

El sistema genera cada mañana, de forma automática, un **reporte diario** con el estado
de toda la flota: arrendado (A), disponible (D), en mantención (M), en taller (T), fuera
de servicio (F), habilitación (H), recepción (R), uso interno (U), leasing (L) y venta (V).

Datos reales del mes (mayo 2026):
- **55 equipos** monitoreados día a día.
- Distribución por estado, por operación (Coquimbo/Calama) y por cliente.
- Curva de **tendencia mensual** + OEE + alertas críticas en una sola pantalla.
- Histórico cargado: **enero a mayo 2026** (7.512 estados diarios reales).

🔗 **Reporte diario:** https://pilladoiceo.netlify.app/dashboard/reporte-diario

---

## 3. GPS + Geocercas: ubicación real de la flota

La flota está rastreada por GPS (proveedor Radicom/Navixy) con actualización **horaria**.
El sistema sabe dónde está cada equipo y, mediante **geocercas**, en qué faena o taller
se encuentra.

Datos reales hoy:
- **51 equipos rastreados** en línea (actualización cada hora).
- **15 geocercas** que cubren las zonas operativas reales: 4 bases/talleres
  (Coquimbo, Calama) y 11 faenas de cliente.
- **Ocupación actual por zona:** Taller Pillado Coquimbo 21 · Spence (Calama) 9 ·
  Taller Pillado Calama 6 · Francke (Taltal) 4 · CMP Romeral 3 · y faenas de
  El Abra, Caserones, Mina Teck, Los Bronces, ESM, etc.
- **Control de zona esperada:** 13 equipos en la faena correcta de su cliente,
  **7 equipos fuera de su zona esperada** — detectado automáticamente.

Las geocercas se generaron a partir de la **posición GPS real** de la flota y están
ligadas al contrato de cada cliente.

🔗 **Mapa GPS + geocercas:** https://pilladoiceo.netlify.app/dashboard/flota/mapa

---

## 4. Operación Calama

Faena Calama opera **19 equipos** (Spence, El Abra, División Ministro Hales, ESM, etc.)
con un módulo dedicado de control en terreno:
- Planificación semanal de la operación (carta Gantt importada desde Excel).
- App de terreno: órdenes de trabajo, avance real del operador, evidencias fotográficas.
- Tablero de supervisión con filtro de período (Hoy/Ayer/Semana) y **curva S** de avance.
- Aceptación y validación de OTs en línea.

🔗 **Panel Calama:** https://pilladoiceo.netlify.app/dashboard/operacion-calama

---

## 5. Control de combustible (antifraude)

El combustible se controla con **Costo Promedio Ponderado (CPP) móvil**: cada salida se
valoriza al costo real vigente. El despacho exige **evidencia obligatoria** (foto de
patente + foto del medidor + firma y RUT del receptor), lo que cierra la puerta al fraude.

- 3 estanques con **kardex valorizado** y control teórico vs físico (varillaje).
- Traspaso entre estanques, recirculación y registro de vehículos externos autorizados.
- **Portal del cliente:** el cliente ve sus despachos y consumos en línea.

🔗 **Panel combustible:** https://pilladoiceo.netlify.app/dashboard/combustible

---

## 6. Mantención, taller y QR por activo

- **Plan semanal de taller** tipo Kanban (preventivas + correctivas, arrastrar y soltar,
  con KPI de cumplimiento).
- **Planes preventivos automáticos** por kilometraje / horas / tiempo.
- **QR por equipo:** se escanea y muestra la ficha del activo con su bitácora e historial
  de órdenes de servicio (incluido el histórico legacy importado).
- Checklist digital en terreno (funciona sin conexión) con fotos y firma.

🔗 **Plan semanal taller:** https://pilladoiceo.netlify.app/dashboard/mantenimiento/plan-semanal-taller
🔗 **Equipos / QR:** https://pilladoiceo.netlify.app/dashboard/activos

---

## 7. Comercial y clientes

La flota atiende una cartera diversificada de clientes mineros: **Rentamaq, CMP, Boart
Longyear, TPM Minería, Major Drilling, CM Cenizas, Drilling Service & Solution, Orbit
Garant, San Gerónimo, ESM**. El sistema controla contratos, estado comercial de cada
activo (arrendado / disponible / leasing / uso interno) y las pérdidas comerciales.

🔗 **Comercial:** https://pilladoiceo.netlify.app/dashboard/comercial
🔗 **Contratos:** https://pilladoiceo.netlify.app/dashboard/contratos

---

## 8. Indicadores (OEE / ICEO)

El sistema calcula la **eficiencia operacional (OEE)** y el índice ICEO por contrato y por
activo, con metodología de disponibilidad, utilización y calidad, segmentado por operación
(Coquimbo / Calama).

🔗 **Fiabilidad / OEE:** https://pilladoiceo.netlify.app/dashboard/fiabilidad
🔗 **Indicadores ICEO:** https://pilladoiceo.netlify.app/dashboard/iceo

---

## 9. El siguiente salto: automatización (roadmap)

La plataforma ya **detecta la ubicación** de cada equipo y **sugiere** automáticamente los
cambios de estado cuando un equipo sale de la faena de su cliente. El roadmap inmediato:

1. **Estado de flota automático:** la geocerca + GPS determinan el estado del equipo
   (arrendado / en taller / fuera de zona), con override manual cuando se requiera (modo
   híbrido).
2. **Reporte que se envía solo:** cada mañana a la gerencia, por correo.

Se pasa de *reportar a mano* a un *tablero que se actualiza y se distribuye solo*. La base
ya está construida (geocercas, detección de entrada/salida, sugerencias cada 15 minutos).

---

## Cierre

De la planilla a la plataforma: una sola fuente de verdad para flota, operación, mantención
y combustible; datos reales y en línea; trazabilidad y control antifraude; y automatización
en marcha (GPS → estado → reporte).

*Pillado · SICOM-ICEO · Mayo 2026*
