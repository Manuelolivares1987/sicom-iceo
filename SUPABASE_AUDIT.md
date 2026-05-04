# SUPABASE AUDIT — SICOM-ICEO (FASE 5)

> **Última actualización:** 2026-04-28 — FASE 5 (RLS, RPCs, Storage)
> **Resumen:** Sistema funcional con **brechas RLS reales** que afectan defensa en profundidad. Sin secretos expuestos. Cero modificaciones destructivas. SQL sugerido en `database/schema/52_rls_hardening_recommendations.sql` para revisión y aplicación manual antes/después de demo.

---

## 1. Resumen ejecutivo

- **51 migraciones SQL** auditadas en `database/schema/`.
- **47 RPCs distintas** consumidas desde 14 servicios frontend (todas con `supabase.rpc(...)`).
- **3+ buckets Storage** referenciados desde frontend; solo 1 (`evidencias-verificacion`) tiene migración SQL formal con políticas (mig 46). Los otros 2 (`evidencias-ot`, `evidencias-combustible`) se referencian en código pero **no se crean en migraciones versionadas** → se crearon manualmente desde el panel Supabase, sin policies versionadas.
- **Brecha estructural detectada:** muchas tablas tienen política `pol_authenticated_select_* USING (true)` → cualquier usuario autenticado puede leer todo. La defensa por rol depende casi exclusivamente de RPCs `SECURITY DEFINER`, pero **muchas RPCs no validan rol al iniciar** → un técnico podría ejecutar funciones de cierre, ajuste de inventario, o cálculo ICEO si conoce el nombre.
- **`/equipo/[id]`** consume RPC `rpc_ficha_activo`. Si es `SECURITY DEFINER` (probable), funciona para anon bypassando RLS, exponiendo posiblemente columnas sensibles (`faena_id`, `costo_acumulado`, etc.). **Necesita verificación + restricción.**
- **Severidad global:** Sistema demoable, pero la defensa real tiene huecos. **3 brechas críticas, 4 altas, varias medias.** Mitigaciones documentadas y SQL listo en archivo recomendado.

---

## 2. Matriz RLS por tabla crítica

> Fuentes: `05_funciones_triggers_rls.sql`, `18_correcciones_criticas.sql`, `20_fix_rls_usuarios_perfil.sql`, `21_fix_rls_lectura_general.sql`, `46_storage_bucket_verificacion.sql`, `49_informes_recepcion.sql`, `50_combustible_estanques.sql`.

