# SICOM-ICEO: Guia Operativa de KPIs, Bloqueantes e ICEO
## Documento para Presentacion — Empresas Pillado

---

# PARTE 1: COMO FUNCIONA EL SISTEMA DIA A DIA

## El Ciclo Operativo Diario

Cada dia en una faena minera ocurre lo siguiente:

1. **El planificador** revisa el Plan Semanal en SICOM → ve las sugerencias de mantenimiento preventivo + agrega OTs correctivas, de abastecimiento, lubricacion, etc.

2. **El tecnico** abre "Mis OTs" → ve sus ordenes asignadas → inicia la OT → ejecuta el checklist item por item → sube fotos de evidencia → registra los materiales que consumio de bodega

3. **El tecnico finaliza la OT** → el sistema valida que tenga checklist completo + evidencia fotografica → marca la OT como ejecutada

4. **El supervisor cierra la OT** → revisa costos, evidencia, checklist → cierra definitivamente → **EN ESE MOMENTO el sistema recalcula automaticamente los KPIs del mes**

5. **Los KPIs alimentan el ICEO** → el score se actualiza → si hay bloqueantes, salta la alerta

**Cada OT cerrada mueve los numeros.** No hay entrada manual de KPIs. Todo sale de las operaciones reales.

---

## Como se Registra Cada Tipo de Trabajo

### Mantenimiento Preventivo
1. El sistema sugiere automaticamente las mantenciones de la semana (basado en pautas del fabricante)
2. El planificador acepta la sugerencia → se crea una OT tipo "preventivo"
3. El tecnico ejecuta segun el checklist predefinido de la pauta
4. Registra materiales consumidos (filtros, aceite, etc.) → se descuentan del inventario
5. Sube fotos antes/durante/despues
6. Finaliza → supervisor cierra → **alimenta KPI B1 (PM Fijos) y C1 (PM Moviles)**

### Correctivo
1. Se detecta una falla → el planificador crea OT tipo "correctivo"
2. El tecnico repara → el tiempo entre inicio y fin es el **tiempo de reparacion**
3. Se registran repuestos consumidos
4. Al cerrar → **alimenta KPI B3 (MTTR Fijos) y C3 (MTTR Moviles)**
5. El tiempo que el equipo estuvo fuera de servicio → **alimenta KPI B2 (Disponibilidad Fijos) y C2 (Disponibilidad Moviles)**

### Abastecimiento
1. Se programa una ruta de despacho con puntos a visitar
2. El operador ejecuta la ruta, registrando cantidad despachada en cada punto
3. Se compara cantidad programada vs real (tolerancia ±0.5%)
4. Al completar la ruta → **alimenta KPI A2 (Precision Despacho) y A3 (Cumplimiento Rutas)**

### Inventario
1. El bodeguero realiza conteo fisico con escaner
2. Compara stock fisico vs sistema
3. Las diferencias se valorizan
4. Supervisor aprueba → se generan ajustes automaticos
5. → **alimenta KPI A4 (Exactitud Inventario Combustibles), B5 (Repuestos Fijos), C6 (Repuestos Moviles)**

### Cumplimiento Documental
1. Se registran certificaciones por activo (SEC, SEREMI, SOAP, revision tecnica, calibraciones)
2. El sistema alerta 30 dias antes del vencimiento
3. Certificaciones vigentes vs requeridas → **alimenta KPI A7 (Documental Combustibles), B4 (Calibraciones), C4 (Certificaciones Vehiculares)**

---

# PARTE 2: LOS 21 KPIs EXPLICADOS UNO POR UNO

## AREA A — ADMINISTRACION DE COMBUSTIBLES Y LUBRICANTES (Peso: 35% del ICEO)

