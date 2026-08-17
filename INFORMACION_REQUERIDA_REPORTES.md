# Información requerida para el Reporte Semanal (GG) y el Directorio

**Fecha de auditoría:** 2026-08-16
**Fuente:** consulta directa a la base de datos de producción (SICOM-ICEO)

---

## 1. Lo que el sistema YA tiene — no necesitas enviarme nada

Estos datos están vivos y actualizados al 14-ago-2026. El reporte los toma solo:

| Dato | Estado | Volumen |
|---|---|---|
| Estado diario de flota (A/D/M/T/F...) | ✅ vivo, hasta 14-ago | 12.649 registros |
| Órdenes de trabajo | ✅ vivo, hasta 14-ago | 121 OT |
| No Conformidades | ✅ vivo, hasta 13-ago | 102 NC |
| Ejecuciones ENEX (Calama) | ✅ vivo, hasta 14-ago | 5 ejecuciones |
| Maestro de flota | ✅ | 69 activos |
| GPS / geocercas | ✅ parcial | 52 mapeados |
| Faenas y contratos | ✅ | ~20 faenas, 4 regiones |

**Distribución real de flota hoy:**
- Coquimbo: 37 equipos (28 operativos, 5 fuera de servicio, 4 en mantención)
- Calama: 18 equipos (14 operativos, 4 fuera de servicio)
- Sin operación asignada: 13 equipos (11 en mantención, 2 fuera de servicio)

---

## 2. Módulos construidos pero SIN USO — necesito una decisión tuya

No es que falte el dato: es que nadie lo está registrando. Si van al reporte,
van a salir en cero y eso se ve mal frente al GG.

| Módulo | Último registro | Volumen | Pregunta |
|---|---|---|---|
| Combustible (movimientos) | 29-abr-2026 | 2 registros | ¿Se opera en papel / otro sistema? |
| Calama — proyecto Centinela | 01-jun-2026 | 16 ejecuciones | ¿Terminó, está parado, o no se registra? |
| Recorridos Gemba | nunca | 0 registros | Recién desplegado. ¿Arranca este mes? |
| Períodos ICEO | 01-mar-2026 | 6 períodos | ¿Se dejó de calcular el incentivo? |

**Decisión:** para cada uno → (a) lo incluimos y mostramos el cero como brecha,
(b) lo excluimos del reporte, o (c) cargamos el histórico y lo ponemos al día.

---

## 3. Hallazgos operacionales que debes confirmar antes de publicarlos

Estos números salen del sistema y son **malos**. Antes de ponerlos frente al GG
necesito saber si son reales o si son un artefacto de datos incompletos:

| Indicador | Valor actual | ¿Real o artefacto? |
|---|---|---|
| Cumplimiento de mantención preventiva | **0,0 %** | 37 PM vencidos, 32 equipos sin plan, 0 al día |
| Alertas críticas abiertas | **302** en 53 equipos | doc. vencidos + GPS sin señal + incumplimiento |
| GPS sin señal >24 h | **28 de 52** mapeados | ¿equipos detenidos o falla de reporte? |
| Equipos en mantención sin operación asignada | **11** | ¿están en taller Coquimbo? |
| Costos por faena | **todos en $0** | no hay tarifa de mano de obra cargada |

---

## 4. LO QUE TE PIDO — información que el sistema NO tiene

Ordenada por impacto. Lo del bloque A es lo que realmente mueve la aguja con
un Gerente General y un Directorio: hoy el sistema es fuerte en operación y
ciego en plata.

### A. Comercial y financiero  ← PRIORIDAD 1

1. **Facturación mensual por operación y por cliente** (ene–ago 2026).
   Formato: Excel con columnas `mes | operación | cliente | contrato | monto neto`.

2. **Tarifa de arriendo por equipo** (o por tipo de equipo), en $/día o $/mes.
   *Por qué importa:* con esto el sistema calcula automáticamente el **ingreso
   perdido por cada equipo detenido**. Hoy tenemos 9 equipos fuera de servicio
   y no podemos decir cuánto cuestan.

3. **Valor y vigencia real de los contratos.** Hoy en la base, de ~12 contratos
   activos **solo 1 tiene valor cargado** y varios no tienen fecha de término.
   Necesito: `contrato | cliente | valor | fecha inicio | fecha fin | estado renovación`.

4. **Estado de cobranza / cuentas por cobrar** por cliente (al día, 30, 60, 90+).

5. **Costo hora-hombre de técnico** (por especialidad si varía) — sin esto los
   costos por OT y por faena quedan en cero.

### B. Seguridad y personas  ← PRIORIDAD 2

6. **Accidentes e incidentes** del período: fecha, operación, tipo, días perdidos.
7. **Horas-hombre trabajadas** por operación (para índice de frecuencia y gravedad).
8. **Dotación por operación**: headcount, turnos, ausentismo del mes.

### C. Contexto para el Directorio  ← PRIORIDAD 3

9. **Presupuesto 2026 vs real** (ingresos y costos, por operación).
10. **Plan de inversiones**: compras de equipos comprometidas o en evaluación.
11. **Pipeline comercial**: licitaciones presentadas, contratos en negociación,
    contratos en riesgo de no renovarse.
12. **Fecha de la reunión de Directorio** y quiénes asisten.
13. **Los 3 a 5 temas que TÚ quieres que se decidan** en esa reunión.
    (Un directorio no es un informe: es un lugar donde se aprueban cosas.)

---

## 5. Formato de entrega

Cualquiera de estos me sirve, en orden de preferencia:

1. **Excel / CSV** — lo cargo directo a la base y queda permanente (ya existen
   scripts de carga: `cargar-confiabilidad.mjs`, `cargar-status-cam.mjs`, etc.).
2. **Foto o PDF de la planilla** — lo transcribo.
3. **Me lo dictas por chat** — sirve para lo puntual (fechas, nombres, montos).

**Mínimo viable:** con los puntos **1, 2 y 3** (facturación, tarifas y contratos)
ya puedo entregar un reporte semanal que hable de dinero y no solo de fierros.
El resto lo vamos incorporando por capas.

---

## 6. Lo que yo hago mientras tanto

No te quedes esperando: con lo que ya hay en el sistema avanzo en paralelo con

- el generador del reporte semanal automático (flota, OT, NC, alertas, ENEX),
- el envío por correo con resumen + link (reusa Resend/SMTP ya configurado),
- el informe de directorio actualizado a agosto,
- el deck para proyectar.

Cuando llegue tu información, la enchufo y los números financieros aparecen solos.
