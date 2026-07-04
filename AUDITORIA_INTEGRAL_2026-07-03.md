# Auditoría integral del sistema — 2026-07-03

Auditoría de punta a punta ejecutada con 6 revisiones independientes: (1) base de datos y migraciones, (2) frontend y navegación, (3) coherencia de métricas y fuentes de verdad, (4) seguridad, (5) comparación con mejores prácticas mundiales (ISO 55000, SAE JA1011, EN 15341, SMRP), y (6) verificación de datos reales en producción (solo SELECT).

**Veredicto global: madurez ~3.0/5 ("proactivo emergente")** — muy por sobre el promedio para una flota de 55-68 activos (que suele operar en Excel), con fortalezas de clase mundial en trazabilidad de combustible y costeo FIFO, pero con 3 problemas estructurales que hay que cerrar: **seguridad de acceso (el control vive en el cliente, no en la BD)**, **múltiples fuentes de verdad para la misma información** (estado de flota, disponibilidad, costeo), y **sin respaldos de la base de datos**.

---

## 1. CRÍTICOS — actuar esta semana

### C1. RPC de cierre diario abierta a anónimos, reescribe toda la flota
`rpc_confirmar_cierre_diario(DATE, JSONB)` (`database/production_run/106_cierre_diario_flota.sql:104-200`) es SECURITY DEFINER, **no valida `auth.uid()` ni rol**, y tiene `GRANT EXECUTE TO anon` (línea 200). Cualquiera con la anon key (pública en el bundle JS) puede reescribir `estado_comercial`, `cliente_actual` y `contrato_id` de todos los activos, en cualquier fecha, sin login. Los `activo_id` necesarios se obtienen del reporte público (C3). **Fix: validar rol dentro de la RPC y revocar el GRANT a anon** (también en `fn_propuesta_cierre_diario`).

### C2. Script re-ejecutable que borra TODAS las OTs
`database/production_run/118_borrar_ots_prueba.sql:26` contiene `DELETE FROM ordenes_trabajo;` **sin WHERE**. Hoy hay 74 OTs reales. Una re-ejecución accidental con `aplicar-migracion.mjs` arrasa el módulo taller en cascada, **sin backup para recuperar** (plan Free). `121_borrar_ots_prueba_limpias.sql` tiene el mismo problema atenuado. **Fix: borrar ambos archivos o envolverlos en un guard que aborte** (`RAISE EXCEPTION 'one-shot ya aplicado'`).

### C3. Reporte público de fiabilidad expone datos sensibles sin token
`fn_reporte_fiabilidad_publico` (GRANT a anon, `169_reporte_fiabilidad_sin_faena.sql:114`) devuelve por equipo: UUID del activo, patente, cliente, faena, contratos con días de arriendo, **VIN de chasis y número de motor** (`146:36-39`). La página `/reporte-fiabilidad` no tiene guard ni token en la URL. Fuga de inteligencia comercial + identificadores físicos (útiles para clonación de vehículos) + los UUIDs que habilitan C1. **Fix: exigir un token secreto en la URL/parámetro de la RPC y quitar VIN/motor del payload público.**

### C4. Sin respaldos de la base de datos
Plan Supabase Free, tier Micro, sin backups automáticos (ya hubo un incidente que tumbó la BD en mayo). Toda la trazabilidad construida (FIFO, kardex, auditoría) vale cero si se pierde la BD. **Fix: upgrade al plan Pro (backups diarios) o, mínimo, `pg_dump` programado diario a almacenamiento externo. Es la brecha más barata de cerrar con el mayor riesgo asociado.**

### C5. Bug activo: valor del stock de combustible queda inflado tras cada salida
La RPC de salida vigente (`78_combustible_kilometraje_externo_obligatorio.sql:253-256`) solo descuenta **litros**, no el **valor CLP** — regresión de la versión que reemplazó (`40_combustible_cpp_movil.sql:340-344` sí lo bajaba). El kardex guarda el valor correcto, pero `v_combustible_stock_valorizado.valor_total_clp` sobreestima hasta el próximo ingreso. Mismo linaje que el bug de `salida_externa`. **Fix: 1 migración que restaure el UPDATE de `valor_total_stock` y recalcule los saldos desde el kardex.**

---

## 2. Seguridad — estructural (2-4 semanas)

El repo está **limpio de secretos versionados** (verificado: `.env*.local` fuera de git y sin rastro en el historial). El problema es que el control de acceso vive en el cliente:

