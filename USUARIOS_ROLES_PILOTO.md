# USUARIOS Y ROLES PARA PILOTO OPERATIVO — SICOM-ICEO

> **Última actualización:** 2026-04-28 — FASE 5.1
> **Estado:** Sistema apto para piloto controlado con 11 roles prioritarios definidos.

---

## 1. Roles existentes detectados

### 1.1 Coherencia frontend ↔ DB

| Origen | Cantidad | Detalle |
|---|---|---|
| `frontend/src/types/enums.ts` (`RolUsuario`) | 15 | administrador, gerencia, subgerente_operaciones, supervisor, planificador, tecnico_mantenimiento, bodeguero, operador_abastecimiento, auditor, rrhh_incentivos, jefe_operaciones, jefe_mantenimiento, comercial, prevencionista, colaborador |
| `frontend/src/hooks/use-permissions.ts` (matriz) | 15 | Idénticos al enum. **Coinciden 100%.** |
| DB `rol_usuario_enum` (mig 02 + 31) | 15 | Idénticos al enum frontend. **Sincronizados.** |
| Tabla `_roles_matriz_permisos` (mig 31) | 15 | Documentación viva en DB. |

✅ **No hay drift entre frontend y DB.**

### 1.2 Auditoría: ¿qué admin podía asignar antes vs ahora?

| Rol | En enum DB | En use-permissions | En modal admin (antes de FASE 5.1) | En modal admin (después de FASE 5.1) |
|---|---|---|---|---|
| administrador | ✅ | ✅ | ✅ | ✅ |
| gerencia | ✅ | ✅ | ✅ | ✅ |
| subgerente_operaciones | ✅ | ✅ | ✅ | ✅ |
| supervisor | ✅ | ✅ | ✅ | ✅ |
| planificador | ✅ | ✅ | ✅ | ✅ |
| tecnico_mantenimiento | ✅ | ✅ | ✅ | ✅ |
| bodeguero | ✅ | ✅ | ✅ | ✅ |
| operador_abastecimiento | ✅ | ✅ | ✅ | ✅ |
| auditor | ✅ | ✅ | ✅ | ✅ |
| rrhh_incentivos | ✅ | ✅ | ✅ | ✅ |
| **jefe_operaciones** | ✅ | ✅ | ❌ **faltaba** | ✅ |
| **jefe_mantenimiento** | ✅ | ✅ | ❌ **faltaba** | ✅ |
| **comercial** | ✅ | ✅ | ❌ **faltaba** | ✅ |
| **prevencionista** | ✅ | ✅ | ❌ **faltaba** | ✅ |
| **colaborador** | ✅ | ✅ | ❌ **faltaba** | ✅ |

✅ **Brecha cerrada en FASE 5.1:** el modal `EditarUsuarioModal` ya soporta los 15 roles del enum.

### 1.3 Migraciones de usuarios demo detectadas

| Migración | Propósito | Estado |
|---|---|---|
| `23_usuarios_demo.sql` | Seed parcial de 5 perfiles (operador, supervisor, bodeguero, planificador, gerencia) | **Comentado** (espera UUIDs reales del Supabase Auth Dashboard) |
| `35_seed_usuarios_perfil_completo.sql` | Seed completo de 14 perfiles para los 15 roles | **Comentado** (espera UUIDs reales). Solo el bloque `DO $$ ... $$` de verificación se ejecuta. |
| `31_perfiles_usuario_extendidos.sql` | Extiende `rol_usuario_enum` con 5 roles nuevos (jefe_operaciones, jefe_mantenimiento, comercial, prevencionista, colaborador) + crea funciones helper `fn_user_has_any_role`, `fn_user_is_gerencia`, `fn_user_is_operaciones`, etc. + tabla `_roles_matriz_permisos` | ✅ Aplicado |

---

## 2. Roles prioritarios para piloto (11)

> Roles **secundarios** (los 4 restantes: `jefe_operaciones`, `planificador`, `colaborador`, `comercial`) **NO se eliminan** — solo se clasifican como secundarios para la primera ola del piloto. Se pueden activar después.

### 2.1 Matriz de roles para piloto

