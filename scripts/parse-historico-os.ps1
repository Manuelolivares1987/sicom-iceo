# Parsea Historico OS Auditoria.xlsx -> genera SQL para MIG58 con seed bulk insert.
# Output: ../database/production_run/_seed_os_historico.sql (intermedio, se concatena en MIG58)

$ErrorActionPreference = 'Stop'

$xlsxPath  = "C:\Users\Manuel Olivares\Desktop\2026\PILLADO\Mantenimiento\Historico OS Auditoria.xlsx"
$outSql    = "$PSScriptRoot\..\database\production_run\_seed_os_historico.sql"

# ============================================================================
# Mapeo de grafias de modelo -> canonica BD
# ============================================================================
$mapeoModelo = @{
  # Mercedes Actros
  'actros 3336k'               = 'Actros 3336 K'
  'actros 3336 k'              = 'Actros 3336 K'
  'mercedes actros 3336 k'     = 'Actros 3336 K'
  'mercedes benz actros 3336k' = 'Actros 3336 K'
  'actros 3341'                = 'Actros 3341'
  'mercedes actros 3341'       = 'Actros 3341'
  # Atego
  'atego'                      = 'Atego 1624A 4x4'
  'atego 1624'                 = 'Atego 1624A 4x4'
  'atego 1624a'                = 'Atego 1624A 4x4'
  'atego 1624a 4x4'            = 'Atego 1624A 4x4'
  'mercedes atego'             = 'Atego 1624A 4x4'
  # Axor
  'axor'                       = 'Axor 2633'
  'axor 2633'                  = 'Axor 2633'
  'axor 2633/45'               = 'Axor 2633/45'
  'axor 2645'                  = 'Axor 2633/45'
  'mercedes axor'              = 'Axor 2633'
  # Accelo
  'accelo'                     = 'Accelo 1016/44'
  'accelo 1016'                = 'Accelo 1016/44'
  'accelo 1016/44'             = 'Accelo 1016/44'
  'mercedes accelo'            = 'Accelo 1016/44'
  # Mack
  'mack'                       = 'GU 813 autom'
  'mack gu813'                 = 'GU 813 autom'
  'mack gu813e'                = 'GU813E Mec'
  'gu813'                      = 'GU 813 autom'
  'gu813 autom'                = 'GU 813 autom'
  'gu 813 autom'               = 'GU 813 autom'
  'gu813e'                     = 'GU813E Mec'
  'gu813e mec'                 = 'GU813E Mec'
  'gu813e allison'             = 'GU813E Allison'
  'mack gu813e allison'        = 'GU813E Allison'
  'mack granite'               = 'GU 813 autom'
  # Volvo
  'volvo vm 350'               = 'VM 350'
  'vm 350'                     = 'VM 350'
  'vm350'                      = 'VM 350'
  'volvo fmx 420'              = 'FMX 420'
  'fmx 420'                    = 'FMX 420'
  'fmx420'                     = 'FMX 420'
  'volvo fmx 540'              = 'FMX 540'
  'fmx 540'                    = 'FMX 540'
  'fmx540'                     = 'FMX 540'
  # Volvo VM (typos: VMX en Excel)
  'volvo vmx 350'              = 'VM 350'
  'vmx 350'                    = 'VM 350'
  'volvo vmx'                  = 'VM 350'
  'vmx'                        = 'VM 350'
  'volvo vmx-350'              = 'VM 350'
  'volvo mx'                   = 'VM 350'
  'volvo vm'                   = 'VM 350'
  # Mercedes (varias variantes de grafia)
  'm.benz actros 3341'         = 'Actros 3341'
  'm. benz actros 3341'        = 'Actros 3341'
  'm.b. actros 3341'           = 'Actros 3341'
  'm.b. actros 341'            = 'Actros 3341'
  'm. benz actros 3336'        = 'Actros 3336 K'
  'm.benz actros 3336'         = 'Actros 3336 K'
  'm. benz actros'             = 'Actros 3336 K'
  'm.benz actros'              = 'Actros 3336 K'
  'mercedes benz/ actros'      = 'Actros 3336 K'
  'mercedes benz/actros'       = 'Actros 3336 K'
  'mercedes / actros'          = 'Actros 3336 K'
  'mercedes/actros'            = 'Actros 3336 K'
  'mercedes benz / axor'       = 'Axor 2633'
  'mercedes benz / acelo'      = 'Accelo 1016/44'
  'mercedes benz atego 1624'   = 'Atego 1624A 4x4'
  'm.benz acceli 1016'         = 'Accelo 1016/44'
  'acceli 1016'                = 'Accelo 1016/44'
  'acelo'                      = 'Accelo 1016/44'
  # Nissan variantes
  'nissan np 300 4x4'          = 'NP300 Dob Cab'
  'nissan np-300'              = 'NP300 Dob Cab'
  'np-300'                     = 'NP300 Dob Cab'
  'np 300'                     = 'NP300 Dob Cab'
  # Scania
  'scania'                     = 'P450B'
  'scania p450'                = 'P450B'
  'p450b'                      = 'P450B'
  'p450'                       = 'P450B'
  'scania p450b'               = 'P450B'
  # Renault
  'renault c440'               = 'C440'
  'c440'                       = 'C440'
  # Nissan
  'nissan np300'               = 'NP300 Dob Cab'
  'np300'                      = 'NP300 Dob Cab'
  'np300 dob cab'              = 'NP300 Dob Cab'
  # Mitsubishi
  'canter'                     = 'Canter 7.5'
  'canter 7.5'                 = 'Canter 7.5'
  'mitsubishi canter'          = 'Canter 7.5'
  # Toyota
  'hilux'                      = 'New Hilux 4x4 2.4 MT DX'
  'toyota hilux'               = 'New Hilux 4x4 2.4 MT DX'
  'hilux 2.8'                  = 'Hilux 2.8 Autom'
  'hilux 2.8 autom'            = 'Hilux 2.8 Autom'
  'new hilux'                  = 'New Hilux 4x4 2.4 MT DX'
  'toyota 02-7fda50'           = '02-7FDA50'
  '02-7fda50'                  = '02-7FDA50'
  # Yale
  'yale gdp30tk'               = 'GDP 30TK'
  'yale gdp 30tk'              = 'GDP 30TK'
  'gdp 30tk'                   = 'GDP 30TK'
  'gdp30tk'                    = 'GDP 30TK'
  # Maxus
  'maxus t60'                  = 'T60 4x4 DX'
  't60 4x4 dx'                 = 'T60 4x4 DX'
  't60 4x4 dx plus 6 mt'       = 'T60 4x4 DX Plus 6 MT'
  't60 plus'                   = 'T60 4x4 DX Plus 6 MT'
  # Citroen
  'berlingo'                   = 'Berlingo K9 1.6 Diesel'
  'citroen berlingo'           = 'Berlingo K9 1.6 Diesel'
  'berlingo k9'                = 'Berlingo K9 1.6 Diesel'
  # RAM
  'ram 1500'                   = '1500 LIMITED 5,7L'
  'ram'                        = '1500 LIMITED 5,7L'
  '1500 limited'               = '1500 LIMITED 5,7L'
  # Chevrolet
  'montana'                    = 'Montana 1.2 MT'
  'chevrolet montana'          = 'Montana 1.2 MT'
}

