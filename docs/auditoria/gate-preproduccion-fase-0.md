# Gate de preproducción — Fase 0 (commit c8834e4)

**Revisor:** puerta formal independiente de seguridad y BD · **Fecha:** 2026-07-04
**Regla cumplida:** las migraciones 185/186/187/188 se compilaron y ejecutaron **por primera vez en un entorno NO productivo** — un PostgreSQL real local efímero (`embedded-postgres`, PG 18.4) que reproduce el modelo de roles de Supabase. Producción **no** se usó como banco de pruebas; contra prod solo hubo `SELECT` (extracción de esquema sin filas + verificaciones).

---

## A. VEREDICTO: **NO-GO** (rev. 3 · 2026-07-04)

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

---

# REV. 3 — Gate final: reconciliación, grafo de llamadores y endurecimiento

**Fecha:** 2026-07-04 · **Veredicto:** **NO-GO** (bloqueadores en §M3). Preprod: **46/46 tests** (`database/preprod/gate_out_evidencia.txt`).

## O. Reconciliación de conteos (sección 1) — cuadra con el catálogo

Consulta directa a `pg_proc` + `has_function_privilege` (`database/preprod/gen-reconciliacion.mjs`, tabla completa en `database/preprod/reconciliacion_48.md`):

| Métrica | Catálogo real | Inventario documentado |
|---|---|---|
| Total escritura anónima sin validación | **48** | 48 ✅ |
| P0 / P1 / P2 | **19 / 24 / 5** | 19 / 24 / 5 ✅ |
| Cierra MIG185 | 1 P0 | 1 ✅ |
| Cierra MIG189 | 45 (11 GrupoA + 7 GrupoB + 27 P1/P2) | 18 P0 + 27 P1/P2 ✅ |
| Allowlist QR | 2 | 2 ✅ |
| Cerradas a anon (185+189) | **46 de 48** | 46 ✅ |

La aritmética del inventario es **correcta**; no hubo que ajustar documentación. (Contexto: hay 169 funciones DEFINER ejecutables por anon que escriben; 121 ya validan sesión/rol; las 48 sin validación son las tratadas.)

## P. Grafo completo de llamadores (sección 2)

Búsqueda en frontend (`.ts/.tsx`), `database/scripts` (`.mjs`), `.ps1`, `.py`, `supabase/functions` (edge), SQL, `pg_trigger`, `pg_proc` (fn→fn) y `cron.job`.

| Función | Llamador | Tipo | Identidad | ¿PostgREST? | Tras MIG189 |
|---|---|---|---|---|---|
| 11 P0 Grupo A | páginas/servicios frontend | cliente | authenticated | sí | guard decide |
| `rpc_ingestar_gps_batch` (P1) | edge `gps-radicom-poll` | Edge Function | **service_role** | sí | **GRANT service_role** (ver hallazgo) |
| `fn_mantenimiento_diario` (P1) | cron + script `.mjs` | cron/script | postgres | no | REVOKE anon (postgres OK) |
| `fn_generar_nc_desde_checklist_ot` | `trg_nc_al_cerrar_checklist_ot` | trigger | postgres | no | trigger sigue OK |
| `fn_generar_nc_desde_v3_ot` | `trg_nc_al_pausar_finalizar_ot` | trigger | postgres | no | trigger sigue OK |
| `fn_auto_crear_planes_activo` | `trg_auto_planes_activo` | trigger | postgres | no | trigger sigue OK |
| `verificar_certificaciones` | cron `verificar-certificaciones` | cron | postgres | no | cron sigue OK |
| `generar_ots_preventivas` | **nadie** (el cron homónimo inlinea la lógica, NO la llama) | — | — | no | **huérfana** → REVOKE seguro |
| `fn_reconciliar_estado_ficha_desde_matriz` | **nadie** (manual/admin) | — | postgres | no | REVOKE seguro |
| `fn_reconciliar_comercial_ficha_desde_matriz` | **nadie** (manual/admin) | — | postgres | no | REVOKE seguro |

**Hallazgo crítico (corregido):** `rpc_ingestar_gps_batch` la invoca la **edge function GPS con `SUPABASE_SERVICE_ROLE_KEY`**. La versión previa de MIG189 (`REVOKE anon, PUBLIC` + `GRANT authenticated`) le habría quitado el acceso a `service_role` (que hoy lo tiene vía PUBLIC) → **habría roto la ingesta GPS**. Corregido: MIG189 ahora `GRANT ... TO service_role` para esa función (única necesidad documentada; ninguna API route Next llama a las 48). Los triggers/cron corren como `postgres`, no dependen de anon. `generar_ots_preventivas` y los `fn_reconciliar_*` quedaron **sin llamadores** (candidatos a deprecación en Fase 1).

## Q. Bloqueo permanente del portal cliente (sección 3) — implementado

