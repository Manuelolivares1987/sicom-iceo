# PILOTO OPERATIVO — SICOM-ICEO

> **Última actualización:** 2026-04-28 — FASE 5.1
> **Objetivo:** Plan de estabilización y operación controlada por 7 días con roles definidos. Reducir riesgo operativo sin frenar el uso real.

---

## 1. Módulos habilitados por rol (resumen)

> Marca: ✅ Visible y CRUD, 👁️ Solo lectura, ⚠️ Acción crítica con RLS pendiente, ❌ No accesible.

| Módulo | admin | gerencia | subgerente | jefe_mant | supervisor | tecnico | bodeguero | abast. | prevenc. | auditor | rrhh |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Dashboard | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ |
| Activos | ✅ | 👁️ | 👁️ | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | ❌ |
| Flota | ✅ | 👁️ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | 👁️ | 👁️ | ❌ |
| Mis OTs | ✅ | 👁️ | 👁️ | ✅ | ✅ | ✅ | 👁️ | ❌ | ❌ | 👁️ | ❌ |
| Órdenes de Trabajo | ✅ | 👁️ | ⚠️ aprobar | ⚠️ crear/cerrar | ⚠️ aprobar | 👁️ asignadas | 👁️ | ❌ | 👁️ | 👁️ | ❌ |
| Mantenimiento | ✅ | 👁️ | 👁️ | ✅ | ✅ | 👁️ | ❌ | ❌ | ❌ | 👁️ | ❌ |
| Inventario | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | ⚠️ movs/ajustes | 👁️ alta limitada | ❌ | 👁️ | ❌ |
| Combustible | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | ⚠️ movs/varillaje | ❌ | 👁️ | ❌ |
| Prevención | ✅ | 👁️ | 👁️ | ❌ | 👁️ | ❌ | ❌ | ❌ | ✅ | 👁️ | ❌ |
| Cumplimiento | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | ❌ | ❌ | ❌ | ✅ | 👁️ | ❌ |
| Fiabilidad | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | ❌ | ❌ | ❌ | ❌ | 👁️ | ❌ |
| KPI | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | ❌ | ❌ | ❌ | ❌ | 👁️ | 👁️ |
| ICEO | ⚠️ calc | 👁️ | ⚠️ calc | ❌ | 👁️ | ❌ | ❌ | ❌ | ❌ | 👁️ | 👁️ |
| Reportes | ✅ | ✅ exportar | ✅ exportar | ✅ exportar | ✅ exportar | ❌ | ✅ | ❌ | ✅ exportar | ✅ exportar | ✅ exportar |
| Reporte Diario | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | 👁️ | ❌ | ❌ | 👁️ | 👁️ | ❌ |
| Contratos | ✅ | 👁️ | 👁️ | 👁️ | 👁️ | ❌ | ❌ | ❌ | ❌ | 👁️ | ❌ |
| Comercial | ✅ | 👁️ | 👁️ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 👁️ | ❌ |
| Abastecimiento | ✅ | 👁️ | 👁️ | ❌ | 👁️ | 👁️ | ❌ | ✅ | ❌ | 👁️ | ❌ |
| Auditoría | ✅ | 👁️ | 👁️ | ❌ | 👁️ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Administración | ✅ usuarios | 👁️ general | 👁️ general | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Equipo (público) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 2. Acciones críticas — estado de gating

