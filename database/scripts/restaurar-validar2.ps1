# restaurar-validar2.ps1 - Restauracion end-to-end robusta (Seccion 6).
# Descifra el ultimo .7z, restaura en PG17 temporal (puerto propio, datadir fresco),
# valida objetos y conteos criticos, DESTRUYE la copia temporal. Sin escritura a prod.
$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupDir = Join-Path $scriptDir '..\..\backups-fase0'
$passFile  = Join-Path $backupDir '.enc-pass.dpapi'
$BIN = 'C:\Program Files\PostgreSQL\17\bin'
$sevenz = 'C:\Program Files\7-Zip\7z.exe'
$PORT = 55441
$DATA = Join-Path $env:TEMP 'pg17r2'
$work = Join-Path $env:TEMP 'restore-work2'

function Step($m){ Write-Output ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) }

$enc = Get-ChildItem $backupDir -Filter 'sicom-*.dump.7z' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Step ("Backup: {0} ({1} MB)" -f $enc.Name,[math]::Round($enc.Length/1MB,2))

$sec = Get-Content $passFile | ConvertTo-SecureString
$pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force $work | Out-Null
& $sevenz e "-p$pass" -o"$work" $enc.FullName | Out-Null
$dump = Get-ChildItem $work -Filter '*.dump' | Select-Object -First 1
if (-not $dump) { Step 'FALLO descifrado'; exit 1 }
Step 'Descifrado OK'

if (Test-Path $DATA) { Remove-Item $DATA -Recurse -Force -ErrorAction SilentlyContinue }
Set-Content "$env:TEMP\pwr2.txt" 'postgres' -NoNewline
& "$BIN\initdb.exe" -D $DATA -U postgres --pwfile "$env:TEMP\pwr2.txt" --encoding=UTF8 --locale=C > "$env:TEMP\initdb2.log" 2>&1
Remove-Item "$env:TEMP\pwr2.txt"
if (-not (Test-Path "$DATA\PG_VERSION")) { Step 'FALLO initdb'; Get-Content "$env:TEMP\initdb2.log"|Select-Object -Last 5; exit 1 }
Step 'initdb OK'
& "$BIN\pg_ctl.exe" -D $DATA -l "$DATA\srv.log" -o "-p $PORT" -w start > "$env:TEMP\pgctl2.log" 2>&1
$env:PGPASSWORD='postgres'; $P=@('-h','127.0.0.1','-p',"$PORT",'-U','postgres','-d','postgres')
Step 'servidor arrancado'

# Scaffold por archivo (no stdin)
$scaffoldSql = @'
DO $$ BEGIN CREATE ROLE anon NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticator LOGIN PASSWORD 'x' NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE TABLE IF NOT EXISTS auth.users(id uuid PRIMARY KEY, email varchar);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $fn$ SELECT NULLIF(current_setting('request.jwt.claims',true)::jsonb->>'sub','')::uuid $fn$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $fn$ SELECT current_setting('request.jwt.claims',true)::jsonb->>'role' $fn$;
'@
Set-Content "$env:TEMP\scaffold2.sql" $scaffoldSql -Encoding ASCII
& "$BIN\psql.exe" @P -q -v ON_ERROR_STOP=0 -f "$env:TEMP\scaffold2.sql" > "$env:TEMP\scaffold2.out" 2>&1
Step 'scaffold OK'

& "$BIN\pg_restore.exe" @P --schema=public --section=pre-data --no-owner --no-privileges --no-comments $dump.FullName > "$env:TEMP\r2_pre.log" 2>&1
Step 'pre-data restaurado'
& "$BIN\psql.exe" @P -q -c "INSERT INTO auth.users(id) SELECT id FROM public.usuarios_perfil ON CONFLICT DO NOTHING;" > $null 2>&1
& "$BIN\pg_restore.exe" @P --schema=public --section=data --no-owner --no-privileges --disable-triggers $dump.FullName > "$env:TEMP\r2_data.log" 2>&1
Step 'data restaurado'
& "$BIN\pg_restore.exe" @P --schema=public --section=post-data --no-owner --no-privileges $dump.FullName > "$env:TEMP\r2_post.log" 2>&1
Step 'post-data restaurado'

$qSql = @'
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
  'auditoria_eventos_tabla',(SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename='auditoria_eventos'),
  'fk_huerfanos_ot_activo',(SELECT count(*) FROM ordenes_trabajo o LEFT JOIN activos a ON a.id=o.activo_id WHERE o.activo_id IS NOT NULL AND a.id IS NULL)
))
'@
Set-Content "$env:TEMP\q2.sql" $qSql -Encoding ASCII
Write-Output "=== VALIDACION DE LA RESTAURACION ==="
& "$BIN\psql.exe" @P -tA -f "$env:TEMP\q2.sql"

& "$BIN\pg_ctl.exe" -D $DATA stop -m immediate > $null 2>&1
Start-Sleep 2
Remove-Item $DATA -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
Step 'Copia temporal DESTRUIDA. Validacion completa.'
