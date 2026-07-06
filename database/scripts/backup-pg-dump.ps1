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

# Retención robusta: conservar la copia MÁS RECIENTE de cada período
# (NO depende de que el proceso corra un día específico):
#   7 diarias · 5 semanales (semana ISO) · 12 mensuales.
$cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
$dumps = Get-ChildItem $backupDir -Filter 'sicom-*.dump' |
    ForEach-Object {
        $s = $_.BaseName.Substring(6, 8)
        $f = $null; [void][datetime]::TryParseExact($s, 'yyyyMMdd', $null, [System.Globalization.DateTimeStyles]::None, [ref]$f)
        if ($null -eq $f) { return }
        [pscustomobject]@{ File = $_; Fecha = $f
            Semana = '{0}-{1:00}' -f $f.Year, $cal.GetWeekOfYear($f, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
            Mes = '{0}-{1:00}' -f $f.Year, $f.Month }
    } | Sort-Object Fecha -Descending
$conservar = New-Object System.Collections.Generic.HashSet[string]
$dumps | Select-Object -First 7 | ForEach-Object { [void]$conservar.Add($_.File.FullName) }          # 7 diarias
$dumps | Group-Object Semana | Sort-Object Name -Descending | Select-Object -First 5 | ForEach-Object { [void]$conservar.Add(($_.Group | Select-Object -First 1).File.FullName) }  # 5 semanales
$dumps | Group-Object Mes | Sort-Object Name -Descending | Select-Object -First 12 | ForEach-Object { [void]$conservar.Add(($_.Group | Select-Object -First 1).File.FullName) }     # 12 mensuales
$dumps | Where-Object { -not $conservar.Contains($_.File.FullName) } | ForEach-Object { Remove-Item $_.File.FullName -Confirm:$false }
Write-Output "Backup OK: $outFile ($sizeMB MB). Conservados tras retención: $($conservar.Count)"
