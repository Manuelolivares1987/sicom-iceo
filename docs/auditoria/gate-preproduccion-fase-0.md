# Gate de preproducción — Fase 0 (commit c8834e4)

**Revisor:** puerta formal independiente de seguridad y BD · **Fecha:** 2026-07-04
**Regla cumplida:** las migraciones 185/186/187/188 se compilaron y ejecutaron **por primera vez en un entorno NO productivo** — un PostgreSQL real local efímero (`embedded-postgres`, PG 18.4) que reproduce el modelo de roles de Supabase. Producción **no** se usó como banco de pruebas; contra prod solo hubo `SELECT` (extracción de esquema sin filas + verificaciones).

---

## A. VEREDICTO: **NO-GO** (rev. 2 · 2026-07-04)

> **Actualización rev. 2:** MIG189 fue **rediseñada** — pasó de "REVOKE anon + GRANT authenticated" (insuficiente: `authenticated` no es autorización de negocio) a **autorización real por función**. Las 11 P0 de usuario tienen **guard interno fail-closed**; las 7 P0 internas quedan sin acceso PostgREST. Probado en preprod: **42/42 tests** (ver sección G). Aun así el veredicto se mantiene **NO-GO** hasta cerrar los bloqueadores de la sección C (esquema completo, backup, ratificación).

Las migraciones **185, 186 y 187 están verificadas** (24/24) y **MIG189 v2** cierra la autorización de las 19 P0 con guards internos (probado individualmente). Pero el SISTEMA **no** puede recibir `APLICAR EN PRODUCCIÓN` mientras queden abiertos:

| Entregable | Estado |
|---|---|
| MIG185 / 186 / 187 | ✅ ejecutadas y probadas en preprod (24/24 tests) |
| **MIG189 v2 (autorización P0 real)** | ✅ guards fail-closed en las 11 P0 de usuario + 7 internas cerradas; **42/42 tests** en preprod P0. ⛔ falta pase de **esquema completo** (P1/P2 + cuerpos reales sobre todas las tablas) |
| MIG188 (regularización) | ⛔ **desautorizada** (correcto); demo excluido, precondiciones + backup trazado (probado) |
| Backup end-to-end | ⛔ **no ejecutado** (sin `pg_dump`) → bloqueante |
| Ratificación negocio (roles cierre diario) | ⛔ pendiente decisión empresa |
| Scope por faena/contrato (IDOR) | ⛔ **no implementado** (los guards son por rol); decisión de negocio |

---

## B. EVIDENCIA

### B.1 Entorno de preproducción (sección 2)
| Ítem | Valor |
|---|---|
| Tipo | PostgreSQL real local efímero (`embedded-postgres`) — opción 4 (base temporal para pruebas) |
| Versión PostgreSQL | 18.4 local · prod 17.6 (diferencia sin efecto en el DDL/plpgsql ejercitado) |
| Supabase CLI / Docker | No disponibles (Docker daemon caído, sin CLI) → se descartó Supabase local |
| Fecha construcción | 2026-07-04 |
| Migración base | estado **pre-185** reconstruido desde prod (esquema sin datos) |
| Roles | `anon`, `authenticated`, `service_role`, `authenticator` (LOGIN, NOINHERIT), `prod_owner` (NOSUPERUSER BYPASSRLS, reproduce al `postgres` de prod) |
| Datos | ficticios/anonimizados (`database/preprod/03_seed.sql`) |
| Diferencias conocidas | funciones de fiabilidad y `v_combustible_proyeccion_stock` son stubs; subconjunto de tablas (las que tocan 185/186/187) |
| Reproducible | `database/preprod/` (harness completo) · evidencia: `gate_out_evidencia.txt` |

**Fidelidad clave verificada contra prod (solo lectura):**
- `postgres` en prod: `is_superuser=off` **pero** `rolbypassrls=true` y **dueño** de tablas y funciones ⇒ las funciones `SECURITY DEFINER` sí omiten RLS ⇒ MIG185 no rompe el cierre diario. (Reproducido con `prod_owner`.)
- El script de correo y `psql-cli` conectan como `session_user='postgres'` ⇒ la excepción de MIG186 los deja pasar. (Ver sección B.5.)
- **Ningún cron** llama a `fn_reporte_fiabilidad_publico` (0 filas) y **todos los cron corren como `postgres`** ⇒ ni MIG186 ni MIG189 afectan a los jobs.

