# Wrapper PowerShell: aplica una migracion SQL a Supabase usando aplicar-migracion.mjs
# Uso:
#   .\aplicar.ps1 ..\production_run\75_combustible_recirculacion.sql
#   .\aplicar.ps1 ..\production_run\75_combustible_recirculacion.sql -DryRun
#   .\aplicar.ps1 ..\production_run\75_combustible_recirculacion.sql -NoTx
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$SqlPath,
    [switch]$DryRun,
    [switch]$NoTx
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

if (-not (Test-Path "node_modules\pg")) {
    Write-Host "Instalando dependencias (pg + dotenv)..." -ForegroundColor Yellow
    npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        Write-Error "npm install fallo"
        exit 1
    }
}

$extra = @()
if ($DryRun) { $extra += "--dry-run" }
if ($NoTx)   { $extra += "--no-tx" }

node aplicar-migracion.mjs $SqlPath @extra
exit $LASTEXITCODE
