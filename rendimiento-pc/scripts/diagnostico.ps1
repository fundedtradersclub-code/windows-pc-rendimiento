<#
.SYNOPSIS
  Diagnóstico de rendimiento de Windows. SOLO LEE: no cambia nada en el equipo.

.DESCRIPTION
  Revisa hardware, discos, memoria, procesos, programas al inicio, servicios de terceros,
  programas pesados instalados, archivos temporales, antivirus, plan de energía y errores
  de disco. Escribe un informe en Markdown (para leer) y, si se pide, un JSON (para comparar
  antes y después).

.PARAMETER Json
  Ruta de un archivo .json donde guardar los datos crudos.

.PARAMETER Rapido
  No mide el tamaño de las carpetas del usuario (puede tardar minutos con muchos archivos).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File diagnostico.ps1 -Json "$env:TEMP\antes.json"
#>
[CmdletBinding()]
param(
    [string]$Json,
    [switch]$Rapido
)

. (Join-Path $PSScriptRoot 'comun.ps1')
$ErrorActionPreference = 'Continue'

$catalogo = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'programas-pesados.json') | ConvertFrom-Json
$senales = New-Object System.Collections.Generic.List[object]
function Senal([string]$Gravedad, [string]$Tema, [string]$Texto) {
    $senales.Add([pscustomobject]@{ Gravedad = $Gravedad; Tema = $Tema; Texto = $Texto })
}

# ---------------------------------------------------------------- Equipo
$so = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cs = Get-CimInstance Win32_ComputerSystem
$ramTotal = [double]$cs.TotalPhysicalMemory
$ramLibre = [double]$so.FreePhysicalMemory * 1KB
$ramUsoPct = [math]::Round(100 * (1 - $ramLibre / $ramTotal))
$encendido = (Get-Date) - $so.LastBootUpTime
$esPortatil = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

# Herramientas con las que se ejecuta el diagnóstico (Claude Code, Node, terminal): inflan la RAM medida.
$propios = @(Get-Process -Name claude, node, powershell, pwsh, WindowsTerminal, OpenConsole, conhost -ErrorAction SilentlyContinue)
$ramPropiaMB = [math]::Round((($propios | Measure-Object WorkingSet64 -Sum).Sum) / 1MB)
$ramUsoSinPropiosPct = [math]::Round(100 * (1 - ($ramLibre + $ramPropiaMB * 1MB) / $ramTotal))

# Ranuras de RAM: cuántas hay, cuántas están ocupadas y el máximo que admite la placa.
$ranuras = $null
try {
    $arreglo = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction Stop | Where-Object { $_.Use -eq 3 } | Select-Object -First 1
    $modulos = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)
    $ranuras = [ordered]@{
        Total     = $arreglo.MemoryDevices
        Ocupadas  = $modulos.Count
        MaximoGB  = if ($arreglo.MaxCapacityEx) { [math]::Round($arreglo.MaxCapacityEx / 1MB) } elseif ($arreglo.MaxCapacity) { [math]::Round($arreglo.MaxCapacity / 1MB) } else { $null }
        Modulos   = ($modulos | ForEach-Object { '{0} GB {1} MHz ({2})' -f [math]::Round($_.Capacity / 1GB), $_.Speed, $_.DeviceLocator }) -join '; '
    }
} catch { }

