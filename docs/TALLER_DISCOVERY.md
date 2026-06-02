# Taller — Descubrimiento para planificación + ejecución (validar con jefe de taller)

> Fecha: 2026-06-02. Fuente: base de datos productiva + carpetas locales
> (`Desktop\2026\PILLADO\Mantenimiento` y `OneDrive - PILLADO`).
> Objetivo: tener la base para (a) mejorar la barra lateral, (b) armar el
> concepto de **planificación de taller con ejecución de tareas**.

---

## 1. Checklists cargados (validar contenido con jefe de taller)

### Check-Lists V02 (arriendo) — `checklist_template_v2`
| Código | Nombre | Momento | Ítems | Activo |
|---|---|---|---|---|
| `CL-ENTREGA-V02` | Check-List Entrega V02-2026 (inicio arriendo) | entrega_arriendo | **40** | sí |
| `CL-RECEPCION-V02` | Check-List Recepción V02-2026 (devolución) | recepcion_devolucion | **118** | sí |

Cubren tipos de equipamiento: **aljibe_agua, aljibe_combustible, pluma_grua,
ampliroll, grua_horquilla, camioneta, tracto, genérico**.

### Checklists QR (operador) — `qr_checklist_templates`
- **14 plantillas** QR (chequeo operador en terreno vía QR).

> **Para validar:** ¿los 40/118 ítems están completos y correctos? ¿faltan
> tipos de equipo? Hay un **`Check List Rapido - TC8.xlsx`** en las carpetas que
> conviene contrastar.

---

## 2. Pautas de fabricante con TIEMPOS — `pautas_fabricante`

**83 registros, pero solo 54 únicos → hay ~29 duplicados (limpiar).**
Cada pauta trae frecuencia (h / km / días) y `duracion_estimada_hrs`.

Modelos/equipos con pauta cargada y tiempo:
- **Mercedes Actros**: SI 100h (1.2h), SL 200h (2.7h), SM1 400h (4.2h), SM2 800h (6.4h), SM3 1600h (10.8h), SM4 3200h (12.6h), SM5 4800h (13.2h), SM6 9600h (15.0h)
- **Atego / Axor**: SL/SM1/SM2/SM3/SM4 (2.7–12.6h)
- **Volvo FMX 420 / VM 350**: S/M/L + Eje + Caja I-Shift (1.5–8.0h)
- **Volvo FH 540**: PM 250h (3h), 500h (6h), 10.000km (4h)
- **Nissan NP300**: inspección 10K (2.4h), 20K (2.3h), cambio 40K (2.5h)
- **Atlas Copco XAS 185**: PM 500h (3h)
- **Gilbarco Encore 700**: PM mensual (2h), trimestral (4h)
- **Lincoln PowerMaster**: PM mensual (1.5h)
- **Mack GU813E**: SL/SM1/SM2/SM3 — *sin duración cargada*
- **Renault C440**: básico/intermedio/mayor/overhaul — *sin duración cargada*
- Genéricos (cambio aceite, engrase, filtros, frenos) — *sin duración cargada*

> **Para validar:** (1) confirmar/ajustar los **tiempos (HH)** con el jefe de
> taller; (2) completar los que están en blanco (Mack, Renault, genéricos);
> (3) **eliminar duplicados**.

---

## 3. Planes de mantenimiento — `planes_mantenimiento`

- **212 planes activos** sobre **36 activos**.
- Por tipo: por_horas 82 · mixto 84 · por_kilometraje 40 · por_tiempo 6.
- Cada plan referencia una pauta y guarda última/próxima ejecución (km/h/fecha).

---

## 4. Órdenes de trabajo — `ordenes_trabajo`

**36 OT en total. 30 abiertas:**
| Estado | N° |
|---|---|
| creada | 16 |
| asignada | 6 |
| en_ejecución | 4 |
| pausada | 4 |
| ejecutada_ok | 2 |
| ejecutada_con_observaciones | 1 |
| no_ejecutada | 1 |
| cancelada | 1 |

Por tipo: preventivo 15 · correctivo 9 · verificación_disponibilidad 8 · inspección 2 · abastecimiento 1.

Planificación semanal de taller ya existe: `taller_planes_semanales`,
`taller_plan_semanal_ots`, `taller_plan_semanal_dias` (Kanban estilo Calama).

---

## 5. Inventario de fuentes (carpetas)

### `Desktop\2026\PILLADO\Mantenimiento`
- **Pautas por modelo**: `Pauta Mantencion Camion Actros (Agua Industrial)`,
  `... Atego (Combustible)`, `... Axor (Combustible)`, `... Volvo (General)`,
  y **`Pautas Mantencion Maestro.xlsx`** (no se pudo abrir — posible archivo
  solo-en-nube de OneDrive; **descargarlo** para procesarlo).
- `Check List Rapido - TC8.xlsx`
- `Comparativo 3 Politicas Mantencion.xlsx`, `Historico OS Auditoria.xlsx`,
  `Memo Ejecutivo - Rediseño Sistema Mantencion Flota.docx`
- **~200 OS históricas** (2020–2026): `N°xxxx - Servicio Equipo PPU - … - %`.
  Sirven para tiempos reales y patrones de falla.
- `Manuales\` — PDFs técnicos por modelo.

### `OneDrive - PILLADO`
- `detalle de tareas.xlsx`, `Item restantes.xlsx`,
  `Diseño Alcances de los Servicios.pptx`, `Panel de Control Flota V23 …`,
  carpeta `Manuales e Información Técnica - Documentos`.

---

## 6. Hallazgos / data quality
1. **Pautas duplicadas** (83 vs 54 únicas) → deduplicar.
2. **Tiempos faltantes** en Mack, Renault y pautas genéricas.
3. **`Pautas Mantencion Maestro.xlsx`** no descargado localmente (placeholder).
4. Conviene contrastar checklists DB vs `Check List Rapido - TC8.xlsx`.

---

## 7. Próximos pasos propuestos
1. **Validar con jefe de taller**: ítems de checklists + tiempos (HH) por pauta.
2. **Limpiar pautas** (dedup + completar tiempos).
3. **Concepto planificación + ejecución**: atar pauta → OT (con tareas y tiempos)
   → ejecución (Kanban taller ya existe). Definir el flujo de "ejecución de tareas".
4. **Barra lateral**: consolidar entradas dispersas (ver `feedback_unificacion_modulos`).