| Acción | RPC | Filtro UI | Filtro RLS / SECURITY DEFINER | Estado |
|---|---|---|---|---|
| Crear OT | `rpc_crear_ot` | ❌ Sin gating UI | ⚠️ RPC sin role-check | **Pendiente FASE 5.x** |
| Editar OT | UPDATE directo | ❌ | RLS authenticated USING(true) | **Pendiente FASE 5.x** |
| Transicionar OT | `rpc_transicion_ot` | ❌ | ⚠️ RPC sin role-check | **Pendiente FASE 5.x** |
| Cerrar OT supervisor | `rpc_cerrar_ot_supervisor` | ❌ | ⚠️ RPC sin role-check | **Pendiente FASE 5.x** |
| Aprobar OT | `rpc_transicion_ot` | ❌ | ⚠️ | **Pendiente FASE 5.x** |
| Salida inventario | `rpc_registrar_salida_inventario` | ❌ | ⚠️ | **Pendiente FASE 5.x** |
| Entrada inventario | `rpc_registrar_entrada_inventario` | ❌ | ⚠️ | **Pendiente FASE 5.x** |
| Ajuste inventario | `rpc_registrar_ajuste_inventario` | ❌ | ⚠️ | **Pendiente FASE 5.x** |
| Aprobar conteo | `rpc_aprobar_conteo_inventario` | ❌ | ⚠️ | **Pendiente FASE 5.x** |
| Calcular ICEO | `rpc_calcular_iceo_periodo` | ❌ | ⚠️ | **Pendiente FASE 5.x** |
| Calcular incentivos | `rpc_calcular_incentivos_periodo` | ❌ | ⚠️ | **Pendiente FASE 5.x** |
| Cerrar período KPI | `rpc_cerrar_periodo_kpi` | ❌ | ⚠️ | **Pendiente FASE 5.x** |
| Editar usuarios | `updateUsuario` | ✅ **(FASE 5.1)** | ⚠️ RLS pendiente | **Mejorado** |
| Cambiar roles | `updateUsuario` | ✅ **(FASE 5.1)** | ⚠️ RLS pendiente | **Mejorado** |
| Exportar reportes | (CSV/Excel client) | El menú filtra; los botones exportar no están gated por permiso | OK (datos vienen RLS-filtrados) | OK |
| Ver auditoría | `getEventosAuditoria` | El menú filtra | RLS authenticated USING(true) | **Pendiente FASE 5.x** |
| Subir evidencias OT | `supabase.storage.upload` | ❌ | Bucket sin policies versionadas | **Pendiente FASE 5.x** |
| Movimiento combustible | `fn_registrar_movimiento_combustible` | ❌ | ⚠️ | **Pendiente FASE 5.x** |

> **Estrategia de mitigación durante el piloto:** dado que muchas acciones críticas dependen de RLS para enforcement real (FASE 5 detectó brechas), la **mitigación operativa** es:
> - Los usuarios reciben formación previa sobre qué pueden hacer.
> - El administrador audita diariamente el log de `/dashboard/auditoria`.
> - El acceso al sistema se otorga **solo a personas confiables** durante esta ola.
> - Las brechas RLS de la FASE 5 deben cerrarse antes de abrir el piloto a usuarios externos o partners.

---

## 3. Módulos restringidos temporalmente para el piloto

| Ruta | Razón | Recomendación |
|---|---|---|
| `/dashboard/admin/gps` | Depende de hardware GPS externo no validado | No abrir en demo o piloto si no hay trackers conectados |
| `/dashboard/inventario/scanner` | Requiere cámara, permisos de navegador, no testeado en todos los devices | Solo abrir en device pre-validado |
| `/dashboard/inventario/cargar-maestro` | Bundle 414 KB; carga lenta | Uso administrativo offline, no en presentación |
| `/dashboard/flota/recepcion/[informeId]/emitir` | Bundle 597 KB (PDF); carga lenta | Solo abrir con un informe pre-cargado |
| `/equipo/[id]` (público QR) | Expone columnas sensibles si RLS no filtra | Aplicar Block A de `database/schema/52_*.sql` antes de habilitar QR público |

---

## 4. Acciones bloqueadas / Acciones bajo observación durante el piloto

### 4.1 Acciones que **NO** se ejecutan durante el piloto (acuerdo operativo)

- **Cierre de período KPI** — solo al final del mes calendario, con autorización del administrador.
- **Cálculo de incentivos** — solo en presencia del administrador o gerencia.
- **Eliminación de OTs** — operativamente prohibido; cancelar en lugar de eliminar.
- **Carga masiva de inventario** — solo con backup de la BD del día anterior.