`fn_tiene_permiso_modulo` (MIG185) ahora deniega **por regla** a cualquier usuario con fila activa en `cliente_portal_perfil`, ANTES de mirar el rol interno:
```sql
IF EXISTS (SELECT 1 FROM public.cliente_portal_perfil cpp
           WHERE cpp.user_id = auth.uid() AND cpp.activo) THEN RETURN false; END IF;
```
Ya no depende de la ausencia accidental de intersección. **Perfil dual** (fila en ambas tablas, incluso como `administrador`): **denegado por defecto** — probado en preprod (test S3 dual). Si a futuro se quisieran perfiles duales operativos, requeriría una regla explícita de selección de contexto (claim/sesión); hoy **no existe** y se deniega. Pruebas: portal explícito denegado, dual denegado (46/46).

## R. Cierre diario admin-only (sección 4) — implementado

MIG185: `rpc_confirmar_cierre_diario` ya **no** usa fallback amplio; su default es **`ARRAY['administrador']`**. Supervisores u otros roles se habilitan solo por override en Admin (MIG126) tras ratificación. Alinea con `rpc_confirmar_estado_dia` (§I). Propuesta de permisos (no aplicar aún):

| Usuario | Rol | Permiso actual (pre-185) | Permiso propuesto | Justificación |
|---|---|---|---|---|
| admin@pillado.cl | administrador | total (anon incluso) | cierre: sí | admin |
| admin@sicom-iceo.cl | administrador | total | cierre: sí | admin |
| supcalama@pillado.cl | supervisor | (vía anon, sin control) | **cierre: NO por defecto** | override tras ratificación |
| supervisor.mp/pc/pe@sicom-iceo.cl | supervisor | (vía anon) | **cierre: NO por defecto** | override tras ratificación |

## S. Alcance por faena (sección 5) — decisión pendiente + análisis por función

El sistema **no** modela alcance por faena para staff interno (todos operan sobre toda la flota). La empresa debe elegir **Regla A (global)** o **Regla B (restringida por faena)**. Análisis de las 11 P0 si se adoptara Regla B:

| Función | ¿Afecta otra faena? | Roles con acceso | Impacto de operación cruzada | Recomendación |
|---|---|---|---|---|
| `rpc_cambiar_contrato_activo` | sí (contrato global) | admin | **alto** (comercial) | admin-only mitiga; scope contrato en Fase 1 si Regla B |
| `rpc_confirmar_estado_dia` | sí (estado global) | admin | alto | admin-only mitiga |
| `rpc_cerrar_ot_supervisor` | sí (OT de otra faena) | admin+jefes+supervisor | medio | scope por faena de la OT si Regla B |
| `rpc_crear_ot` / `rpc_transicion_ot` | sí (OT/activo otra faena) | jefes+planif+super+técnico | medio | scope por faena si Regla B |
| `rpc_registrar_salida_inventario` | sí (inventario compartido) | bodeguero+abastec | medio | scope por bodega/faena si Regla B |
| `rpc_actualizar_metricas_activo` / `rpc_generar_qr_activo` | sí (activo otra faena) | admin+auditor+jefes | bajo-medio | scope por faena del activo si Regla B |
| `rpc_asignar_pauta` | sí (plan otra faena) | admin+auditor+jefe+planif | bajo | scope si Regla B |
| `rpc_crear_auxiliar` | sí (crea activo) | admin | bajo | admin-only mitiga |
| `rpc_validar_sugerencia` | sí (sugerencia otra faena) | amplio | bajo | scope si Regla B |

Recomendación técnica: **Regla A (global) es coherente con la operación actual**; si se elige Regla B, es trabajo de Fase 1 (agregar `usuarios_perfil.faena_id` al guard de las funciones con `faena_id`/`activo_id`). **No es bloqueante de seguridad anónima**, sí una decisión de gobernanza.

## T. `search_path` (sección 10) — verificado

Las 11 P0 Grupo A + las de MIG185–187: `SET search_path = public, pg_temp` (`pg_temp` AL FINAL). Demostración de no-shadowing (no solo permiso global):
- `has_schema_privilege('anon'|'authenticated'|'PUBLIC','public','CREATE')` = **false** (verificado) ⇒ nadie no confiable crea objetos en `public`.
- `pg_temp` va **último** ⇒ toda referencia no calificada resuelve primero en `public`; solo caería a `pg_temp` si el objeto NO existiera en `public` (no es el caso).
- **Sin SQL dinámico** (`EXECUTE format/'...'`) en ninguna de las 11 (verificado) ⇒ sin superficie de inyección.
- El guard llama `public.fn_tiene_permiso_modulo` calificado.

Conclusión: `public, pg_temp` es seguro aquí. `search_path = ''` requeriría calificar todas las referencias de los cuerpos originales (hoy sin calificar) → cambio de mayor riesgo; se deja como endurecimiento opcional Fase 1.

## U. Rollback y bundle (secciones 11, 12)