$equipo = [ordered]@{
    Sistema      = "$($so.Caption) (compilación $($so.BuildNumber))"
    Procesador   = "$($cpu.Name.Trim()) · $($cpu.NumberOfCores) núcleos / $($cpu.NumberOfLogicalProcessors) hilos"
    RamGB        = [math]::Round($ramTotal / 1GB, 1)
    RamUsoPct    = $ramUsoPct
    RamUsoSinAsistentePct = $ramUsoSinPropiosPct
    RamDelAsistenteMB = $ramPropiaMB
    RanurasRam   = if ($ranuras) { "$($ranuras.Ocupadas) de $($ranuras.Total) ocupadas · máx. $($ranuras.MaximoGB) GB · $($ranuras.Modulos)" } else { 'no informado' }
    DiasEncendido = [math]::Round($encendido.TotalDays, 1)
    Portatil     = $esPortatil
}
$textoRanuras = if ($ranuras -and $ranuras.Total) {
    if ($ranuras.Ocupadas -lt $ranuras.Total) { " Hay $($ranuras.Total - $ranuras.Ocupadas) ranura(s) libre(s): se puede agregar un módulo." }
    else { " Las $($ranuras.Total) ranuras están ocupadas: ampliar implica cambiar módulos por otros más grandes (o puede que parte esté soldada)." }
} else { ' Windows no informa las ranuras: revisar el manual o la ficha del modelo (algunas laptops tienen la RAM soldada).' }
$usoReal = $ramUsoSinPropiosPct
if ($equipo.RamGB -lt 7.5) {
    Senal 'alta' 'Memoria' "Solo $($equipo.RamGB) GB de RAM: con navegador y Office abiertos Windows usa el disco como memoria. Ampliar a 8 GB o más es la mejora más notoria.$textoRanuras"
} elseif ($equipo.RamGB -lt 9 -and $usoReal -ge 70) {
    Senal 'media' 'Memoria' "8 GB de RAM y en uso al $usoReal % (sin contar las herramientas del asistente): va justo con navegador, Office y videollamadas. Primero ajustar el navegador (ver references); si sigue trabándose, ampliar a 16 GB.$textoRanuras"
} elseif ($usoReal -ge 85) {
    Senal 'alta' 'Memoria' "La RAM está al $usoReal % (sin contar las herramientas del asistente). Revisa qué procesos la ocupan antes de pensar en ampliar."
}
if ($encendido.TotalDays -ge 7) { Senal 'baja' 'Sistema' "El equipo lleva $([math]::Round($encendido.TotalDays)) días sin reiniciar. Reiniciar (no solo apagar con inicio rápido) libera memoria y termina actualizaciones." }

# ---------------------------------------------------------------- Discos
$discos = @()
# Qué disco físico tiene Windows: un HDD de datos no frena el sistema; un HDD con Windows, sí.
$discoSistema = $null
try { $discoSistema = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop | Get-Disk -ErrorAction Stop).Number } catch { }
try {
    $discos = Get-PhysicalDisk | ForEach-Object {
        [pscustomobject]@{ Nombre = $_.FriendlyName; Tipo = "$($_.MediaType)"; Salud = "$($_.HealthStatus)"; TamanoGB = [math]::Round($_.Size / 1GB); Sistema = ("$($_.DeviceId)" -eq "$discoSistema") }
    }
} catch { }
foreach ($d in $discos) {
    if ($d.Tipo -eq 'HDD' -and $d.Sistema) { Senal 'alta' 'Disco' "Windows está instalado en un disco mecánico (HDD, '$($d.Nombre)'). Cambiarlo por un SSD es la mejora más grande posible: arranque y programas varias veces más rápidos." }
    elseif ($d.Tipo -eq 'HDD') { Senal 'baja' 'Disco' "El disco '$($d.Nombre)' es mecánico (HDD) pero no tiene Windows: está bien para guardar archivos; lo que se abra desde ahí será algo más lento." }
    if ($d.Salud -and $d.Salud -ne 'Healthy') { Senal 'alta' 'Disco' "Windows informa salud '$($d.Salud)' en el disco '$($d.Nombre)'. Haz copia de seguridad antes de cualquier otro cambio." }
}

$unidades = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{
        Unidad   = $_.DeviceID
        TotalGB  = [math]::Round($_.Size / 1GB, 1)
        LibreGB  = [math]::Round($_.FreeSpace / 1GB, 1)
        LibrePct = if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size) } else { 0 }
    }
}
$sistema = $unidades | Where-Object Unidad -eq $env:SystemDrive
if ($sistema -and ($sistema.LibrePct -lt 15 -or $sistema.LibreGB -lt 20)) {
    Senal 'alta' 'Espacio' "La unidad del sistema ($($sistema.Unidad)) tiene solo $($sistema.LibreGB) GB libres ($($sistema.LibrePct) %). Con menos de ~15 % libre Windows se vuelve lento y las actualizaciones fallan."
}
$otras = @($unidades | Where-Object { $_.Unidad -ne $env:SystemDrive -and $_.LibreGB -ge 30 })