### A1 — Disponibilidad de Puntos de Abastecimiento
- **Que mide:** Cuantas horas estuvieron operativos los surtidores y estanques respecto al total de horas del mes
- **Formula:** (horas operativas / horas programadas) × 100
- **De donde salen los datos:** OTs correctivas de surtidores — el tiempo de reparacion es downtime
- **Meta:** >= 98%
- **Peso en ICEO:** 5.0%
- **Bloqueante:** SI — si baja de 90% se bloquea el incentivo
- **Ejemplo:** 3 surtidores × 720 hrs/mes = 2.160 hrs programadas. Si estuvieron fuera de servicio 32 hrs en total → (2.160 - 32) / 2.160 = 98.5% → EXCELENTE
- **Que hacer si baja:** Revisar plan de mantenimiento de surtidores, stock de repuestos criticos, tiempos de respuesta del equipo

### A2 — Precision de Despacho de Combustible
- **Que mide:** Que tan preciso es cada despacho comparando litros programados vs reales
- **Formula:** (despachos dentro de ±0.5% / total despachos) × 100
- **De donde salen los datos:** Tabla de abastecimientos — cada registro tiene cantidad_programada y cantidad_real
- **Meta:** >= 99%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** NO
- **Ejemplo:** 1.250 despachos en el mes, 1.240 dentro de tolerancia → 99.2% → EXCELENTE
- **Que hacer si baja:** Calibrar surtidores, revisar procedimiento de despacho, capacitar operadores

### A3 — Cumplimiento de Rutas Programadas
- **Que mide:** Cuantas rutas de despacho se completaron vs las programadas
- **Formula:** (rutas completadas / rutas programadas) × 100
- **De donde salen los datos:** Tabla rutas_despacho — estado = 'completada' vs total
- **Meta:** >= 97%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** NO
- **Ejemplo:** 192 de 200 rutas completadas → 96% → CUMPLE (90 pts)

### A4 — Exactitud de Inventario de Combustibles
- **Que mide:** Cuantos items de combustible coinciden entre el conteo fisico y el sistema
- **Formula:** (items sin diferencia / total items contados) × 100
- **De donde salen los datos:** Conteos de inventario (categoria combustible)
- **Meta:** >= 99.5%
- **Peso en ICEO:** 5.0%
- **Bloqueante:** SI — si baja de 95%, el ICEO se PENALIZA (se reduce a la mitad)
- **Ejemplo:** 200 items contados, 197 coinciden → 98.5% → CUMPLE. Pero si solo 188 coinciden (94%), se activa penalizacion: ICEO × 0.5

### A5 — Tiempo de Respuesta a Solicitudes
- **Que mide:** Cuantas solicitudes de abastecimiento se atendieron dentro del plazo
- **Formula:** (solicitudes en plazo / total solicitudes) × 100
- **De donde salen los datos:** OTs tipo abastecimiento — fecha_programada vs fecha_termino
- **Meta:** >= 95%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** NO

### A6 — Merma Operacional de Combustible
- **Que mide:** Cuanto combustible se pierde (evaporacion, fugas, errores) respecto al total despachado
- **Formula:** (litros merma / litros totales despachados) × 100 — **MENOS ES MEJOR**
- **De donde salen los datos:** Movimientos de inventario tipo 'merma' vs tipo 'salida' para combustibles
- **Meta:** <= 0.3%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** SI — si supera 1.0%, se DESCUENTAN 30 PUNTOS del ICEO
- **Ejemplo:** 500.000 L despachados, 1.200 L de merma → 0.24% → EXCELENTE. Si fueran 5.500 L (1.1%) → bloqueante activado → ICEO pierde 30 puntos
- **Este KPI protege contra perdidas economicas significativas**

### A7 — Cumplimiento Documental Combustibles
- **Que mide:** Porcentaje de documentacion requerida (SEC, permisos) que esta vigente
- **Formula:** (documentos vigentes / documentos requeridos) × 100
- **De donde salen los datos:** Certificaciones de activos de administracion de combustibles
- **Meta:** 100%
- **Peso en ICEO:** 3.0%
- **Bloqueante:** SI — si baja de 90%, se bloquea el incentivo