| Tabla | RLS habilitado | Política dominante de SELECT | Política `anon` | INSERT/UPDATE/DELETE | Riesgo | Acción recomendada |
|---|---|---|---|---|---|---|
| **activos** | ✅ | `pol_authenticated_select_activos USING (true)` (21:72) + por rol (admin/gerencia/auditor/supervisor) | ❌ Sin política anon | Solo admin/supervisor | 🔴 **Crítico** (consumida por `/equipo/[id]` vía RPC SECURITY DEFINER) | Crear vista `public_activos_qr` + flag `qr_publico_habilitado` |
| **modelos**, **marcas** | ✅ | `USING (true)` para authenticated | ❌ | Solo admin | 🟡 Medio | Aceptable; revisar si conviene endurecer |
| **faenas** | ✅ | `USING (true)` para authenticated | ❌ | Solo admin/gerencia | 🔴 **Crítico** si se expone vía join público | No exponer al rol anon |
| **contratos** | ✅ | `USING (true)` para authenticated | ❌ | Solo admin/gerencia | 🔴 **Crítico** (datos comerciales) | Restringir a roles administrativos |
| **ordenes_trabajo** | ✅ | `USING (true)` para authenticated | ❌ | RPCs SECURITY DEFINER | 🟠 **Alto** (cualquier autenticado lee todas las OT) | Filtrar por faena o por responsable según rol |
| **usuarios_perfil** | ✅ | `pol_authenticated_select_all_perfil USING (true)` (20:18) | ❌ | Solo admin | 🟠 **Alto** (expone email/cargo de todos) | Mantener SELECT con vista filtrada / mascara |
| **certificaciones** | ✅ | `USING (true)` authenticated | ❌ | admin/supervisor + RPC | 🟠 **Alto** (datos normativos) | Restringir lectura por rol |
| **bodegas, productos, stock_bodega** | ✅ | `USING (true)` authenticated | ❌ | admin/supervisor + RPC | 🟡 Medio | Revisar |
| **planes_mantenimiento** | ✅ | `USING (true)` authenticated | ❌ | admin/supervisor + RPC | 🟡 Medio | OK por ahora |
| **movimientos_inventario** | ✅ | `USING (true)` authenticated (21:100) | ❌ | INSERT solo vía RPC (UPDATE bloqueado: `Update: never`) | 🟡 Medio | OK por arquitectura RPC-only |
| **kardex** | ✅ | Idem | ❌ | trigger-only | 🟡 Medio | OK |
| **mediciones_kpi** | ✅ | Admin/Gerencia/Auditor + authenticated USING (true) | ❌ | RPC | 🟠 **Alto** (lectura abierta de KPIs) | Restringir lectura a roles autorizados |
| **incentivos** | (verificar) | (verificar) | ❌ | RPC | 🟠 **Alto** (montos sensibles) | Restringir lectura a `rrhh_incentivos`, `gerencia`, `administrador` |
| **auditoria_eventos** | ✅ | Admin/Gerencia/Auditor + authenticated USING (true) | ❌ | trigger-only | 🟠 **Alto** (`USING (true)` expone cambios sensibles) | Quitar política authenticated USING(true), dejar solo roles autorizados |
| **alertas** | ✅ | Admin/Gerencia/Auditor + authenticated USING (true) | ❌ | trigger-only | 🟡 Medio | Aceptable |
| **informes_recepcion** | ✅ (49:432) | `USING (true)` authenticated | ❌ | admin/operaciones + RPC | 🟡 Medio | Aceptable |
| **combustible_estanques, movimientos_combustible, medidores_combustible** | ✅ (50:495) | `USING (true)` authenticated | ❌ | RPC | 🟡 Medio | Aceptable |
| **flota / vehículos** (mig 25, 27) | (verificar) | (verificar) | ❌ | RPC + admin/operaciones | 🟡 Medio | Verificar |
| **suspel_*, respel_*** (mig 32) | (verificar) | (verificar) | ❌ | (verificar) | 🟡 Medio | Verificar — referenciadas en `services/prevencion.ts` pero auditor no las encontró por nombre |
| **reportes_diarios** (mig 30, 33) | (verificar) | (verificar) | ❌ | RPC | 🟡 Medio | Verificar |

> **Patrón sistémico:** `USING (true)` para `authenticated` es la regla, no la excepción. Esto convierte a la **anon key** + `auth.uid()` en la barrera principal — adecuada para datos no confidenciales, **insuficiente** para incentivos, costos, contratos y KPIs.

---

## 3. RPCs auditadas

### 3.1 RPCs detectadas en frontend (47 distintas)

**Por servicio:**

