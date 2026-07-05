# Estrategia de respaldo de la base de datos — SICOM-ICEO

**Estado:** propuesta lista para decisión (auditoría Fase 0, 2026-07-03).
**Dato pendiente de validación en panel Supabase:** el plan actual y si existe algún backup administrado activo. Nada de este documento asume que exista; el diseño cubre ambos escenarios.

## Objetivos propuestos (a ratificar por la empresa)

| Parámetro | Propuesta | Justificación |
|---|---|---|
| **RPO** (pérdida máxima de datos) | 24 h (1 h si se contrata PITR) | El sistema registra operación diaria; perder más de un día de kardex/OTs obliga a reconstrucción manual desde evidencias. |
| **RTO** (tiempo máximo de restauración) | 4 h hábiles | La operación puede sostenerse unas horas con papel/planillas; más de un turno ya impacta despachos de combustible y taller. |
| **Retención** | Diaria ×14, semanal ×8, mensual ×12 | Cubre errores detectados tarde (p.ej. el descuadre C5 llevaba ~6 semanas sin detectarse). |

## Alternativa A — Backups administrados de Supabase (recomendada como base)

- **Qué es:** upgrade al plan Pro: backups diarios automáticos gestionados por Supabase, retención 7 días (ampliable; PITR con WAL como add-on baja el RPO a minutos).
- **Pros:** cero mantenimiento, restauración desde el panel, cubre también roles/extensiones/config.
- **Contras:** costo mensual; retención base de 7 días es menor a la propuesta → se complementa con la Alternativa B para retención larga.
- **Acción:** decidir upgrade en el panel (Settings → Billing). Verificar después en Settings → Database → Backups que aparezcan los respaldos diarios.

## Alternativa B — `pg_dump` programado (complemento, o mínimo viable si no hay upgrade)

- **Qué es:** volcado lógico diario con `pg_dump` (formato custom `-Fc`, comprimido) ejecutado desde una máquina de la empresa (o un runner/cron externo), subido cifrado a un destino FUERA de Supabase.
- **Script preparado:** `database/scripts/backup-pg-dump.ps1` (lee credenciales de `.env.supabase-admin.local`, NO las contiene). Requiere `pg_dump` instalado (PostgreSQL client tools, misma versión mayor que el servidor).
- **Destino:** carpeta sincronizada a un almacenamiento externo (Google Drive de la empresa, S3, o disco de red con copia fuera de oficina). Nunca solo el disco local de una notebook.
- **Cifrado:** el script comprime y puede cifrarse con 7-Zip AES-256 (contraseña en un gestor de claves, no en el script) antes de subir.
- **Frecuencia:** diaria 03:00 (antes del job `mantenimiento-diario` de las 04:00). Programar con el Programador de tareas de Windows o cron.
- **Retención:** el script elimina >14 diarios, conserva el primero de cada semana ×8 y el primero de cada mes ×12.

## Protección de credenciales

- La cadena de conexión vive únicamente en `.env.supabase-admin.local` (verificado: no versionado, cubierto por `.gitignore`).
- El script no imprime la contraseña ni la incluye en logs.
- Recomendación de la auditoría: **rotar la contraseña de BD** dado que hoy vive en texto plano en el disco de trabajo, y restringir el archivo con permisos NTFS al usuario actual.

## Validación de integridad y prueba de restauración

Un backup no probado no es un backup:

1. **Integridad automática (cada backup):** el script ejecuta `pg_restore --list` sobre el dump generado (verifica que el archivo es legible y completo) y registra tamaño + duración en `backups/backup-log.csv`. Un dump <50% del tamaño del anterior genera advertencia.
2. **Prueba de restauración (mensual):** restaurar el último dump en una BD limpia y correr las consultas de humo:
   ```
   pg_restore -d <bd_prueba> --no-owner --no-privileges <dump>
   -- luego:
   SELECT count(*) FROM ordenes_trabajo;
   SELECT count(*) FROM combustible_kardex_valorizado;
   SELECT count(*) FROM estado_diario_flota;
   SELECT max(fecha_movimiento) FROM combustible_kardex_valorizado; -- debe ser reciente
   ```
   Opciones para la BD de prueba: un Postgres local (Docker) o un proyecto Supabase gratuito de staging. Registrar el resultado (fecha, quién, OK/FALLO) al final de este documento.
3. **Alertas de fallo:** el Programador de tareas debe configurarse con "ejecutar aunque falle" + notificación; adicionalmente el script escribe `ULTIMO_BACKUP_OK.txt` con timestamp — un chequeo semanal humano (o un cron del sistema que alerte si el archivo tiene >48 h) cierra el ciclo.

## Procedimiento de restauración (resumen ejecutable)

1. Congelar escrituras: pausar los cron jobs (`SELECT cron.unschedule(jobname) …` documentado en el plan de despliegue) y avisar a los usuarios.
2. Restaurar:
   - Plan Pro: panel Supabase → Backups → Restore (crea el estado al punto elegido).
   - pg_dump: crear proyecto/BD limpia → `pg_restore --no-owner --no-privileges -d <nueva_bd> <dump>` → repuntar `SUPABASE_DB_URL`/env de Netlify si cambió el proyecto.
3. Smoke tests: los 4 SELECT de arriba + login de un usuario + carga del dashboard.
4. Reanudar crons y avisar.

## Responsable y gobernanza

- **Responsable propuesto:** Manuel Olivares (operación) como dueño del proceso; delegable la ejecución mensual de la prueba de restauración.
- **Revisión:** este documento se revisa al cambiar de plan Supabase o al superar 500 MB de BD.

## Decisión pendiente de la empresa

1. ¿Upgrade a plan Pro (backups administrados + soporte) o solo pg_dump programado?  → la auditoría recomienda **ambos**: Pro para RPO/RTO cortos + pg_dump semanal a destino propio para retención larga e independencia del proveedor.
2. Ratificar RPO/RTO/retención de la tabla inicial.
3. Autorizar la rotación de la contraseña de BD.

## Registro de pruebas de restauración

| Fecha | Ejecutor | Backup probado | Resultado | Observaciones |
|---|---|---|---|---|
| — | — | — | — | (pendiente primera prueba) |