- **Rollback MIG189 v2** (`database/rollback/rollback_189_fase01.sql`): restaura los 11 cuerpos originales (sin guard) + re-otorga anon a las 48. Reabre la escritura anónima (incl. P0). Estructuralmente idéntico al rollback de MIG185, **cuyo ciclo aplicar→rollback→reabrir→reaplicar→cerrar está probado** (tests R1/R2). El ciclo completo de 189 sobre esquema completo queda para el pase de §M3-cond2 (mismo bloqueador que el apply completo de 189).
- **Bundle reanudable** (`database/scripts/aplicar-bundle-fase0.mjs`, dry-run probado): aplica 185→186→187→189 en tx separadas, **postvalida cada una**, se **detiene** al primer error, registra estado en `.fase0_deploy_state.json`, **reanuda** saltando las aplicadas, y **NO** hace rollback automático (política: detener y corregir hacia adelante; nunca reabrir anon). Estados intermedios y su riesgo:

| Estado | Riesgo | Funcionamiento | Acción |
|---|---|---|---|
| Ninguna | vulnerabilidades C1/C3/C5 + 48 anón abiertas | actual | aplicar bundle |
| Solo 185 | C3/C5 abiertas; cierre diario y edf ya seguros | OK parcial | continuar |
| 185–186 | C5 abierta; reporte ya cerrado + combustible restaurado | OK | continuar |
| 185–187 | 48 anón aún abiertas; C1/C3/C5 cerradas | OK | continuar a 189 |
| 185–187+189 | superficie anónima cerrada (46/48) | objetivo | desplegar frontend |
| MIG188 | pendiente aparte (desautorizada) | n/a | ventana separada |

## V. Backup y esquema completo (secciones 6, 13) — bloqueadores de entorno

No alcanzables en este entorno de revisión y **deben ejecutarse en la máquina de operaciones**:
- **`pg_dump` no disponible** (no hay binario; `pg-dump-restore` solo hace `spawn` de un `pg_dump` del PATH; no hay PostgreSQL instalado). Por eso el preprod usa reconstrucción por catálogo (cuerpos y firmas **reales**, no stubs, para las funciones ejercitadas) + PG 18.4 en vez de 17.6.
- **Backup end-to-end (§13)**: no ejecutado (sin `pg_dump`/`pg_restore`). Precondición dura.
- **Esquema completo (§6)**: el pase con las 48 funciones, todas las tablas, triggers, policies y **extensiones** (`pg_cron`, `pg_net`, `vault`) no es reconstruible localmente (extensiones no instalables). Lo tratado en preprod: las 11 P0 con **cuerpo real guardado** + un flujo end-to-end completo con cambio real validado (`rpc_cambiar_contrato_activo`).

Instrucciones exactas para el pase final (ops): `pg_dump --schema-only` de prod → restaurar en PG17 local con extensiones → sembrar datos ficticios → correr `database/preprod/run-gate.mjs` adaptado + backup restore.

## M3. Tabla final de criterios (sección 14)

| Condición | Estado | Evidencia | Bloqueante |
|---|---|---|---|
| Conteos reconciliados | ✅ | §O (48=19+24+5, 46 cerradas) | — |
| Grafo completo de llamadores | ✅ | §P (+ fix service_role GPS) | — |
| Portal cliente denegado por **regla** | ✅ | §Q, tests S3 (incl. dual) | — |
| MIG189 pasa con cuerpos + esquema completo | ⛔ parcial (cuerpos reales sí; esquema completo no) | §V | **SÍ** |
| 11 P0 flujos completos exitosos | ⚠️ 1 completo + 10 con autorización probada | §S7, §J | **parcial** |
| 7 internas por trigger/cron/admin | ✅ triggers/cron reales verificados; sin PostgREST | §P | — |
| Rollback MIG189 v2 probado | ⚠️ estructura ok; ciclo completo requiere esquema completo | §U | ligado a esquema |
| Backup restaurado | ⛔ NO (sin `pg_dump`) | §V | **SÍ** |
| Cierre diario admin-only o ratificado | ✅ admin-only por defecto | §R | — |
| Alcance global/faena decidido | ⛔ decisión pendiente empresa | §S | decisión |
| MIG188 separada y desautorizada | ✅ | guard v_autorizado=false | — |

## Veredicto rev. 3: **NO-GO**

Cerrado en esta revisión: reconciliación de conteos, grafo completo de llamadores (con fix real de `service_role` para GPS), bloqueo permanente de portal cliente + perfil dual, cierre diario admin-only, `search_path`/SQL dinámico, orquestador de despliegue reanudable, y un flujo end-to-end completo con cambio real validado. **Bloqueadores restantes** (todos de entorno o de negocio): (a) pase de MIG189 sobre **esquema completo** con las 48 funciones y extensiones; (b) **backup restaurado** end-to-end; (c) **decisión de alcance** global vs faena; y la ratificación del cierre diario ya resuelta por defecto admin-only. No recomiendo `APLICAR EN PRODUCCIÓN` mientras (a) y (b) sigan abiertos.