| # | Hallazgo | Evidencia |
|---|----------|-----------|
| S1 | **Tablas núcleo sin RLS**: `no_conformidades`, `estado_diario_flota`, `verificaciones_disponibilidad`, `registro_jornada_conductor`, `normativa_documentos`, `suspel_*`, `respel_*`. En Supabase, sin RLS = lectura/escritura total para cualquier autenticado, **incluido el portal cliente**. | `schema/25/27/32`; ningún `ENABLE ROW LEVEL SECURITY` en el repo |
| S2 | **99 policies `USING (true)`**, muchas `FOR ALL`: quality gates (7 tablas, `125:1027-1037`), combustible Franke (`130:236`, `131:186`), materiales NC (`138:56`), solicitudes bodega (`144:91`), checklist cliente con UPDATE abierto (`127:93`). Se reintrodujo el patrón que MIG72 ya había corregido tras un bug real con el portal cliente. | production_run 125/130/131/132/138/142/144 |
| S3 | **SELECT abierto a todo autenticado en bodega/kardex**: el portal cliente puede ver precios de compra, proveedores, CECOs, movimientos completos. | `04_apply_mig55:68-361`, `07:63,90`, `10:45` |
| S4 | **Tres sistemas de permisos que divergen**: matriz hardcodeada en frontend (`use-permissions.ts`) + overrides BD (MIG126) + listas fijas en 21+ RPCs (`fn_user_rol() IN (...)`). Cambiar permisos en Admin no afecta las RPCs; `auditor_calidad` quedó fuera de listas antiguas; `/dashboard/mantencion` usa un set propio que contradice al sidebar. | `126`, `159:39`, `73:280`, `mantencion/page.tsx:14-19` |
| S5 | **Sin `middleware.ts`**: la protección de `/dashboard/*` es un hook cliente; casi ninguna página verifica permisos (contratos, auditoría, salidas de bodega/combustible, KPI accesibles por URL a cualquier rol logueado). Riesgo S07 de `SEGURIDAD_Y_ENTORNO.md` sigue "diferido". | `dashboard/layout.tsx` |
| S6 | **Escrituras anónimas sin rate-limit**: `rpc_checklist_cliente_guardar` y `rpc_guardar_checklist_publico` permiten inserciones ilimitadas + subida de archivos anónima al bucket `documentos` sin validación de tipo/tamaño. En tier Micro esto reproduce a voluntad el incidente de I/O. | `127:156-211`, `14B:546-654` |
| S7 | Edge function `gps-radicom-poll` sin secreto propio y `verify_jwt` no fijado en `config.toml`; `/api/reporte-flota/enviar` es un relay de correo abierto para cualquier autenticado (destinatarios y HTML arbitrarios vía Resend). | `supabase/functions/gps-radicom-poll/index.ts:55-68`, `api/reporte-flota/enviar/route.ts:24-74` |
| S8 | ~287 funciones SECURITY DEFINER, 30+ sin `SET search_path` (las de MIG153+ sí lo traen). Cierre trivial en bloque. | linter Supabase estándar |

Nota positiva verificada: el botón "iniciar mantención" de la ficha QR pública **sí** exige login y rol (`14B:724-835`).

---

## 3. Coherencia de la información — por qué los números no cuadran entre pantallas

Veredicto por concepto:

