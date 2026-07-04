# Fichas de decisión pendientes — auditoría 2026-07

Estas decisiones NO se tomaron automáticamente en Fase 0 (por instrucción). Cada ficha resume la situación con evidencia para que la empresa decida. Las referencias detalladas están en `AUDITORIA_INTEGRAL_2026-07-03.md`.

---

## D1. Método de valorización de bodega: FIFO vs CPP

- **Situación actual:** conviven dos valorizaciones alimentadas por la misma recepción: capas FIFO (`inventario_capas`, vistas financieras MIG39) y CPP legacy (`stock_bodega.valor_total`). El costo de materiales de la OT usa **CPP** (`schema/09_rpc_transaccional.sql:430-474`) mientras las vistas "Costos por OT/CECO" usan **FIFO** (`39:77-129`).
- **Diferencias encontradas:** dos tabs del mismo reporte muestran costos distintos para la misma salida; existe vista de reconciliación precisamente porque divergen.
- **Riesgo:** cifras financieras no comparables; discusiones con finanzas/auditoría externa.
- **Alternativa A (recomendada):** FIFO como método único. Ya es lo que usan las vistas financieras y los smoke tests; migrar `ordenes_trabajo.costo_materiales` a FIFO con recálculo histórico opcional.
- **Alternativa B:** CPP como método único (más simple, menos trazable; implicaría deprecar las capas).
- **Impacto histórico:** recalcular costo de materiales de OTs cerradas (o cortar por fecha: "desde X todo FIFO").
- **Impacto frontend:** ficha OT y reportes de bodega leerían una sola fuente.
- **Impacto contable:** cambia el costo unitario reportado por OT/CECO; requiere aviso a quien consuma esos números.
- **Decisión de la empresa:** elegir método y fecha de corte.

## D2. Fuente única del estado de flota (`estado_diario_flota` como verdad)

- **Situación actual:** 4 almacenes (matriz diaria, ficha `activos.estado/estado_comercial`, `gps_estado_actual`, `historico_estado_activo`); ya divergieron (24/55 según MIG100) y la reconciliación es manual. Además los cambios de `estado_comercial` posteriores al 16-jun no se están historizando (6 activos contradicen su histórico).
- **Alternativa A (recomendada):** la matriz manda; trigger deriva la ficha (estado_comercial/cliente/contrato) desde el último cierre confirmado, e historiza cada cambio.
- **Alternativa B:** la ficha manda y la matriz se genera desde ella (pierde el detalle diario editado en el cierre).
- **Impacto:** dashboards MIG85 y reportes contarían igual en todas las pantallas; requiere reconciliación inicial (los 6 activos divergentes) y definir qué pasa con ediciones directas de ficha.
- **Decisión de la empresa:** ratificar la matriz como fuente y autorizar la reconciliación inicial.

## D3. Definición oficial de UP y DOWN

- **Situación actual:** 4 definiciones vivas de "equipo caído": M,T,F,R,H (fiabilidad física, MIG171), M,T,F (OEE-A y disponibilidad mecánica), M,T,F,H (`v_resumen_diario_flota`), M,T (solo MTTR). El mismo mes da cifras distintas en `/dashboard/reporte-diario` vs `/reporte-fiabilidad`. La misma pantalla pública tiene MTTR con dos bases.
- **Pregunta concreta a responder:** ¿R (recepción) y H (habilitación) cuentan como indisponibilidad? ¿el denominador es días calendario o días con registro?
- **Recomendación técnica:** UN diccionario en UNA función SQL (`fn_definicion_updown()`), consumida por reporte diario, fiabilidad y OEE; publicar la definición en el propio informe.
- **Decisión de la empresa:** qué códigos bajan la disponibilidad **comercial** vs la **mecánica** (pueden ser dos KPIs con nombre distinto, pero cada uno con UNA definición).

## D4. Fórmula oficial de OEE

- **Situación actual:** 3 OEE conviven — A×P×Q (SQL, `schema/41`), Disp×Util×Calidad por horas (reporte diario) y DispFísica×CalidadTaller (TS, panel fiabilidad). Dos aparecen en la misma pantalla.
- **Recomendación técnica:** para una flota de arriendo, OEE completo (con Performance y Quality) suele ser sobre-ingeniería; candidato: quedarse con Disponibilidad Física + Utilización como KPIs oficiales y retirar el OEE de las pantallas donde confunde.
- **Decisión de la empresa:** cuál OEE (o ninguno) es el oficial y en qué pantallas se muestra.