### B.2 Migraciones aplicadas individualmente (sección 3)
Estado de PARTIDA (vulnerable, reproducido): `anon_cierre=true, anon_reporte=true, edf_rls=false, anon_edf_insert=true`.

| Mig | Duración | Resultado | Objetos | Grants/policies finales |
|---|---|---|---|---|
| 185 | ~3 ms | ✅ + smoke interno OK | `fn_tiene_permiso_modulo` (nueva), `rpc_confirmar_cierre_diario` (reemplazada), RLS + policy `pol_edf_select_authenticated` | anon EXECUTE cierre/propuesta = **false**; authenticated = true; `edf_rls=true`; anon INSERT edf = **false** |
| 186 | ~6 ms | ✅ | `fn_reporte_fiabilidad_publico` (reemplazada, +combustible) | anon EXECUTE reporte = **false**; claves completas incl. `combustible` |
| 187 | ~4 ms | ✅ | salida + traspaso combustible (reemplazadas) | anon EXECUTE salida = **false** |

`search_path` de las 5 funciones nuevas/tocadas = `public, pg_temp` (verificado). MIG188 dry-run: **abortó por guard** (correcto).

### B.3 Tests de seguridad ejecutados (sección 4) — **24/24 OK**
Contextos reales (`authenticator`→`SET ROLE`, no como owner):

| Test | Contexto | Esperado | Real | ✓ |
|---|---|---|---|---|
| T01 cierre diario | anon | DENEGADO | `permission denied for function` | ✓ |
| T02 INSERT directo `estado_diario_flota` | anon | DENEGADO | `permission denied for table` | ✓ |
| T03 cierre diario | auth técnico (sin permiso) | DENEGADO | `No autorizado…` | ✓ |
| T04 cierre diario | auth administrador | PERMITIDO | `confirmados=1` | ✓ |
| T05 lote con activo inexistente | auth administrador | RECHAZO TOTAL | rechazado, filas 0→0 (sin parciales) | ✓ |
| T06 reporte fiabilidad | anon | DENEGADO | `permission denied for function` | ✓ |
| T07 reporte fiabilidad | auth administrador | PERMITIDO + claves | `matriz,equipos,categorias,combustible…` | ✓ |
| T-CORREO reporte | **session_user=postgres** (script/cron) | PERMITIDO | ok, con combustible | ✓ |
| T08 salida combustible | auth bodeguero | litros **y** valor bajan juntos | stock 117→107, valor 94700→**51.15** (esper 51.15) | ✓ |
| T09 salida > stock | auth bodeguero | DENEGADA sin stock negativo | denegada, stock intacto | ✓ |
| E1 módulo inexistente | auth supervisor | FALSE | false | ✓ |
| E2 acción inexistente | auth supervisor | FALSE (fail-closed) | false *(tras endurecer el helper — ver C.2)* | ✓ |
| E3 usuario sin perfil | auth uid sin `usuarios_perfil` | DENEGADO | `No autorizado` | ✓ |
| E4 usuario deshabilitado (`activo=false`) | auth supervisor | DENEGADO | denegado (`fn_user_rol` filtra `activo=true`) | ✓ |
| E5 override niega approve | auth supervisor + override `[view]` | DENEGADO | denegado | ✓ |
| E6 override otorga approve | auth comercial + override `[approve]` | PERMITIDO | confirmados=1 | ✓ |
| E7 service_role sin uid | service_role | DENEGADO | `permission denied` | ✓ |
| E8 vin/motor solo tras auth | auth administrador | anon no accede (T06) | payload interno con vin | ✓ |
| E9 sobrecargas salida vs anon | catálogo | 0 sobrecargas anon | 1 sobrecarga, 0 anon | ✓ |
| R1 rollback 185 reabre vuln | prod_owner | reabre | anon_cierre→true, rls→false, helper→0 | ✓ |
| R2 reaplicar 185 cierra vuln | prod_owner | cierra | anon_cierre→false, rls→true, helper→1 | ✓ |
| M1 188 corrige reales | autorizado | reales cuadran | cuadran | ✓ |
| M2 188 NO toca demo | demo excluido | demo intacto | 16000000 → 16000000 | ✓ |
| M3 188 backup trazado | backup | filas no-demo con motivo/valor | trazado OK | ✓ |