function NormalizeModelo([string]$raw) {
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  $key = $raw.ToLower().Trim() -replace '\s+',' '
  if ($mapeoModelo.ContainsKey($key) -and $null -ne $mapeoModelo[$key]) {
    return $mapeoModelo[$key]
  }
  # Intentos parciales, ordenados por longitud DESC (mas especificos primero)
  $sortedKeys = $mapeoModelo.Keys | Sort-Object -Property Length -Descending
  foreach ($k in $sortedKeys) {
    $val = $mapeoModelo[$k]
    if ($null -eq $val) { continue }  # skip alias NULL (ambiguous)
    if ($key.Contains($k) -or $k.Contains($key)) { return $val }
  }
  return $null
}

function NormalizePatente([string]$raw) {
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  $s = ($raw -replace '\s','').ToUpper()
  # XXXX-NN o XXXXNN
  if ($s -match '^([A-Z]{4})[-]?(\d{2})$') {
    return "$($Matches[1])-$($Matches[2])"
  }
  return $s
}

function SqlStr([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return 'NULL' }
  return "'" + ($s -replace "'","''") + "'"
}

function SqlNum($v) {
  if ($null -eq $v -or "$v".Trim() -eq '') { return 'NULL' }
  $clean = "$v" -replace '\.', '' -replace ',','.' -replace '[^\d\.\-]',''
  if ($clean -eq '' -or $clean -eq '-') { return 'NULL' }
  $n = 0.0
  if ([double]::TryParse($clean, [ref]$n)) { return $clean }
  return 'NULL'
}

function SqlDate([string]$raw) {
  if ([string]::IsNullOrWhiteSpace($raw)) { return 'NULL' }
  $dt = [DateTime]::MinValue
  if ([DateTime]::TryParse($raw, [ref]$dt)) {
    return "'" + $dt.ToString("yyyy-MM-dd") + "'"
  }
  return 'NULL'
}