### 4.2 Acciones bajo observación reforzada

- Cambio de estado de flota (especialmente paso a "fuera de servicio").
- Ajustes de inventario (positivos y negativos).
- Transiciones de OT a "no_ejecutada".

---

## 5. Cómo reportar errores

1. **Capturar:**
   - URL completa donde ocurre el error.
   - Pasos para reproducir.
   - Captura de pantalla del error / consola.
   - Email del usuario que reportó.
   - Hora aproximada (zona Chile).

2. **Reportar a:**
   - Canal Slack `#sicom-piloto` (o similar) — **inmediato**.
   - Issue en GitHub si el equipo tiene repo accesible.

3. **El administrador debe:**
   - Revisar el evento en `/dashboard/auditoria` filtrando por `usuario_id` y franja horaria.
   - Si afecta datos: hacer snapshot SQL antes de intervenir.
   - Si es un bug funcional: documentar y abrir issue.

---

## 6. Checklist diario del administrador (rutina piloto)

### Mañana (10 min)
- [ ] Verificar que `/dashboard/reporte-diario` generó snapshot del día anterior.
- [ ] Revisar `/dashboard/auditoria` últimas 24 h: ¿hay acciones inusuales? (¿alguien intentó eliminar?)
- [ ] Confirmar que el dashboard ejecutivo carga sin errores con todos los roles activos.
- [ ] Ver `/dashboard/cumplimiento` — ¿hay certificaciones que vencieron hoy?

### Mediodía (5 min)
- [ ] Revisar tickets `#sicom-piloto` o cola de issues.
- [ ] Verificar que las OTs creadas por la mañana siguen en estado coherente.

### Tarde (10 min)
- [ ] Revisar movimientos de inventario del día.
- [ ] Si hubo cambios de estado de flota, validar el motivo.
- [ ] Confirmar que el cron de `reporte_diario` corre a la hora configurada (mig 30, 33).
- [ ] Backup manual del estado de `usuarios_perfil` si hubo cambios.

### Semanal (30 min)
- [ ] Exportar reporte de OTs cerradas de la semana.
- [ ] Exportar log de auditoría completo.
- [ ] Revisar valorización de inventario vs semana anterior.
- [ ] Reunión de retroalimentación con usuarios piloto.

---

## 7. Plan de estabilización 7 días

### Día 1 — Lunes: arranque controlado
- Solo usuarios `administrador`, `subgerente_operaciones`, `supervisor` activos.
- Rondar los flujos de `/dashboard/flota`, `/dashboard/ordenes-trabajo`.
- Capturar issues. Cero alta de datos críticos.

### Día 2 — Martes: incorporar mantenimiento + bodega
- Activar `jefe_mantenimiento`, `tecnico_mantenimiento`, `bodeguero`.
- Probar ciclo: crear OT → asignar técnico → ejecutar → cerrar.
- Probar inventario: salida con OT.

### Día 3 — Miércoles: incorporar prevención + abastecimiento
- Activar `prevencionista`, `operador_abastecimiento`.
- Probar combustible: registrar varillaje + movimiento con foto.
- Probar prevención: SUSPEL/RESPEL + certificaciones.

### Día 4 — Jueves: incorporar gerencia + auditor
- Activar `gerencia`, `auditor`.
- Verificar que solo ven (no mutan).
- Validar ICEO histórico, KPI drill-down.

### Día 5 — Viernes: incorporar rrhh_incentivos
- Activar `rrhh_incentivos`.
- Cálculo de incentivos del mes (con autorización).
- Cerrar primera semana con reporte ejecutivo.

### Día 6 — Sábado: revisión técnica
- Backup completo de DB.
- Aplicar Block A de `52_rls_hardening_recommendations.sql` (vista pública QR).
- Revisar logs de auditoría completos de la semana.
- Documentar bugs encontrados.