# Errores de disco recientes (controlador de disco y NTFS) en el registro de eventos.
$erroresDisco = 0
try {
    $erroresDisco = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk', 'Ntfs', 'storahci', 'stornvme'; Level = 1, 2, 3; StartTime = (Get-Date).AddDays(-14) } -ErrorAction Stop).Count
} catch { }
if ($erroresDisco -ge 5) { Senal 'alta' 'Disco' "Hay $erroresDisco avisos o errores de disco en los últimos 14 días. Puede ser un disco fallando: copia de seguridad primero." }

# ---------------------------------------------------------------- Procesos
$procesos = Get-Process | Where-Object { $_.Id -ne 0 } | Group-Object ProcessName | ForEach-Object {
    [pscustomobject]@{
        Proceso = $_.Name
        Instancias = $_.Count
        RamMB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
        CpuSeg = [math]::Round(($_.Group | Measure-Object CPU -Sum).Sum)
    }
} | Sort-Object RamMB -Descending | Select-Object -First 12

# ---------------------------------------------------------------- Programas al inicio
function Estado-Aprobado([string]$Raiz, [string]$Sub, [string]$Nombre) {
    $v = (Get-ItemProperty -Path "$Raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$Sub" -Name $Nombre -ErrorAction SilentlyContinue).$Nombre
    if ($v -is [byte[]] -and $v.Length -gt 0 -and ($v[0] -band 1)) { return 'desactivado' }
    return 'activo'
}
$inicio = New-Object System.Collections.Generic.List[object]
foreach ($o in @(
        @{ Ruta = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Raiz = 'HKCU:'; Sub = 'Run'; Ambito = 'usuario' },
        @{ Ruta = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Raiz = 'HKLM:'; Sub = 'Run'; Ambito = 'equipo' },
        @{ Ruta = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Raiz = 'HKLM:'; Sub = 'Run32'; Ambito = 'equipo' })) {
    $p = Get-ItemProperty -Path $o.Ruta -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($prop in $p.PSObject.Properties) {
        if ($prop.Name -like 'PS*') { continue }
        $inicio.Add([pscustomobject]@{ Nombre = $prop.Name; Ambito = $o.Ambito; Estado = Estado-Aprobado $o.Raiz $o.Sub $prop.Name; Comando = "$($prop.Value)" })
    }
}
foreach ($o in @(
        @{ Ruta = [Environment]::GetFolderPath('Startup'); Raiz = 'HKCU:'; Ambito = 'usuario' },
        @{ Ruta = [Environment]::GetFolderPath('CommonStartup'); Raiz = 'HKLM:'; Ambito = 'equipo' })) {
    Get-ChildItem -LiteralPath $o.Ruta -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini' | ForEach-Object {
        $inicio.Add([pscustomobject]@{ Nombre = $_.Name; Ambito = $o.Ambito; Estado = Estado-Aprobado $o.Raiz 'StartupFolder' $_.Name; Comando = $_.FullName })
    }
}
foreach ($i in $inicio) {
    # Solo el nombre y el archivo que se ejecuta: la ruta completa da falsos positivos ("ProgramData" contiene "amD").
    $ejecutable = if ($i.Comando -match '^\s*"([^"]+)"') { $Matches[1] } else { ($i.Comando -split '\s+')[0] }
    $texto = "$($i.Nombre) $([IO.Path]::GetFileName($ejecutable))"
    $c = $catalogo.inicio | Where-Object { $texto -match $_.patron } | Select-Object -First 1
    $i | Add-Member -NotePropertyName QueEs -NotePropertyValue $(if ($c) { $c.que_es } else { 'sin información: preguntar o buscar antes de tocarlo' })
    $i | Add-Member -NotePropertyName Impacto -NotePropertyValue $(if ($c) { $c.impacto } else { '?' })
    $i | Add-Member -NotePropertyName Sugerencia -NotePropertyValue $(if (-not $c) { 'no tocar sin saber qué es' } elseif ($c.mantener) { 'mantener' } else { $c.consejo })
}
$inicioActivos = @($inicio | Where-Object Estado -eq 'activo')
$remotos = @($inicioActivos | Where-Object { $_.QueEs -match 'acceso remoto' })
if ($remotos.Count) { Senal 'media' 'Seguridad' "Arranca con Windows un programa de acceso remoto ($($remotos.Nombre -join ', ')): permite que otra persona controle la PC. Confirmar que la persona lo usa y sabe quién tiene acceso." }
if ($inicioActivos.Count -ge 8) { Senal 'media' 'Inicio' "$($inicioActivos.Count) programas arrancan solos con Windows. Cada uno alarga el arranque y ocupa memoria todo el día." }

