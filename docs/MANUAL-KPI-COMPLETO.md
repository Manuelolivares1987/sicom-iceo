# MANUAL DE KPIs — SICOM-ICEO
## Empresas Pillado — Trayectoria y Compromiso

---

# ÁREA A — ADMINISTRACIÓN DE LUBRICANTES Y COMBUSTIBLES

---

## KPI A1 — Disponibilidad de Puntos de Abastecimiento

### Para el usuario:
Mide cuántas horas estuvieron operativos los puntos de abastecimiento (surtidores, dispensadores, islas) respecto al total de horas programadas en el período. Si un surtidor estuvo fuera de servicio por falla o mantención, esas horas se descuentan.

**¿Por qué importa?** Si los puntos de abastecimiento no están disponibles, la operación minera se detiene. Cada hora sin surtidor es un camión esperando combustible.

### Para auditoría:
- **Fórmula:** `(horas_operativas / horas_programadas) × 100`
- **Fuente:** Tabla `activos` (estado operativo de surtidores) + `ordenes_trabajo` (OTs correctivas que generaron downtime, calculando duración entre `fecha_inicio` y `fecha_termino`)
- **Función SQL:** `calcular_kpi_a1(contrato, faena, inicio, fin)`
- **Periodicidad:** Mensual
- **Meta:** ≥ 98%
- **Peso en ICEO:** 5.0%
- **Bloqueante:** SÍ — si cae bajo 90%, se bloquea el incentivo

| Nivel | Rango | Puntaje | Significado |
|-------|-------|---------|-------------|
| Excelente | ≥ 98% | 100 pts | Surtidores disponibles casi todo el mes |
| Cumple | 95-97.9% | 90 pts | Alguna interrupción menor, dentro de tolerancia |
| Alerta | 90-94.9% | 75 pts | Interrupciones frecuentes, revisar causas |
| No cumple | < 90% | 0-60 pts | **BLOQUEANTE:** Se suspende incentivo del período |

**Ejemplo:** Si en marzo hubo 2.150 horas programadas para 3 surtidores y estuvieron operativos 2.118 horas → Disponibilidad = 98.5% → Excelente (100 pts) → Sin impacto negativo.

**Decisión operacional:** Si cae bajo 95%, investigar: ¿fue falla mecánica? ¿falta de repuestos? ¿mantención no programada? Permite priorizar PM de surtidores.

---

## KPI A2 — Precisión de Despacho de Combustible

### Para el usuario:
Mide qué tan preciso es cada despacho de combustible. Compara la cantidad programada vs. la cantidad real entregada. Si la diferencia está dentro de la tolerancia (±0.5%), el despacho es "preciso".

**¿Por qué importa?** Despachos imprecisos pueden significar pérdidas de combustible, errores de facturación o problemas de calibración en surtidores.

### Para auditoría:
- **Fórmula:** `(despachos_dentro_tolerancia / total_despachos) × 100`
- **Fuente:** Tabla `abastecimientos` (campos `cantidad_programada` vs `cantidad_real`, tolerancia ±0.5%)
- **Función SQL:** `calcular_kpi_a2(contrato, faena, inicio, fin)`
- **Periodicidad:** Mensual
- **Meta:** ≥ 99%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** NO

| Nivel | Rango | Puntaje |
|-------|-------|---------|
| Excelente | ≥ 99% | 100 pts |
| Cumple | 95-98.9% | 90 pts |
| Alerta | 90-94.9% | 75 pts |
| No cumple | < 90% | 0-60 pts |

**Ejemplo:** De 1.250 despachos en el mes, 1.240 estuvieron dentro de ±0.5% → 99.2% → Excelente.

**Decisión:** Si baja, revisar calibración de surtidores y capacitación de operadores.

---

## KPI A3 — Cumplimiento de Rutas Programadas

### Para el usuario:
Mide cuántas rutas de despacho de combustible/lubricante se completaron respecto a las que fueron programadas. Una ruta incompleta significa que algún punto no fue abastecido.

**¿Por qué importa?** Si no se completan las rutas, hay equipos o faenas sin combustible, afectando directamente la producción.

### Para auditoría:
- **Fórmula:** `(rutas_completadas / rutas_programadas) × 100`
- **Fuente:** Tabla `rutas_despacho` (estado = 'completada' vs total programadas)
- **Función SQL:** `calcular_kpi_a3(contrato, faena, inicio, fin)`
- **Periodicidad:** Mensual
- **Meta:** ≥ 97%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** NO

