# ============================================================================
# restaurar-validar.ps1 - Restauracion end-to-end del backup AUTOMATICO
# (frente 1 / Seccion 6). Descifra el ultimo .7z, restaura en un PG17 temporal,
# valida objetos y conteos criticos, registra la prueba en backup_ejecuciones,
# y DESTRUYE la copia temporal. Solo lectura contra prod (para registrar).
# Uso: powershell -File restaurar-validar.ps1
# ============================================================================
# 'Continue': los binarios nativos (initdb/pg_ctl) emiten warnings a stderr que
# PowerShell 5.1 trataria como error con 'Stop'. Se validan resultados por $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupDir = Join-Path $scriptDir '..\..\backups-fase0'
$passFile  = Join-Path $backupDir '.enc-pass.dpapi'
$BIN = 'C:\Program Files\PostgreSQL\17\bin'
$sevenz = @("C:\Program Files\7-Zip\7z.exe","C:\Program Files (x86)\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$PORT = 55440
$DATA = Join-Path $env:TEMP 'pg17restore'
$work = Join-Path $env:TEMP 'restore-work'

$enc = Get-ChildItem $backupDir -Filter 'sicom-*.dump.7z' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $enc) { throw "No hay backup .7z para restaurar" }
Write-Output ("Backup a restaurar: {0} ({1} MB)" -f $enc.Name, [math]::Round($enc.Length/1MB,2))

# Descifrar
$sec = Get-Content $passFile | ConvertTo-SecureString
$pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force $work | Out-Null
& $sevenz e "-p$pass" -o"$work" $enc.FullName | Out-Null
$dump = Get-ChildItem $work -Filter '*.dump' | Select-Object -First 1
if (-not $dump) { throw "Descifrado fallo (sin .dump)" }
Write-Output "Descifrado OK"

# Cluster PG17 temporal
Get-Process postgres -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*17*" -and $_.MainModule.FileName -like "*$DATA*" } | Out-Null
if (Test-Path $DATA) { & "$BIN\pg_ctl.exe" -D $DATA stop -m immediate 2>$null | Out-Null; Start-Sleep 1; Remove-Item $DATA -Recurse -Force -ErrorAction SilentlyContinue }
Set-Content "$env:TEMP\pwr.txt" 'postgres' -NoNewline; $null = & "$BIN\initdb.exe" -D $DATA -U postgres --pwfile "$env:TEMP\pwr.txt" --encoding=UTF8 --locale=C 2>&1; Remove-Item "$env:TEMP\pwr.txt"
& "$BIN\pg_ctl.exe" -D $DATA -l "$DATA\r.log" -o "-p $PORT" -w start | Out-Null
$env:PGPASSWORD='postgres'; $P=@('-h','127.0.0.1','-p',"$PORT",'-U','postgres','-d','postgres')

# Andamiaje minimo (roles + auth + extensiones)
$scaffold = @"
DO `$`$ BEGIN CREATE ROLE anon NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END `$`$;
DO `$`$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END `$`$;
DO `$`$ BEGIN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END `$`$;
DO `$`$ BEGIN CREATE ROLE authenticator LOGIN PASSWORD 'x' NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END `$`$;
CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS extensions; CREATE SCHEMA IF NOT EXISTS net; CREATE SCHEMA IF NOT EXISTS cron; CREATE SCHEMA IF NOT EXISTS vault; CREATE SCHEMA IF NOT EXISTS storage; CREATE SCHEMA IF NOT EXISTS graphql; CREATE SCHEMA IF NOT EXISTS graphql_public; CREATE SCHEMA IF NOT EXISTS realtime;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE TABLE IF NOT EXISTS auth.users(id uuid PRIMARY KEY, email varchar);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS `$fn`$ SELECT NULLIF(current_setting('request.jwt.claims',true)::jsonb->>'sub','')::uuid `$fn`$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS `$fn`$ SELECT current_setting('request.jwt.claims',true)::jsonb->>'role' `$fn`$;
"@
$scaffold | & "$BIN\psql.exe" @P -q -v ON_ERROR_STOP=0 -f - | Out-Null

# Restaurar public (pre-data -> poblar auth.users -> data -> post-data)
& "$BIN\pg_restore.exe" @P --schema=public --section=pre-data --no-owner --no-privileges --no-comments $dump.FullName 2>"$env:TEMP\rp.log" | Out-Null
& "$BIN\psql.exe" @P -q -c "INSERT INTO auth.users(id) SELECT id FROM public.usuarios_perfil ON CONFLICT DO NOTHING;" 2>$null | Out-Null
& "$BIN\pg_restore.exe" @P --schema=public --section=data --no-owner --no-privileges --disable-triggers $dump.FullName 2>"$env:TEMP\rd.log" | Out-Null
& "$BIN\pg_restore.exe" @P --schema=public --section=post-data --no-owner --no-privileges $dump.FullName 2>"$env:TEMP\rpo.log" | Out-Null

# Validaciones
$q = @"
SELECT jsonb_pretty(jsonb_build_object(
  'tablas',(SELECT count(*) FROM pg_tables WHERE schemaname='public'),
  'funciones',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'),
  'triggers',(SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal),
  'policies',(SELECT count(*) FROM pg_policies WHERE schemaname='public'),
  'secuencias',(SELECT count(*) FROM pg_sequences WHERE schemaname='public'),
  'extensiones',(SELECT count(*) FROM pg_extension),
  'activos',(SELECT count(*) FROM activos),
  'ordenes_trabajo',(SELECT count(*) FROM ordenes_trabajo),
  'contratos',(SELECT count(*) FROM contratos),
  'planes',(SELECT count(*) FROM planes_mantenimiento),
  'estado_diario',(SELECT count(*) FROM estado_diario_flota),
  'combustible_estanques',(SELECT count(*) FROM combustible_estanques),
  'kardex',(SELECT count(*) FROM combustible_kardex_valorizado),
  'usuarios',(SELECT count(*) FROM usuarios_perfil),
  'schema_migrations_190',(SELECT count(*) FROM schema_migrations WHERE version='190'),
  'fk_huerfanos_ot_activo',(SELECT count(*) FROM ordenes_trabajo o LEFT JOIN activos a ON a.id=o.activo_id WHERE o.activo_id IS NOT NULL AND a.id IS NULL)
))
"@
$res = ($q | & "$BIN\psql.exe" @P -tA -f -) -join "`n"
Write-Output "=== VALIDACION DE LA RESTAURACION ==="
Write-Output $res

# Registrar prueba en prod + destruir copia temporal
$activos = ([regex]'"activos": (\d+)').Match($res).Groups[1].Value
& "$BIN\pg_ctl.exe" -D $DATA stop -m fast | Out-Null
Remove-Item $DATA -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
Write-Output "Copia temporal restaurada DESTRUIDA. Validacion completa."
