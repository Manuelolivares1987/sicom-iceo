# Plan de despliegue y rollback — Fase 0 auditoría

**Rama:** `fix/auditoria-seguridad-fase-0` · **Requiere la instrucción explícita:** `APLICAR EN PRODUCCIÓN`

## Alcance

| Pieza | Tipo | Aplica en |
|---|---|---|
| MIG185 seguridad cierre diario | SQL | BD prod |
| MIG186 reporte fiabilidad autenticado + combustible | SQL | BD prod |
| MIG187 combustible: valor en salidas/traspasos | SQL | BD prod |
| MIG188 regularización histórica de valor | SQL **one-shot con guard** | BD prod (paso separado) |
| Frontend `/reporte-fiabilidad` (guard sesión + contrato) | Next.js | Deploy Netlify |
| Guards 118/121 + verificador destructivas + docs | Repo | Solo git |

## Ventana sugerida

Fuera de horario de despachos de combustible y del cierre diario (p. ej. 21:00–23:00 CLT). Duración estimada: 20 min. Las migraciones son transaccionales e idempotentes; no bloquean tablas de forma prolongada.

## Paso 0 — Backup previo (obligatorio)

```
powershell -File database/scripts/backup-pg-dump.ps1
```
(o confirmar backup administrado del día en el panel si ya hay plan Pro). **No continuar sin backup verificado** (`pg_restore --list` OK, lo hace el script).

## Paso 1 — Prevalidación (solo lectura)

```
node database/scripts/psql-cli.mjs -f database/diagnostics/combustible_reconciliacion.sql
node database/scripts/psql-cli.mjs "SELECT has_function_privilege('anon','public.rpc_confirmar_cierre_diario(date, jsonb)','EXECUTE') AS anon_cierre, has_function_privilege('anon','public.fn_reporte_fiabilidad_publico(date, date)','EXECUTE') AS anon_reporte"
```
Esperado: `anon_cierre=true`, `anon_reporte=true` (estado vulnerable aún), reconciliación mostrando los 3 descuadres conocidos.

## Paso 2 — Migraciones (en este orden)

```
node database/scripts/aplicar-migracion.mjs database/production_run/185_seguridad_cierre_diario.sql
node database/scripts/aplicar-migracion.mjs database/production_run/186_reporte_fiabilidad_autenticado.sql
node database/scripts/aplicar-migracion.mjs database/production_run/187_combustible_valor_stock_en_salidas.sql
```
Cada una tiene smoke test interno que ABORTA (rollback automático) si algo queda mal. 188 NO va en este paso.

## Paso 3 — Tests de seguridad (transacción con ROLLBACK, no persiste nada)

```
node database/scripts/psql-cli.mjs -f database/tests/fase0_seguridad_rpc.sql
```
Esperado: `T01…T09 OK`. Si alguno falla → Paso R (rollback).

## Paso 4 — Deploy frontend

Merge de la rama → deploy Netlify normal. El orden importa: **BD primero, frontend después** (el frontend nuevo tolera la RPC vieja, pero la RPC nueva con la página vieja dejaría a usuarios anónimos viendo error crudo en vez del aviso de login — ventana de minutos, aceptable).

## Paso 5 — Smoke tests funcionales (manual, 10 min)

1. `/reporte-fiabilidad` sin sesión → aviso "requiere iniciar sesión" (no datos).
2. Con sesión → informe carga y **vuelve a mostrar "Stock de combustible"**.
3. `/dashboard/flota/cierre-diario` con usuario administrador → propuesta carga y confirmar un día de prueba funciona.
4. Registrar una salida de combustible pequeña de prueba (consumo interno) → en `/dashboard/combustible` el valor del estanque baja junto con los litros. (Reversar con anulación si el flujo lo permite, o dejarla documentada como consumo real de prueba.)
5. Correo: `node database/scripts/generar-reporte-fiabilidad-outlook.mjs --dry-run` (o el flujo habitual) → genera con sección combustible.