## D5. Universo oficial de equipos para KPIs

- **Situación actual:** los denominadores difieren: reportes públicos filtran 5 tipos (`camion_cisterna, camion, camioneta, lubrimovil, equipo_menor`), el dashboard MIG85 incluye todo salvo baja, el reporte por operación no filtra tipo. La lista de tipos está hardcodeada en ≥3 archivos frontend + varias migraciones, con una 4ª versión divergente.
- **Recomendación técnica:** una función/vista `fn_universo_flota_rodante()` como única definición + un catálogo `tipos_flota_rodante` en BD; el frontend la consume.
- **Decisión de la empresa:** confirmar qué tipos componen la "flota rodante" oficial y si surtidores/estanques/auxiliares entran en algún KPI.

## D6. Diesel B5 S-50: ¿bodega o combustible?

- **Situación actual:** el producto existe en bodega con 33.585 lt de diferencia entre su kardex (78.500) y `stock_bodega` (44.915), mientras el combustible operativo vive en el módulo combustible (que cuadra exacto). Duplicidad conceptual.
- **Alternativa A (recomendada):** el diesel vive SOLO en el módulo combustible; el producto de bodega se cierra (ajuste documentado a 0 y bloqueo de nuevos movimientos).
- **Alternativa B:** mantener ambos con conciliación periódica bodega↔combustible (costo administrativo permanente).
- **Impacto:** reportes de valorización de bodega bajan; el histórico queda con el ajuste trazado.
- **Decisión de la empresa:** dónde vive el diesel y quién ejecuta el ajuste.

## D7. Libro legacy de combustible (`combustible_movimientos`)

- **Situación actual:** coexiste con el kardex valorizado; el trigger legacy mueve saldo sin kardex ni CPP y las reglas de evidencia divergen (MIG78 solo endureció la variante valorizada). Hoy tiene apenas 2 ajustes registrados.
- **Alternativa A (recomendada):** deprecarlo — bloquear inserciones nuevas (trigger que rechaza o revocación de la RPC legacy), conservar la tabla como histórico de solo lectura.
- **Alternativa B:** mantenerlo sincronizado (doble escritura) — no recomendado, duplica la superficie de bugs.
- **Impacto frontend:** verificar que ninguna pantalla siga escribiendo por la vía legacy (el panel viejo `/dashboard/inventario/combustible` es el candidato).
- **Decisión de la empresa:** autorizar la deprecación y fecha.

## D8. Métricas por horas de operación vs días calendario

- **Situación actual:** MTBF/MTTR se calculan en días desde la matriz (MIG170): una falla de 2 horas cuenta como día caído; el horómetro ya se captura (cargas de combustible, GPS) pero no alimenta los KPI.
- **Alternativa A:** mantener días (simple, ya acordado con operaciones) y documentarlo como limitación.
- **Alternativa B (clase mundial, SMRP):** MTBF/MTTR por horas de operación usando horómetro; requiere disciplina de captura y backfill imposible (los KPIs históricos no son comparables).
- **Recomendación técnica:** B como meta de Fase 3, manteniendo A en paralelo durante un trimestre de doble reporte.
- **Decisión de la empresa:** si el salto a horas vale el esfuerzo de captura y desde cuándo.

## D9 (nueva, surgida en Fase 0). Estanques DEMO de Franke

- **Situación actual:** CAM-DEMO-1/2 (`es_demo=true`) descuadran litros en 20.000 lt c/u por seed incompleto y contaminan cualquier reporte que no filtre `es_demo`.
- **Alternativa A (recomendada):** borrarlos (con sus movimientos demo) ahora que Franke opera con datos reales.
- **Alternativa B:** conservarlos y garantizar `WHERE NOT es_demo` en TODOS los reportes (frágil).
- **Decisión de la empresa:** autorizar el borrado de los datos demo.

## D10 (nueva). Acceso externo al informe de fiabilidad

- **Situación actual:** tras MIG186 el informe exige sesión. Si el directorio u otros externos necesitan verlo SIN cuenta, NO reabrir el acceso anónimo.
- **Diseño propuesto si se necesita:** tabla `reporte_tokens` (token aleatorio ≥128 bits guardado como hash SHA-256, expiración, alcance = solo KPIs agregados SIN vin/motor/contratos, revocable, rate limit por IP en un route handler de Next que haga de proxy server-side, log de accesos, `Referrer-Policy: no-referrer`).
- **Decisión de la empresa:** ¿quién necesita el informe sin cuenta? (alternativa simple: crear cuentas de solo lectura).
