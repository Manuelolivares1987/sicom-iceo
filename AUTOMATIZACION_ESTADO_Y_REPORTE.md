# Automatización: Estado de flota por geocercas + Envío automático del reporte

> **Estado:** Diseño/roadmap. Decidido 2026-05-25. Ejecutar **después del directorio**.
> Decisiones tomadas por Manuel:
> - Estado de flota: **híbrido (auto por GPS/geocerca + override manual)**.
> - Envío del reporte: **planificado** (no construido aún).

Este es el "valor agregado": que el estado de la flota se derive solo del GPS+geocercas
y que el reporte diario se envíe solo, sin trabajo manual en Excel.

---

## Lo que YA existe (base construida)

- Geocercas (círculo: centro+radio) asociadas a contrato/cliente/faena. Tipos: `base_pillado`,
  `faena_cliente`, `bodega`, `taller_externo`, `zona_restringida`, `punto_interes`. (MIG56)
- Detección de ubicación: `fn_punto_en_geocerca` + Haversine; trigger en `gps_estado_actual`
  registra entrada/salida en `gps_geocerca_eventos` + alerta. (MIG56)
- Evaluación cada 15 min `fn_evaluar_activos_fuera_geocerca`: **sugiere** cambios de estado
  comercial (arrendado→en_transito→en_recepcion) en `cambios_estado_sugeridos`. (MIG59)
- Reporte diario auto-generado (cron 06:30 Chile) con sección GPS+geocercas. (MIG33/86)

## Lo que FALTA

### PARTE A — Estado de flota híbrido (auto por geocerca + override)

Objetivo: `estado_diario_flota.estado_codigo` se derive de DÓNDE está el equipo (geocerca),
respetando override manual y la prioridad de seguridad (OT/cert).

Pasos:
1. **Mapeo geocerca → estado** (definir con Manuel):
   - dentro de `faena_cliente` (del contrato del activo) → `A` (arrendado/operativo en cliente)
   - dentro de `base_pillado` / `taller_externo` → `M`/`T` (mantención/taller)
   - dentro de `bodega` → `D` (disponible) o `H` (habilitación) — definir
   - sin señal / fuera de toda geocerca esperada >Xh → mantener último estado o marcar revisión
2. **Función `fn_estado_por_geocerca(p_activo_id, p_fecha)`**: lee `gps_estado_actual`,
   resuelve en qué geocerca está, devuelve estado_codigo sugerido (o NULL si sin señal).
3. **Integrar en la cascada** `fn_calcular_estado_diario_automatico` (database/schema/30:51-138),
   en este orden (mayor a menor prioridad):
   1. override_manual (ya existe) — **el "override" del híbrido**
   2. OT abierta (T/M) y certificación vencida (F) — seguridad, no se pisan
   3. **NUEVO: estado por geocerca** (`fn_estado_por_geocerca`)
   4. estado_comercial (fallback actual)
   5. default D
4. **Mitigar ruido GPS**: exigir N lecturas consistentes o permanencia mínima (ej. >30-60 min
   dentro/fuera) antes de cambiar; no cambiar si la última señal es vieja (>X h).

**PRERREQUISITO de datos:** debe existir una geocerca `faena_cliente` por cada faena/cliente
activo (Rentamaq, CMP, Boart Longyear, TPM, Major Drilling, CM Cenizas, etc.). Hoy hay que
verificar cobertura: sin geocerca dibujada, no hay auto-estado para ese equipo.

### PARTE B — Envío automático del reporte diario

Objetivo: el snapshot diario (cron 06:30) se envíe solo a los destinatarios.

Pasos:
1. **Proveedor de correo**: Resend (free tier simple) — requiere cuenta + API key + dominio
   verificado (o usar dominio de prueba al inicio). Guardar API key como secret de la edge function.
2. **Tabla `reporte_destinatarios`** (email, nombre, rol, activo bool, secciones[]).
3. **Edge Function `reporte-diario-enviar`**: lee el snapshot del día de `reportes_diarios_snapshot`,
   arma email HTML (resumen ejecutivo: flota por estado, OEE, alertas críticas, fuera de zona) +
   link al reporte completo, y envía vía Resend a los destinatarios activos.
4. **Cron** (pg_cron + net.http_post) ~06:45 Chile (después de generar el snapshot) que invoca
   la edge function. OJO tier Micro: es 1 invocación/día, liviano.
5. (Opcional futuro) WhatsApp vía Twilio en vez de/además de email.

---

## Tensión a resolver: fuente de verdad

Hoy los estados se cargan **manual desde Excel** (preciso). La automatización por GPS iría en
otra dirección. Con la decisión **híbrida**: el GPS/geocerca setea el estado automático y el
Excel/override manual corrige excepciones. Plan de transición: arrancar con auto+override en
paralelo al Excel, comparar contra los datos reales (ya cargados ENE-MAY) para calibrar
umbrales y cobertura de geocercas, y recién entonces dejar el GPS como fuente principal.
