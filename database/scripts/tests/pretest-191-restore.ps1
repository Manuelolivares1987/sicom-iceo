# Restaura prod en PG17 temporal (puerto 55442), scaffold storage, aplica MIG191.
# Deja el servidor CORRIENDO para las pruebas. Uso interno de desarrollo.
$ErrorActionPreference = 'Continue'
$BIN='C:\Program Files\PostgreSQL\17\bin'
$sevenz='C:\Program Files\7-Zip\7z.exe'
$PORT=55442
$DATA=Join-Path $env:TEMP 'pg17inf'
$work=Join-Path $env:TEMP 'inf-work'
$backupDir='C:\Users\Manuel Olivares\sicom-iceo\backups-fase0'
function Step($m){ Write-Output ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m) }

# 1) Descifrar backup completo (134600 = full con auditoria)
$enc=Get-ChildItem "$backupDir\sicom-20260705-134600.dump.7z"
$sec=Get-Content "$backupDir\.enc-pass.dpapi" | ConvertTo-SecureString
$pass=[System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
if(Test-Path $work){ [System.IO.Directory]::Delete($work,$true) }
New-Item -ItemType Directory -Force $work | Out-Null
& $sevenz e "-p$pass" -o"$work" $enc.FullName | Out-Null
$dump=(Get-ChildItem "$work\*.dump" | Select-Object -First 1).FullName
Step "descifrado: $dump"

# 2) Cluster fresco
& "$BIN\pg_ctl.exe" -D $DATA stop -m immediate 2>$null | Out-Null
if(Test-Path $DATA){ [System.IO.Directory]::Delete($DATA,$true) }
Set-Content "$env:TEMP\pwi.txt" 'postgres' -NoNewline
& "$BIN\initdb.exe" -D $DATA -U postgres --pwfile "$env:TEMP\pwi.txt" --encoding=UTF8 --locale=C > "$env:TEMP\initinf.log" 2>&1
Remove-Item "$env:TEMP\pwi.txt"
Step "initdb OK"

# 3) Arranca postgres DETACHED (evita cuelgue de pg_ctl con redireccion)
Start-Process -FilePath "$BIN\postgres.exe" -ArgumentList @('-D',$DATA,'-p',"$PORT",'-k',$DATA) -WindowStyle Hidden
$env:PGPASSWORD='postgres'; $P=@('-h','127.0.0.1','-p',"$PORT",'-U','postgres','-d','postgres')
for($i=0;$i -lt 30;$i++){ & "$BIN\pg_isready.exe" @P *> $null; if($LASTEXITCODE -eq 0){break}; Start-Sleep 1 }
Step "servidor listo"

# 4) Scaffold roles/auth/extensions/storage
$scaffold=@'
DO $$ BEGIN CREATE ROLE anon NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticator LOGIN PASSWORD 'x' NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS extensions; CREATE SCHEMA IF NOT EXISTS storage;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE TABLE IF NOT EXISTS auth.users(id uuid PRIMARY KEY, email varchar);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $fn$ SELECT NULLIF(current_setting('request.jwt.claims',true)::jsonb->>'sub','')::uuid $fn$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $fn$ SELECT current_setting('request.jwt.claims',true)::jsonb->>'role' $fn$;
CREATE TABLE IF NOT EXISTS storage.buckets(id text PRIMARY KEY, name text, public boolean DEFAULT false);
CREATE TABLE IF NOT EXISTS storage.objects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text, name text, owner uuid, created_at timestamptz DEFAULT now());
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA storage TO anon, authenticated;
GRANT SELECT ON storage.buckets TO anon, authenticated;
GRANT SELECT, INSERT ON storage.objects TO authenticated;
'@
Set-Content "$env:TEMP\scaf-inf.sql" $scaffold -Encoding ASCII
& "$BIN\psql.exe" @P -q -v ON_ERROR_STOP=0 -f "$env:TEMP\scaf-inf.sql" > "$env:TEMP\scaf-inf.out" 2>&1
Step "scaffold OK"

# 5) Restaura public (pre/data/post)
& "$BIN\pg_restore.exe" @P --schema=public --section=pre-data --no-owner --no-privileges --no-comments $dump > "$env:TEMP\inf_pre.log" 2>&1
& "$BIN\psql.exe" @P -q -c "INSERT INTO auth.users(id) SELECT id FROM public.usuarios_perfil ON CONFLICT DO NOTHING;" > $null 2>&1
& "$BIN\pg_restore.exe" @P --schema=public --section=data --no-owner --no-privileges --disable-triggers $dump > "$env:TEMP\inf_data.log" 2>&1
& "$BIN\pg_restore.exe" @P --schema=public --section=post-data --no-owner --no-privileges $dump > "$env:TEMP\inf_post.log" 2>&1
$nt=(& "$BIN\psql.exe" @P -tA -c "SELECT count(*) FROM pg_tables WHERE schemaname='public'") -join ''
Step "restore OK (tablas public: $nt)"

# 6) Aplica MIG191
& "$BIN\psql.exe" @P -v ON_ERROR_STOP=1 -f "C:\Users\Manuel Olivares\sicom-iceo\database\production_run\191_informes_intervencion.sql" > "$env:TEMP\mig191.out" 2>&1
$rc=$LASTEXITCODE
Write-Output "=== salida MIG191 (postval) ==="
Get-Content "$env:TEMP\mig191.out" | Select-String -Pattern 'POSTVAL|ERROR|NOTICE|CREATE|ALTER' | Select-Object -Last 6 | ForEach-Object { $_.Line }
Write-Output "mig191_exit: $rc"
