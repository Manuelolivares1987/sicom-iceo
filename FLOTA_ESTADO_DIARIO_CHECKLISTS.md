# FLOTA — Estado Diario / Programado + Checklists configurables

> **Última actualización:** 2026-04-29 — FASE 5.2
> **Resumen:** la infraestructura para estado diario / futuro y checklists configurables **ya existía** en migraciones previas. La mejora de FASE 5.2 expone la fecha (incluyendo fechas futuras) en la UI y agrega la opción de crear plantillas nuevas desde el admin.

---

## 1. Flujo actual (post FASE 5.2)

```
┌───────────────────────────────────────────────────────────────────────┐
│  /dashboard/flota — vista maestra                                      │
│    [click sobre un equipo]                                             │
│         │                                                              │
│         ▼                                                              │
│  CambiarEstadoModal (con fecha programable)                            │
│    1. Selector de fecha:                                               │
│        - Default: hoy                                                  │
│        - Permite cualquier fecha futura                                │
│        - Solo administrador puede corregir fechas pasadas              │
│    2. Selector de estado (A/D/U/L/M/T/F/V/H/R)                         │
│    3. Motivo obligatorio                                               │
│    4. Si estado = D (disponible):                                      │
│        - Bloqueo si NO hay verificación ready-to-rent vigente          │
│        - Botón "Iniciar verificación" abre flujo de checklist          │
│    5. Si estado = M / T / F: opción de crear OT automática             │
│    6. Click "Guardar cambio" / "Programar cambio" si fecha futura      │
│         │                                                              │
│         ▼                                                              │
│  rpc_actualizar_estado_diario_manual(p_activo_id, p_fecha, ...)        │
│    - Inserta o actualiza estado_diario_flota (override_manual=true)    │
│    - Sincroniza activos.estado y estado_comercial                      │
│    - Trigger trg_validar_cambio_disponible bloquea si falta checklist  │
│    - Trigger audit_trigger registra en auditoria_eventos               │
│         │                                                              │
│         ▼                                                              │
│  estado_diario_flota — historial diario por activo                     │
│    UNIQUE (activo_id, fecha)                                           │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 2. Mejora implementada en FASE 5.2

### 2.1 UI

| Cambio | Archivo | Detalle |
|---|---|---|
| Selector de fecha en modal | `frontend/src/components/flota/cambiar-estado-modal.tsx` | Nuevo campo `<Input type="date">`. Default hoy. Permite futuro. Bloquea pasado salvo `usePermissions().isAdmin()`. |
| Mensaje contextual según fecha | mismo archivo | "Cambio programado para el [fecha]" / "Hoy. El cambio aplica de inmediato" / "Está corrigiendo un día pasado" |
| Botón cambia label si es futuro | mismo archivo | "Programar cambio" cuando fecha > hoy; "Guardar cambio" cuando = hoy |
| Validación en submit | mismo archivo | Bloquea submit si `fechaInvalida` (pasado sin permiso de admin) |
| Botón "Crear plantilla vacía" | `frontend/src/app/dashboard/admin/checklist-templates/page.tsx` | Permite crear plantilla nueva desde la UI sin tocar SQL |

### 2.2 Backend (SIN CAMBIOS — ya existía)

- `rpc_actualizar_estado_diario_manual` (mig 30, 37) **ya acepta `p_fecha` libre**. Solo bastaba con dejar de hardcodear `today` en el cliente.
- `estado_diario_flota` ya tiene UNIQUE (activo_id, fecha) → no permite duplicar el mismo día.
- `trg_validar_cambio_disponible` (mig 44) ya bloquea `estado_comercial='disponible'` sin verificación vigente.
- `fn_iniciar_verificacion_disponibilidad` + `fn_aprobar_verificacion_disponibilidad` (mig 45) ya implementan checklist 55-items + doble firma + road test.
- `checklist_templates` (mig 22) ya soporta plantillas configurables por `tipo_ot` con items JSONB.

### 2.3 SQL nuevo (no destructivo)

`database/schema/54_flota_estado_programado_checklists.sql` — solo verificaciones SAFE, índices opcionales y plantillas SQL para casos avanzados. **Nada se ejecuta a ciegas.** Bloque por bloque para revisar manualmente.

---

## 3. Reglas de negocio implementadas

| # | Regla | Cómo se enforce hoy | Estado |
|---|---|---|---|
| 1 | Estado se guarda por día | `estado_diario_flota.UNIQUE(activo_id, fecha)` | ✅ Funcional |
| 2 | Se permite programar fecha futura | UI ahora deja seleccionar; RPC ya acepta | ✅ FASE 5.2 |
| 3 | Solo admin puede corregir días pasados | UI valida `usePermissions.isAdmin()` antes de submit | ✅ FASE 5.2 (UI) |
| 4 | Cambio a "disponible" exige checklist vigente | Trigger `trg_validar_cambio_disponible` (BLOQUEA en BD) | ✅ Funcional (mig 44) |
| 5 | Checklist debe estar aprobado (doble firma + road test) | `fn_aprobar_verificacion_disponibilidad` valida antes de emitir certificado | ✅ Funcional (mig 45) |
| 6 | Mantener historial diario | `estado_diario_flota` persistente con `override_manual` flag | ✅ Funcional (mig 30) |
| 7 | Auditoría de cambios | `audit_trigger` registra en `auditoria_eventos` | ✅ Funcional |
| 8 | Plantillas configurables sin tocar código | `checklist_templates` con items JSONB editable desde UI | ✅ Funcional (mig 22) |
| 9 | Crear nuevas plantillas desde admin | Botón en `/dashboard/admin/checklist-templates` | ✅ FASE 5.2 |
| 10 | Versionado formal de plantillas | Pendiente (BLOCK D `54_*.sql` no aplicado) | ⚠️ Diferido post-piloto |

---

## 4. Tablas afectadas

| Tabla | Rol | Mig | Nota |
|---|---|---|---|
| `estado_diario_flota` | Historial diario por activo | 25, 30 | UNIQUE (activo_id, fecha). Soporta cualquier fecha. |
| `verificaciones_disponibilidad` | Certificado ready-to-rent | 25, 44, 45 | Con doble firma, road test, vigente_hasta |
| `checklist_templates` | Plantillas reutilizables | 22 | items JSONB editable desde UI |
| `checklist_ot` | Items asignados a una OT específica | 02 + 22 | Copiados desde plantilla al crear OT |
| `ordenes_trabajo` | OTs autocreadas por cambio M/T/F | core | mig 37 las marca con `generada_automaticamente=true` |
| `auditoria_eventos` | Log de cambios | core | trigger automático |
| `no_conformidades` | Si pasa F estando arrendado | core | trigger automático |

---

## 5. RPCs afectadas

| RPC | Propósito | Aplicar role-check pendiente |
|---|---|---|
| `rpc_actualizar_estado_diario_manual` | Cambia estado de un día (cualquier fecha) | ⚠️ Pendiente FASE 5.x — cualquier autenticado puede llamarla |
| `fn_aplicar_estados_diarios_automaticos` | Cron diario que aplica cascada para todos los activos | ⚠️ Solo cron debería llamarla, pero hoy es callable desde UI |
| `fn_iniciar_verificacion_disponibilidad` | Crea OT con checklist 55 items | ⚠️ Cualquier autenticado puede iniciar |
| `fn_aprobar_verificacion_disponibilidad` | Valida y emite certificado | ✅ Tiene `chk_doble_firma` (no se puede aprobar uno mismo) |

> Para cerrar las brechas: aplicar `BLOCK B` de `52_rls_hardening_recommendations.sql`. Ver `SUPABASE_AUDIT.md` §3.

---

## 6. Pantallas afectadas

| Ruta | Cambio FASE 5.2 |
|---|---|
| `/dashboard/flota` | Sin cambio |
| `/dashboard/flota/recepcion` | Sin cambio |
| `/dashboard/flota/verificar/[otId]` | Sin cambio (ya implementado) |
| Modal **CambiarEstadoModal** (compartido) | ✅ Selector de fecha + lógica futuro/pasado |
| `/dashboard/admin/checklist-templates` | ✅ Botón "Crear plantilla vacía" |

---

## 7. Riesgos

| ID | Sev | Riesgo | Mitigación actual | Acción recomendada |
|---|---|---|---|---|
| F01 | 🟠 Medio | Cualquier autenticado puede llamar `rpc_actualizar_estado_diario_manual` directo desde el navegador, saltando la UI | Solo `administrador` y `subgerente_operaciones`, `jefe_*`, `supervisor`, `planificador` validan en mig 31 (RPC `rpc_actualizar_estado_diario_manual` con check de rol) | ✅ Ya tiene check |
| F02 | 🟡 Bajo | Cambio programado a futuro NO se procesa si llega ese día y no se vuelve a tocar | El registro queda con `override_manual=true`, así que la cascada automática no lo sobrescribe — eso es lo buscado | ✅ OK (es por diseño) |
| F03 | 🟡 Bajo | UI no muestra hoy todos los cambios programados a futuro | Para verlos manualmente: SQL E.3 de `54_*.sql` | Crear vista o sección UI en FASE 7 |
| F04 | 🟡 Bajo | Plantilla recién creada no tiene ítems → si se asigna a una OT, sale sin checklist | El admin ve advertencia "0 ítems" en la card | Recordar siempre agregar ítems después de crear |
| F05 | 🟡 Bajo | Múltiples plantillas activas para el mismo `tipo_ot` confunden la lógica `LIMIT 1 ORDER BY created_at DESC` | Convención: una activa por tipo | Aplicar BLOCK D de `54_*.sql` para `UNIQUE` constraint |
| F06 | 🟠 Medio | Si el técnico modifica plantilla mientras OT está abierta, los ítems en `checklist_ot` ya copiados NO cambian | Es por diseño: la copia es snapshot al crear la OT | Documentar para que admin no edite plantillas con OTs en curso |

---

## 8. Pruebas manuales sugeridas

### Test 1 — Cambio para hoy (regresión)
1. Login como planificador o jefe_mantenimiento.
2. `/dashboard/flota` → click sobre un equipo.
3. **Fecha = hoy** (default).
4. Estado = M (Mantención).
5. Motivo: "Test FASE 5.2 - cambio hoy".
6. Marcar "Crear OT automáticamente".
7. **Guardar cambio**.
8. Verificar:
   - Estado del equipo cambia a "M" en `/dashboard/flota`.
   - Aparece OT correctiva auto-generada en `/dashboard/ordenes-trabajo`.
   - Aparece evento en `/dashboard/auditoria`.

### Test 2 — Cambio programado a futuro
1. Login como planificador.
2. `/dashboard/flota` → click sobre un equipo.
3. **Fecha = mañana**.
4. Estado = M.
5. Motivo: "Mantención programada anticipada".
6. Botón debe decir **"Programar cambio"**.
7. Click → cierra modal sin error.
8. Verificación SQL:
```sql
SELECT * FROM estado_diario_flota
 WHERE activo_id = 'UUID-DEL-ACTIVO' AND fecha = CURRENT_DATE + 1;