| Nivel | Rango | Puntaje |
|-------|-------|---------|
| Excelente | ≥ 97% | 100 pts |
| Cumple | 95-96.9% | 90 pts |
| Alerta | 90-94.9% | 75 pts |
| No cumple | < 90% | 0-60 pts |

**Ejemplo:** 192 rutas completadas de 200 programadas → 96% → Cumple (90 pts). Faltan 8 rutas: investigar si fue por clima, acceso o falla de cisterna.

---

## KPI A4 — Exactitud de Inventario de Combustibles

### Para el usuario:
Mide qué tan preciso es el inventario de combustibles comparando el conteo físico con lo que dice el sistema. Si hay muchas diferencias, significa que el control de inventario falla.

**¿Por qué importa?** Diferencias grandes pueden significar robo, fugas, errores de despacho o fallas de medición. Afecta directamente el resultado económico del contrato.

### Para auditoría:
- **Fórmula:** `(items_dentro_tolerancia / total_items_contados) × 100`
- **Fuente:** Tablas `conteo_detalle` + `conteos_inventario` + `productos` (categoría = combustible)
- **Función SQL:** `calcular_kpi_a4(contrato, faena, inicio, fin)`
- **Periodicidad:** Mensual
- **Meta:** ≥ 99.5%
- **Peso en ICEO:** 5.0%
- **Bloqueante:** SÍ — si cae bajo 95%, se **penaliza** el ICEO (se reduce a la mitad)

| Nivel | Rango | Puntaje | Efecto |
|-------|-------|---------|--------|
| Excelente | ≥ 99.5% | 100 pts | Normal |
| Cumple | 95-99.4% | 75-90 pts | Normal |
| Alerta | 90-94.9% | 60-75 pts | Revisar urgente |
| No cumple | < 95% | 0-40 pts | **PENALIZACIÓN: ICEO × 0.5** |

**Ejemplo:** Se contaron 200 ítems de combustible. 197 coincidieron con el sistema → 98.5% → Cumple. Pero 3 ítems tienen diferencia: investigar si es error de despacho o medición.

---

## KPI A5 — Tiempo de Respuesta a Solicitudes de Abastecimiento

### Para el usuario:
Mide qué porcentaje de solicitudes de abastecimiento se atendieron dentro del plazo comprometido (SLA). Si se pide combustible y llega tarde, la operación se retrasa.

### Para auditoría:
- **Fórmula:** `(solicitudes_en_plazo / total_solicitudes) × 100`
- **Fuente:** Tabla `ordenes_trabajo` (tipo = abastecimiento, comparando fecha_programada vs fecha_termino)
- **Función SQL:** `calcular_kpi_a5(contrato, faena, inicio, fin)`
- **Periodicidad:** Mensual
- **Meta:** ≥ 95%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** NO

| Nivel | Rango | Puntaje |
|-------|-------|---------|
| Excelente | ≥ 95% | 100 pts |
| Cumple | 90-94.9% | 75-90 pts |
| Alerta | 85-89.9% | 60 pts |
| No cumple | < 85% | 0-40 pts |

---

## KPI A6 — Merma Operacional de Combustible

### Para el usuario:
Mide cuánto combustible se pierde (merma) respecto al total despachado. La merma puede ser por evaporación, fugas, errores de medición o hurto.

**¿Por qué importa?** El combustible es el costo operacional más alto. Cada 0.1% de merma puede significar millones de pesos al año.

### Para auditoría:
- **Fórmula:** `(volumen_merma / volumen_total_despachado) × 100` — **MENOS ES MEJOR**
- **Fuente:** Tabla `movimientos_inventario` (tipo = 'merma' vs tipo = 'salida', para combustibles)
- **Función SQL:** `calcular_kpi_a6(contrato, faena, inicio, fin)`
- **Periodicidad:** Mensual
- **Meta:** ≤ 0.3%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** SÍ — si supera 1.0%, se **descuentan 30 puntos** del ICEO

| Nivel | Rango | Puntaje | Efecto |
|-------|-------|---------|--------|
| Excelente | ≤ 0.3% | 100 pts | Normal |
| Cumple | 0.3-0.5% | 90 pts | Normal |
| Alerta | 0.5-1.0% | 60-75 pts | Investigar causas |
| No cumple | > 1.0% | 0 pts | **DESCUENTO: ICEO - 30 puntos** |

**Ejemplo:** Se despacharon 500.000 litros en el mes. Se registraron 1.200 litros de merma → 0.24% → Excelente. Si fueran 5.500 litros (1.1%), se activa el bloqueante y se descuentan 30 puntos del ICEO.

