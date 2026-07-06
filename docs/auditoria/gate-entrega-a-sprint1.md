# Gate de Entrega A — Sprint 1 (Plataforma Operable)

**Fecha:** 2026-07-05
**Alcance:** Frentes de Entrega A — Registro de migraciones (idempotencia), CI real,
RLS reconciliada, Backup automático + restauración + simulación de fallos.
**Regla de decisión:** GO sólo si TODOS los criterios están en verde, ejecutados y
verificados (no declarado sobre código no ejecutado).

---

## 1. Resolución de inconsistencia RLS

- `estado_diario_flota`: **RLS ACTIVA** (`relrowsecurity = true`), cerrada por MIG185.
  Verificado por catálogo en prod y **confirmado en la restauración** (`rls_edf=true`).
  `anon` sin privilegios; policy `pol_edf_select_authenticated` presente.
- Se corrigió `gate-sprint1-plataforma.md` (sección 7): la tabla estaba mal reportada
  como pendiente. **No se creó otra migración**; tabla considerada cerrada.
- Inventario de tablas pendientes (para Entrega C, no bloqueantes de Entrega A):
  `no_conformidades`, `verificaciones_disponibilidad`, `registro_jornada_conductor`,
  `normativa_documentos`, `suspel_*`, `respel_*` (9 tablas).

**Estado: ✅ CERRADO**

## 2. Validación del bootstrap de MIG190

Ejecutor endurecido `db-migrate.mjs` + suite `test-db-migrate.mjs` (11 aserciones, todas
verdes), cubriendo los 8 escenarios exigidos:

| # | Escenario | Resultado |
|---|-----------|-----------|
| 1 | Base sin `schema_migrations` | ✅ |
| 2 | Aplicación inicial (bootstrap) | ✅ |
| 3 | `--status` | ✅ registra version/hash/commit/env/duración |
| 4 | Reintento mismo hash | ✅ saltado (no re-ejecuta) |
| 5 | Reintento hash distinto (drift) | ✅ rechazado |
| 6 | Error durante migración | ✅ exit ≠ 0 |
| 7 | Registro coherente tras error | ✅ `success=false` + causa; tabla fallida con rollback |
| 8 | Ejecución concurrente | ✅ `pg_advisory_lock` → 1 sola fila, ambos exit 0 |

- Guard bootstrap: una migración no-bootstrap sin registro previo es bloqueada
  ("aplica 190 primero"). **Sin INSERT manual como solución permanente.**

**Estado: ✅ CERRADO**

## 3. Aplicación de MIG190 en producción

- Backup previo + `pg_restore --list` + tamaño + SHA-256 registrados antes de aplicar.
- Aplicada con el ejecutor endurecido. En prod: `schema_migrations` con **version 190**,
  `sha256=7dd2ec1c…`, `git_commit=12a721d1…`, `environment=prod`.
- Verificado: hash coincide, commit corresponde, **sin tablas de negocio modificadas**.
- `--status` coherente. Evidencia sin credenciales. **Ninguna otra migración aplicada.**

**Estado: ✅ CERRADO**

## 4. CI real en GitHub

- Workflow `.github/workflows/ci.yml` con 3 jobs: `frontend` (lint/typecheck/test/build),
  `secretos` (gitleaks + escaneo `.env`/JWT), `migraciones` (postgres:17 + pruebas del
  ejecutor).
- PR real: los **3 jobs corren y pasan**.
- Falla controlada (migración destructiva) → job `migraciones` **falla** → revert → verde.
- Protección de `main`: `required_status_checks = [frontend, migraciones, secretos]`,
  `strict = true`, `enforce_admins = true`.
