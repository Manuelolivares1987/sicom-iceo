# ============================================================================
# backup-diario.ps1 - Backup automatico operativo (frente 1, Sprint 1).
# ----------------------------------------------------------------------------
# pg_dump -Fc -> cifrado AES-256 (7-Zip) -> SHA-256 -> registro en
# backup_ejecuciones (+ fallback CSV local si la BD no responde) -> copia
# externa -> retencion robusta -> alerta exito/fallo. Sale != 0 en fallo.
#
# Seguridad:
#   - La password de cifrado NO se guarda en texto plano: DPAPI por usuario.
#     Setup una sola vez:  powershell -File backup-diario.ps1 -SetupPassword
#   - La conexion se lee de .env.supabase-admin.local (no versionada); nunca
#     se imprime ni se pasa como argumento visible (usa variables PG*).
#
# Alertas: <backupDir>/estado-backup.json y, si existe BACKUP_ALERT_WEBHOOK,
# hace POST del evento (sin secretos).
#
# Uso:
#   powershell -File backup-diario.ps1 -SetupPassword       # una vez
#   powershell -File backup-diario.ps1                      # backup diario
#   powershell -File backup-diario.ps1 -SimularFallo <tipo> # pruebas
# ============================================================================
param(
    [switch]$SetupPassword,
    [string]$SimularFallo = ''   # cred | destino | corrupto
)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile   = Join-Path $scriptDir '..\..\.env.supabase-admin.local'
$backupDir = Join-Path $scriptDir '..\..\backups-fase0'
$externDir = if ($env:BACKUP_EXTERNAL_DIR) { $env:BACKUP_EXTERNAL_DIR } else { Join-Path $backupDir 'externo' }
$passFile  = Join-Path $backupDir '.enc-pass.dpapi'
$logCsv    = Join-Path $backupDir 'backup-log.csv'
$estadoJson= Join-Path $backupDir 'estado-backup.json'
$BIN = 'C:\Program Files\PostgreSQL\17\bin'
$sevenz = @("C:\Program Files\7-Zip\7z.exe","C:\Program Files (x86)\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
New-Item -ItemType Directory -Force $backupDir | Out-Null

function Restrict-Acl($path) { $a=Get-Acl $path; $a.SetAccessRuleProtection($true,$false); $a.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME,'FullControl','Allow'))); Set-Acl $path $a }

if ($SetupPassword) {
    $rb = New-Object 'System.Byte[]' 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rb)
    $pw = -join ($rb | ForEach-Object { $_.ToString('x2') })
    ConvertFrom-SecureString (ConvertTo-SecureString $pw -AsPlainText -Force) | Set-Content $passFile
    Restrict-Acl $passFile
    Write-Output "Password de cifrado generada y guardada cifrada (DPAPI). NO impresa."
    exit 0
}
if (-not (Test-Path $passFile)) { throw "Falta la password de cifrado. Ejecuta: backup-diario.ps1 -SetupPassword" }
$sec  = Get-Content $passFile | ConvertTo-SecureString
$pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