### B.4 Rollbacks ejecutados (sección 8)
Ciclo probado: estado cerrado → `rollback_185` (reabre C1) → reaplicar 185 (cierra). Scripts **específicos** (no reaplican migraciones históricas) en `database/rollback/` para 185/186/187/189, generados desde las definiciones exactas pre-migración y con validación posterior. Nota: se demostró empíricamente por qué "reaplicar la migración histórica anterior" **no** sirve de rollback — reaplicar MIG106 falla en su smoke test por dependencias (`gps_*`) ausentes; de ahí los rollbacks quirúrgicos.

### B.5 Validación de `session_user='postgres'` (sección 5)
| Vía | `session_user` | ¿pasa el guard 186? | ¿correcto? |
|---|---|---|---|
| Frontend autenticado (PostgREST) | `authenticator`→`SET ROLE authenticated` | No por la excepción; pasa por `auth.uid()`+perfil | ✅ |
| service_role (backend) | `authenticator`→`service_role` | Sin `auth.uid()` ⇒ denegado (T-E7 análogo) | ✅ (usar RPC interna si se requiere) |
| pg_cron | `postgres` | Sí — pero **ningún cron llama al reporte** | ✅ n/a |
| Script de correo (`generar-reporte-fiabilidad-outlook.mjs`) | **`postgres`** (verificado: conecta por `SUPABASE_DB_URL` como postgres) | Sí | ✅ |
| Conexión SQL admin | `postgres` | Sí | ✅ |

**Conclusión:** la excepción `session_user='postgres'` es correcta para el caso real (script de correo y admin), y no abre acceso a usuarios finales (que nunca son `postgres`, sino `authenticator`). No requiere cambio.

### B.6 MIG188 excluyendo demo (sección 9)
Rediseñada (`188_...sql`): demo **excluido por defecto** (`v_incluir_demo` aparte), precondiciones bloqueantes (MIG187 aplicada, sin stock negativo, **conjunto real == aprobado**, **delta máximo** ≤ umbral), y **backup con valor anterior/nuevo, fecha, usuario y motivo**. Probado en preprod: con demo excluido corrige solo los reales y **deja el demo intacto** (M1/M2/M3). Además, la precondición de "conjunto == aprobado" **abortó correctamente** cuando el estado cambió respecto al dry-run.

### B.7 Funciones P0 anónimas (sección 7)
Clasificación real desde prod (`database/preprod/clasificar-funcs.mjs`): **48** funciones `SECURITY DEFINER` ejecutables por `anon`, que escriben, sin validar sesión/rol.

| Prio | # | Ejemplos | Cierre |
|---|---|---|---|
| **P0** (tabla crítica) | 19 | `rpc_cambiar_contrato_activo` (**verificada explotable**: cambia el contrato de cualquier activo por su ID, sin login), `rpc_crear_ot`, `rpc_transicion_ot`, `rpc_cerrar_ot_supervisor`, `generar_ots_preventivas`, `rpc_reconciliar_estado_ficha_desde_matriz`, `rpc_confirmar_estado_dia`, `fn_generar_nc_desde_*` | **MIG189** |
| **P1** (insert ilimitado) | 24 | `rpc_guardar_checklist_publico`*, `rpc_checklist_cliente_guardar`*, `rpc_ingestar_gps_batch`, `fn_guardar_reporte_diario`, `rpc_registrar_entrada_inventario` | MIG189 (excepto * allowlist) |
| **P2** (limitado) | 5 | `rpc_aprobar_conteo_inventario`, `rpc_portal_marcar_acceso` | MIG189 |
| P3 | 0 | — | — |

`* allowlist` = escrituras públicas legítimas por QR; se mantienen anónimas (su **rate-limit** queda como pendiente P1, ver D). **MIG189** revoca `anon`+`PUBLIC` y otorga `authenticated` a las 46 restantes (mecanismo idéntico al ya validado en 185/187; seguro para crons que corren como `postgres`).

---