# ---------------------------------------------------------------- Servicios de terceros en ejecución
$servicios = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State='Running'" | Where-Object {
        $_.PathName -and $_.PathName -notmatch '\\Windows\\(System32|SysWOW64|servicing)\\|\\Windows Defender\\|\\Microsoft\\'
    } | Sort-Object DisplayName -Unique | Select-Object @{n = 'Servicio'; e = { $_.DisplayName } }, @{n = 'Ruta'; e = { $_.PathName } })

# ---------------------------------------------------------------- Programas instalados que suelen pesar
$instalados = @(Obtener-ProgramasInstalados)
$pesados = New-Object System.Collections.Generic.List[object]
foreach ($prog in $instalados) {
    foreach ($c in $catalogo.programas) {
        if ($prog.Nombre -match $c.patron) {
            $pesados.Add([pscustomobject]@{ Programa = $prog.Nombre; Categoria = $c.categoria; QueEs = $c.que_es; Consejo = $c.consejo; TamanoMB = $prog.TamanoMB })
            break
        }
    }
}
$emuladores = @($pesados | Where-Object Categoria -eq 'emulador')
if ($emuladores.Count -gt 0) { Senal 'alta' 'Programas' "Hay emuladores de Android instalados ($($emuladores.Programa -join ', ')). Activan virtualización y servicios en segundo plano que restan mucho rendimiento aunque no se usen." }
if ($pesados.Count -gt 0) { Senal 'media' 'Programas' "Se encontraron $($pesados.Count) programas que suelen consumir recursos. Revisa la tabla y decide cuáles usas." }

# ---------------------------------------------------------------- Antivirus
$antivirus = @()
try { $antivirus = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Select-Object -ExpandProperty displayName) } catch { }
$terceros = @($antivirus | Where-Object { $_ -notmatch 'Windows Defender|Microsoft Defender' })
if ($terceros.Count -ge 2) { Senal 'alta' 'Seguridad' "Hay más de un antivirus de terceros ($($terceros -join ', ')). Dos antivirus a la vez se estorban y vuelven lento todo. Deja uno solo (Microsoft Defender basta para la mayoría)." }
$defender = $null
try { $defender = Get-MpComputerStatus -ErrorAction Stop } catch { }
if ($defender -and -not $defender.RealTimeProtectionEnabled -and $terceros.Count -eq 0) { Senal 'alta' 'Seguridad' 'La protección en tiempo real de Microsoft Defender está apagada y no hay otro antivirus. No es un problema de velocidad, pero sí de seguridad: actívala.' }

# ---------------------------------------------------------------- Temporales y cachés
$rutasLimpieza = [ordered]@{
    'Temporales del usuario'        = $env:TEMP
    'Temporales de Windows'         = Join-Path $env:windir 'Temp'
    'Descargas de Windows Update'   = Join-Path $env:windir 'SoftwareDistribution\Download'
    'Optimización de distribución'  = Join-Path $env:windir 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
}
$limpiables = foreach ($k in $rutasLimpieza.Keys) {
    $m = Medir-Carpeta $rutasLimpieza[$k]
    [pscustomobject]@{ Que = $k; RequiereAdmin = ($k -ne 'Temporales del usuario'); Ruta = $rutasLimpieza[$k]; Bytes = $m.Bytes; Tamano = $(if ($m.SinPermiso) { 'sin permiso para medir (requiere administrador)' } else { Formatear-Tamano $m.Bytes }) }
}
$totalLimpiable = ($limpiables | Measure-Object Bytes -Sum).Sum
if ($totalLimpiable -ge 2GB) { Senal 'media' 'Espacio' "Hay $(Formatear-Tamano $totalLimpiable) en temporales y cachés que se pueden borrar sin riesgo." }