---

## KPI A7 — Cumplimiento Documental Combustibles

### Para el usuario:
Mide si toda la documentación requerida (certificaciones SEC, permisos, autorizaciones) está vigente. 100% significa que todos los documentos están al día.

### Para auditoría:
- **Fórmula:** `(documentos_vigentes / documentos_requeridos) × 100`
- **Fuente:** Tabla `certificaciones` (estado = 'vigente' para activos de administración combustibles)
- **Función SQL:** `calcular_kpi_a7(contrato, faena, inicio, fin)`
- **Meta:** 100%
- **Peso:** 3.0%
- **Bloqueante:** SÍ — si cae bajo 90%, se bloquea el incentivo

---

## KPI A8 — Tasa de Incidentes Ambientales (Combustibles)

### Para el usuario:
Mide si hubo incidentes ambientales relacionados con combustibles (derrames, contaminación, fugas). **La meta es CERO.** Cualquier incidente ambiental es inaceptable.

**¿Por qué importa?** Un incidente ambiental puede generar multas millonarias, paralización de operaciones y daño reputacional irreparable.

### Para auditoría:
- **Fórmula:** Conteo de incidentes tipo 'ambiental' en el período — **MENOS ES MEJOR, meta = 0**
- **Fuente:** Tabla `incidentes` (tipo = 'ambiental')
- **Función SQL:** `calcular_kpi_a8(contrato, faena, inicio, fin)`
- **Meta:** 0 incidentes
- **Peso:** 3.0%
- **Bloqueante:** SÍ — **ANULAR: Si hay 1 o más incidentes, el ICEO se va a 0**

| Nivel | Rango | Efecto |
|-------|-------|--------|
| Excelente | 0 incidentes | Normal |
| No cumple | ≥ 1 incidente | **ICEO = 0 — MÁXIMA PENALIZACIÓN** |

**Este es el KPI más severo del sistema.** Un solo derrame de combustible anula completamente el ICEO del período y suspende todo incentivo.

---

# ÁREA B — MANTENIMIENTO DE PUNTOS FIJOS

---

## KPI B1 — Cumplimiento Plan Preventivo Plataformas Fijas

### Para el usuario:
Mide cuántas mantenciones preventivas programadas para equipos fijos (surtidores, estanques, bombas, mangueras) se ejecutaron efectivamente.

**¿Por qué importa?** El mantenimiento preventivo evita fallas. Si no se ejecuta, los equipos fallan y la operación se detiene.

### Para auditoría:
- **Fórmula:** `(OTs_PM_ejecutadas / OTs_PM_programadas) × 100` (solo activos tipo fijo)
- **Fuente:** Tabla `ordenes_trabajo` (tipo = 'preventivo', activo tipo fijo, estado ejecutada/cerrada vs total programadas)
- **Función SQL:** `calcular_kpi_b1(contrato, faena, inicio, fin)`
- **Meta:** ≥ 98%
- **Peso:** 7.0% (el más alto del área B)
- **Bloqueante:** SÍ — si cae bajo 85%, se bloquea incentivo

| Nivel | Rango | Puntaje |
|-------|-------|---------|
| Excelente | ≥ 98% | 100 pts |
| Cumple | 95-97.9% | 90 pts |
| Alerta | 85-94.9% | 60-75 pts |
| No cumple | < 85% | 0-40 pts → **BLOQUEA INCENTIVO** |

**Decisión:** Si baja del 95%, revisar: ¿faltaron repuestos? ¿personal? ¿las pautas están mal definidas? ¿se generaron OTs pero no se asignaron?

---

## KPI B2 — Disponibilidad de Activos Fijos

### Para el usuario:
Mide qué porcentaje del tiempo los equipos fijos estuvieron operativos (sin estar fuera de servicio por falla o reparación).

### Para auditoría:
- **Fórmula:** `(horas_operativas / horas_totales_período) × 100`
- **Fuente:** `activos` (estado) + `ordenes_trabajo` (correctivas con duración = downtime)
- **Función SQL:** `calcular_kpi_b2(contrato, faena, inicio, fin)`
- **Meta:** ≥ 97%
- **Peso:** 7.0%
- **Bloqueante:** SÍ — si cae bajo 90%, se **penaliza** ICEO (× 0.5)

---

## KPI B3 — MTTR Activos Fijos (Tiempo Medio de Reparación)

