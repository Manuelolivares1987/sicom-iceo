# ============================================================================
# softland-sync.ps1 - Copia diaria Softland -> SICOM (MIG594)
# ----------------------------------------------------------------------------
# Lee las salidas de bodega (iw_gsaen + iw_gmovi, Tipo S, Estado V, conceptos
# 07 consumo y 08 EPP), las ordenes de compra (owordencom + owordendet, MIG628)
# y los centros de costo (cwtccos) de
# SERVERPILLADO\SQLEXPRESS por la LAN, y los sube a Supabase con las RPC de
# MIG594 (anon key + secreto 'softland_sync'; nunca el service_role).
#
# Corre una vez al dia y solo si este PC ve al servidor: la tarea programada lo
# lanza cada hora y el script sale sin hacer nada si ya corrio bien hoy o si
# no esta en la red de la oficina. Si un dia no corre, el siguiente relee la
# ventana completa (60 dias; 400 los domingos), asi que no se pierde nada.
# Las OC se releen siempre 400 dias: su estado (PE/AP/UN) y lo recibido
# cambian semanas despues de emitidas.
#
# Secretos: config cifrada con DPAPI (solo este usuario de Windows en este PC)
# en %LOCALAPPDATA%\SICOM\softland-sync. Nunca se imprimen.
#
# Uso:
#   powershell -File softland-sync.ps1 -Configurar -Excel "<ruta .xlsx con la conexion>"
#   powershell -File softland-sync.ps1 -InstalarTarea
#   powershell -File softland-sync.ps1                 # corrida normal (1 vez al dia)
#   powershell -File softland-sync.ps1 -Forzar         # corre aunque ya haya corrido hoy
#   powershell -File softland-sync.ps1 -Desde 2014-01-01   # carga historica
#   powershell -File softland-sync.ps1 -Forzar -DesdeOC 2014-01-01   # historico de OC
# ============================================================================
param(
    [switch]$Configurar,
    [string]$Excel = '',
    [switch]$InstalarTarea,
    [switch]$Forzar,
    [string]$Desde = '',
    [string]$DesdeOC = ''
)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir   = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
$dataDir   = Join-Path $env:LOCALAPPDATA 'SICOM\softland-sync'
$cfgFile   = Join-Path $dataDir 'config.dpapi'
$estadoFile= Join-Path $dataDir 'estado.json'
$logFile   = Join-Path $dataDir 'softland-sync.log'
$SERVIDOR  = 'SERVERPILLADO'
$LOTE      = 250   # documentos por llamada
New-Item -ItemType Directory -Force $dataDir | Out-Null

function Log($m) {
    $l = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $m
    Add-Content -Path $logFile -Value $l -Encoding UTF8
    Write-Output $l
}
function Restrict-Acl($path) {
    $a = Get-Acl $path; $a.SetAccessRuleProtection($true, $false)
    $a.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME, 'FullControl', 'Allow')))
    Set-Acl $path $a
}
function Guardar-Config($obj) {
    $json = $obj | ConvertTo-Json -Compress
    ConvertFrom-SecureString (ConvertTo-SecureString $json -AsPlainText -Force) | Set-Content $cfgFile
    Restrict-Acl $cfgFile
}
function Leer-Config {
    if (-not (Test-Path $cfgFile)) { throw "Falta configurar. Ejecuta: softland-sync.ps1 -Configurar -Excel <ruta>" }
    $sec = Get-Content $cfgFile | ConvertTo-SecureString
    $json = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    return $json | ConvertFrom-Json
}