$envVars = @{}; Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+)\s*$') { $envVars[$Matches[1]] = $Matches[2].Trim() } }
# Almacenamiento externo off-host: prioridad env de proceso; si no, del .env; si
# no, ./externo (mismo disco, solo respaldo minimo). La tarea programada hereda
# la ruta desde el .env sin necesidad de variables de entorno persistentes.
if (-not $env:BACKUP_EXTERNAL_DIR -and $envVars.ContainsKey('BACKUP_EXTERNAL_DIR') -and $envVars['BACKUP_EXTERNAL_DIR']) { $externDir = $envVars['BACKUP_EXTERNAL_DIR'] }
function Set-PgEnv {
    if ($envVars.ContainsKey('SUPABASE_DB_URL') -and $envVars['SUPABASE_DB_URL']) {
        $u = [uri]$envVars['SUPABASE_DB_URL']
        $env:PGHOST=$u.Host; $env:PGPORT=($(if($u.Port -gt 0){$u.Port}else{5432})); $env:PGUSER=[uri]::UnescapeDataString($u.UserInfo.Split(':')[0]); $env:PGPASSWORD=[uri]::UnescapeDataString($u.UserInfo.Split(':')[1]); $env:PGDATABASE=$u.AbsolutePath.TrimStart('/'); $env:PGSSLMODE='require'
    } else { $env:PGHOST=$envVars['SUPABASE_DB_HOST']; $env:PGPORT=$envVars['SUPABASE_DB_PORT']; $env:PGUSER=$envVars['SUPABASE_DB_USER']; $env:PGPASSWORD=$envVars['SUPABASE_DB_PASSWORD']; $env:PGDATABASE=$envVars['SUPABASE_DB_NAME']; $env:PGSSLMODE='require' }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $backupDir "sicom-$stamp.dump"
$encFile = "$outFile.7z"
$t0 = Get-Date
$estado = 'error'; $msgError = ''; $sha=''; $sizeBytes=0

function Emitir-Alerta($sev, $est, $msg) {
    $evt = @{ servicio='backup'; operacion='backup-diario'; fecha=(Get-Date -Format s); resultado=$est; severidad=$sev; mensaje=$msg; archivo=(Split-Path $encFile -Leaf) }
    $evt | ConvertTo-Json -Compress | Set-Content $estadoJson
    if ($env:BACKUP_ALERT_WEBHOOK) { try { Invoke-RestMethod -Method Post -Uri $env:BACKUP_ALERT_WEBHOOK -Body ($evt|ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 10 } catch {} }
    Write-Output ("ALERTA[{0}] backup {1}: {2}" -f $sev, $est, $msg)
}

try {
    Set-PgEnv
    if ($SimularFallo -eq 'cred') { $env:PGPASSWORD = 'password-invalida-xyz' }
    if ($SimularFallo -eq 'destino') { throw "Destino de backup no disponible o no escribible (simulado)" }

    # pg_dump con reintentos y backoff (metodo por variables PG*, estable de
    # madrugada; el pooler cae en COPY largos con carga). keepalives via env.
    $env:PGCONNECT_TIMEOUT='30'
    $intentos = 0; $dumpOk = $false; $maxIntentos = 5
    while (-not $dumpOk -and $intentos -lt $maxIntentos) {
        $intentos++
        if (Test-Path $outFile) { [System.IO.File]::Delete($outFile) }
        & "$BIN\pg_dump.exe" -Fc --no-owner --no-privileges -f $outFile
        if ($LASTEXITCODE -eq 0) { $dumpOk = $true }
        else { Write-Output ("  intento {0}/{1} fallo, reintentando..." -f $intentos,$maxIntentos); Start-Sleep -Seconds (8 * $intentos) }
    }
    if (-not $dumpOk) { throw "pg_dump fallo tras $intentos intentos; revisar credenciales o red" }
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue

    # Simula corrupcion en un BLOQUE DE DATOS (offset ~40%), no en el marcador
    # EOF final: corromper la cola no altera el TOC ni un bloque, y no seria
    # detectable. La corrupcion en datos si debe hacer fallar el gate -f NUL.
    if ($SimularFallo -eq 'corrupto') { $fs=[System.IO.File]::Open($outFile,'Open','Write'); $fs.Position=[long]((Get-Item $outFile).Length*0.4); $bad=New-Object byte[] 4096; for($i=0;$i -lt 4096;$i++){$bad[$i]=0xFF}; $fs.Write($bad,0,4096); $fs.Close() }

    if ((Get-Item $outFile).Length -eq 0) { throw "Dump vacio" }
    # Integridad de CABECERA (TOC).
    & "$BIN\pg_restore.exe" --list $outFile > "$env:TEMP\toc-$stamp.txt" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Integridad: pg_restore --list fallo (cabecera/TOC corrupto)" }
    # Integridad de DATOS: --list solo lee el TOC y NO detecta corrupcion en los
    # bloques de datos ni un dump truncado. -f NUL descomprime y recorre TODOS los
    # bloques sin necesidad de una BD destino; falla ante corrupcion o truncamiento.
    & "$BIN\pg_restore.exe" -f NUL --no-owner $outFile 2>"$env:TEMP\intg-$stamp.txt"
    if ($LASTEXITCODE -ne 0) { throw "Integridad: lectura completa fallo (dump corrupto o incompleto)" }

    & $sevenz a -t7z "-p$pass" -mhe=on $encFile $outFile | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $encFile)) { throw "Cifrado 7-Zip fallo" }
    [System.IO.File]::Delete($outFile)
    Restrict-Acl $encFile
    $sizeBytes = (Get-Item $encFile).Length
    $sha = (Get-FileHash $encFile -Algorithm SHA256).Hash

    New-Item -ItemType Directory -Force $externDir | Out-Null
    Copy-Item $encFile (Join-Path $externDir (Split-Path $encFile -Leaf)) -Force

    $estado = 'ok'
} catch {
    $msgError = $_.Exception.Message
    if (Test-Path $outFile) { [System.IO.File]::Delete($outFile) }  # limpia el plano fallido; NO toca copias previas
}