## C. BLOQUEADORES (deben cerrarse antes de `APLICAR EN PRODUCCIÓN`)

1. **MIG189 sin pase de preprod completo.** Está generada desde firmas reales y su mecanismo (REVOKE/GRANT) quedó validado, pero sus 46 funciones no están en el preprod mínimo. **Acción:** construir un preprod con esquema completo (o `pg_dump --schema-only` de prod a una BD local) y correr 189 + verificar que (a) anon pierde EXECUTE en las 46, (b) ningún flujo autenticado del frontend se rompe.
2. **Backup end-to-end no ejecutado.** No hay `pg_dump` en este entorno. **Acción (precondición bloqueante):** en la máquina de operaciones, ejecutar `backup-pg-dump.ps1`, verificar `pg_restore --list`, restaurar en una BD temporal y correr los conteos; además confirmar en el panel Supabase el plan y si hay backups administrados. La lógica de retención del script se probó y poda bien el tramo diario (ver D, hallazgo menor de anclaje semanal/mensual).
3. **Ratificación de negocio del rol de cierre diario (sección 6).** La lista default de MIG185 otorgaría el cierre a **6 usuarios activos: 2 administradores + 4 supervisores** (`supcalama@`, `supervisor.mp@`, `supervisor.pc@`, `supervisor.pe@`). La regla exige ratificación explícita antes de dar el cierre a `supervisor`. **Acción:** la empresa confirma la lista; si se restringe, se ajusta el `p_roles_default` de MIG185 (o se deja el permiso solo por override en Admin).

---

## D. RIESGOS ACEPTADOS TEMPORALMENTE

| Riesgo | Responsable | Fecha límite | Mitigación | Criterio de cierre |
|---|---|---|---|---|
| P1/P2 anónimas (24+5) siguen abiertas hasta MIG189 | Manuel | mismo despliegue | 189 las cierra salvo allowlist | anon sin EXECUTE en las 46 |
| Allowlist QR sin rate-limit (`rpc_guardar_checklist_publico`, `rpc_checklist_cliente_guardar`) | Manuel | Fase 1 | inserción anónima acotada por tamaño/frecuencia | rate-limit desplegado |
| Validación por-función (defensa en profundidad) no agregada a las P0 (solo REVOKE) | Manuel | Fase 1 | REVOKE ya impide anon; guard interno pendiente | `auth.uid()`+rol en las P0 |
| Retención de backup anclada a lunes/día-1 (frágil si se omite ese día) | Manuel | Fase 1 | cambiar a "más reciente por ISO-semana y por mes" | script actualizado |
| ~30 funciones SECURITY DEFINER sin `search_path` (antiguas) | Manuel | Fase 1 | bajo riesgo; barrido en bloque | `search_path` fijado |

---

## E. COMANDOS DE DESPLIEGUE REVISADOS (NO ejecutar en prod aún)

```
# 0. Backup previo (BLOQUEANTE) + verificación
powershell -File database/scripts/backup-pg-dump.ps1
#    y confirmar backup del día en panel Supabase.

# 1. Prevalidación (solo lectura)
node database/scripts/psql-cli.mjs -f database/diagnostics/combustible_reconciliacion.sql

# 2. Bundle Fase 0 + 0.1 (en orden)
node database/scripts/aplicar-migracion.mjs database/production_run/185_seguridad_cierre_diario.sql
node database/scripts/aplicar-migracion.mjs database/production_run/186_reporte_fiabilidad_autenticado.sql
node database/scripts/aplicar-migracion.mjs database/production_run/187_combustible_valor_stock_en_salidas.sql
node database/scripts/aplicar-migracion.mjs database/production_run/189_fase01_revocar_anon_escritura.sql

# 3. Postvalidación (solo lectura)
node database/scripts/psql-cli.mjs "SELECT has_function_privilege('anon','public.rpc_confirmar_cierre_diario(date,jsonb)','EXECUTE') AS a, has_function_privilege('anon','public.rpc_cambiar_contrato_activo(uuid,uuid,text)','EXECUTE') AS b"
#    esperado: a=false, b=false

# 4. Deploy frontend (guard de sesión en /reporte-fiabilidad)

# 5. 24-48 h después, con dry-run fresco: MIG188 (editar v_autorizado + v_expected_ids)
node database/scripts/aplicar-migracion.mjs database/production_run/188_recalculo_valor_stock_combustible.sql
```