# ----------------------------------------------------------------------------
# Configuracion (una vez)
# ----------------------------------------------------------------------------
if ($Configurar) {
    if (-not $Excel -or -not (Test-Path $Excel)) { throw "Indica -Excel con la planilla que trae la conexion a Softland." }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Excel).Path)
    try {
        $ent = $zip.Entries | Where-Object FullName -eq 'xl/connections.xml'
        if (-not $ent) { throw "La planilla no trae conexiones." }
        $sr = New-Object System.IO.StreamReader($ent.Open()); $xml = [xml]$sr.ReadToEnd(); $sr.Close()
    } finally { $zip.Dispose() }
    $odbc = ($xml.connections.connection | Where-Object { $_.dbPr.connection -match 'SERVER=' } | Select-Object -First 1).dbPr.connection
    if (-not $odbc) { throw "No encontre la cadena ODBC en la planilla." }
    $odbc = ($odbc -replace 'APP=[^;]*;?', '' -replace 'WSID=[^;]*;?', '') + ';APP=SICOM softland-sync'

    $envVars = @{}
    Get-Content (Join-Path $repoDir 'frontend\.env.local') | ForEach-Object {
        if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+)\s*$') { $envVars[$Matches[1]] = $Matches[2].Trim().Trim('"') } }
    $rb = New-Object 'System.Byte[]' 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rb)
    $secreto = -join ($rb | ForEach-Object { $_.ToString('x2') })

    # El hash del secreto se registra en Supabase con la conexion de administracion.
    $tmp = Join-Path $dataDir ("reg-{0}.sql" -f [guid]::NewGuid())
    "SELECT fn_sistema_set_secreto('softland_sync', '$secreto', 'Sincronizador Softland en PC de oficina ($env:COMPUTERNAME). MIG594.');" |
        ForEach-Object { [System.IO.File]::WriteAllText($tmp, $_, (New-Object System.Text.UTF8Encoding($false))) }
    try {
        # node escribe su progreso en stderr; con 'Stop' PowerShell lo toma como error.
        Push-Location $scriptDir
        $ErrorActionPreference = 'Continue'
        $out = & node aplicar-migracion.mjs $tmp 2>&1 | Out-String
        $ErrorActionPreference = 'Stop'
        Pop-Location
        if ($out -notmatch 'APLICADO OK') {
            $err = ($out -split "`n" | Where-Object { $_ -match 'error|fall' }) -join ' ' -replace $secreto, '***'
            throw "No se pudo registrar el secreto en Supabase. $err" }
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

    Guardar-Config @{
        odbc = $odbc
        url  = $envVars['NEXT_PUBLIC_SUPABASE_URL']
        anon = $envVars['NEXT_PUBLIC_SUPABASE_ANON_KEY']
        secreto = $secreto
    }
    Log "Configuracion guardada (cifrada) y secreto registrado en Supabase."
    exit 0
}

# ----------------------------------------------------------------------------
# Tarea programada: cada hora de 8 a 20; el script decide si toca correr.
# ----------------------------------------------------------------------------
if ($InstalarTarea) {
    $ps  = (Get-Command powershell.exe).Source
    $act = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`""
    $trg = New-ScheduledTaskTrigger -Daily -At '08:00'
    $trg.Repetition = (New-ScheduledTaskTrigger -Once -At '08:00' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Hours 12)).Repetition
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'SICOM - Softland sync' -Action $act -Trigger $trg -Settings $set `
        -Description 'Copia diaria de salidas de bodega Softland a SICOM (MIG594).' -Force | Out-Null
    Log "Tarea programada 'SICOM - Softland sync' instalada (cada hora 08-20, corre 1 vez al dia)."
    exit 0
}

# ----------------------------------------------------------------------------
# Corrida
# ----------------------------------------------------------------------------
$hoy = (Get-Date).ToString('yyyy-MM-dd')
$estado = if (Test-Path $estadoFile) { Get-Content $estadoFile -Raw | ConvertFrom-Json } else { $null }
if (-not $Forzar -and -not $Desde -and -not $DesdeOC -and $estado -and $estado.ultima_ok -eq $hoy) { exit 0 }