### A8 — Tasa de Incidentes Ambientales
- **Que mide:** Numero de incidentes ambientales (derrames, contaminacion) relacionados con combustibles
- **Formula:** Conteo directo de incidentes tipo 'ambiental' — **META = CERO**
- **De donde salen los datos:** Tabla de incidentes
- **Meta:** 0 incidentes
- **Peso en ICEO:** 3.0%
- **Bloqueante:** SI — **ANULADOR: Un solo incidente ambiental lleva el ICEO a 0**
- **ESTE ES EL KPI MAS SEVERO DEL SISTEMA. Un derrame de combustible anula completamente el ICEO del periodo y suspende todo incentivo.**

---

## AREA B — MANTENIMIENTO DE PUNTOS FIJOS (Peso: 35% del ICEO)

Puntos fijos: surtidores, dispensadores, estanques, bombas, mangueras, equipos de bombeo

### B1 — Cumplimiento Plan Preventivo Puntos Fijos
- **Que mide:** Cuantas mantenciones preventivas programadas se ejecutaron
- **Formula:** (OTs preventivas ejecutadas / OTs preventivas programadas) × 100
- **De donde salen los datos:** OTs tipo 'preventivo' con activo tipo fijo
- **Meta:** >= 98%
- **Peso en ICEO:** 7.0% (el mayor peso del area B)
- **Bloqueante:** SI — bajo 85% bloquea incentivo
- **Ejemplo:** 49 de 50 PM ejecutadas → 98% → EXCELENTE. Si solo 42 → 84% → BLOQUEA INCENTIVO

### B2 — Disponibilidad de Activos Fijos
- **Que mide:** Porcentaje de tiempo que los equipos fijos estuvieron operativos
- **Formula:** (horas operativas / horas totales del periodo) × 100
- **De donde salen los datos:** Duracion de OTs correctivas = downtime
- **Meta:** >= 97%
- **Peso en ICEO:** 7.0%
- **Bloqueante:** SI — bajo 90%, ICEO se PENALIZA (× 0.5)

### B3 — MTTR Activos Fijos (Tiempo Medio de Reparacion)
- **Que mide:** Cuantas horas en promedio toma reparar un equipo fijo — **MENOS ES MEJOR**
- **Formula:** Suma horas reparacion / cantidad de reparaciones
- **De donde salen los datos:** OTs correctivas — diferencia entre fecha_inicio y fecha_termino
- **Meta:** <= 4 horas
- **Peso en ICEO:** 5.0%
- **Bloqueante:** NO
- **Ejemplo:** 12 correctivos, 42 hrs totales → MTTR = 3.5 hrs → EXCELENTE

### B4 — Cumplimiento de Calibraciones
- **Que mide:** Porcentaje de calibraciones de equipos de medicion que estan vigentes
- **Formula:** (calibraciones vigentes / calibraciones requeridas) × 100
- **De donde salen los datos:** Certificaciones tipo 'calibracion' de activos fijos
- **Meta:** 100%
- **Peso en ICEO:** 5.0%
- **Bloqueante:** SI — bajo 90% bloquea incentivo

### B5 — Exactitud Inventario Repuestos Fijos
- **Que mide:** Precision del inventario de repuestos para equipos fijos
- **Formula:** (items correctos / items contados) × 100
- **De donde salen los datos:** Conteos de inventario (categoria repuesto para activos fijos)
- **Meta:** >= 98%
- **Peso en ICEO:** 4.0%
- **Bloqueante:** NO

### B6 — Backlog de Correctivas Fijos
- **Que mide:** Porcentaje de OTs correctivas que siguen abiertas — **MENOS ES MEJOR**
- **Formula:** (correctivas abiertas / correctivas totales) × 100
- **De donde salen los datos:** OTs correctivas de activos fijos por estado
- **Meta:** <= 5%
- **Peso en ICEO:** 5.0%
- **Bloqueante:** NO