function SqlBool([string]$raw) {
  if ([string]::IsNullOrWhiteSpace($raw)) { return 'false' }
  $v = $raw.Trim().ToLower()
  if ($v -in @('1','x','si','sí','yes','true','t','y','✓','✔')) { return 'true' }
  return 'false'
}

# ============================================================================
# Leer Excel
# ============================================================================
Write-Host "Abriendo Excel..." -ForegroundColor Cyan
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false
$wb = $xl.Workbooks.Open($xlsxPath, $false, $true)
$ws = $wb.Worksheets.Item("Detalle OS")

$totalRows = $ws.UsedRange.Rows.Count
Write-Host "Total filas en hoja: $totalRows" -ForegroundColor Cyan

# Data empieza en fila 3 (fila 1 = titulo, fila 2 = headers)
$osRows = @()
$modelosSinMatch = @{}
$patentesSinFormato = @{}

for ($r = 3; $r -le $totalRows; $r++) {
  $anio        = $ws.Cells.Item($r, 1).Text
  $osNum       = $ws.Cells.Item($r, 2).Text
  $osCqbo      = $ws.Cells.Item($r, 3).Text
  $patenteRaw  = $ws.Cells.Item($r, 4).Text
  $tipoRaw     = $ws.Cells.Item($r, 5).Text
  $modeloRaw   = $ws.Cells.Item($r, 6).Text
  $faena       = $ws.Cells.Item($r, 7).Text
  $cliente     = $ws.Cells.Item($r, 8).Text
  $ubicacion   = $ws.Cells.Item($r, 9).Text
  $fechaRec    = $ws.Cells.Item($r,10).Text
  $fechaEnt    = $ws.Cells.Item($r,11).Text
  $horometro   = $ws.Cells.Item($r,12).Text
  $kilometraje = $ws.Cells.Item($r,13).Text
  $cumpl       = $ws.Cells.Item($r,14).Text
  $resp        = $ws.Cells.Item($r,15).Text
  $esPrev      = $ws.Cells.Item($r,16).Text
  $esCorr      = $ws.Cells.Item($r,17).Text
  $esNeum      = $ws.Cells.Item($r,18).Text
  $esRT        = $ws.Cells.Item($r,19).Text
  $esHE        = $ws.Cells.Item($r,20).Text
  $esSE        = $ws.Cells.Item($r,21).Text
  $cantTrab    = $ws.Cells.Item($r,22).Text
  $horasMO     = $ws.Cells.Item($r,23).Text
  $ultManFecha = $ws.Cells.Item($r,24).Text
  $ultManHoras = $ws.Cells.Item($r,25).Text
  $frecuencia  = $ws.Cells.Item($r,26).Text

  # Skip filas vacias o de subtitulos
  if ([string]::IsNullOrWhiteSpace($osNum) -and [string]::IsNullOrWhiteSpace($osCqbo)) { continue }
  if ([string]::IsNullOrWhiteSpace($patenteRaw)) { continue }

  $patente = NormalizePatente $patenteRaw
  $modeloCanonico = NormalizeModelo $modeloRaw

  if (-not [string]::IsNullOrWhiteSpace($modeloRaw) -and -not $modeloCanonico) {
    if (-not $modelosSinMatch.ContainsKey($modeloRaw)) {
      $modelosSinMatch[$modeloRaw] = 0
    }
    $modelosSinMatch[$modeloRaw]++
  }

  # Determinar tipo_servicio dominante
  $tipoServicio = 'otro'
  if ((SqlBool $esPrev) -eq 'true') { $tipoServicio = 'preventivo' }
  elseif ((SqlBool $esCorr) -eq 'true') { $tipoServicio = 'correctivo' }
  elseif ((SqlBool $esNeum) -eq 'true') { $tipoServicio = 'neumaticos' }
  elseif ((SqlBool $esRT) -eq 'true')   { $tipoServicio = 'revision_tecnica' }
  elseif ((SqlBool $esHE) -eq 'true')   { $tipoServicio = 'habilitacion_estanque' }
  elseif ((SqlBool $esSE) -eq 'true')   { $tipoServicio = 'servicio_externo' }

  $osRows += [PSCustomObject]@{
    osNum = $osNum; osCqbo = $osCqbo; anio = $anio; patente = $patente
    modeloCanonico = $modeloCanonico; modeloOriginal = $modeloRaw
    tipoServicio = $tipoServicio
    faena = $faena; cliente = $cliente; ubicacion = $ubicacion
    fechaRec = $fechaRec; fechaEnt = $fechaEnt
    horometro = $horometro; kilometraje = $kilometraje
    cumpl = $cumpl; resp = $resp
    esPrev = $esPrev; esCorr = $esCorr; esNeum = $esNeum
    esRT = $esRT; esHE = $esHE; esSE = $esSE
    cantTrab = $cantTrab; horasMO = $horasMO
    ultManFecha = $ultManFecha; ultManHoras = $ultManHoras
    frecuencia = $frecuencia
  }
}