| Rol | Perfil recomendado | Módulos que debe ver | Acciones que puede hacer | Acciones que NO debe hacer |
|---|---|---|---|---|
| **administrador** | TI / responsable del sistema | Todos | CRUD total, configurar parámetros, gestionar usuarios | — |
| **gerencia** | Gerente / dueño | Todos (lectura) | Ver dashboards, KPI, ICEO, exportar reportes | Editar OTs, mover inventario, calcular incentivos |
| **subgerente_operaciones** | Subgerente Ops | Todos operativos | Ver, exportar, aprobar OTs, editar flota, calcular ICEO | Editar usuarios, cambiar parámetros sistema |
| **jefe_mantenimiento** | Jefe taller | OT, Mantenimiento, Activos, Flota, Inventario (lectura) | Crear/editar/aprobar OTs, gestionar planes PM, editar activos | Aprobar incentivos, cambiar usuarios, contratos |
| **supervisor** | Supervisor de faena | OT, Mis OTs, Flota, Mantenimiento, Cumplimiento, KPI (lectura) | Crear/editar/aprobar OTs, cerrar OTs supervisor, editar flota | Calcular incentivos, editar usuarios, ICEO calc |
| **tecnico_mantenimiento** | Técnico de terreno | Mis OTs, Activos (lectura), Inventario (lectura), OT detalle | Editar OTs asignadas, subir evidencias, completar checklist | Crear OT desde cero, cerrar como supervisor, ver KPI/ICEO/Incentivos |
| **bodeguero** | Encargado bodega | Inventario, Activos (lectura), OT (lectura) | Movimientos inventario, conteos, salidas, ajustes | Cierre OT, KPI/ICEO, configurar usuarios |
| **operador_abastecimiento** | Operador combustibles | Abastecimiento, Combustible, Inventario (limitado) | Crear movimientos combustible, registrar varillaje, despachos | Cerrar OT, calcular incentivos |
| **prevencionista** | Prevencionista de riesgos | Prevención, Cumplimiento, Reportes | CRUD prevención, certificaciones (alta/edición), exportar | OT, inventario, KPI/ICEO |
| **auditor** | Auditor interno/externo | Todos (solo lectura) + Auditoría | Ver eventos auditoría, exportar reportes | Cualquier mutación |
| **rrhh_incentivos** | RRHH / Compensaciones | KPI, ICEO, Incentivos, Reportes (lectura) | Ver KPIs, ver incentivos calculados, exportar | Calcular ICEO, modificar OT, editar usuarios |

### 2.2 Roles secundarios (no priorizados para piloto, pero NO eliminados)

| Rol | Razón de postergar | Cuándo activar |
|---|---|---|
| `jefe_operaciones` | Solapa con `subgerente_operaciones` y `supervisor` | Si la organización lo requiere por estructura |
| `planificador` | Solapa con `jefe_mantenimiento` para crear OTs | Cuando exista figura específica de planificación |
| `colaborador` | Demasiado genérico (lectura básica de varios módulos) | Para usuarios con permisos limitados específicos |
| `comercial` | Si no hay equipo comercial separado, lo cubre `subgerente_operaciones` | Cuando se incorpore equipo comercial |

---

## 3. Usuarios demo sugeridos

> **IMPORTANTE:** Supabase Auth requiere crear los usuarios **primero** desde el Dashboard (Authentication → Users → Add user). El SQL solo inserta el perfil **después** de tener el UUID real. Las contraseñas demo deben rotarse en producción.

### 3.1 Tabla recomendada (cubriendo los 11 roles prioritarios)

| # | Email demo | Rol | Faena sugerida | Qué probar |
|---|---|---|---|---|
| 1 | `admin@pillado.cl` | administrador | (sin faena) | Acceso total. Ya existe (UUID `d8d49f65-0bad-44a2-9565-09a4f2bd5abc`). |
| 2 | `gerencia@pillado.cl` | gerencia | (sin faena) | Dashboard ejecutivo, ICEO, KPI, reportes. Verificar que NO ve botones de mutación. |
| 3 | `subgerente@pillado.cl` | subgerente_operaciones | FAE-TALLER-CQB | Aprobar OT, ver flota completa, exportar reportes. |
| 4 | `jefe.mantenimiento@pillado.cl` | jefe_mantenimiento | FAE-TALLER-CQB | Crear OT desde plan, aprobar OT, gestionar PM. |
| 5 | `supervisor@pillado.cl` | supervisor | FAE-TALLER-CQB | Cerrar OT como supervisor, editar estado flota. |
| 6 | `tecnico@pillado.cl` | tecnico_mantenimiento | FAE-TALLER-CQB | Login → Mis OTs → checklist → evidencia → finalizar. |
| 7 | `bodeguero@pillado.cl` | bodeguero | FAE-TALLER-CQB | Salida inventario, conteo con scanner. |
| 8 | `abastecimiento@pillado.cl` | operador_abastecimiento | FAE-TALLER-CQB | Registrar movimiento combustible (con foto), varillaje. |
| 9 | `prevencion@pillado.cl` | prevencionista | FAE-TALLER-CQB | Crear certificación, ver SUSPEL/RESPEL. |
| 10 | `auditor@pillado.cl` | auditor | (sin faena) | Listar eventos auditoría, exportar a Excel. |
| 11 | `rrhh@pillado.cl` | rrhh_incentivos | (sin faena) | Ver KPI calculado, ver incentivos calculados, exportar. |

