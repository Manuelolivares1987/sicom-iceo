# Limpia template_maestro_bodega.xlsx aplicando defaults:
# - unidad_medida vacía -> 'un'
# - bodega_nombre vacía cuando hay stock_inicial > 0 -> bodega por defecto
# - elimina filas con codigo vacio
# - deduplica codigos (conserva primera ocurrencia)
# Genera archivo nuevo _LIMPIO.xlsx sin tocar el original.

$ErrorActionPreference = 'Stop'

$pathIn         = "C:\Users\Manuel Olivares\Desktop\Copia de template_maestro_bodega.xlsx"
$pathOut        = "C:\Users\Manuel Olivares\Desktop\template_maestro_bodega_LIMPIO.xlsx"
$bodegaDefault  = "Bodega Central Repuestos $([char]0x2014) Taller Coquimbo"
$unidadDefault  = "un"

Write-Host "Abriendo Excel original..." -ForegroundColor Cyan
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false

$wbIn  = $xl.Workbooks.Open($pathIn, $false, $true)   # ReadOnly
$wsIn  = $wbIn.Worksheets.Item("Productos")
$totalRows = $wsIn.UsedRange.Rows.Count
$totalCols = 14

Write-Host "Total filas input: $totalRows. Leyendo a memoria..." -ForegroundColor Cyan

# Leer todo a un array bidimensional en una sola operacion (mucho mas rapido)
$range = $wsIn.Range($wsIn.Cells.Item(1, 1), $wsIn.Cells.Item($totalRows, $totalCols))
$rawData = $range.Value2

Write-Host "Creando workbook de salida..." -ForegroundColor Cyan
$wbOut = $xl.Workbooks.Add()
$wsOut = $wbOut.Worksheets.Item(1)
$wsOut.Name = "Productos"

# Construir array de salida fila por fila aplicando reglas
$outRows = New-Object 'System.Collections.Generic.List[object[]]'
$seenCodigos = @{}
$skippedVacios = 0
$skippedDuplicados = 0
$fixedUnidad = 0
$fixedBodega = 0

# Headers (fila 1 del input)
$header = @(); for ($c = 1; $c -le $totalCols; $c++) { $header += $rawData[1, $c] }
$outRows.Add($header)

for ($r = 2; $r -le $totalRows; $r++) {
    $cod = "$($rawData[$r, 1])".Trim()
    if (-not $cod) { $skippedVacios++; continue }
    if ($seenCodigos.ContainsKey($cod)) { $skippedDuplicados++; continue }
    $seenCodigos[$cod] = $true

    # Copiar valores
    $fila = @()
    for ($c = 1; $c -le $totalCols; $c++) { $fila += $rawData[$r, $c] }

    # Default unidad_medida (col 4)
    if (-not "$($fila[3])".Trim()) {
        $fila[3] = $unidadDefault
        $fixedUnidad++
    }

    # Default bodega_nombre (col 10) cuando hay stock_inicial > 0 (col 11)
    $stockRaw = "$($fila[10])".Trim()
    $stockNum = 0.0
    if ($stockRaw) { [double]::TryParse(($stockRaw -replace ",", "."), [ref]$stockNum) | Out-Null }
    if ($stockNum -gt 0 -and -not "$($fila[9])".Trim()) {
        $fila[9] = $bodegaDefault
        $fixedBodega++
    }

    $outRows.Add($fila)
}

Write-Host "Estadisticas:" -ForegroundColor Green
Write-Host "  Filas validas: $($outRows.Count - 1)"
Write-Host "  Skipped codigo vacio: $skippedVacios"
Write-Host "  Skipped duplicados: $skippedDuplicados"
Write-Host "  Fixed unidad_medida: $fixedUnidad"
Write-Host "  Fixed bodega_nombre: $fixedBodega"

# Escribir todo de una vez (mucho mas rapido que celda por celda)
Write-Host "Escribiendo salida..." -ForegroundColor Cyan
$nRows = $outRows.Count
$arr = New-Object 'object[,]' $nRows, $totalCols
for ($i = 0; $i -lt $nRows; $i++) {
    for ($j = 0; $j -lt $totalCols; $j++) {
        $arr[$i, $j] = $outRows[$i][$j]
    }
}
$wsOut.Range($wsOut.Cells.Item(1, 1), $wsOut.Cells.Item($nRows, $totalCols)).Value2 = $arr

# Formato basico al header
$headerRange = $wsOut.Range($wsOut.Cells.Item(1, 1), $wsOut.Cells.Item(1, $totalCols))
$headerRange.Font.Bold = $true
$headerRange.Interior.Color = 12698049  # gris claro

# Auto-ajustar columnas
$wsOut.Columns.AutoFit() | Out-Null

# Guardar como xlsx (formato 51)
if (Test-Path $pathOut) { Remove-Item $pathOut -Force }
$wbOut.SaveAs($pathOut, 51)
Write-Host "OK guardado: $pathOut" -ForegroundColor Green

$wbOut.Close($false)
$wbIn.Close($false)
$xl.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($xl) | Out-Null

$size = [math]::Round((Get-Item $pathOut).Length / 1024, 1)
Write-Host "Tamano: $size KB" -ForegroundColor Green