### Para el usuario:
Mide cuántas horas en promedio toma reparar un equipo fijo cuando falla. Menos horas = mejor respuesta del equipo de mantenimiento.

### Para auditoría:
- **Fórmula:** `Σ(horas_reparación) / cantidad_reparaciones` — **MENOS ES MEJOR**
- **Fuente:** `ordenes_trabajo` (tipo = correctivo, activo fijo, EXTRACT horas entre fecha_inicio y fecha_termino)
- **Función SQL:** `calcular_kpi_b3(contrato, faena, inicio, fin)`
- **Meta:** ≤ 4 horas
- **Peso:** 5.0%
- **Bloqueante:** NO

| Nivel | Rango | Puntaje |
|-------|-------|---------|
| Excelente | ≤ 4 hrs | 100 pts |
| Cumple | 4-5 hrs | 90 pts |
| Alerta | 5-8 hrs | 60-75 pts |
| No cumple | > 8 hrs | 0-40 pts |

**Ejemplo:** Hubo 12 correctivos en el mes. Tiempo total de reparación: 42 horas → MTTR = 3.5 hrs → Excelente.

---

## KPI B4 — Cumplimiento de Calibraciones Programadas

### Para el usuario:
Mide si todas las calibraciones de equipos de medición (caudalímetros, medidores de nivel, balanzas) se realizaron en fecha.

### Para auditoría:
- **Fórmula:** `(calibraciones_vigentes / calibraciones_requeridas) × 100`
- **Fuente:** `certificaciones` (tipo = 'calibracion', estado vigente vs total)
- **Función SQL:** `calcular_kpi_b4(contrato, faena, inicio, fin)`
- **Meta:** 100%
- **Peso:** 5.0%
- **Bloqueante:** SÍ — bajo 90% bloquea incentivo

---

## KPI B5 — Exactitud Inventario Repuestos Fijos

### Para el usuario:
Mide la precisión del inventario de repuestos para plataformas fijas. Similar al A4 pero para repuestos, no combustibles.

### Para auditoría:
- **Fórmula:** `(items_correctos / items_contados) × 100`
- **Fuente:** `conteo_detalle` + `productos` (categoría repuesto, asociados a activos fijos)
- **Meta:** ≥ 98%
- **Peso:** 4.0%
- **Bloqueante:** NO

---

## KPI B6 — Backlog de Correctivas Fijos

### Para el usuario:
Mide cuántas OTs correctivas están abiertas (pendientes) respecto al total de correctivas del período. Un backlog alto significa que las fallas no se están reparando a tiempo.

### Para auditoría:
- **Fórmula:** `(OTs_correctivas_abiertas / OTs_correctivas_totales) × 100` — **MENOS ES MEJOR**
- **Fuente:** `ordenes_trabajo` (tipo = correctivo, activo fijo, estado abierto vs total)
- **Meta:** ≤ 5%
- **Peso:** 5.0%
- **Bloqueante:** NO

**Ejemplo:** 2 correctivas abiertas de 40 totales → 5% → Cumple justo. Si fueran 5 abiertas (12.5%), hay un problema de capacidad de respuesta.

---

# ÁREA C — MANTENIMIENTO DE PUNTOS MÓVILES

---

## KPI C1 — Cumplimiento Plan Preventivo Plataformas Móviles

### Para el usuario:
Mide cuántas mantenciones preventivas de la flota móvil (camiones cisterna, lubrimóviles, equipos de bombeo) se ejecutaron vs. las programadas.

### Para auditoría:
- **Fórmula:** `(OTs_PM_ejecutadas / OTs_PM_programadas) × 100` (activos tipo móvil)
- **Fuente:** `ordenes_trabajo` + `activos` (tipo móvil)
- **Función SQL:** `calcular_kpi_c1(contrato, faena, inicio, fin)`
- **Meta:** ≥ 97%
- **Peso:** 6.0%
- **Bloqueante:** SÍ — bajo 85% bloquea incentivo

---

## KPI C2 — Disponibilidad de Flota Móvil

### Para el usuario:
Mide qué porcentaje de la flota móvil estuvo operativa durante el período. Un camión cisterna en taller es un camión que no despacha combustible.

### Para auditoría:
- **Fórmula:** `(unidades_operativas / total_flota) × 100`
- **Fuente:** `activos` (tipo móvil, estado operativo vs total)
- **Meta:** ≥ 95%
- **Peso:** 6.0%
- **Bloqueante:** SÍ — bajo 85%, ICEO penalizado (× 0.5)

---

## KPI C3 — MTTR Flota Móvil

