# ============================================================================
# backup-pg-dump.ps1 — Respaldo lógico diario de la BD SICOM-ICEO
# ----------------------------------------------------------------------------
# Lee la conexión desde ..\..\.env.supabase-admin.local (NUNCA contiene
# credenciales este script). Requiere pg_dump en el PATH (PostgreSQL client
# tools, misma versión mayor que el servidor).
#
# Uso manual:      powershell -File backup-pg-dump.ps1
# Programado:      Programador de tareas Windows, diario 03:00.
# Retención:       diaria x14, semanal (lunes) x8, mensual (día 1) x12.
# Ver estrategia:  docs/operacion/estrategia-respaldo-base-datos.md
# ============================================================================
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile   = Join-Path $scriptDir '..\..\.env.supabase-admin.local'
$backupDir = Join-Path $scriptDir '..\..\backups'
if (-not (Test-Path $envFile)) { throw "No existe $envFile" }
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Force $backupDir | Out-Null }

# Parsear .env (KEY=VALUE) sin imprimir valores
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+)\s*$') { $envVars[$Matches[1]] = $Matches[2].Trim() }
}

$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $backupDir "sicom-$stamp.dump"

if ($envVars.ContainsKey('SUPABASE_DB_URL') -and $envVars['SUPABASE_DB_URL']) {
    & pg_dump --format=custom --no-owner --file=$outFile $envVars['SUPABASE_DB_URL']
} else {
    $env:PGPASSWORD = $envVars['SUPABASE_DB_PASSWORD']
    $port = if ($envVars['SUPABASE_DB_PORT']) { $envVars['SUPABASE_DB_PORT'] } else { '5432' }
    $db   = if ($envVars['SUPABASE_DB_NAME']) { $envVars['SUPABASE_DB_NAME'] } else { 'postgres' }
    & pg_dump --format=custom --no-owner --file=$outFile `
        -h $envVars['SUPABASE_DB_HOST'] -p $port -U $envVars['SUPABASE_DB_USER'] -d $db
    Remove-Item Env:PGPASSWORD
}
if ($LASTEXITCODE -ne 0) { throw "pg_dump falló (exit $LASTEXITCODE)" }

# Validación de integridad: el dump debe ser listable
& pg_restore --list $outFile | Out-Null
if ($LASTEXITCODE -ne 0) { throw "pg_restore --list falló: dump corrupto" }

$sizeMB = [math]::Round((Get-Item $outFile).Length / 1MB, 1)
Add-Content (Join-Path $backupDir 'backup-log.csv') "$stamp,$sizeMB MB,OK"
Set-Content (Join-Path $backupDir 'ULTIMO_BACKUP_OK.txt') (Get-Date -Format 's')

# Retención: diarios >14 días se eliminan, salvo lunes (<=8 semanas) y día 1 (<=12 meses)
Get-ChildItem $backupDir -Filter 'sicom-*.dump' | ForEach-Object {
    if ($_.Name -match 'sicom-(\d{8})-') {
        $fecha = [datetime]::ParseExact($Matches[1], 'yyyyMMdd', $null)
        $edad  = (New-TimeSpan -Start $fecha -End (Get-Date)).Days
        $esLunes  = $fecha.DayOfWeek -eq 'Monday'
        $esDia1   = $fecha.Day -eq 1
        $borrar = ($edad -gt 14 -and -not $esLunes -and -not $esDia1) `
              -or ($edad -gt 56 -and $esLunes -and -not $esDia1) `
              -or ($edad -gt 365 -and $esDia1)
        if ($borrar) { Remove-Item $_.FullName -Confirm:$false }
    }
}
Write-Output "Backup OK: $outFile ($sizeMB MB)"