| Concepto | Veredicto | Raíz |
|----------|-----------|------|
| Estado de flota | **DESCUADRA** | 4 almacenes: matriz `estado_diario_flota`, ficha `activos.estado`+`estado_comercial`, `gps_estado_actual`, `historico_estado_activo`. Ya divergieron (24/55 vehículos, `MIG100`); la reconciliación es manual. Dashboard MIG85 cuenta desde la ficha; reporte diario y público desde la matriz. |
| Disponibilidad / fiabilidad / OEE | **DESCUADRA** | "DOWN" tiene 4 definiciones vivas (M,T,F,R,H vs M,T,F vs M,T,F,H vs M,T). MTTR con 2 bases **en la misma pantalla pública** (`reporte-fiabilidad/page.tsx:165` vs `171:76`). 3 fórmulas de OEE conviviendo. Reporte diario divide por días calendario, fiabilidad por días con registro. En UI hay 4 vías de cálculo de disponibilidad (2 familias de RPCs + cálculo en cliente + vista). |
| Combustible | **DESCUADRA** (C5) + doble libro | Kardex valorizado vs `combustible_movimientos` legacy con reglas divergentes (MIG78 solo endureció la variante valorizada). El trigger legacy mueve saldo sin kardex (`schema/50:262-274`). 2 paneles de combustible en UI con fuentes distintas. Proyección de stock ignora consumo interno (`122:37,67`). |
| Inventario bodega | **DESCUADRA** | Doble valorización estructural: FIFO por capas + CPP legacy alimentados por la misma recepción. La OT se costea por **CPP** (`schema/09:430-474`) mientras las vistas financieras usan **FIFO** (`39:77-129`) — dos tabs del mismo reporte muestran costos distintos para la misma salida. |
| Cumplimiento PM | **DESCUADRA** | Dashboard flota cuenta vencidos solo por **fecha** (`85:30`); el taller es multi-eje km/horas/días (`174:75-77`). Los planes por km/horas **nunca** aparecen vencidos en el dashboard flota. Además off-by-one (`<` hoy vs `<=0`) y dos "% cumplimiento" con denominadores distintos en la misma UI. |
| Horas/kilometraje | **RIESGO** | GPS solo sube, combustible usa GREATEST, pero la edición manual usa COALESCE sin GREATEST y puede retroceder lecturas. Sin columna de origen/timestamp de la lectura vigente. Líneas base de preventivas sembradas con valor del momento o 0 (`80:70,77`) — pendiente conocido. |
| Universo de flota | **DESCUADRA** | Los denominadores no usan el mismo conjunto: MIG96/104/106/113 filtran 5 tipos; MIG85 incluye todo salvo baja; el reporte por operación no filtra tipo. Los totales no son comparables entre pantallas. Lista de tipos hardcodeada 3 veces + 1 versión divergente en frontend. |

Otros: código `'C'` (en contrato) válido en la matriz pero invisible en UI y en el RPC manual; `'D'` significa "disponible/up" en el reporte público y "pérdida" en el reporte diario; dos definiciones de "sin señal" en la misma página de mapa; el reporte público **perdió la sección de combustible** desde MIG146 (el frontend la consume y falla en silencio con `?? []` desde ~16-jun).

**Las 3 raíces que explican casi todo:**
1. Elegir la matriz `estado_diario_flota` como única fuente de estado y derivar la ficha por trigger (no reconciliación manual).
2. Decidir FIFO **o** CPP y hacer que `ordenes_trabajo.costo_materiales` use el mismo método que las vistas financieras.
3. Publicar un diccionario único UP/DOWN en **una** función SQL y que reporte diario, fiabilidad y OEE la consuman.

---

## 4. Datos reales en producción — qué cuadra y qué no (verificado 2026-07-03)

**CUADRA (lo esencial está sano):**
- Kardex combustible: los 8 estanques reales cuadran exacto (<0,01 lt); 0 litros negativos; 0 movimientos huérfanos; tipos completos. Solo descuadran los 2 estanques DEMO de Franke (20.000 lt c/u — excluir de reportes o regularizar).
- OTs (74): 0 finalizadas sin fecha, 0 en ejecución sin inicio, 0 huérfanas.
- GPS: 51/51 mapeos correctos, sin duplicados.
- Checklists: 0 huérfanos, 0 valores fuera de rango.
- Integridad referencial: 0 huérfanos en ~20 tablas críticas.
- Retención de logs activa (pg_cron purgando), BD en 172 MB de 350 de umbral.

**DESCUADRA (corregir):**
1. **Diesel B5 S-50 en bodega: 33.585 lt de diferencia** entre kardex (78.500) y `stock_bodega` (44.915). Menores: Rimula −45,5 lt, Gadus −13 kg.
2. **6 activos con estado comercial que contradice el histórico de arriendos** (AI-20-02, CC-15-09, AI-20-03, AI-20-07, AI-25-03, CP-06-02): los cambios posteriores a la carga del 16-jun **no se están historizando** — rompe la trazabilidad de arriendos de MIG147.
3. **2 pares de OTs preventivas duplicadas** misma semana/plan: OT-202606-00042 + OT-202606-00053 (CC-44-03) y OT-202607-00005 + OT-202607-00006 (AI-22-04). Causa de fondo: `planes_mantenimiento` sin UNIQUE(activo, pauta) y dedup no atómico.
4. **6 planes PM de surtidores/compresor vencidos hace 75-96 días sin OT**: el cron solo genera para activos en estado `operativo`. Decidir: desactivar esos planes o ampliar el criterio.
5. Higiene: `auditoria_eventos` (50 MB, la tabla más grande) **sin retención**; **13.965 alertas 100% no leídas** creciendo ~140/día (la purga solo borra leídas); 36 checklists "en_progreso" abiertos >14 días. La retención de `prevencion-db-salud.sql` cubre solo 4 tablas — faltan `taller_plan_jornada_eventos`, `historial_estado_ot`, `auditoria_eventos`, `sugerencias`, `sync_queue_offline`, etc. (mismo vector del incidente de mayo).

