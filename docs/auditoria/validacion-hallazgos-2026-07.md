# Validación técnica de hallazgos de auditoría — Fase 0

**Fecha:** 2026-07-03 · **Rama:** `fix/auditoria-seguridad-fase-0`
**Método:** cada hallazgo del informe `AUDITORIA_INTEGRAL_2026-07-03.md` se verificó contra el código fuente, las migraciones, y el estado REAL de producción mediante consultas de solo lectura (`pg_proc`, `pg_tables`, `has_function_privilege`, `information_schema`, SELECTs de datos). No se ejecutó ninguna escritura en producción.

## Contexto del repositorio (verificado)

| Ítem | Valor |
|---|---|
| Framework | Next.js 14.2 (App Router), React 18.3, TypeScript 5.5 |
| Gestor de paquetes | npm (`frontend/package.json`; scripts `lint`, `typecheck`, `build`) |
| Última migración existente | `184_sugerencias_update_policy.sql` → las nuevas parten en 185 |
| Mecanismo de migraciones | `database/scripts/aplicar-migracion.mjs <archivo>`: ejecuta **solo el archivo indicado** dentro de BEGIN/COMMIT. **No** recorre directorios, **no** hay tabla de control de migraciones aplicadas, **no** valida hashes. La re-ejecución es siempre una acción manual explícita. |
| Usuario/rol/permisos | `auth.uid()` + `fn_user_rol()` (JWT `user_metadata.rol` con fallback a `usuarios_perfil`). Matriz de permisos hardcodeada en `frontend/src/hooks/use-permissions.ts`; overrides en BD (`rol_permisos_modulo`, MIG126) — **vacía en prod** (0 filas), por lo que hoy mandan los defaults del frontend. |

## Tabla de validación