## Paso 6 — Postvalidación (solo lectura)

```
node database/scripts/psql-cli.mjs "SELECT has_function_privilege('anon','public.rpc_confirmar_cierre_diario(date, jsonb)','EXECUTE') AS anon_cierre, has_function_privilege('anon','public.fn_reporte_fiabilidad_publico(date, date)','EXECUTE') AS anon_reporte, (SELECT rowsecurity FROM pg_tables WHERE tablename='estado_diario_flota') AS edf_rls"
```
Esperado: `false, false, true`.

## Paso 7 — MIG188 (regularización histórica) — SEPARADO

Solo tras 24-48 h de operación estable con MIG187 (así se confirma que ninguna vía sigue inflando el valor):
1. Re-ejecutar el diagnóstico (Paso 1) — las diferencias deben ser EXACTAMENTE las mismas 3 filas (si aparecieron nuevas, hay otra vía escribiendo: investigar antes).
2. Editar `188_recalculo_valor_stock_combustible.sql`: `v_autorizado := true`.
3. `node database/scripts/aplicar-migracion.mjs database/production_run/188_recalculo_valor_stock_combustible.sql`
4. La última SELECT imprime el detalle de cambios; el respaldo queda en `combustible_estanques_valor_bkp_mig188`.
5. Revertir el flag a `false` en el repo (el guard queda cerrado de nuevo).

## Paso 8 — Monitoreo (48 h)

- `/dashboard/combustible`: valores de estanque coherentes tras cada despacho.
- Reclamos de acceso: si un rol legítimo quedó fuera del cierre diario, otorgar `approve` del módulo `flota` a ese rol desde `/dashboard/admin/perfiles-roles` (no requiere migración: MIG185 lee los overrides).
- Correo de fiabilidad del día siguiente llega con combustible.

## Criterios de rollback

Rollback si: el cierre diario falla para usuarios legítimos y no se resuelve con un override de permisos; el correo/reporte no genera; o los despachos de combustible fallan.

## Paso R — Rollback (concreto)

Las migraciones son `CREATE OR REPLACE` + grants: se revierte re-aplicando las versiones anteriores, todas presentes en el repo:

| Para revertir | Ejecutar |
|---|---|
| MIG185 (funciones) | `aplicar-migracion.mjs database/production_run/106_cierre_diario_flota.sql` y luego `107_cierre_diario_uso_interno_pin.sql` (restauran las funciones y, ojo, el GRANT a anon: volver a estado vulnerable es la definición de este rollback) |
| MIG185 (RLS estado_diario_flota) | `psql-cli.mjs "ALTER TABLE public.estado_diario_flota DISABLE ROW LEVEL SECURITY; GRANT SELECT,INSERT,UPDATE,DELETE ON public.estado_diario_flota TO anon;"` — solo si algo legítimo dependía del acceso (no se encontró nada) |
| MIG186 | `aplicar-migracion.mjs database/production_run/169_reporte_fiabilidad_sin_faena.sql` (vuelve la versión anónima SIN combustible) |
| MIG187 | `aplicar-migracion.mjs database/production_run/78_combustible_kilometraje_externo_obligatorio.sql` (salida+despacho) y `99_fix_traspaso_folio_unico.sql` **después de** `76_combustible_traspasos.sql` + `92`/`93` (cadena del traspaso) — restaura el bug de valor conocido |
| MIG188 | UPDATE desde `combustible_estanques_valor_bkp_mig188` (bloque comentado al final de la propia migración) |
| Frontend | revert del commit / redeploy del deploy anterior en Netlify |

Nota: el rollback de 185/186 REABRE las vulnerabilidades C1/C3; usarlo solo como último recurso y por el mínimo tiempo.

## Registro de ejecución

| Paso | Fecha/hora | Ejecutor | Resultado |
|---|---|---|---|
| — | — | — | (pendiente de `APLICAR EN PRODUCCIÓN`) |