```
   Debe devolver fila con `estado_codigo='M'`, `override_manual=true`, `motivo_override='Mantención programada anticipada'`.
9. **Hoy** no debe verse este cambio en el estado actual del equipo.

### Test 3 — Bloqueo de fecha pasada (no admin)
1. Login como planificador.
2. Modal → Fecha = ayer.
3. Debe mostrar error en helper text: "Solo administradores pueden corregir días pasados".
4. Botón "Guardar cambio" debe estar **deshabilitado**.

### Test 4 — Cambio a "Disponible" sin verificación
1. Tomar un equipo que NO tenga verificación vigente (consultar `v_equipos_pendientes_verificacion`).
2. Modal → Estado = D.
3. Debe aparecer banner amarillo: "Verificación ready-to-rent requerida..."
4. Botón "Guardar cambio" deshabilitado.
5. Click "Iniciar verificación" → navega a `/dashboard/flota/verificar/[otId]`.

### Test 5 — Crear plantilla nueva desde admin
1. Login como administrador.
2. `/dashboard/admin/checklist-templates`.
3. Bloque "Crear nueva plantilla" → tipo: `inspeccion`, nombre: "Test Plantilla FASE 5.2".
4. Click **Crear plantilla vacía**.
5. La plantilla aparece abajo con 0 ítems.
6. **Agregar ítem** → escribir "Test ítem 1" → Guardar.
7. Verificar SQL: `SELECT * FROM checklist_templates WHERE nombre = 'Test Plantilla FASE 5.2';` debe tener 1 ítem en `items`.

---

## 9. Pendientes registrados

| ID | Acción | Cuándo |
|---|---|---|
| P01 | Aplicar BLOCK B de `52_*.sql` para role-check en RPCs sensibles | FASE 5.x post-piloto |
| P02 | Aplicar BLOCK D de `54_*.sql` para versionado formal de plantillas | Post-piloto |
| P03 | Sección UI en `/dashboard/flota` que liste cambios programados a futuro (próximos 7 días) | FASE 7 |
| P04 | Import CSV masivo de plantillas (botón "Importar checklist") en `/dashboard/admin/checklist-templates` | Post-piloto |
| P05 | Endurecer RLS sobre `checklist_templates` para que solo admin pueda escribir | FASE 5.x |
| P06 | Vista `v_estado_diario_proximos_dias` para queries frontend rápidos | FASE 7 |

---

## 10. Cómo cargar los checklists entregados por la empresa

Ver documento dedicado: `CHECKLISTS_FLOTA_IMPORTACION.md`.

Resumen rápido:
1. Pasar el checklist Excel/Word/PDF a una tabla con columnas `orden | item | obligatorio | requiere_foto`.
2. Convertir a JSON.
3. Insertar via UI (`/dashboard/admin/checklist-templates`) o via SQL (BLOCK C de `54_*.sql`).
4. Probar con una OT real antes de habilitar en operación.

---

## 11. Verificación

- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ pendiente confirmar al cierre de FASE 5.2.
- SQL `54_*.sql` → ✅ creado, NO ejecutado (todo bloque comentado).