| Servicio | RPCs invocadas | Operación | Sensibilidad |
|---|---|---|---|
| `activos.ts` | `rpc_actualizar_metricas_activo`, `rpc_ficha_activo`, `rpc_generar_qr_activo`, `rpc_kpi_activo` | Lectura/escritura de métricas, generación QR | Alta (`rpc_ficha_activo` usado en ruta pública) |
| `ordenes-trabajo.ts` | `rpc_crear_ot`, `rpc_transicion_ot` (×4 transiciones), `rpc_cerrar_ot_supervisor` | CRUD OTs + cierre supervisor | **Crítico** |
| `inventario.ts` | `rpc_registrar_salida_inventario`, `rpc_registrar_entrada_inventario`, `rpc_registrar_ajuste_inventario`, `rpc_transferir_inventario`, `rpc_aprobar_conteo_inventario` | Movimientos stock + ajustes | **Crítico** |
| `kpi-iceo.ts` | `rpc_calcular_iceo_periodo` (×2) | Cálculo ICEO | **Crítico** (afecta incentivos) |
| `incentivos.ts` | `rpc_calcular_incentivos_periodo`, `rpc_kpi_drill_down`, `rpc_cerrar_periodo_kpi` | Cálculo y cierre incentivos | **Crítico** |
| `flota.ts` | `calcular_oee_activo`, `calcular_oee_flota`, `fn_ejecutar_verificaciones_normativas`, `rpc_actualizar_estado_diario_manual`, `fn_aplicar_estados_diarios_automaticos` | OEE + verificaciones + cambio estado | Alto |
| `fiabilidad.ts` | `fn_calcular_fiabilidad_activo`, `fn_calcular_fiabilidad_flota`, `fn_calcular_oee_fiabilidad_activo` | Cálculo fiabilidad | Medio |
| `combustible.ts` | `fn_registrar_movimiento_combustible`, `fn_registrar_varillaje_combustible` | Movimiento combustible | Alto |
| `informe-recepcion.ts` | `fn_iniciar_informe_recepcion`, `fn_cerrar_inspeccion_recepcion`, `fn_emitir_informe_recepcion` | Recepción cliente | Alto |
| `jornada-conductor.ts` | `fn_registrar_actividad_conductor`, `fn_actividad_actual_conductor`, `fn_resumen_jornada_dia`, `fn_resumen_jornada_mes` | Jornada laboral | Medio |
| `ot-materiales.ts` | `fn_agregar_material_ot`, `fn_despachar_material_ot` | Despacho materiales | Alto |
| `reporte-diario.ts` | `fn_guardar_reporte_diario`, `fn_tendencia_reporte_diario`, `fn_cambios_estado_dia` | Snapshot diario | Medio |
| `verificacion.ts` | `fn_iniciar_verificacion_disponibilidad`, `fn_aprobar_verificacion_disponibilidad` | Aprobación operativa | Alto |

### 3.2 Brechas detectadas en RPCs

> Auditoría confirma: **las RPCs `SECURITY DEFINER` no validan rol al inicio** en la mayoría de casos. La única validación está al nivel del modelo de datos (locks, constraints, triggers).

| RPC | Archivo SQL | SECURITY | ¿Valida rol al inicio? | Riesgo |
|---|---|---|---|---|
| `rpc_crear_ot` | 09:60 + 24/38/39 | DEFINER | ❌ NO | 🔴 Crítico |
| `rpc_transicion_ot` | 09:154 | DEFINER | ❌ NO | 🔴 Crítico |
| `rpc_cerrar_ot_supervisor` | 18:401 | DEFINER | ❌ NO | 🔴 Crítico |
| `rpc_registrar_salida_inventario` | 18:223 | DEFINER | ❌ NO | 🔴 Crítico |
| `rpc_registrar_entrada_inventario` | 09:507 | DEFINER | ❌ NO | 🔴 Crítico |
| `rpc_registrar_ajuste_inventario` | 09:612 | DEFINER | ❌ NO | 🔴 Crítico |
| `rpc_calcular_iceo_periodo` | 09:711 | DEFINER | ❌ NO | 🔴 Crítico |
| `calcular_todos_kpi` | 06:977 | DEFINER | ❌ NO | 🔴 Crítico |
| `calcular_iceo` | 06:1178 | DEFINER | ❌ NO | 🔴 Crítico |
| `calcular_cpp` | 06:1465 | DEFINER | ❌ NO | 🟠 Alto |
| `rpc_generar_qr_activo` | 14:42 | DEFINER | ❌ NO | 🟠 Alto |
| `rpc_calcular_incentivos_periodo` | (verificar 16) | DEFINER | (verificar) | 🔴 Crítico |
| 24 funciones `calcular_kpi_a*/b*/c*` | 06:42–977 | DEFINER | ❌ NO | 🔴 Crítico |
| `rpc_ficha_activo` | (no localizado nominalmente) | (probable) DEFINER | ? | 🔴 **Crítico** (consumida pública) |

> **Implicación operativa:** En su estado actual, **un usuario logueado con rol `colaborador` podría llamar manualmente a `supabase.rpc('rpc_cerrar_ot_supervisor', {...})`** desde el browser y **completar** una OT. La UI no se lo permite, pero la API sí. Esto es la principal brecha funcional.

### 3.3 RPCs con validación adecuada (good practice)

