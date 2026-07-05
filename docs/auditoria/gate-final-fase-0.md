# Gate final — Fase 0 (bundle 185/186/187/189)

**Revisor:** puerta de preproducción independiente · **Fecha:** 2026-07-05
**Veredicto:** **GO** (condicionado a ejecutar el despliegue con el procedimiento de §10).
El historial detallado de las revisiones previas está en `gate-preproduccion-fase-0.md`; este documento es la conclusión ejecutable.

---

## 1. Decisiones definitivas (dadas por la empresa)

1. Personal interno autorizado: **alcance global temporal** sobre toda la flota.
2. Restricción por faena: **Fase 1** (no bloquea Fase 0).
3. Cierre diario: **administrador-only** por defecto.
4. Supervisores: acceso al cierre **solo por override individual** en Admin (MIG126).
5. Portal cliente: **denegado** en todas las P0.
6. Perfil dual interno+portal: **denegado** en las P0.
7. Funciones internas (trigger/cron/admin): **sin acceso PostgREST**.
8. MIG188: **separada y desautorizada**.
9. Funciones QR: **allowlist temporal**; límites y rate-limit → Fase 1.

## 2. Ambiente utilizado

| Ítem | Valor |
|---|---|
| Cliente/Servidor | **PostgreSQL 17.10** (`winget install PostgreSQL.PostgreSQL.17`) — pg_dump/pg_restore/psql 17.10, compatible con prod **17.6** |
| Preproducción | Instancia local PG17 aislada (puerto local), restaurada desde backup real de prod |
| Modelo Supabase | Roles `anon`/`authenticated`/`service_role`/`authenticator`, esquema `auth` (users + uid/role), `postgres` dueño |
| Datos | **Reales restaurados y ANONIMIZADOS** (0 VIN/patente/email reales; script `database/preprod/anonimizar.mjs`) |
| Contra producción | **Solo** `pg_dump` (schema+data, lectura) y `SELECT` de catálogo. Ninguna escritura. |
| Diferencias documentadas | 41 constraints FK **periféricas** (a `auth.users`/tablas Calama) no re-añadidas; extensiones administradas (`pg_cron`/`pg_net`/`vault`) representadas por andamiaje. **Verificado que no afectan los flujos probados** (las 11 P0 completaron con datos reales). |

Restaurado: **168 tablas, 373 funciones, 86 triggers, 331 policies**, con datos (74 OTs, 68 activos, 16 usuarios). Errores pre-data/data = **0**.

## 3. Migraciones probadas

Aplicadas **individualmente** en preprod con postvalidación tras cada una (orquestador `database/scripts/aplicar-bundle-fase0.mjs`):

| Mig | Resultado | Postvalidación |
|---|---|---|
| 185 | ✅ | cierre diario cerrado a anon; RLS `estado_diario_flota`; `fn_tiene_permiso_modulo` presente (fail-closed + bloqueo portal) |
| 186 | ✅ | reporte cerrado a anon; sección combustible restaurada |
| 187 | ✅ | salida y traspaso combustible actualizan `valor_total_stock` |
| 189 v2 | ✅ | 46/48 funciones anónimas cerradas; guards P0; `rpc_ingestar_gps_batch` **solo service_role** |
| **188** | ⛔ **desautorizada** | guard `v_autorizado=false` (no en el bundle) |

## 4. Funciones P0 probadas (sobre esquema completo)

**11/11 P0 de usuario** — denegación en 6 contextos + flujo autorizado completo con cambio real + rechazo de id inexistente:

| Función | Denegaciones (anon/sin-perfil/inactivo/portal/dual/sin-permiso) | Flujo autorizado (cambio real) | Rechazo id inválido |
|---|---|---|---|
| rpc_cambiar_contrato_activo | 6/6 D | ✅ contrato cambiado | ✅ |
| rpc_actualizar_metricas_activo | 6/6 D | ✅ km actualizado | ✅ |
| rpc_generar_qr_activo | 6/6 D | ✅ QR generado | ✅ |
| rpc_confirmar_estado_dia | 6/6 D | ✅ estado_diario escrito | ✅ |
| rpc_crear_ot | 6/6 D | ✅ OT creada (n+1) | ✅ |
| rpc_transicion_ot | 6/6 D | ✅ estado avanzado | ✅ |
| rpc_cerrar_ot_supervisor | 6/6 D | ✅ OT cerrada | ✅ |
| rpc_crear_auxiliar | 6/6 D | ✅ auxiliar creado | ✅ |
| rpc_asignar_pauta | 6/6 D | ✅ pauta asignada | ✅ |
| rpc_registrar_salida_inventario | 6/6 D | ✅ salida registrada | ✅ (sobre-stock rechazado) |
| rpc_validar_sugerencia | 6/6 D | ✅ sugerencia rechazada | ✅ |

**Funciones internas (Grupo B, 7/7):** anon y authenticated **denegados** (sin EXECUTE); trigger `trg_auto_planes_activo` presente; `verificar_certificaciones` ejecutable vía admin/cron (postgres) pese al REVOKE.