---

## 5. Comparación con mejores prácticas mundiales

Madurez por dominio (1-5):

| Dominio | Nota | Resumen |
|---------|:---:|---------|
| Gestión de mantenimiento | 3.0 | OTs maduras, 212 planes PM multi-eje, Kanban semanal con control de cambios. Falta: códigos de falla, análisis de fallas, predictivo. |
| KPIs | 3.0 | Definiciones explícitas y versionadas en SQL (MIG170/171) — exactamente lo que pide EN 15341. Falta: % planificado vs reactivo, backlog en semanas-cuadrilla, granularidad horas. |
| Inventario/bodega | 3.0 | FIFO por capas en producción con trazabilidad OC→OT→CECO. Falta: ABC, puntos de reorden, KPI de exactitud de inventario, conteos cíclicos calendarizados. |
| Combustible | 4.0 | **Nivel clase mundial**: CPP + kardex inmutable, evidencia obligatoria, 3 sellos, NC automática >0,5%. Falta: alertas de desviación de rendimiento por equipo y cuadre diario en todos los estanques (hoy solo Franke). |
| Datos maestros | 2.5 | Criticidad como atributo pero sin metodología ni uso para priorizar; jerarquía de 1 solo nivel; sin taxonomía ISO 14224. |
| Gobernanza | 3.0 | Auditoría transaccional + gestión documental normativa chilena integrada a disponibilidad comercial (diferenciador real). Falta: RLS, permisos server-side, backups. |

**Top brechas vs clase mundial** (en orden de impacto):
1. **Sin códigos de falla al cierre de OT** → imposible hacer Pareto de fallas, MTBF por modo, eliminación de defectos (ISO 14224, SAE JA1011). Es la brecha que impide pasar de 3 a 4.
2. **MTBF/MTTR en días calendario, no horas de operación** — un cambio de filtro de 2 h cuenta como 1 día caído; el horómetro ya se captura en cargas de combustible y no se usa (SMRP 3.5.1/3.5.2).
3. **Criticidad sin metodología ni uso** para priorizar PM/backlog (ISO 14224 §8).
4. Faltan **% planificado vs reactivo** y **backlog en semanas-cuadrilla** (clase mundial: >80% planificado, backlog 2-4 semanas).
5. **Cero mantenimiento por condición** (análisis de aceite en componentes mayores es estándar en minería).
6. Inventario sin **ABC ni exactitud** como KPI (clase mundial >95-98%).
7. **Rendimiento de combustible sin línea base por modelo ni alertas de desviación** (señal clásica de fraude o falla incipiente — el propio doc de trazabilidad lo lista como principio pendiente).
8. **Sin costo de ciclo de vida por activo** para decisiones reparar/reemplazar — clave en un negocio de arriendo.

**Top fortalezas (ya a nivel o sobre el promedio de la industria):**
1. Trazabilidad antifraude de combustible (la mayoría de las mineras medianas no la tiene).
2. Costeo FIFO por capas hasta OT y CECO con overrides auditados — estándar de auditoría externa que muchos CMMS comerciales no logran.
3. Ciclo semanal de planificación/programación **operando de verdad** (el ritual que SMRP considera el corazón de la gestión).
4. KPIs de confiabilidad con definiciones escritas y versionadas en el código.
5. Cumplimiento normativo chileno integrado a la disponibilidad comercial del activo.

---

## 6. Frontend — calidad y deuda