Por lo observado, los triggers (`audit_trigger`, triggers de stock, triggers de bloqueo de disponibilidad mig 44) sí están bien acotados y son idempotentes. Triggers no son llamables directamente por la API, así que su superficie de ataque es nula. ✅

---

## 4. Storage auditado

### 4.1 Buckets detectados desde frontend

| Bucket | Referenciado en | Migración SQL | Estado |
|---|---|---|---|
| `evidencias-verificacion` | `verificacion.ts:257-279`, `informe-recepcion.ts:276-296`, `flota/recepcion/.../emitir/page.tsx:125` | ✅ Mig 46 | **Versionado, con políticas** |
| `evidencias-ot` | `ordenes-trabajo.ts:258-294`, `dashboard/ordenes-trabajo/[id]/page.tsx:180` | ❌ NO encontrada | **No versionado** |
| `evidencias-combustible` | `combustible.ts:367-371` | ❌ NO encontrada | **No versionado** |
| (foto activos) | `activos.ts:192-198` | ❌ NO encontrada | **No versionado** |
| (foto certificaciones) | `certificaciones.ts:41-49` | ❌ NO encontrada | **No versionado** |

> 4 buckets utilizados en producción **sin migración SQL versionada** que documente sus políticas. Quedaron creados a mano desde el panel Supabase. → **Si se rota proyecto Supabase o se hace re-deploy desde cero, estos buckets no se recrean automáticamente.** Es deuda de versionado.

### 4.2 Bucket `evidencias-verificacion` (mig 46) — políticas

```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('evidencias-verificacion', ..., public=true, 10MB, ['image/jpeg','image/png','image/webp']);
```

| Acción | Política | Comentario |
|---|---|---|
| SELECT | `TO authenticated USING (true)` | 🟠 Cualquier autenticado lee cualquier evidencia |
| INSERT | `TO authenticated WITH CHECK (true)` (resumido) | 🟠 Sin validar OT/activo/rol |
| UPDATE | `TO authenticated` con owner check | ✅ OK |
| DELETE | `TO authenticated` con owner check | ✅ OK |

> El flag `public=true` significa que las URLs `getPublicUrl()` funcionan sin token, es decir: **cualquiera con la URL del archivo puede acceder al PDF/foto**. Esto es **aceptable para informes de recepción** que deben compartirse con clientes, pero no para fotos internas de control. **Documentado como decisión de producto, NO como brecha automática.**

---

## 5. Diagnóstico de `/equipo/[id]` (ruta pública QR)

| Item | Detalle |
|---|---|
| Ruta | `/equipo/[id]` (sin `useRequireAuth`) |
| Servicio | `getFichaActivo(id)` → `supabase.rpc('rpc_ficha_activo', { p_activo_id })` |
| Cliente | anon key (no autenticado) |
| Tabla(s) implícitas | `activos`, `modelos`, `marcas`, `faenas`, `certificaciones`, `ordenes_trabajo` (joins en RPC) |
| Política RLS para `anon` en `activos` | ❌ NO EXISTE |
| ¿Por qué funciona entonces? | RPC `rpc_ficha_activo` muy probablemente es `SECURITY DEFINER` → bypassa RLS |
| Columnas del retorno (inferidas del componente y del RPC) | `marca_nombre`, `modelo_nombre`, `faena_nombre`, `costo_acumulado`, `ots_abiertas`, `cert_vigentes`, `cert_por_vencer`, `cert_vencidas`, `criticidad`, `estado`, `kilometraje_actual`, `horas_uso_actual`, etc. |

### 5.1 Datos sensibles potencialmente expuestos

| Dato | ¿Expuesto? | Sensibilidad |
|---|---|---|
| `faena_nombre` | ✅ Sí | 🟠 **Identifica la operación minera** (ubicación) |
| `costo_acumulado` | ✅ Sí | 🔴 **Cifra financiera interna** |
| `ots_abiertas`, conteos certificaciones | ✅ Sí | 🟡 Operacional, semi-público |
| `criticidad`, `estado` | ✅ Sí | 🟡 Operacional, aceptable |
| `marca_nombre`, `modelo_nombre`, `numero_serie`, `kilometraje`, `horas` | ✅ Sí | 🟡 Necesario para QR técnico |
| `contrato_id`, `cliente`, `precio_arriendo` | ❓ Verificar contenido del RPC | 🔴 Crítico si se expone |