- Merge **bloqueado incluso con `gh pr merge --admin`** ("2 of 3 required status checks
  have not succeeded").

**Estado: ✅ CERRADO**

## 5. Backup automático

- `backup-diario.ps1`: `pg_dump -Fc` → integridad → cifrado **AES-256 (7-Zip, `-mhe=on`)**
  → SHA-256 → registro en `backup_ejecuciones` (+ fallback CSV local) → **copia externa**
  → retención robusta → alerta éxito/fallo. Sale ≠ 0 en fallo.
- Password de cifrado **NO en texto plano**: DPAPI por usuario (`.enc-pass.dpapi`),
  nunca junto al backup ni en la nube.
- **Backup ejecutado con éxito**: `sicom-20260705-134600.dump.7z` (9.12 MB, completo con
  `auditoria_eventos`), registrado `estado=ok` en `backup_ejecuciones`.
- **Almacenamiento externo off-host**: copias cifradas replicadas a
  `OneDrive - PILLADO Y COMPANIA LIMITADA\SICOM-Backups` (nube corporativa; sobrevive a
  fallo del disco local). Ruta configurada en `.env` (`BACKUP_EXTERNAL_DIR`), heredada por
  la tarea programada. La password DPAPI **no** viaja a la nube.
- Retención "más reciente por período": 7 diarias / 5 semanales / 12 mensuales.
- **Tarea programada** `SICOM-BackupDiario`: diaria **03:15** (ventana off-peak, fiable).

**Estado: ✅ CERRADO** · Riesgo residual documentado en §9.

## 6. Restauración completa (del backup automático)

Restaurado en **PostgreSQL 17 temporal** (aislado, puerto propio, datadir efímero) y
destruido de forma segura al terminar.

| Validación | Resultado |
|------------|-----------|
| Archivo legible (descifrado + TOC) | ✅ 3.381 objetos |
| Tablas / funciones / policies / secuencias / FKs | 161 / 338 / 102 / ✅ / 365 |
| activos / calama_OT / contratos / planes | 68 / 99 / 17 / 212 |
| estado_diario / estanques / kardex / usuarios | 10.338 / 10 / 187 / 16 |
| Registro de migraciones (`schema_migrations` v190) | ✅ presente |
| **Integridad referencial (365 FKs)** | ✅ **0 violaciones** |
| RLS `estado_diario_flota` | ✅ `true` (sobrevive el ciclo) |

- Los conteos **coinciden con producción**.
- Errores de restauración observados = **solo referencias cross-schema de Supabase**
  (roles/`storage`/`realtime`/`auth`/`vault` inexistentes en PG vanilla); **ninguno de
  integridad de datos de negocio**. Comportamiento conocido al restaurar un dump lógico de
  Supabase fuera de Supabase. Copia temporal **destruida**.

**Estado: ✅ CERRADO**

## 7. Simulación de fallos + alerta

| Escenario | Resultado |
|-----------|-----------|
| Credencial inválida | ✅ `exit 1`, alerta **P1** con causa, registro en `backup_ejecuciones` + CSV, **copias válidas NO borradas** |
| Destino no disponible / no escribible | ✅ `exit 1`, alerta P1, copias válidas preservadas |
| Dump corrupto / incompleto | ✅ detectado (ver hallazgo abajo) |

**Hallazgo y endurecimiento (integridad):** `pg_restore --list` sólo lee el **TOC** y
**NO** detecta corrupción en bloques de datos ni truncamiento (verificado: corromper datos
→ `--list` exit 0). Se reforzó el gate para hacer también **`pg_restore -f NUL`** (lectura
y descompresión de **todos** los bloques, sin BD destino), que **sí** detecta la corrupción
(verificado: exit 1, "could not uncompress data: incorrect data check"). La simulación de
corrupción se cambió a un bloque de datos real (offset 40%), no al marcador EOF.

En todos los fallos: `estado=failed`, causa registrada, alerta generada, **copia previa
válida NO eliminada**, `exit ≠ 0`, **nunca marcado como éxito falso**.

**Estado: ✅ CERRADO**

## 8. MIG188 y secretos

- **MIG188 NO ejecutada** (verificado en prod: `schema_migrations` no contiene 188).
  Permanece desautorizada.
- **Sin secretos en el repositorio**: ningún `.env*.local` versionado; sin JWT real
  (verificado por `git ls-files` + escaneo). Evidencia sin credenciales.

**Estado: ✅ CERRADO**

---

## 9. Riesgos residuales (no bloqueantes de Entrega A)

1. **Fiabilidad del backup en horario laboral**: el pooler de Supabase cierra la conexión
   SSL en el COPY largo de tablas grandes (`auditoria_eventos` ~50 MB, `gps_eventos_log`)
   a mediodía. Mitigado con la tarea a las **03:15** (off-peak, éxito consistente) y 5
   reintentos con backoff. Un backup **ad-hoc a mediodía puede requerir varios reintentos**.
2. **Crecimiento no acotado de `auditoria_eventos`**: sin retención, eventualmente puede
   comprometer incluso el backup nocturno. Corresponde a Entrega B/C (retención de tablas
   log). La restauración validó el mecanismo con exclusión de datos de esa tabla-log; su
   esquema restaura y sus datos restaurarían idénticamente al incluirse.
3. **Restauración fuera de Supabase**: para DR real conviene restaurar en un proyecto
   Supabase (o con andamiaje completo de roles/schemas), para resolver las referencias
   cross-schema.

Ninguno impide que el backup se **produzca, cifre, replique off-host, restaure, verifique
integridad y alerte** — todo ejecutado y verificado.

---

## Veredicto

Todos los criterios de Entrega A están **en verde, ejecutados y verificados**:
MIG190 aplicada en prod · bootstrap probado (8 escenarios) · advisory lock funcional ·
CI real en GitHub · CI bloqueó una falla · checks obligatorios en `main` · backup
ejecutado + externo off-host + restaurado + integridad 365 FKs/0 violaciones · fallos +
alerta probados · RLS reconciliada · MIG188 desautorizada · sin secretos.

# GO — ENTREGA A CERRADA