**Rollback:** `database/rollback/rollback_{185,186,187,189}_*.sql` (cada uno indica qué vulnerabilidad reabre). Plan completo: `docs/auditoria/plan-despliegue-fase-0.md`.

---

## F. RECOMENDACIÓN

**NO** se puede entregar aún la instrucción `APLICAR EN PRODUCCIÓN` para el sistema completo.
Se puede autorizar **cuando** se cierren los 3 bloqueadores de la sección C:

1. MIG189 pasa un preprod de esquema completo (anon cerrado, frontend intacto).
2. Backup ejecutado, restaurado y verificado + plan Supabase confirmado.
3. La empresa ratifica quién puede confirmar el cierre diario.

Cerrados esos tres, el bundle **185+186+187+189** queda listo para `APLICAR EN PRODUCCIÓN`, seguido de MIG188 en ventana separada. Las migraciones 185/186/187 en sí ya están verificadas y aprobadas; el condicionamiento es del **sistema**, por las P0 anónimas preexistentes que 189 cierra.

---

# REV. 2 — Rediseño de autorización de las 19 P0 (MIG189 v2)

## G. Matriz de las 19 P0 (sección 2 del pedido)

Clasificación por **quién las llama** (verificado: grep frontend + `cron.job`):
- **Grupo A (11)** = llamadas por el frontend ⇒ **guard interno fail-closed** + `GRANT authenticated`.
- **Grupo B (7)** = solo cron/trigger (corren como `postgres`) ⇒ **REVOKE de anon, authenticated y PUBLIC** (sin PostgREST). No se les pone guard `auth.uid()` porque **rompería el cron**.
- La 19ª (`rpc_confirmar_cierre_diario`) ya quedó con guard en MIG185.

| Función | Grupo | Tablas | Módulo/Acción | Llamador | Riesgo original |
|---|---|---|---|---|---|
| `rpc_cambiar_contrato_activo` | A | activos | contratos/edit | frontend | **verificado explotable**: cambia contrato de cualquier activo sin login |
| `rpc_crear_ot` | A | ordenes_trabajo | ordenes_trabajo/create | frontend | crear OT anónima |
| `rpc_transicion_ot` | A | ordenes_trabajo | ordenes_trabajo/edit | frontend | cambiar estado de OT ajena |
| `rpc_cerrar_ot_supervisor` | A | ordenes_trabajo | ordenes_trabajo/approve | frontend | cerrar OT sin ser supervisor |
| `rpc_registrar_salida_inventario` | A | ordenes_trabajo, inventario | inventario/create | frontend | salida de inventario anónima |
| `rpc_confirmar_estado_dia` | A | activos, estado_diario_flota | flota/approve | frontend | reescribir estado de flota |
| `rpc_actualizar_metricas_activo` | A | activos | activos/edit | frontend | alterar km/horas |
| `rpc_asignar_pauta` | A | planes_mantenimiento | mantenimiento/edit | frontend | reasignar pauta PM |
| `rpc_crear_auxiliar` | A | activos | activos/create | frontend | crear activo auxiliar |
| `rpc_generar_qr_activo` | A | activos | activos/edit | frontend | regenerar QR |
| `rpc_validar_sugerencia` | A | activos | flota/edit | frontend | validar sugerencia GPS |
| `generar_ots_preventivas` | B | ordenes_trabajo, planes | (interno) | **cron** | generar OTs masivas |
| `verificar_certificaciones` | B | activos | (interno) | **cron** | tocar disponibilidad por cert. |
| `fn_auto_crear_planes_activo` | B | planes_mantenimiento | (interno) | trigger | crear planes duplicados |
| `fn_generar_nc_desde_checklist_ot` | B | no_conformidades | (interno) | trigger | crear NC |
| `fn_generar_nc_desde_v3_ot` | B | no_conformidades | (interno) | trigger | crear NC |
| `fn_reconciliar_estado_ficha_desde_matriz` | B | activos | (interno) | manual/admin | reescribir ficha |
| `fn_reconciliar_comercial_ficha_desde_matriz` | B | activos | (interno) | manual/admin | reescribir comercial |