# ---------------------------------------------------------------- Carpetas del usuario
$carpetasUsuario = @()
if (-not $Rapido) {
    $carpetasUsuario = foreach ($n in 'Desktop', 'Downloads', 'Documents', 'Videos', 'Pictures', 'Music') {
        $ruta = if ($n -eq 'Downloads') {
            (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' -ErrorAction SilentlyContinue).'{374DE290-123F-4565-9164-39C4925E467B}'
        } else { [Environment]::GetFolderPath($(if ($n -eq 'Documents') { 'MyDocuments' } elseif ($n -eq 'Videos') { 'MyVideos' } elseif ($n -eq 'Pictures') { 'MyPictures' } elseif ($n -eq 'Music') { 'MyMusic' } else { $n })) }
        if (-not $ruta) { continue }
        $m = Medir-Carpeta $ruta
        $etiqueta = @{ Desktop = 'Escritorio'; Downloads = 'Descargas'; Documents = 'Documentos'; Videos = 'Videos'; Pictures = 'Imagenes'; Music = 'Musica' }[$n]
        [pscustomobject]@{ Carpeta = $etiqueta; Ruta = $ruta; Unidad = $ruta.Substring(0, 2); Bytes = $m.Bytes; Tamano = Formatear-Tamano $m.Bytes; EnOneDrive = $ruta -match 'OneDrive' }
    }
    $grandesEnC = @($carpetasUsuario | Where-Object { $_.Unidad -eq $env:SystemDrive -and $_.Bytes -ge 10GB -and -not $_.EnOneDrive })
    if ($grandesEnC.Count -gt 0 -and $otras.Count -gt 0) {
        Senal 'media' 'Espacio' "Las carpetas $($grandesEnC.Carpeta -join ', ') ocupan $(Formatear-Tamano (($grandesEnC | Measure-Object Bytes -Sum).Sum)) en $env:SystemDrive y hay espacio en $($otras.Unidad -join ', '). Se pueden mover allá sin cambiar cómo las usas."
    }
}

# ---------------------------------------------------------------- Energía y otros
$plan = (powercfg /getactivescheme 2>$null) -join ' '
if ($plan -match 'Ahorro|saver') { Senal 'media' 'Energía' 'El plan de energía es "Ahorro de energía": el procesador trabaja más lento a propósito. En un equipo enchufado conviene "Equilibrado".' }

$reinicioPendiente = (Test-Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($reinicioPendiente) { Senal 'media' 'Sistema' 'Hay actualizaciones esperando un reinicio. Mientras tanto Windows puede ir más lento.' }

# ---------------------------------------------------------------- Informe
$orden = @{ alta = 0; media = 1; baja = 2 }
$senalesOrdenadas = $senales | Sort-Object { $orden[$_.Gravedad] }

$md = New-Object System.Text.StringBuilder
function L([string]$t = '') { [void]$md.AppendLine($t) }
L "# Diagnóstico de rendimiento · $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
L
L '## Señales encontradas (de más a menos importante)'
if ($senalesOrdenadas) { foreach ($s in $senalesOrdenadas) { L "- **[$($s.Gravedad)] $($s.Tema):** $($s.Texto)" } } else { L '- No se encontraron problemas evidentes.' }
L
L '## Equipo'
foreach ($k in $equipo.Keys) { L "- $k`: $($equipo[$k])" }
L
L '## Discos'
foreach ($d in $discos) { L "- $($d.Nombre): $($d.Tipo), $($d.TamanoGB) GB, salud $($d.Salud)$(if ($d.Sistema) { ' · tiene Windows' })" }
foreach ($u in $unidades) { L "- Unidad $($u.Unidad): $($u.LibreGB) GB libres de $($u.TotalGB) GB ($($u.LibrePct) %)" }
L "- Avisos de disco en 14 días: $erroresDisco"
L
L "## Procesos que más memoria usan ahora (las herramientas del asistente suman $ramPropiaMB MB: no cuentan como problema)"
L '| Proceso | Instancias | RAM (MB) | CPU (s) |'; L '|---|---|---|---|'
foreach ($p in $procesos) { L "| $($p.Proceso) | $($p.Instancias) | $($p.RamMB) | $($p.CpuSeg) |" }
L
L "## Programas al inicio ($($inicioActivos.Count) activos de $($inicio.Count))"
L '| Nombre | Ámbito | Estado | Impacto | Qué es | Sugerencia |'; L '|---|---|---|---|---|---|'
foreach ($i in $inicio) { L "| $($i.Nombre) | $($i.Ambito) | $($i.Estado) | $($i.Impacto) | $($i.QueEs) | $($i.Sugerencia) |" }
L
L "## Servicios de terceros en ejecución ($($servicios.Count))"
foreach ($s in $servicios) { L "- $($s.Servicio)" }
L
L '## Programas instalados que suelen consumir recursos'
if ($pesados.Count) {
    L '| Programa | Tipo | Qué es | Consejo |'; L '|---|---|---|---|'
    foreach ($p in $pesados) { L "| $($p.Programa) | $($p.Categoria) | $($p.QueEs) | $($p.Consejo) |" }
} else { L '- Ninguno del catálogo.' }
L
$sinAdmin = ($limpiables | Where-Object { -not $_.RequiereAdmin } | Measure-Object Bytes -Sum).Sum
L "## Temporales y cachés (total $(Formatear-Tamano $totalLimpiable); sin administrador se pueden limpiar $(Formatear-Tamano $sinAdmin))"
foreach ($x in $limpiables) { L "- $($x.Que): $($x.Tamano)$(if ($x.RequiereAdmin) { ' · requiere administrador' })" }
L
if ($carpetasUsuario) {
    L '## Carpetas del usuario'
    foreach ($c in $carpetasUsuario) { L "- $($c.Carpeta): $($c.Tamano) en $($c.Unidad)$(if ($c.EnOneDrive) { ' (OneDrive)' })" }
    L
}
L '## Otros'
L "- Antivirus registrados: $(if ($antivirus) { $antivirus -join ', ' } else { 'ninguno informado' })"
L "- Plan de energía: $($plan -replace '^.*?\(|\)\s*$','')"
L "- Reinicio pendiente: $(if ($reinicioPendiente) { 'sí' } else { 'no' })"
L "- Ejecutado como administrador: $(if (Test-Administrador) { 'sí' } else { 'no (algunos datos pueden faltar)' })"

$texto = $md.ToString()
Write-Output $texto

if ($Json) {
    $datos = [ordered]@{
        Fecha = (Get-Date).ToString('s'); Equipo = $equipo; Discos = $discos; Unidades = $unidades; ErroresDisco = $erroresDisco
        Ranuras = $ranuras; Procesos = $procesos; Inicio = $inicio; Servicios = $servicios; Pesados = $pesados; Limpiables = $limpiables
        CarpetasUsuario = $carpetasUsuario; Antivirus = $antivirus; Plan = $plan; ReinicioPendiente = $reinicioPendiente; Senales = $senalesOrdenadas
    }
    try {
        $carpetaJson = Split-Path -Parent ([IO.Path]::GetFullPath($Json))
        if ($carpetaJson) { New-Item -ItemType Directory -Force -Path $carpetaJson | Out-Null }
        [System.IO.File]::WriteAllText($Json, ($datos | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
        Write-Host "Datos guardados en $Json"
    } catch { Write-Host "No se pudieron guardar los datos en $Json`: $($_.Exception.Message)" }
}