if (-not (Test-Connection $SERVIDOR -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
    Log "Sin acceso a $SERVIDOR (fuera de la red de la oficina). Se reintenta en la proxima hora."
    exit 0
}

$cfg = Leer-Config
$inicio = (Get-Date).ToUniversalTime()
$run = [guid]::NewGuid().ToString()
$desdeFecha = if ($Desde) { [datetime]::ParseExact($Desde, 'yyyy-MM-dd', $null) }
              elseif ((Get-Date).DayOfWeek -eq 'Sunday') { (Get-Date).Date.AddDays(-400) }
              else { (Get-Date).Date.AddDays(-60) }
$ventanaOC = if ($DesdeOC) { [datetime]::ParseExact($DesdeOC, 'yyyy-MM-dd', $null) }
           elseif ($Desde) { $desdeFecha }
           else { (Get-Date).Date.AddDays(-400) }
Log "Inicio corrida $run desde $($desdeFecha.ToString('yyyy-MM-dd')) (OC desde $($ventanaOC.ToString('yyyy-MM-dd')))"

function Rpc($nombre, $cuerpo) {
    $json = $cuerpo | ConvertTo-Json -Depth 8 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $h = @{ apikey = $cfg.anon; Authorization = "Bearer $($cfg.anon)" }
    for ($i = 1; $i -le 3; $i++) {
        try {
            return Invoke-RestMethod -Method Post -Uri "$($cfg.url)/rest/v1/rpc/$nombre" -Headers $h `
                -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 120
        } catch {
            if ($i -eq 3) { throw "RPC $nombre fallo: $($_.Exception.Message)" }
            Start-Sleep -Seconds (10 * $i)
        }
    }
}
function Txt($v) { if ($v -is [System.DBNull] -or $null -eq $v) { return $null } return ([string]$v).Trim() }
function Num($v) { if ($v -is [System.DBNull] -or $null -eq $v) { return 0 } return [double]$v }
$md5 = [System.Security.Cryptography.MD5]::Create()
function Hash($s) { -join ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) }

$cn = New-Object System.Data.Odbc.OdbcConnection $cfg.odbc
$cn.ConnectionTimeout = 15
try {
    $cn.Open()

    # 1) Centros de costo
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = "SELECT CodiCC, DescCC FROM pillado.softland.cwtccos"
    $r = $cmd.ExecuteReader(); $ccs = @()
    while ($r.Read()) { $ccs += @{ codigo = (Txt $r['CodiCC']); descripcion = (Txt $r['DescCC']) } }
    $r.Close()
    $nCc = Rpc 'rpc_softland_cargar_cc' @{ p_secreto = $cfg.secreto; p_cc = $ccs }
    Log "Centros de costo: $($ccs.Count) leidos, $nCc cargados"

    # 2) Salidas de bodega en la ventana. Orden estable para que el hash no cambie.
    $cmd = $cn.CreateCommand()
    $cmd.CommandTimeout = 300
    $cmd.CommandText = @"
SELECT g.Tipo, g.CodBode, g.NroInt, g.Folio, g.Concepto, g.Fecha, g.Glosa, g.Orden, g.CodiCC, g.CodAux,
       b.DesBode, m.CodProd, p.DesProd, m.CantDespachada, m.PreUniMB, m.TotLinea
  FROM pillado.softland.iw_gsaen g
  JOIN pillado.softland.iw_gmovi m ON m.Tipo = g.Tipo AND m.NroInt = g.NroInt AND m.CodBode = g.CodBode
  LEFT JOIN pillado.softland.iw_tbode b ON b.CodBode = g.CodBode
  LEFT JOIN pillado.softland.iw_tprod p ON p.CodProd = m.CodProd
 WHERE g.Tipo = 'S' AND g.Estado = 'V' AND g.Concepto IN ('07', '08') AND g.Fecha >= ?
 ORDER BY g.Tipo, g.CodBode, g.NroInt, m.CodProd, m.CantDespachada, m.TotLinea
"@
    [void]$cmd.Parameters.Add((New-Object System.Data.Odbc.OdbcParameter('@d', [System.Data.Odbc.OdbcType]::DateTime)))
    $cmd.Parameters[0].Value = $desdeFecha
    $r = $cmd.ExecuteReader()

    $docs = New-Object System.Collections.ArrayList
    $cur = $null; $curKey = ''; $sb = $null
    $tot = @{ docs = 0; cambiados = 0; lineas = 0 }
    function Cerrar-Doc {
        if ($script:cur) {
            $script:cur.hash = Hash $script:sb.ToString()
            [void]$script:docs.Add($script:cur)
        }
    }
    function Enviar {
        if ($script:docs.Count -eq 0) { return }
        $res = Rpc 'rpc_softland_cargar_docs' @{ p_secreto = $cfg.secreto; p_run = $run; p_docs = @($script:docs) }
        $script:tot.docs += $res.docs; $script:tot.cambiados += $res.cambiados; $script:tot.lineas += $res.lineas
        $script:docs.Clear()
    }
    while ($r.Read()) {
        $key = "$(Txt $r['Tipo'])|$(Txt $r['CodBode'])|$($r['NroInt'])"
        if ($key -ne $curKey) {
            Cerrar-Doc
            if ($docs.Count -ge $LOTE) { Enviar }
            $curKey = $key
            $fecha = ([datetime]$r['Fecha']).ToString('yyyy-MM-dd')
            $cur = [ordered]@{
                tipo = (Txt $r['Tipo']); cod_bode = (Txt $r['CodBode']); nro_int = [int]$r['NroInt']
                folio = $(if ($r['Folio'] -is [System.DBNull]) { $null } else { [int]$r['Folio'] })
                concepto = (Txt $r['Concepto']); fecha = $fecha; glosa = (Txt $r['Glosa'])
                orden = $(if ($r['Orden'] -is [System.DBNull]) { $null } else { [int]$r['Orden'] })
                codi_cc = (Txt $r['CodiCC']); cod_aux = (Txt $r['CodAux']); bodega = (Txt $r['DesBode'])
                hash = ''; lineas = (New-Object System.Collections.ArrayList)
            }
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("$key|$($cur.folio)|$($cur.concepto)|$fecha|$($cur.glosa)|$($cur.orden)|$($cur.codi_cc)|$($cur.cod_aux)")
        }
        $lin = [ordered]@{
            cod_prod = (Txt $r['CodProd']); des_prod = (Txt $r['DesProd'])
            cantidad = (Num $r['CantDespachada']); precio_unit = (Num $r['PreUniMB']); total = (Num $r['TotLinea'])
        }
        [void]$cur.lineas.Add($lin)
        [void]$sb.Append("#$($lin.cod_prod)|$($lin.cantidad)|$($lin.precio_unit)|$($lin.total)")
    }
    $r.Close()
    Cerrar-Doc
    Enviar

    # 3) Ordenes de compra (todas; el panel usa solo las AP). Orden estable para el hash.
    $cmd = $cn.CreateCommand()
    $cmd.CommandTimeout = 300
    $cmd.CommandText = @"
SELECT c.NumInterOC, c.NumOC, c.FechaOC, c.CodEstado, c.CodAux, a.NomAux, c.CodiCC AS CcOC, c.CodArn, c.Usuario,
       c.NomAprobador, c.SubTotalOC, c.ValorTotOC,
       d.NumLinea, d.CodProd, d.DetProd, d.CodiCC AS CcLinea, d.FechaEnt, d.Cantidad, d.Recibido, d.Saldo,
       d.PrecioUnit, d.ValorTotal
  FROM pillado.softland.owordencom c
  LEFT JOIN pillado.softland.owordendet d ON d.NumInterOC = c.NumInterOC
  LEFT JOIN pillado.softland.cwtauxi a ON a.CodAux = c.CodAux
 WHERE c.FechaOC >= ?
 ORDER BY c.NumInterOC, d.NumLinea
"@
    [void]$cmd.Parameters.Add((New-Object System.Data.Odbc.OdbcParameter('@d', [System.Data.Odbc.OdbcType]::DateTime)))
    $cmd.Parameters[0].Value = $ventanaOC
    $r = $cmd.ExecuteReader()
    $ocs = New-Object System.Collections.ArrayList
    $oc = $null; $ocKey = $null; $osb = $null
    $totOc = @{ ocs = 0; cambiadas = 0; lineas = 0 }
    function Cerrar-Oc {
        if ($script:oc) { $script:oc.hash = Hash $script:osb.ToString(); [void]$script:ocs.Add($script:oc) }
    }
    function Enviar-Oc {
        if ($script:ocs.Count -eq 0) { return }
        $res = Rpc 'rpc_softland_cargar_oc' @{ p_secreto = $cfg.secreto; p_run = $run; p_ocs = @($script:ocs) }
        $script:totOc.ocs += $res.ocs; $script:totOc.cambiadas += $res.cambiadas; $script:totOc.lineas += $res.lineas
        $script:ocs.Clear()
    }
    function Fecha($v) { if ($v -is [System.DBNull] -or $null -eq $v) { return $null } return ([datetime]$v).ToString('yyyy-MM-dd') }
    while ($r.Read()) {
        $key = [int]$r['NumInterOC']
        if ($key -ne $ocKey) {
            Cerrar-Oc
            if ($ocs.Count -ge $LOTE) { Enviar-Oc }
            $ocKey = $key
            $oc = [ordered]@{
                num_inter_oc = $key
                num_oc = $(if ($r['NumOC'] -is [System.DBNull]) { $null } else { [int]$r['NumOC'] })
                fecha_oc = (Fecha $r['FechaOC']); estado = (Txt $r['CodEstado'])
                cod_aux = (Txt $r['CodAux']); proveedor = (Txt $r['NomAux']); codi_cc = (Txt $r['CcOC'])
                cod_arn = (Txt $r['CodArn']); usuario = (Txt $r['Usuario']); aprobador = (Txt $r['NomAprobador'])
                neto = (Num $r['SubTotalOC']); total_oc = (Num $r['ValorTotOC'])
                hash = ''; lineas = (New-Object System.Collections.ArrayList)
            }
            $osb = New-Object System.Text.StringBuilder
            [void]$osb.Append("$key|$($oc.num_oc)|$($oc.fecha_oc)|$($oc.estado)|$($oc.cod_aux)|$($oc.proveedor)|$($oc.codi_cc)|$($oc.cod_arn)|$($oc.aprobador)|$($oc.neto)|$($oc.total_oc)")
        }
        if (-not ($r['NumLinea'] -is [System.DBNull])) {
            $lin = [ordered]@{
                num_linea = [int]$r['NumLinea']; cod_prod = (Txt $r['CodProd']); det_prod = (Txt $r['DetProd'])
                codi_cc = (Txt $r['CcLinea']); fecha_ent = (Fecha $r['FechaEnt'])
                cantidad = (Num $r['Cantidad']); recibido = (Num $r['Recibido']); saldo = (Num $r['Saldo'])
                precio_unit = (Num $r['PrecioUnit']); total = (Num $r['ValorTotal'])
            }
            [void]$oc.lineas.Add($lin)
            [void]$osb.Append("#$($lin.num_linea)|$($lin.cod_prod)|$($lin.det_prod)|$($lin.codi_cc)|$($lin.cantidad)|$($lin.recibido)|$($lin.saldo)|$($lin.precio_unit)|$($lin.total)")
        }
    }
    $r.Close()
    Cerrar-Oc
    Enviar-Oc
    $cierreOc = Rpc 'rpc_softland_cerrar_oc' @{ p_secreto = $cfg.secreto; p_run = $run; p_desde = $ventanaOC.ToString('yyyy-MM-dd') }
    Log "OC: $($totOc.ocs) ordenes ($($totOc.cambiadas) nuevas o cambiadas, $($totOc.lineas) lineas), $($cierreOc.borradas) borradas"

    # 4) Cierre: borra lo anulado en la ventana, refresca el resumen y deja bitacora.
    $stats = @{ docs = $tot.docs; cambiados = $tot.cambiados; lineas = $tot.lineas; equipo = $env:COMPUTERNAME; centros_costo = $ccs.Count
                ocs = $totOc.ocs; ocs_cambiadas = $totOc.cambiadas; oc_lineas = $totOc.lineas }
    $cierre = Rpc 'rpc_softland_cerrar_corrida' @{
        p_secreto = $cfg.secreto; p_run = $run; p_inicio = $inicio.ToString('o')
        p_desde = $desdeFecha.ToString('yyyy-MM-dd'); p_stats = $stats }
    Log "OK: $($tot.docs) documentos ($($tot.cambiados) nuevos o cambiados, $($tot.lineas) lineas), $($cierre.borrados) borrados"
    @{ ultima_ok = $hoy; run = $run; docs = $tot.docs } | ConvertTo-Json | Set-Content $estadoFile -Encoding UTF8
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($cn.State -eq 'Open') { $cn.Close() }
}