Write-Host "OS leidas: $($osRows.Count)" -ForegroundColor Green
Write-Host "Modelos sin match: $($modelosSinMatch.Count)" -ForegroundColor Yellow
$modelosSinMatch.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { "   $($_.Key) ($($_.Value) OS)" }

$wb.Close($false)
$xl.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($xl) | Out-Null

# ============================================================================
# Generar SQL
# ============================================================================
Write-Host "Escribiendo SQL en $outSql..." -ForegroundColor Cyan

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("-- ===========================================================================")
[void]$sb.AppendLine("-- _seed_os_historico.sql (generado automaticamente por parse-historico-os.ps1)")
[void]$sb.AppendLine("-- Fuente: Historico OS Auditoria.xlsx - hoja Detalle OS")
[void]$sb.AppendLine("-- Total OS: $($osRows.Count)")
[void]$sb.AppendLine("-- Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$sb.AppendLine("-- ===========================================================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("-- Tabla temporal para staging y normalizacion antes de mover a os_historico_importado")
[void]$sb.AppendLine("CREATE TEMP TABLE tmp_os_seed (")
[void]$sb.AppendLine("  os_numero VARCHAR, os_cqbo VARCHAR, anio INT, patente VARCHAR,")
[void]$sb.AppendLine("  modelo_canonico VARCHAR, modelo_original VARCHAR,")
[void]$sb.AppendLine("  tipo_servicio VARCHAR,")
[void]$sb.AppendLine("  faena VARCHAR, cliente VARCHAR, ubicacion VARCHAR,")
[void]$sb.AppendLine("  fecha_recepcion DATE, fecha_entrega DATE,")
[void]$sb.AppendLine("  horometro NUMERIC, kilometraje NUMERIC, pct_cumpl NUMERIC, responsable VARCHAR,")
[void]$sb.AppendLine("  es_prev BOOLEAN, es_corr BOOLEAN, es_neum BOOLEAN,")
[void]$sb.AppendLine("  es_rt BOOLEAN, es_he BOOLEAN, es_se BOOLEAN,")
[void]$sb.AppendLine("  cant_trabajos INT, horas_mo NUMERIC,")
[void]$sb.AppendLine("  ult_man_fecha DATE, ult_man_horas NUMERIC, frecuencia VARCHAR")
[void]$sb.AppendLine(");")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("INSERT INTO tmp_os_seed VALUES")

$values = @()
foreach ($o in $osRows) {
  $row = "  (" +
    (SqlStr $o.osNum) + ", " +
    (SqlStr $o.osCqbo) + ", " +
    (SqlNum $o.anio) + ", " +
    (SqlStr $o.patente) + ", " +
    (SqlStr $o.modeloCanonico) + ", " +
    (SqlStr $o.modeloOriginal) + ", " +
    (SqlStr $o.tipoServicio) + ", " +
    (SqlStr $o.faena) + ", " +
    (SqlStr $o.cliente) + ", " +
    (SqlStr $o.ubicacion) + ", " +
    (SqlDate $o.fechaRec) + ", " +
    (SqlDate $o.fechaEnt) + ", " +
    (SqlNum $o.horometro) + ", " +
    (SqlNum $o.kilometraje) + ", " +
    (SqlNum $o.cumpl) + ", " +
    (SqlStr $o.resp) + ", " +
    (SqlBool $o.esPrev) + ", " +
    (SqlBool $o.esCorr) + ", " +
    (SqlBool $o.esNeum) + ", " +
    (SqlBool $o.esRT) + ", " +
    (SqlBool $o.esHE) + ", " +
    (SqlBool $o.esSE) + ", " +
    (SqlNum $o.cantTrab) + ", " +
    (SqlNum $o.horasMO) + ", " +
    (SqlDate $o.ultManFecha) + ", " +
    (SqlNum $o.ultManHoras) + ", " +
    (SqlStr $o.frecuencia) + ")"
  $values += $row
}
[void]$sb.AppendLine(($values -join ",`n") + ";")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("-- Resumen para verificacion")
[void]$sb.AppendLine("SELECT COUNT(*) AS total_seed, MIN(anio) AS desde, MAX(anio) AS hasta FROM tmp_os_seed;")

[System.IO.File]::WriteAllText($outSql, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "OK: $outSql" -ForegroundColor Green
Write-Host "Tamano: $([math]::Round((Get-Item $outSql).Length / 1024, 1)) KB" -ForegroundColor Green