| ID | Hallazgo | Estado | Evidencia | Riesgo real | Acción |
|----|----------|--------|-----------|-------------|--------|
| C1 | `rpc_confirmar_cierre_diario` ejecutable por `anon`, sin validar sesión ni rol | **CONFIRMADO y AGRAVADO** | Prod: `has_function_privilege('anon',…)=true`, `prosecdef=true`, `proconfig=null` (sin search_path). Código: `106_cierre_diario_flota.sql:104-200`. **Agravante encontrado en la validación:** `estado_diario_flota` está **sin RLS** (`pg_tables.rowsecurity=false`) y `anon` conserva grants completos de tabla → escritura anónima DIRECTA vía PostgREST, sin pasar por la RPC. `fn_propuesta_cierre_diario` también con EXECUTE para anon. | Crítico: reescritura anónima del estado comercial/contrato/cliente de toda la flota y de la matriz diaria que alimenta los KPI. | **MIG185** (implementada): autorización server-side + REVOKE anon/PUBLIC + RLS en `estado_diario_flota`. |
| C2 | `118_borrar_ots_prueba.sql` re-ejecutable con `DELETE FROM ordenes_trabajo;` sin WHERE | **CONFIRMADO (matizado)** | Archivo verificado (línea 26). Matiz: el ejecutor **no** recorre directorios (solo ejecuta el archivo nombrado), así que el riesgo es re-ejecución manual accidental, no automática. No hay tabla de control que lo impida. No es verificable si 118 o 121 se aplicaron (quedan 74 OTs con folios desde 2026-03, compatibles con re-cargas posteriores); da igual para la mitigación. `121` tiene la variante atenuada (DELETE con WHERE NOT IN). | Alto: pérdida del módulo taller completo sin backup. | **Guard permanente** agregado a 118 y 121 (RAISE EXCEPTION al inicio; se conservan por trazabilidad) + **verificador automático** `verificar-migraciones-destructivas.mjs` (227 archivos en verde, 118 como excepción documentada). |
| C3 | Reporte fiabilidad expone VIN/motor/clientes/contratos a `anon` | **CONFIRMADO** | Prod: `anon_execute=true`, def contiene `vin_chasis` (versión MIG169 vigente). Página `/reporte-fiabilidad` sin guard, fuera de `/dashboard`, sin `middleware.ts` (verificado con `git ls-files`). | Alto: fuga de inteligencia comercial e identificadores físicos; entrega los UUID que habilitan C1. | **MIG186** (implementada): la RPC exige sesión + perfil (excepción: `session_user='postgres'` para el script de correo y cron); REVOKE anon/PUBLIC; página con guard de sesión. Sistema declarado de uso interno → NO se implementó token estático (ver ficha de decisión si a futuro se pide acceso externo). |
| C4 | Sin respaldos de BD (plan Free) | **REQUIERE ACCESO ADICIONAL** | No es verificable por SQL (los backups administrados de Supabase se gestionan en el panel). El plan Free históricamente no incluye backups automáticos y hay constancia del incidente de I/O de mayo sin backup disponible. | Crítico si se confirma: pérdida total ante corrupción/borrado. | **Documento de estrategia** `docs/operacion/estrategia-respaldo-base-datos.md` + script `backup-pg-dump.ps1` listos. **PENDIENTE: confirmar en panel Supabase** el estado real y decidir plan Pro vs pg_dump programado. |
| C5 | Salidas de combustible no descuentan `valor_total_stock` (regresión MIG77/78 vs MIG40) | **CONFIRMADO + ALCANCE AMPLIADO** | Prod (`pg_get_functiondef`): la salida vigente NO contiene `valor_total_stock`; MIG40 sí lo actualizaba (`40:340-344`). **Ampliación:** `rpc_registrar_traspaso_combustible` tiene el mismo defecto (calcula `v_val_*_post` para el kardex pero no lo escribe en los estanques). `rpc_registrar_despacho_combustible_con_sellos` delega en la salida (sin defecto propio); `rpc_registrar_recirculacion_combustible` es neutra en stock (NO afectada, se descarta del fix). Datos reales: EST-1K valor $94.700 vs $55,93 según kardex; EST-15K $4.493 vs $466; CAM-DEMO-1 $16.000.000 con stock 0. Litros SÍ cuadran (kardex = columna en los 8 estanques reales). | Alto (información financiera del stock sobreestimada); no afecta litros ni kardex. | **MIG187** (fix futuro: salida + traspaso actualizan valor en la misma transacción con la fila bloqueada) + **MIG188** (regularización histórica SEPARADA, con dry-run, backup y rollback; NO aplicar sin autorización). Dry-run ejecutado: cambiaría exactamente 3 filas (−$16.000.000 demo, −$94.644,07, −$4.027,54). |
| C6 | Reporte fiabilidad perdió la sección `combustible` desde MIG146 | **CONFIRMADO — frontend SÍ la necesita** | Prod: def vigente sin clave `'combustible'`. Frontend la consume en `reporte-fiabilidad/page.tsx:100+` (tarjeta "Stock de combustible") y `reporte-fiabilidad-email.ts:32+` (sección del correo), cayendo en silencio a `?? []`. La vista fuente `v_combustible_proyeccion_stock` existe en prod (3 estanques sin `CAM-%`). | Medio: el informe interactivo y el correo llevan ~2 semanas sin stock de combustible sin que nadie lo detecte. | **MIG186** restaura la sección (cuerpo MIG111 + filtro Franke MIG134) con verificación de contrato en el smoke test; el frontend ahora valida el contrato y **reporta error** si falta una clave (fin del fallo silencioso). |

## Hallazgos adicionales encontrados durante la validación

| ID | Hallazgo | Estado | Detalle |
|----|----------|--------|---------|
| A1 | `estado_diario_flota` sin RLS + grants completos a `anon` | CONFIRMADO (nuevo) | Cubierto por MIG185 (ver C1). |
| A2 | EXECUTE default de PUBLIC nunca revocado a nivel de proyecto | CONFIRMADO (nuevo, sistémico) | **337** funciones de `public` ejecutables por `anon`; **169** son SECURITY DEFINER que escriben (excluyendo triggers); **48 de ellas no validan ni sesión ni rol** (ej.: `fn_guardar_reporte_diario`, `generar_ots_preventivas`, `registrar_kardex`, `actualizar_stock_bodega`, `fn_reconciliar_*`, `fn_mantenimiento_diario`). Por instrucción, NO se corrige masivamente en Fase 0: inventario priorizado abajo. |
| A3 | Traspaso combustible con el mismo defecto de valor que la salida | CONFIRMADO (nuevo) | Incluido en MIG187. |
| A4 | Estanques DEMO Franke descuadrados en litros (kardex vs columna, 20.000 lt c/u) | CONFIRMADO | Datos seed `es_demo=true` (MIG133): CAM-DEMO-1 tiene salidas sin ingreso; CAM-DEMO-2 stock sin kardex. No se toca en Fase 0 → ficha de decisión (excluir de reportes vs regularizar vs borrar demo). |