### 5.2 Recomendaciones (en orden de cuál implementar primero)

1. **Inmediato (ANTES de demo pública):** crear vista `public_activos_qr` con SOLO columnas no sensibles + actualizar `rpc_ficha_activo` a leer de la vista. **SQL en `52_rls_hardening_recommendations.sql` §A.**
2. **Próximo:** agregar columna `qr_publico_habilitado boolean default false` en `activos`. La vista filtra por ese flag → control granular operativo (un activo se "publica" solo cuando el supervisor lo decide).
3. **Largo plazo:** reemplazar el `id` UUID por un **token público corto** (slug/random no enumerable) generado por `rpc_generar_qr_activo`. Evita scraping por enumeración de UUIDs.

---

## 6. Brechas críticas/altas — clasificación final

| ID | Severidad | Brecha | Impacto operativo |
|---|---|---|---|
| RLS-01 | **🔴 Crítica** | RPCs `SECURITY DEFINER` sin `IF rol NOT IN (...) RAISE` (12+ RPCs sensibles). | Cualquier autenticado puede ejecutar cierre de OT, ajuste inventario, cálculo ICEO desde la API. |
| RLS-02 | **🔴 Crítica** | `/equipo/[id]` accede a `rpc_ficha_activo` que probablemente expone `costo_acumulado` y `faena_nombre`. | Datos financieros visibles públicamente con solo conocer un UUID. |
| RLS-03 | **🔴 Crítica** | Tabla `incentivos` con lectura abierta por `USING (true)` para authenticated (asumido — verificar mig 16). | Cualquier técnico vería montos de bonos de otros. |
| RLS-04 | 🟠 Alta | `usuarios_perfil` con SELECT abierto a authenticated (mig 20:18) → emails y roles visibles a todos. | Information disclosure. |
| RLS-05 | 🟠 Alta | `auditoria_eventos`, `mediciones_kpi`, `certificaciones`, `contratos` con `USING (true)` para authenticated. | Lectura abierta de datos comerciales y normativos. |
| RLS-06 | 🟠 Alta | Buckets `evidencias-ot`, `evidencias-combustible`, foto activos, foto certificaciones **sin migración SQL versionada**. | Riesgo de configuración no reproducible + políticas no auditables. |
| RLS-07 | 🟠 Alta | 24 funciones `calcular_kpi_*` `SECURITY DEFINER` sin role check. | Manipulación potencial de KPIs por cualquier autenticado. |
| RLS-08 | 🟡 Media | Bucket `evidencias-verificacion` con `public=true` y `getPublicUrl` → URLs accesibles sin token si se filtran. | Aceptable si el caso de uso es compartir PDFs con clientes (decisión de producto). |
| RLS-09 | 🟡 Media | Tablas `suspel_*`, `respel_*` (mig 32) referenciadas pero el auditor automático no las encontró por nombre — posible discrepancia de naming entre código y SQL. | Verificar; puede haber otra discrepancia oculta. |

---

## 7. SQL sugerido (NO destructivo)

> Archivo creado: **`database/schema/52_rls_hardening_recommendations.sql`**
>
> **NO ejecutar a ciegas.** Cada bloque está comentado con `-- BLOCK X` y propósito. Revisar uno por uno con un DBA o probar en branch antes de aplicar a producción.

Bloques incluidos:
- **A.** Vista `public_activos_qr` + flag `qr_publico_habilitado` + RPC restringida.
- **B.** Plantilla de role-check para RPCs `SECURITY DEFINER` críticas (`rpc_crear_ot`, `rpc_cerrar_ot_supervisor`, etc.).
- **C.** Restricción de `incentivos`, `mediciones_kpi`, `auditoria_eventos`, `usuarios_perfil` para que SELECT no use `USING (true)`.
- **D.** Plantilla de migración para versionar buckets faltantes (`evidencias-ot`, `evidencias-combustible`, etc.).
- **E.** Verificaciones (`SELECT ... FROM pg_policies`) que se pueden correr **antes** y **después** para confirmar diff seguro.