### Para el usuario:
Tiempo promedio que toma reparar un vehículo o equipo móvil cuando falla. Se tolera más que en fijos (8 hrs vs 4 hrs) porque los móviles son más complejos.

### Para auditoría:
- **Fórmula:** `Σ(horas_reparación) / cantidad_reparaciones` — **MENOS ES MEJOR**
- **Fuente:** `ordenes_trabajo` (correctivo móvil, duración)
- **Meta:** ≤ 8 horas
- **Peso:** 4.0%
- **Bloqueante:** NO

---

## KPI C4 — Cumplimiento Certificaciones Vehiculares

### Para el usuario:
Mide si todos los vehículos tienen su documentación al día: revisión técnica, SOAP, permisos de circulación, licencias especiales.

**¿Por qué importa?** Un vehículo sin documentación vigente no puede circular legalmente. Si Carabineros o la autoridad detecta un vehículo sin papeles, hay multa y retención.

### Para auditoría:
- **Fórmula:** `(vehículos_certificados / total_vehículos) × 100`
- **Fuente:** `certificaciones` (tipo = revision_tecnica + soap, activos tipo móvil)
- **Meta:** 100%
- **Peso:** 5.0%
- **Bloqueante:** SÍ — bajo 95% bloquea incentivo

---

## KPI C5 — Eficiencia Consumo Combustible Flota Propia

### Para el usuario:
Mide si la flota propia consume combustible de forma eficiente. Compara el rendimiento real (km/litro) contra el esperado para cada tipo de vehículo.

### Para auditoría:
- **Fórmula:** `(rendimiento_real / rendimiento_esperado) × 100`
- **Fuente:** `rutas_despacho` (km_reales / litros_despachados vs referencia por modelo)
- **Meta:** ≥ 95%
- **Peso:** 3.0%
- **Bloqueante:** NO

---

## KPI C6 — Exactitud Inventario Repuestos Móviles

### Para el usuario:
Precisión del inventario de repuestos para flota móvil. Igual que B5 pero para repuestos de vehículos.

### Para auditoría:
- **Fórmula:** `(items_correctos / items_contados) × 100`
- **Fuente:** `conteo_detalle` + `productos` (repuestos asociados a activos móviles)
- **Meta:** ≥ 98%
- **Peso:** 3.0%
- **Bloqueante:** NO

---

## KPI C7 — Backlog de Correctivas Móviles

### Para el usuario:
Porcentaje de OTs correctivas de flota móvil que siguen abiertas. Se tolera un poco más que en fijos (8% vs 5%) por la complejidad de las reparaciones.

### Para auditoría:
- **Fórmula:** `(correctivas_abiertas / correctivas_totales) × 100` — **MENOS ES MEJOR**
- **Fuente:** `ordenes_trabajo` (correctivo móvil, estados abiertos)
- **Meta:** ≤ 8%
- **Peso:** 3.0%
- **Bloqueante:** NO

---

# RESUMEN EJECUTIVO

## Mapa de Severidad de Bloqueantes

```
NIVEL MÁXIMO:  A8 (Incidente ambiental) → ICEO = 0
NIVEL ALTO:    A4, B2, C2 (Precisión inventario, Disponibilidad) → ICEO × 0.5
NIVEL ALTO:    A6 (Merma combustible) → ICEO - 30 puntos
NIVEL MEDIO:   A1, A7, B1, B4, C1, C4 (Disponibilidad, Documental, PM, Calibración, Certificaciones) → Bloquea incentivo
```

## Distribución de Pesos

| Área | KPIs | Peso total KPIs | Peso en ICEO | Contribución máxima |
|------|------|-----------------|-------------|---------------------|
| A — Combustibles | 8 | 32% | 35% | 35 puntos |
| B — Fijos | 6 | 33% | 35% | 35 puntos |
| C — Móviles | 7 | 30% | 30% | 30 puntos |
| **Total** | **21** | **95%** | **100%** | **100 puntos** |

## Escala ICEO

| ICEO | Clasificación | Incentivo |
|------|--------------|-----------|
| ≥ 95 | Excelencia | 100% del incentivo máximo |
| 90-94.9 | Muy Bueno | 90% |
| 85-89.9 | Bueno | 75% |
| 80-84.9 | Aceptable | 50% |
| 70-79.9 | Regular | 25% |
| < 70 | Deficiente | 0% |

---

*Manual de KPIs — SICOM-ICEO — Empresas Pillado*
*Versión 1.0 — Marzo 2026*