## H. Guard fail-closed (secciones 3, 6, 8)

Cada P0 del Grupo A abre con (inyectado tras `BEGIN`, antes de tocar tablas):
```sql
IF NOT public.fn_tiene_permiso_modulo('<modulo>', '<accion>', ARRAY[<roles_default>]) THEN
    RAISE EXCEPTION 'No autorizado …' USING ERRCODE = '42501';
END IF;
```
`fn_tiene_permiso_modulo` (endurecida en MIG185) es **fail-closed**: retorna `false` si falta módulo/acción (no canónicos), si `auth.uid()` es NULL (anon), si no hay fila en `usuarios_perfil` (**portal cliente** — verificado 0 overlap con `cliente_portal_perfil`), si el usuario está inactivo, o si el rol no tiene el permiso (override negativo incluido). El `GRANT authenticated` solo abre la puerta; **el guard decide**.

**SECURITY DEFINER (sección 8):** `search_path = public, pg_temp` con `pg_temp` **al final** — verificado en prod que `has_schema_privilege` de CREATE en `public` es **false** para `anon`, `authenticated` y `PUBLIC`, por lo que no hay shadowing posible. Referencias calificadas con `public.`.

## I. ¿Quién recibiría cada permiso? (secciones 4 y 12)

Roles default = los que el frontend ya usa para mostrar el botón (`use-permissions.ts`); MIG126 los sobreescribe por rol vía Admin. Usuarios activos por rol: administrador 2, supervisor 4, tecnico_mantenimiento 3, bodeguero 2, planificador 2, colaborador 1, auditor_calidad 1, comercial 1.

| Función | Roles con acceso por defecto |
|---|---|
| `rpc_cambiar_contrato_activo` | **administrador** (solo) |
| `rpc_crear_auxiliar` | **administrador** (solo) |
| `rpc_confirmar_estado_dia` | **administrador** (solo — anti-lockout; ningún otro rol tiene flota/approve) |
| `rpc_crear_ot` | administrador, jefe_mantenimiento, jefe_operaciones, planificador, supervisor |
| `rpc_transicion_ot` | + auditor_calidad, tecnico_mantenimiento |
| `rpc_cerrar_ot_supervisor` | administrador, jefe_mantenimiento, jefe_operaciones, subgerente_operaciones, supervisor |
| `rpc_registrar_salida_inventario` | administrador, bodeguero, operador_abastecimiento |
| `rpc_actualizar_metricas_activo` | administrador, auditor_calidad, jefe_mantenimiento, jefe_operaciones |
| `rpc_asignar_pauta` | administrador, auditor_calidad, jefe_mantenimiento, planificador |
| `rpc_generar_qr_activo` | administrador, auditor_calidad, jefe_mantenimiento, jefe_operaciones |
| `rpc_validar_sugerencia` | administrador, auditor_calidad, jefe_mantenimiento, jefe_operaciones, planificador, subgerente_operaciones, supervisor |

**Hallazgo de consistencia:** `rpc_confirmar_estado_dia` (flota/approve) queda **admin-only** por defecto, mientras `rpc_confirmar_cierre_diario` (MIG185) usa una lista hardcodeada que incluye supervisor. Ambas confirman estado de flota. Recomendación: **alinear ambas a admin-only por defecto** (fail-closed, como pide la sección 14) y conceder supervisor por **override en Admin** tras ratificación.

## J. Pruebas ejecutadas por función (sección 10) — 42/42 OK

Preprod P0: stubs con firma exacta (granted anon) → aplicar MIG189 v2 → las 11 P0 de usuario reciben su **cuerpo real guardado**. Contextos reales (`authenticator`→`SET ROLE`):

| Contexto | Grupo A (11 fn) | Grupo B (7 fn) |
|---|---|---|
| anon | **DENEGADO** (11/11) | **DENEGADO** (7/7, sin EXECUTE) |
| sin perfil (= **portal cliente**) | DENEGADO (11/11) | n/a |
| usuario deshabilitado | DENEGADO (11/11) | n/a |
| authenticated sin permiso | DENEGADO (11/11) | n/a |
| administrador (con permiso) | **PASA el guard** (11/11; el cuerpo real corre) | n/a |
| authenticated (cualquiera) | — | **DENEGADO** (7/7) |