- **Duplicaciones confirmadas**: 2 paneles de combustible (CPP vs legacy — el legacy debería redirigir), mantencion vs mantenimiento repartidos en 3 grupos del sidebar, ≥5 entradas a combustible, 4 páginas "Reportes" sin jerarquía, 3 entradas "Mis OTs". El doble `/activos` del sidebar **ya está corregido**.
- **Páginas huérfanas** (sin ningún enlace entrante): `/dashboard/kpi` (597 líneas), `/dashboard/mantenimiento/planificacion` (duplicado del plan semanal — la des-dup era Fase B pendiente), `/dashboard/flota/plan-preventivo`. El hub unificado MIG85 (`/flota/dashboard`) quedó él mismo semi-oculto: no está en el sidebar.
- **Catálogos hardcodeados duplicados**: labels/colores de estados en ~8 archivos, labels de OT en 8, tipos de flota rodante en 3 + 1 divergente. Un estado nuevo requiere tocar 8 archivos.
- **Errores de Supabase ignorados en 18 archivos** (patrón `const { data } = ...` sin `error`): un fallo de red/RLS se renderiza como "no hay datos"; en `inventario.ts:292` puede derivar en ajustes calculados con datos vacíos.
- **Componentes gigantes**: plan-semanal-taller (2.335 líneas, 63 hooks), OT detalle (1.809), plan semanal Calama (1.705), fiabilidad-analisis (1.336, con cálculo de KPIs y Excel en el navegador).
- Dos paradigmas de fetching (react-query en 26 páginas, useState/useEffect en 22, supabase directo en el page.tsx en 18).

---

## 7. Plan de acción recomendado

### Fase 0 — Esta semana (riesgo inaceptable)
| # | Acción | Esfuerzo |
|---|--------|----------|
| 1 | Revocar GRANT anon + validar rol en `rpc_confirmar_cierre_diario` y `fn_propuesta_cierre_diario` | 1 migración |
| 2 | Borrar/neutralizar `118_borrar_ots_prueba.sql` y `121_...` | 5 min |
| 3 | Backups: plan Pro o pg_dump diario programado | 1 día |
| 4 | Token secreto en reporte público + quitar VIN/n° motor del payload anon | 1 migración |
| 5 | Fix `valor_total_stock` en salidas de combustible + recalcular saldos desde kardex | 1 migración |
| 6 | Restaurar sección `combustible` en `fn_reporte_fiabilidad_publico` (perdida desde MIG146) | 1 migración |

### Fase 1 — 2-3 semanas (cuadratura de datos)
7. Unificar "PM vencido" multi-eje en dashboard flota y `mantenimiento.ts` (hoy solo-fecha).
8. Reconciliar Diesel B5 bodega (33.585 lt) y decidir si ese producto vive en bodega o solo en combustible.
9. Arreglar historización de `estado_comercial` (trigger en `activos` → `historico_estado_activo`); reconciliar los 6 activos divergentes.
10. UNIQUE(activo_id, pauta) en `planes_mantenimiento` + limpiar las 2 OTs duplicadas; decidir sobre los 6 planes de surtidores vencidos.
11. Diccionario único UP/DOWN en una función SQL; alinear MTTR de la pantalla pública (hoy 2 bases en la misma página); limpiar líneas base km/h de preventivas (pendiente conocido).
12. Retención para `auditoria_eventos` + expiración de alertas no leídas + resto de tablas-log.

### Fase 2 — 1-2 meses (estructura)
13. RLS: habilitar en tablas sin RLS (S1) y reemplazar los `USING(true) FOR ALL` por el patrón de MIG72; cerrar SELECT de bodega al portal cliente.
14. Conectar MIG126 al server: función `fn_tiene_permiso(modulo, accion)` que lea los overrides, usada por las RPCs (reemplaza las 21+ listas hardcodeadas) + `middleware.ts` + guard por página.
15. Estado de flota: matriz como fuente única, ficha derivada por trigger; unificar universo de equipos (una función/vista con el filtro de flota rodante).
16. Elegir FIFO o CPP (recomendado: FIFO, ya es lo que usan las vistas financieras) y migrar `costo_materiales` de OT; deprecar el libro legacy de combustible.
17. Frontend: redirect del panel combustible legacy, extraer catálogos compartidos, borrar páginas huérfanas, destructurar `error` en los 18 archivos.

### Fase 3 — Trimestre (salto 3→4 en madurez)
18. Catálogo de códigos de falla (modo/mecanismo/causa) obligatorio al cierre de OT correctiva → Pareto de fallas.
19. MTBF/MTTR por horas de operación usando el horómetro ya capturado.
20. Matriz de criticidad (probabilidad × consecuencia) y usarla para priorizar backlog.
21. KPIs de proceso: % planificado vs reactivo, backlog en semanas-cuadrilla, exactitud de inventario, ABC.
22. Alertas de desviación de rendimiento de combustible por modelo; cuadre diario en todos los estanques.
23. Costo acumulado de mantenimiento por activo vs valor de reposición (decisión reparar/reemplazar).

---

*Generado por auditoría multi-agente Claude Code, 2026-07-03. Los hallazgos de datos en producción fueron verificados con consultas de solo lectura ese mismo día.*