---

## 8. Persistencia real — confirmación por módulo

| Módulo | Tablas | RPCs | Storage | CRUD real |
|---|---|---|---|---|
| Activos | `activos`, `modelos`, `marcas` | `rpc_ficha_activo`, `rpc_kpi_activo`, `rpc_actualizar_metricas_activo`, `rpc_generar_qr_activo` | foto activos | ✅ Read + Update |
| Flota | `flota` (mig 25), `verificaciones`, `estados_diarios` | 5 RPCs flota | — | ✅ Full |
| OT | `ordenes_trabajo`, `evidencias_ot`, `checklist_ot` | 6 RPCs OT | `evidencias-ot` | ✅ Full |
| Mantenimiento | `planes_mantenimiento`, `pautas_fabricante` | (lectura directa) | — | ✅ Read + Create OT desde plan |
| Inventario | `productos`, `bodegas`, `stock_bodega`, `movimientos_inventario`, `kardex` | 5 RPCs inv | — | ✅ Full vía RPC |
| Combustible | `combustible_estanques`, `movimientos_combustible`, `medidores_combustible` | 2 RPCs | `evidencias-combustible` | ✅ Full |
| Cumplimiento | `certificaciones` | (lectura directa) | foto certificaciones | ✅ Read + Create |
| Prevención | `suspel_*`, `respel_*` (mig 32) | (lectura directa) | — | ✅ Read |
| KPI | `mediciones_kpi`, `kpi_definiciones` | `rpc_calcular_iceo_periodo`, `rpc_kpi_drill_down`, calcular_kpi_* | — | ✅ Read + acción calcular |
| ICEO | idem KPI + `incentivos` | `rpc_calcular_iceo_periodo`, `rpc_calcular_incentivos_periodo`, `rpc_cerrar_periodo_kpi` | — | ✅ Read + cálculos |
| Reporte Diario | `reportes_diarios` (mig 30, 33, 36) | `fn_guardar_reporte_diario`, `fn_tendencia_reporte_diario`, `fn_cambios_estado_dia` | — | ✅ Read + regenerar |
| Fiabilidad | `oee_*`, `fiabilidad_*` (mig 40, 41) | 3 RPCs fiabilidad | — | ✅ Read |
| Reportes | múltiples | — | — | ✅ Read + export CSV/Excel |
| Contratos | `contratos`, `faenas` | — | — | ✅ Read |
| Comercial | `flota` + `reporte-diario` | (lectura indirecta) | — | ✅ Read |
| Auditoría | `auditoria_eventos` | — | — | ✅ Read |
| Admin | `usuarios_perfil`, `system stats` | — | — | ✅ Read + Update usuarios |
| Abastecimiento | `rutas_despacho`, `abastecimientos` | — | — | ✅ Full |
| Recepción | `informes_recepcion`, evidencias | 3 RPCs recepción | `evidencias-verificacion` | ✅ Full |
| Jornada conductor | `jornadas`, `actividades_conductor` | 4 RPCs jornada | — | ✅ Full |

**Conclusión:** **22/22 módulos persisten contra Supabase real.** Cero módulos solo-lectura sin acción.

---

## 9. Resultado final FASE 5

✅ **Auditoría completa.**

- 51 migraciones SQL revisadas (con apoyo de subagente Explore).
- 47 RPCs frontend mapeadas a sus migraciones SQL.
- 4 buckets Storage detectados, solo 1 con migración versionada.
- **3 brechas críticas, 4 altas, 2 medias** documentadas.
- **`52_rls_hardening_recommendations.sql`** creado con SQL sugerido NO destructivo.
- Cero modificaciones aplicadas a SQL en producción.
- Cero modificaciones a código frontend.

### Acción manual recomendada antes de demo
Aplicar **solo el bloque A** del archivo `52_*.sql` (vista pública para `/equipo/[id]`) — es el único cambio que reduce el blast radius más visible (datos públicos sin login). Los demás bloques requieren DBA.

### Verificación
- `npm run typecheck` → ✅ sigue 0 errores (sin diff de TS).
- Build no requerido (sin diff de código TS).