**Edge Function GPS (`rpc_ingestar_gps_batch`):** anon **denegado**, authenticated **denegado**, **service_role permitido** (única vía; ninguna API route Next la llama).

**Portal cliente / dual:** denegados explícitamente por regla en `fn_tiene_permiso_modulo` (bloqueo por fila activa en `cliente_portal_perfil`, incluso con rol interno).

Evidencia: `database/preprod/gate_out_evidencia.txt` y los scripts `flujos-p0*.mjs`.

## 5. Backup y restauración

- **Backup real** (`pg_dump -Fc`, solo lectura sobre prod): ubicación protegida **fuera del repo** (`~/backups-fase0/`, ACL restringida al usuario, NO en git).
- Tamaño **12.5 MB**; SHA-256 `8699CEF0…A01CBD3` (registrado). Duración ~283 s.
- `pg_restore --list`: **OK** (3382 entradas: tablas, funciones, policies, triggers, secuencias).
- **Restaurado** en PG17 local; conteos verificados (168 tablas, datos reales). Los flujos P0 corrieron sobre esta restauración.
- Retención/cifrado: el dump debe **cifrarse** y moverse a almacenamiento externo (script operativo `backup-pg-dump.ps1` + estrategia `docs/operacion/estrategia-respaldo-base-datos.md`).

## 6. Rollback

- Scripts **específicos** por migración en `database/rollback/` (no reaplican migraciones históricas).
- **Ciclo MIG189 v2 probado** en esquema completo: estado cerrado → `rollback_189` (anon reabre) → reaplicar 189 (anon cierra). Cada rollback documenta qué vulnerabilidad reabre.
- **Política de producción:** ante un error **no destructivo**, **detener y corregir hacia adelante**; NO programar rollback automático (reabre acceso anónimo). El orquestador nunca revierte automáticamente ni reabre anon.

## 7. Resultado del build

- `tsc --noEmit`: **exit 0** (sin errores de tipos).
- `next build`: **Compiled successfully**, 99/99 páginas estáticas. Sin errores.
- Lint: 0 errores (warnings preexistentes de `react-hooks/exhaustive-deps`, no introducidos por Fase 0).
- No hay suite de tests unitarios definida en el proyecto (`package.json` sin script `test`); lint+typecheck+build cubren la verificación.
- Secretos: **0** en el diff de la rama (verificado). Backup/`.env`/datadir no versionados.

## 8. Bloqueadores reales

**Ninguno.** Los que quedaban (pg_dump/PG17, backup, esquema completo) se resolvieron instalando PostgreSQL 17 y restaurando un backup real. Las diferencias del entorno (41 FK periféricas, extensiones administradas) están documentadas y verificadas como no incidentes en los flujos probados.

Pendientes de **Fase 1** (no bloquean Fase 0): restricción por faena; rate-limit/límites de las 2 funciones QR; deprecación de funciones huérfanas (`generar_ots_preventivas`, `fn_reconciliar_*`); endurecimiento por-función del resto de P1/P2.

## 9. Veredicto: **GO**

Se cumplen todos los criterios: backup real generado y `pg_restore --list` OK; backup restaurado; esquema completo funcionando (con diferencias documentadas); 185/186/187/189 aplicadas y postvalidadas; **11/11 P0** con flujos reales (denegación + completación + rechazo); internas por su vía real; **GPS service_role**; portal cliente y perfil dual denegados; cierre diario admin-only; rollback MIG189 probado; build/typecheck OK; MIG188 desautorizada; sin secretos en el diff.

## 10. Procedimiento de despliegue (a ejecutar con autorización)

Cada paso tiene **pausa obligatoria** y registro (hora, ejecutor, resultado, hash del archivo, validación posterior). Usar el orquestador reanudable `database/scripts/aplicar-bundle-fase0.mjs` (`APLICAR_FASE0=si`), que se detiene al primer error y **no** revierte automáticamente.

1. **Backup verificado** — `backup-pg-dump.ps1` + `pg_restore --list` + confirmar plan/backup en panel Supabase. (Hash del dump al registro.)
2. **MIG185** → pausa → **postvalidación** (anon sin cierre; RLS edf; helper presente).
3. **MIG186** → pausa → postvalidación (reporte cerrado a anon; combustible presente).
4. **MIG187** → pausa → postvalidación (salida/traspaso actualizan valor).
5. **MIG189 v2** → pausa → postvalidación (0 funciones de escritura anónimas fuera de allowlist; GPS solo service_role; guards P0).
6. **Deploy frontend** (guard de sesión en `/reporte-fiabilidad`).
7. **Smoke tests de usuario**: login administrador → cierre diario OK; supervisor sin override → denegado; reporte con combustible; una salida de combustible baja litros y valor; ingesta GPS (edge) sigue operando.
8. **Monitoreo 48 h**: despachos de combustible, cron GPS, correo de fiabilidad, reclamos de acceso (resolver con override en Admin, sin migración).

**MIG188 NO se incluye.** Se aplica en ventana separada, con su propio dry-run y autorización, tras 24-48 h de operación estable.

**Rollback de emergencia:** `database/rollback/rollback_{185,186,187,189}_*.sql` (reabren las vulnerabilidades correspondientes; usar solo como último recurso).