> Detalles completos en `database/schema/35_seed_usuarios_perfil_completo.sql`.

### 3.2 Cómo crear/asignar roles a usuarios reales

**Opción A — Desde Supabase Dashboard (recomendado para producción):**
1. Authentication → Users → **Add user** (email + password). El sistema genera un UUID.
2. SQL Editor → `INSERT INTO usuarios_perfil (id, email, nombre_completo, rut, cargo, rol, faena_id, telefono, activo) VALUES ('<UUID-real>', ...)`.
3. Verificar con `SELECT * FROM usuarios_perfil WHERE email = '<correo>'`.

**Opción B — Desde la UI admin (post-creación):**
1. El administrador inicia sesión → `/dashboard/admin` → tab **Usuarios**.
2. Click en **Editar** del usuario.
3. Cambia rol, faena, cargo, estado activo. **Guardar Cambios**.
4. La UI invalida la caché y refresca la lista.

> ⚠️ **Solo el rol `administrador` ve la pestaña Usuarios** (gating aplicado en FASE 5.1).
>
> ⚠️ **Solo el rol `administrador` puede ejecutar `updateUsuario` con éxito** — la RLS Supabase debe garantizarlo. Si RLS no está configurada (FASE 5 detectó brechas), un usuario con rol `gerencia` que conociera la API podría intentar editar perfiles. **Hardening pendiente — ver `database/schema/52_rls_hardening_recommendations.sql`.**

### 3.3 Checklist del administrador al crear usuario real

- [ ] Crear usuario en Supabase Auth con email corporativo.
- [ ] Forzar contraseña fuerte (no `Pillado2026!` en producción).
- [ ] Insertar perfil en `usuarios_perfil` con rol correcto.
- [ ] Asignar `faena_id` si el rol opera en una faena específica.
- [ ] Marcar `activo = true`.
- [ ] Compartir credenciales por canal seguro (no email plano).
- [ ] Confirmar con el usuario que puede iniciar sesión.
- [ ] Verificar que el sidebar le muestra los módulos esperados (test rápido).
- [ ] Documentar el alta en una bitácora interna (auditoría no técnica).

### 3.4 Reglas de oro

- ❌ **NO usar cuentas compartidas** en operación real (ej. `bodeguero@pillado.cl` para 3 personas). Cada usuario debe tener su email.
- ❌ **NO asignar `administrador`** salvo a 1–2 personas con responsabilidad clara sobre el sistema.
- ❌ **NO compartir contraseñas** por WhatsApp / email.
- ✅ **SÍ rotar contraseñas demo** antes de cualquier uso real.
- ✅ **SÍ revisar logs de auditoría** semanalmente (`/dashboard/auditoria`).
- ✅ **SÍ desactivar (`activo = false`)** usuarios que ya no operan en lugar de borrarlos (preserva historial).

---

## 4. SQL sugerido — `53_seed_roles_piloto_recommendations.sql`

Plantilla SQL **comentada y NO ejecutable directamente** creada en `database/schema/53_seed_roles_piloto_recommendations.sql`. Cubre los 11 roles del piloto. Reemplaza placeholders `UUID-<rol>` por los UUIDs reales generados por Supabase Auth.

---

## 5. Archivos relacionados

- `frontend/src/hooks/use-permissions.ts` — matriz de permisos.
- `frontend/src/types/enums.ts` — enum de roles.
- `frontend/src/components/admin/editar-usuario-modal.tsx` — UI de cambio de rol (FASE 5.1: 15 roles).
- `frontend/src/app/dashboard/admin/page.tsx` — tab Usuarios con gating `isAdmin()` (FASE 5.1).
- `database/schema/23_usuarios_demo.sql`, `35_seed_usuarios_perfil_completo.sql` — seeds existentes.
- `database/schema/53_seed_roles_piloto_recommendations.sql` — guía piloto (FASE 5.1).
- `PERMISOS_Y_ROLES.md` — auditoría detallada del sistema de permisos.
- `PILOTO_OPERATIVO.md` — modo piloto / módulos habilitados.
