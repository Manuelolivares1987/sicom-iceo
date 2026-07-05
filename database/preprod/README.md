# Harness de preproducción — gate Fase 0

Entorno de pruebas **no productivo** que reproduce el modelo de conexión de Supabase
(roles `anon`/`authenticated`/`service_role`/`authenticator`, esquema `auth`, `postgres`
con `BYPASSRLS`) sobre un **PostgreSQL real local efímero** (`embedded-postgres`, PG 18.4).
Ningún dato real de la empresa: el esquema se extrae **sin filas** desde prod y los datos
son ficticios (`03_seed.sql`).

## Requisitos
```
npm i embedded-postgres pg dotenv
```
(La ruta a `.env.supabase-admin.local` es solo-lectura, para EXTRAER esquema desde prod;
las pruebas corren 100% local.)

## Uso
```
node extraer-esquema.mjs      # 1) genera preprod_base_prod.sql + preprod_funcs_prod.sql (SOLO estructura, sin datos)
node run-gate.mjs             # 2) levanta PG local, construye preprod, aplica 185/186/187, corre 24 tests
node clasificar-funcs.mjs     # (aparte) clasifica funciones anónimas de escritura P0/P1/P2
```

## Qué valida `run-gate.mjs`
- FASE 1: construye el estado **pre-185** (reproduce el estado vulnerable real).
- FASE 2: aplica MIG185/186/187 **individualmente** con su smoke interno; captura grants/policies/search_path.
- FASE 3: MIG188 dry-run (guard aborta) + prueba de que el diseño anterior mezclaba demo.
- FASE 4: T01–T09 + E1–E9 con contextos reales (`authenticator`→`SET ROLE`), no como owner.
- FASE 5: ciclo de rollback de 185 (aplicar→rollback→reabrir→reaplicar→cerrar).
- FASE 6: MIG188 v2 (autorizado, demo excluido, backup trazado).

Resultado de la corrida de evidencia: `gate_out_evidencia.txt` (24/24 OK).

## Diferencias conocidas vs producción
- PG 18.4 local vs 17.6 prod (irrelevante para el DDL/plpgsql ejercitado).
- Funciones de fiabilidad y `v_combustible_proyeccion_stock` son **stubs** (`02_stubs.sql`):
  se prueba la seguridad (guard/grants/contrato de claves), no la matemática de fiabilidad.
- Subconjunto de tablas/funciones (las que tocan 185/186/187). MIG189 (46 funciones)
  requiere un preprod con **esquema completo** para su validación end-to-end.