---

## AREA C — MANTENIMIENTO DE PUNTOS MOVILES (Peso: 30% del ICEO)

Puntos moviles: camiones cisterna, lubrimoviles, camionetas, camiones, equipos menores

### C1 — Cumplimiento Plan Preventivo Flota Movil
- **Que mide:** PM de flota ejecutadas vs programadas
- **Formula:** (OTs PM ejecutadas / OTs PM programadas) × 100
- **Meta:** >= 97%
- **Peso en ICEO:** 6.0%
- **Bloqueante:** SI — bajo 85% bloquea incentivo

### C2 — Disponibilidad de Flota Movil
- **Que mide:** Porcentaje de la flota que estuvo operativa
- **Formula:** (unidades operativas / total flota) × 100
- **Meta:** >= 95%
- **Peso en ICEO:** 6.0%
- **Bloqueante:** SI — bajo 85%, ICEO se PENALIZA (× 0.5)

### C3 — MTTR Flota Movil
- **Que mide:** Tiempo promedio de reparacion de vehiculos — **MENOS ES MEJOR**
- **Formula:** Suma horas reparacion / cantidad reparaciones
- **Meta:** <= 8 horas (mas tolerante que fijos por complejidad)
- **Peso en ICEO:** 4.0%
- **Bloqueante:** NO

### C4 — Certificaciones Vehiculares
- **Que mide:** Documentacion legal vigente de vehiculos (revision tecnica, SOAP, permisos)
- **Formula:** (vehiculos certificados / total vehiculos) × 100
- **Meta:** 100%
- **Peso en ICEO:** 5.0%
- **Bloqueante:** SI — bajo 95% bloquea incentivo
- **Un vehiculo sin papeles no puede circular. Multa + retencion.**

### C5 — Eficiencia Consumo Combustible
- **Que mide:** Rendimiento real km/L vs esperado por modelo
- **Formula:** (rendimiento real / rendimiento esperado) × 100
- **Meta:** >= 95%
- **Peso en ICEO:** 3.0%
- **Bloqueante:** NO

### C6 — Exactitud Inventario Repuestos Moviles
- **Que mide:** Precision inventario de repuestos vehiculares
- **Formula:** (items correctos / items contados) × 100
- **Meta:** >= 98%
- **Peso en ICEO:** 3.0%
- **Bloqueante:** NO

### C7 — Backlog de Correctivas Moviles
- **Que mide:** Correctivas de flota que siguen abiertas — **MENOS ES MEJOR**
- **Formula:** (correctivas abiertas / correctivas totales) × 100
- **Meta:** <= 8%
- **Peso en ICEO:** 3.0%
- **Bloqueante:** NO

---

# PARTE 3: LOS BLOQUEANTES — EL MECANISMO DE SEGURIDAD

## Que es un Bloqueante

Un bloqueante es una regla de seguridad que protege contra situaciones criticas. Cuando un KPI cae por debajo de un umbral inaceptable, el bloqueante se activa y castiga el ICEO.

**Analogia:** Es como un fusible electrico. Si la corriente sube demasiado, el fusible se quema para proteger el circuito. Los bloqueantes protegen la operacion.

## Los 4 Niveles de Castigo (de mas severo a menos severo)

### Nivel 1: ANULAR (ICEO = 0)
**El mas severo. La operacion completa del periodo se considera fallida.**

- **A8 — Incidente Ambiental:** Un solo derrame de combustible → ICEO = 0 → incentivo = $0
- **Logica:** Los incidentes ambientales pueden generar multas millonarias y dano reputacional irreparable. No hay excusa.
- **Como evitarlo:** Cumplir protocolos ambientales, capacitacion continua, mantenimiento de contencion

### Nivel 2: PENALIZAR (ICEO × 0.5)
**Reduce el ICEO a la mitad. Un golpe fuerte pero no total.**