### Día 7 — Domingo: planificar siguiente sprint
- Triage de issues acumulados.
- Decidir si se aplican Blocks B/C/D del SQL hardening.
- Decidir si se incorporan los roles secundarios (jefe_operaciones, planificador, comercial, colaborador).

---

## 8. Datos a revisar cada día

| Dato | Dónde | Esperado | Acción si falla |
|---|---|---|---|
| Snapshot reporte_diario del día anterior | `/dashboard/reporte-diario` | Existe y consistente | Regenerar manualmente |
| Eventos auditoría últimas 24h | `/dashboard/auditoria` | Sin INSERT/UPDATE/DELETE inesperados | Investigar usuario |
| OTs creadas y cerradas | `/dashboard/ordenes-trabajo` | Coherente con operación reportada | Reconciliar con supervisor |
| Movimientos inventario | `/dashboard/inventario` | Sin ajustes manuales sin justificar | Pedir explicación al bodeguero |
| Estado flota | `/dashboard/flota` | Distribución estable | Investigar cambios masivos |
| Certificaciones por vencer | `/dashboard/cumplimiento` | Alertas activas | Coordinar con prevencionista |
| ICEO período actual | `/dashboard/iceo` | Trends razonables | Investigar saltos |
| Logins fallidos | Supabase Dashboard → Auth | Pocos | Investigar si son repetidos |

---

## 9. Recomendaciones finales para el piloto

1. **Aplicar Block A** de `database/schema/52_rls_hardening_recommendations.sql` antes de habilitar QR público en terreno.
2. **No abrir el sistema a usuarios externos** hasta cerrar las brechas RLS de FASE 5.
3. **Cuenta admin única y supervisada** durante esta ola.
4. **Backup diario** de la BD durante los primeros 7 días.
5. **Bitácora de cambios** en hoja de cálculo separada para validar contra `auditoria_eventos`.

---

## 10. Mejora FASE 5.2 — Estado diario / futuro de flota (2026-04-29)

### Qué cambió en la operación

- **Modal "Cambiar Estado de Equipo"** ahora tiene **selector de fecha**.
  - Default: hoy.
  - Permite **fecha futura** (programar cambio).
  - Bloquea fecha pasada salvo rol `administrador`.
  - El botón cambia a "Programar cambio" cuando la fecha es futura.

- **Página `/dashboard/admin/checklist-templates`** ahora permite **crear plantillas nuevas desde la UI** (antes solo editar existentes).

### Casos de uso operativos cubiertos

| Caso | Procedimiento |
|---|---|
| Equipo entra a mantención mañana | Eduardo (planificador): abre modal → fecha = mañana → estado = M → Programar cambio |
| Corregir estado de ayer | Solo administrador: abre modal → fecha = ayer → ajusta → Guardar |
| Cliente avisa que retira equipo el viernes | Planificador: programa cambio a estado A para el viernes |
| Cargar checklist nuevo del cliente | Admin: `/dashboard/admin/checklist-templates` → "Crear plantilla vacía" → agregar ítems uno por uno O usar BLOCK C de `54_*.sql` para insertar JSON masivo |

### Documentación operativa

- Flujo completo + 5 tests manuales: `FLOTA_ESTADO_DIARIO_CHECKLISTS.md`.
- Cómo importar checklists entregados por empresa: `CHECKLISTS_FLOTA_IMPORTACION.md`.

### Recordatorios al administrador

- ⚠️ El cambio "programado a futuro" se persiste en `estado_diario_flota` con `override_manual=true`. La cascada automática (cron diario) NO lo sobrescribe.
- ⚠️ Si una plantilla nueva queda con 0 ítems, las OTs creadas para ese tipo no tendrán checklist. Siempre agregar ítems después de crear.
- ⚠️ No editar plantillas mientras hay OTs en ejecución que las usaron — los ítems en `checklist_ot` ya están copiados, no se actualizan retroactivamente. Es por diseño (snapshot al crear OT).