## Inventario priorizado para Fase 1 (no corregido en Fase 0, por instrucción)

Prioridad de cierre del EXECUTE de `anon`/PUBLIC y validación interna:

1. **P1 — escriben y no validan nada (48 funciones)**: revocar `anon` + agregar guard de sesión/rol. Nota: varias son llamadas por pg_cron/triggers como `postgres`, no vía PostgREST — revocar `anon` no las rompe.
2. **P1 — mismo patrón que C1 en el dominio estado de flota**: `fn_guardar_reporte_diario`, `fn_reconciliar_estado_ficha_desde_matriz`, `fn_reconciliar_comercial_ficha_desde_matriz`, `rpc_actualizar_metricas_activo`.
3. **P2 — escriben y validan rol pero siguen expuestas a anon (≈120)**: solo REVOKE (defensa en profundidad; el guard interno ya bloquea).
4. **P2 — medida sistémica**: `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;` + barrido único de REVOKE, manteniendo una allowlist explícita de funciones intencionalmente anónimas (QR checklist cliente, ficha pública de equipo, reporte flota público — cada una con su propia validación).
5. **P3 — `SET search_path` faltante en ~30 archivos** de funciones SECURITY DEFINER antiguas.

## Tabla campo-por-campo del reporte de fiabilidad (decisión C3)

Uso verificado en `frontend/src/app/reporte-fiabilidad/page.tsx` y `reporte-fiabilidad-email.ts`. Tras MIG186 el consumidor es siempre un usuario interno autenticado (o el script admin del correo).

| Campo | Pantalla que lo usa | Sensibilidad | Decisión |
|---|---|---|---|
| `activo_id` (UUID) | Clave de la matriz/modal (interno) | Media (habilitaba C1 estando anónimo) | **Mantener** (ya no es anónimo) |
| `patente`, `equipamiento`, `marca`, `modelo`, `anio` | Tabla principal + ficha | Baja | Mantener |
| `cliente`, `contrato_codigo`, `contrato_cliente`, `contratos_dias`, `dias_arriendo_total` | Ficha + export Excel | **Alta** (comercial) | **Mantener solo autenticado** (cumplido con MIG186) |
| `vin_chasis`, `numero_motor` | Ficha técnica modal + export Excel (columnas) | **Alta** (identificadores físicos) | **Mantener solo autenticado**; si se creara acceso externo, ELIMINAR del payload externo |
| `capacidad`, `potencia` | Ficha técnica | Baja | Mantener |
| `ubicacion`, `lugar_fisico`, `zona` | Tabla + ficha | Media | Mantener solo autenticado |
| `ult_*` (último arriendo) | Ficha | Alta (comercial) | Mantener solo autenticado |
| KPIs (`dias_*`, `mtbf_dias`, `mttr_dias`, `disponibilidad_*`) | Tabla + KPIs | Media | Mantener |
| `matriz` (estado diario por equipo) | Matriz de letras | Media | Mantener solo autenticado |
| `combustible` (stock por estanque) | Tarjeta "Stock de combustible" + correo | Media | **Restaurar** (MIG186) |
| `faena` | Nada (se devuelve NULL desde MIG169) | — | Candidato a eliminar del contrato en Fase 1 (hoy se mantiene por compatibilidad de tipo) |

## Verificaciones que CUADRARON (sin acción)

- Litros de combustible: kardex = columna en los 8 estanques reales (diferencia < 0,01 lt).
- `rpc_registrar_salida_combustible_valorizada` en prod es byte a byte la versión MIG78 del repo (verificado vía `pg_get_functiondef`) — el repo refleja producción en este flujo.
- El botón "iniciar mantención" de la ficha QR pública valida sesión + rol (no es la vía de escritura anónima).
- `fn_registrar_varillaje_combustible` y `rpc_registrar_ajuste_inventario` no tocan stock/valor directamente.
- Sanidad kardex: 0 litros negativos, 0 movimientos sin estanque, 0 stock negativo, 0 sobre capacidad.