- **A4 — Exactitud Inventario Combustibles** (umbral: 95%): Si mas del 5% de items tienen diferencia → inventario fuera de control
- **B2 — Disponibilidad Puntos Fijos** (umbral: 90%): Si mas del 10% del tiempo los equipos estuvieron fuera de servicio → operacion comprometida
- **C2 — Disponibilidad Flota Movil** (umbral: 85%): Si mas del 15% de la flota estuvo en taller → capacidad de despacho insuficiente
- **Como evitarlo:** Conteos frecuentes, PM al dia, stock de repuestos criticos

### Nivel 3: DESCONTAR (ICEO - 30 puntos)
**Resta puntos fijos al ICEO. Duele mucho.**

- **A6 — Merma de Combustible** (umbral: 1.0%): Si se pierde mas del 1% del combustible → problema grave de control
- **Impacto:** Si el ICEO era 88 (Bueno) y se activa → 88 - 30 = 58 (Deficiente)
- **Como evitarlo:** Control riguroso de mediciones, verificar calibracion de instrumentos, investigar diferencias

### Nivel 4: BLOQUEAR INCENTIVO (ICEO intacto pero sin pago)
**El ICEO no cambia, pero el incentivo economico se suspende.**

- **A1 — Disponibilidad Puntos Abastecimiento** (umbral: 90%)
- **A7 — Cumplimiento Documental** (umbral: 90%)
- **B1 — PM Puntos Fijos** (umbral: 85%)
- **B4 — Calibraciones** (umbral: 90%)
- **C1 — PM Flota Movil** (umbral: 85%)
- **C4 — Certificaciones Vehiculares** (umbral: 95%)
- **Como evitarlo:** Mantener documentacion al dia, ejecutar PM segun plan, calibrar equipos

## Mapa de Severidad Completo

```
ANULADOR (ICEO = 0):
  A8  Incidente ambiental combustibles     → 1 incidente = ICEO muerto

PENALIZADOR (ICEO × 0.5):
  A4  Exactitud inventario combustibles    → bajo 95%
  B2  Disponibilidad puntos fijos          → bajo 90%
  C2  Disponibilidad flota movil           → bajo 85%

DESCUENTO (ICEO - 30 pts):
  A6  Merma combustible                    → sobre 1.0%

BLOQUEO INCENTIVO (ICEO intacto, $0 pago):
  A1  Disponibilidad abastecimiento        → bajo 90%
  A7  Documental combustibles              → bajo 90%
  B1  PM puntos fijos                      → bajo 85%
  B4  Calibraciones                        → bajo 90%
  C1  PM flota movil                       → bajo 85%
  C4  Certificaciones vehiculares          → bajo 95%
```

**12 de 21 KPIs son bloqueantes.** Mas de la mitad tienen consecuencias directas si fallan.

---

# PARTE 4: COMO SE CALCULA EL ICEO

## Paso a Paso

### Paso 1: Calcular cada KPI
Para cada uno de los 21 KPIs, se ejecuta su funcion SQL que consulta datos reales del periodo (ej: mes de marzo 2026).

**Ejemplo KPI B1 (PM Fijos):**
- Consulta: cuantas OTs preventivas de activos fijos se ejecutaron vs programadas
- Resultado: 47 de 50 → valor_medido = 94%

### Paso 2: Determinar cumplimiento respecto a la meta
- Meta de B1 = 98%
- Cumplimiento = 94% / 98% × 100 = 95.9%

Para KPIs "menos es mejor" (ej: MTTR, merma):
- Meta de B3 = 4 hrs, valor = 3.2 hrs
- Cumplimiento = 4 / 3.2 × 100 = 125% (super bien)

### Paso 3: Asignar puntaje segun tramos

| Cumplimiento | Puntaje |
|-------------|---------|
| >= 100% | 100 puntos |
| 95 - 99.9% | 90 puntos |
| 90 - 94.9% | 75 puntos |
| 85 - 89.9% | 60 puntos |
| 80 - 84.9% | 40 puntos |
| < 80% | 0 puntos |