Método: para denegación, el guard hace `RAISE 42501` **antes** de tocar tablas (por eso no requiere esquema completo). Para el caso autorizado, el guard pasa y el cuerpo real intenta ejecutarse (falla luego por tablas ausentes en el preprod acotado = autorización concedida). Evidencia: `database/preprod/gate_out_evidencia.txt`.

## K. Scope por entidad / IDOR (sección 6)

Los guards validan **rol/permiso**, no **alcance por entidad** (faena/contrato/cliente):
- **Portal cliente → activo interno: DENEGADO** ✅ (sin fila en `usuarios_perfil`).
- **Supervisor de faena A → activo de faena B: PERMITIDO** ⚠️ — no hay scope por faena. El sistema no modela hoy alcance por faena para staff interno (todos operan sobre toda la flota); implementarlo sería una **regla de negocio nueva**. **Decisión pendiente de la empresa**: ¿el staff interno debe restringirse por faena? Si sí, es trabajo de Fase 1 (agregar `usuarios_perfil.faena_id` al guard de las funciones con `faena_id`). Riesgo aceptado temporal, no bloqueante de seguridad anónima.

## L. P1/P2 (sección 11)

MIG189 v2 cierra las **28 P1/P2** con `REVOKE anon + GRANT authenticated`. Allowlist QR intacta: `rpc_guardar_checklist_publico`, `rpc_checklist_cliente_guardar`. **Pendiente Fase 1** para la allowlist: tamaño máximo de payload, tipos/tamaño de archivo, ID de QR difícil de adivinar, expiración, rate-limit por token/IP, idempotencia. Riesgo aceptado temporal: inserción anónima acotada; **no** permiten modificar datos críticos (solo checklists de cliente).

## M. Tabla final de criterios (sección 15)

| Condición | Estado | Evidencia | Bloqueante |
|---|---|---|---|
| 1. Las 19 P0 con guards internos + pruebas individuales | ✅ (preprod acotado) | §G–J, 42/42 tests | — |
| 2. MIG189 pasa sobre **esquema completo** | ⛔ NO | solo preprod P0 (stubs+cuerpos guardados) | **SÍ** |
| 3. Portal cliente no ejecuta ninguna P0 | ✅ | 0 overlap + tests denegados | — |
| 4. Accesos por entidad/faena probados | ⚠️ por rol OK; por faena **no aplicado** | §K | decisión negocio |
| 5. Backup restaurado | ⛔ NO (sin `pg_dump`) | §C.2 | **SÍ** |
| 6. Roles del cierre diario ratificados | ⛔ pendiente | §N | **SÍ** |
| 7. MIG188 separada y desautorizada | ✅ | guard v_autorizado=false | — |

## N. Ratificación del cierre diario (sección 14)

Con la lista default de MIG185, recibirían el permiso **6 usuarios activos**:

| Correo | Rol | Alcance | Recomendación |
|---|---|---|---|
| admin@pillado.cl | administrador | total | mantener |
| admin@sicom-iceo.cl | administrador | total | mantener |
| supcalama@pillado.cl | supervisor | Calama | **ratificar** |
| supervisor.mp@sicom-iceo.cl | supervisor | — | **ratificar** |
| supervisor.pc@sicom-iceo.cl | supervisor | — | **ratificar** |
| supervisor.pe@sicom-iceo.cl | supervisor | — | **ratificar** |

**Recomendación técnica (fail-closed):** para una operación que reescribe toda la flota, **sin fallback amplio** — dejar el default en **admin-only** y conceder a supervisores por **override explícito en Admin** (MIG126) tras decisión de la empresa. **No se modifica hasta recibir la decisión.**

## Veredicto rev. 2: **NO-GO**

No recomiendo `APLICAR EN PRODUCCIÓN` mientras: (2) MIG189 no pase un preprod de esquema completo, (5) el backup no esté restaurado y verificado, y (6) no se ratifiquen los roles del cierre diario. Las P0 ya tienen autorización real (guards fail-closed probados) y **ninguna P0 puede ejecutarse por un usuario autenticado sin permiso específico** — pero esos tres bloqueadores impiden el GO del sistema.