$dur = [int]((Get-Date) - $t0).TotalMilliseconds

# Registrar en backup_ejecuciones (best-effort) + fallback CSV local SIEMPRE
$registradoBD = $false
try {
    Set-PgEnv
    $fi = $t0.ToString('s')
    $errSql = if ($msgError) { "'" + (($msgError -replace "'","''").Substring(0,[Math]::Min(280,$msgError.Length))) + "'" } else { 'NULL' }
    $sqlIns = "INSERT INTO public.backup_ejecuciones(fecha_inicio,fecha_fin,tipo,tamano_bytes,sha256,ubicacion_logica,estado,mensaje_error) VALUES ('$fi', now(), 'diario', $sizeBytes, '$sha', 'local+externo', '$estado', $errSql);"
    & "$BIN\psql.exe" -v ON_ERROR_STOP=1 -c $sqlIns *> $null
    if ($LASTEXITCODE -eq 0) { $registradoBD = $true }
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
} catch {}
Add-Content $logCsv ("{0},{1},{2},{3},{4},bd={5}" -f $stamp, $estado, $sizeBytes, $sha, ($msgError -replace ',',';'), $registradoBD)

# Retencion robusta (mas reciente por periodo) SOLO si el backup fue OK
if ($estado -eq 'ok') {
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $dumps = Get-ChildItem $backupDir -Filter 'sicom-*.dump.7z' | ForEach-Object {
        $s=$_.BaseName.Substring(6,8); $f=[datetime]::MinValue; [void][datetime]::TryParseExact($s,'yyyyMMdd',[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::None,[ref]$f)
        if ($f -eq [datetime]::MinValue) { return }
        if ($null -eq $f) { return }
        [pscustomobject]@{ File=$_; Fecha=$f; Semana=('{0}-{1:00}' -f $f.Year,$cal.GetWeekOfYear($f,[System.Globalization.CalendarWeekRule]::FirstFourDayWeek,[DayOfWeek]::Monday)); Mes=('{0}-{1:00}' -f $f.Year,$f.Month) }
    } | Sort-Object Fecha -Descending
    $c = New-Object System.Collections.Generic.HashSet[string]
    $dumps | Select-Object -First 7 | ForEach-Object { [void]$c.Add($_.File.FullName) }
    $dumps | Group-Object Semana | Sort-Object Name -Descending | Select-Object -First 5 | ForEach-Object { [void]$c.Add(($_.Group|Select-Object -First 1).File.FullName) }
    $dumps | Group-Object Mes | Sort-Object Name -Descending | Select-Object -First 12 | ForEach-Object { [void]$c.Add(($_.Group|Select-Object -First 1).File.FullName) }
    $dumps | Where-Object { -not $c.Contains($_.File.FullName) } | ForEach-Object { $_.File | Remove-Item -Force }
}

if ($estado -eq 'ok') { Emitir-Alerta 'P4' 'ok' ("backup cifrado {0} MB, sha {1}, registrado_bd={2}" -f [math]::Round($sizeBytes/1MB,2), $sha.Substring(0,12), $registradoBD); exit 0 }
else { Emitir-Alerta 'P1' 'error' $msgError; exit 1 }