B1 con 95.9% cumplimiento → cae en tramo 95-99.9% → **90 puntos**

### Paso 4: Ponderar por peso
Cada KPI tiene un peso que indica su importancia relativa.

- B1 peso = 7.0%
- Valor ponderado = 90 × 7.0 / 100 = **6.30 puntos**

### Paso 5: Sumar por area
Se suman todos los valores ponderados de cada area:
- Area A: suma de A1 a A8 ponderados → ej: 28.5 puntos (de 32 posibles)
- Area B: suma de B1 a B6 ponderados → ej: 30.1 puntos (de 33 posibles)
- Area C: suma de C1 a C7 ponderados → ej: 25.8 puntos (de 30 posibles)

### Paso 6: Aplicar pesos de area
```
ICEO bruto = (Area A × 0.35) + (Area B × 0.35) + (Area C × 0.30)
ICEO bruto = (28.5 × 0.35) + (30.1 × 0.35) + (25.8 × 0.30)
ICEO bruto = 9.975 + 10.535 + 7.740
ICEO bruto = 28.25...
```

Espera — los pesos de area se aplican sobre los puntajes de area normalizados. Si Area B acumulo 30.1 de 33 posibles, su puntaje normalizado es (30.1/33)×100 = 91.2.

```
ICEO bruto = (89.1 × 0.35) + (91.2 × 0.35) + (86.0 × 0.30)
ICEO bruto = 31.2 + 31.9 + 25.8
ICEO bruto = 88.9
```

### Paso 7: Aplicar bloqueantes
Si algun bloqueante esta activado, se aplica su efecto:
- Si hay ANULADOR → ICEO final = 0
- Si hay PENALIZADOR → ICEO final = ICEO bruto × 0.5 = 44.5
- Si hay DESCUENTO → ICEO final = ICEO bruto - 30 = 58.9
- Si solo hay BLOQUEO INCENTIVO → ICEO final = 88.9 (intacto, pero incentivo = $0)
- Si no hay bloqueantes → ICEO final = 88.9

### Paso 8: Clasificar
- 88.9 → cae en rango 85-94.9 → **Clasificacion: BUENO**

### Paso 9: Determinar incentivo
| ICEO | % Incentivo |
|------|-------------|
| >= 95 | 100% |
| 90 - 94.9 | 90% |
| 85 - 89.9 | 75% |
| 80 - 84.9 | 50% |
| 70 - 79.9 | 25% |
| < 70 | 0% |

ICEO = 88.9 → **75% del incentivo maximo**

Si el incentivo maximo de un supervisor es $500.000 → recibe $375.000
(Siempre que no haya bloqueante de incentivo activo)

---

# PARTE 5: DISTRIBUCION COMPLETA DE PESOS

## Tabla Maestra

| KPI | Nombre | Meta | Peso | Bloqueante | Efecto | Umbral |
|-----|--------|------|------|------------|--------|--------|
| **AREA A — Combustibles (35%)** | | | | | | |
| A1 | Disponibilidad Puntos Abastecimiento | >= 98% | 5.0% | SI | Bloquear incentivo | 90% |
| A2 | Precision Despacho Combustible | >= 99% | 4.0% | NO | — | — |
| A3 | Cumplimiento Rutas Programadas | >= 97% | 4.0% | NO | — | — |
| A4 | Exactitud Inventario Combustibles | >= 99.5% | 5.0% | SI | Penalizar (×0.5) | 95% |
| A5 | Tiempo Respuesta Solicitudes | >= 95% | 4.0% | NO | — | — |
| A6 | Merma Operacional Combustible | <= 0.3% | 4.0% | SI | Descontar (-30pts) | 1.0% |
| A7 | Cumplimiento Documental | 100% | 3.0% | SI | Bloquear incentivo | 90% |
| A8 | Incidentes Ambientales | 0 | 3.0% | SI | **ANULAR (ICEO=0)** | >0 |
| **AREA B — Puntos Fijos (35%)** | | | | | | |
| B1 | Cumplimiento PM Fijos | >= 98% | 7.0% | SI | Bloquear incentivo | 85% |
| B2 | Disponibilidad Activos Fijos | >= 97% | 7.0% | SI | Penalizar (×0.5) | 90% |
| B3 | MTTR Activos Fijos | <= 4 hrs | 5.0% | NO | — | — |
| B4 | Cumplimiento Calibraciones | 100% | 5.0% | SI | Bloquear incentivo | 90% |
| B5 | Exactitud Inventario Repuestos | >= 98% | 4.0% | NO | — | — |
| B6 | Backlog Correctivas Fijos | <= 5% | 5.0% | NO | — | — |
| **AREA C — Puntos Moviles (30%)** | | | | | | |
| C1 | Cumplimiento PM Flota | >= 97% | 6.0% | SI | Bloquear incentivo | 85% |
| C2 | Disponibilidad Flota Movil | >= 95% | 6.0% | SI | Penalizar (×0.5) | 85% |
| C3 | MTTR Flota Movil | <= 8 hrs | 4.0% | NO | — | — |
| C4 | Certificaciones Vehiculares | 100% | 5.0% | SI | Bloquear incentivo | 95% |
| C5 | Eficiencia Combustible Flota | >= 95% | 3.0% | NO | — | — |
| C6 | Exactitud Inventario Rep. Moviles | >= 98% | 3.0% | NO | — | — |
| C7 | Backlog Correctivas Moviles | <= 8% | 3.0% | NO | — | — |

**Total: 21 KPIs | 12 Bloqueantes | 100% peso**

---

# PARTE 6: PREGUNTAS FRECUENTES PARA LA PRESENTACION

**P: Quien calcula los KPIs?**
R: El sistema los calcula automaticamente. Cada vez que se cierra una OT, se dispara el recalculo. Tambien se puede forzar manualmente desde la pagina de KPIs.

**P: Se pueden manipular los numeros?**
R: No. Los KPIs se calculan desde datos operacionales reales (OTs, inventario, certificaciones, incidentes). No hay entrada manual de valores. Cada dato tiene trazabilidad completa con auditoria.

**P: Que pasa si un tecnico no sube foto?**
R: No puede finalizar la OT. El sistema exige al menos 1 foto de evidencia y todos los items obligatorios del checklist completos.

**P: Que pasa si hay un derrame?**
R: Se registra como incidente ambiental → KPI A8 se activa → ICEO = 0 para todo el periodo → nadie cobra incentivo ese mes.

**P: Cuanto vale cada punto de ICEO en incentivos?**
R: Depende del cargo. Ejemplo: si un supervisor tiene incentivo maximo de $500.000 y el ICEO es 88.9 (Bueno, 75%), recibe $375.000. Si hay bloqueante de incentivo activo, recibe $0 independiente del ICEO.

**P: Cada cuanto se calcula el ICEO?**
R: Mensualmente. Se acumula todo lo que paso en el mes y se calcula al cierre. Pero el sistema actualiza los KPIs en tiempo real cada vez que se cierra una OT.

**P: Que es lo primero que hay que cuidar?**
R: Los KPIs anuladores (A8: incidentes ambientales) y penalizadores (A4, B2, C2: inventario y disponibilidad). Son los que mas dano hacen al ICEO.

**P: Como el plan semanal ayuda al ICEO?**
R: El plan semanal organiza las OTs de la semana. Al ejecutar PM a tiempo, sube B1 y C1. Al ejecutar abastecimiento programado, sube A3 y A5. Al mantener equipos disponibles, sube B2 y C2. Todo esta conectado.

---

*Documento de Presentacion — SICOM-ICEO — Empresas Pillado*
*Version 1.0 — Marzo 2026*
