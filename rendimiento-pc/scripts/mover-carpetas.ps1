<#
.SYNOPSIS
  Mueve carpetas del usuario (Escritorio, Descargas, Documentos...) a otro disco. Sin -Aplicar solo revisa.

.DESCRIPTION
  Libera espacio en el disco del sistema sin cambiar cómo se usan las carpetas: Windows las sigue
  mostrando en el mismo lugar del Explorador. Orden seguro, carpeta por carpeta:
    1. Revisa que el destino sea un disco fijo distinto, con espacio suficiente.
    2. COPIA todo (robocopy) sin borrar nada.
    3. Verifica que el destino tenga la misma cantidad de archivos y bytes.
    4. Solo entonces cambia la ruta de la carpeta en Windows.
    5. Pasa al destino lo que haya cambiado mientras tanto y borra el original.
  Si algo falla antes del paso 4, la carpeta queda como estaba y no se borra nada.
  Las carpetas sincronizadas con OneDrive se saltan (OneDrive tiene su propio mecanismo).

.PARAMETER Carpetas
  Cualquiera de: Escritorio, Descargas, Documentos, Imagenes, Musica, Videos.

.PARAMETER Destino
  Carpeta raíz en el otro disco. Ejemplo: D:\MisCarpetas (se crean subcarpetas con el nombre de cada una).

.PARAMETER ConservarOrigen
  No borra el original (sirve de copia de seguridad, pero no libera espacio hasta borrarlo a mano).

.EXAMPLE
  .\mover-carpetas.ps1 -Carpetas Escritorio, Descargas -Destino D:\MisCarpetas            # revisión
  .\mover-carpetas.ps1 -Carpetas Escritorio, Descargas -Destino D:\MisCarpetas -Aplicar
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Carpetas,
    [Parameter(Mandatory)][string]$Destino,
    [switch]$ConservarOrigen,
    [switch]$Aplicar
)

. (Join-Path $PSScriptRoot 'comun.ps1')
$Carpetas = Dividir-Lista $Carpetas
$validas = 'Escritorio', 'Descargas', 'Documentos', 'Imagenes', 'Musica', 'Videos'
$invalidas = @($Carpetas | Where-Object { $validas -notcontains $_ })
if ($invalidas.Count) { throw "Carpeta no reconocida: $($invalidas -join ', '). Usa: $($validas -join ', ')." }
$registro = Iniciar-Registro 'mover-carpetas'
if (-not $Aplicar) { Escribir-Registro 'MODO REVISIÓN: no se mueve nada. Agrega -Aplicar para hacerlo.' -Nivel SIMULACION }

$clavesUsf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$clavesSf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
$mapa = @{
    Escritorio = @{ Valor = 'Desktop'; Sub = 'Escritorio' }
    Descargas  = @{ Valor = '{374DE290-123F-4565-9164-39C4925E467B}'; Sub = 'Descargas' }
    Documentos = @{ Valor = 'Personal'; Sub = 'Documentos' }
    Imagenes   = @{ Valor = 'My Pictures'; Sub = 'Imagenes' }
    Musica     = @{ Valor = 'My Music'; Sub = 'Musica' }
    Videos     = @{ Valor = 'My Video'; Sub = 'Videos' }
}

$unidadDestino = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Destino)).TrimEnd('\')
$disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$unidadDestino'"
if (-not $disco) { throw "La unidad $unidadDestino no existe." }
if ($disco.DriveType -ne 3) { throw "La unidad $unidadDestino no es un disco fijo interno (¿USB o red?). Mover carpetas ahí las dejaría inaccesibles cuando se desconecte." }

# Tipo del disco de destino: mover miles de archivos pequeños a un HDD los vuelve lentos.
$tipoDestino = $null
try {
    $num = (Get-Partition -DriveLetter $unidadDestino.TrimEnd(':') -ErrorAction Stop | Get-Disk -ErrorAction Stop).Number
    $tipoDestino = "$((Get-PhysicalDisk | Where-Object { "$($_.DeviceId)" -eq "$num" }).MediaType)"
} catch { }

$huboCambios = $false
foreach ($nombre in $Carpetas) {
    $m = $mapa[$nombre]
    $crudo = (Get-ItemProperty -Path $clavesUsf -Name $m.Valor -ErrorAction SilentlyContinue).($m.Valor)
    if (-not $crudo) { Escribir-Registro "${nombre}: Windows no tiene registrada esta carpeta." -Nivel AVISO; continue }
    $origen = [Environment]::ExpandEnvironmentVariables($crudo).TrimEnd('\')
    $destinoCarpeta = Join-Path $Destino $m.Sub

    if ($origen -match '\\OneDrive') { Escribir-Registro "${nombre}: está en OneDrive ($origen). Se salta: muévela desde la configuración de OneDrive." -Nivel AVISO; continue }
    if ($origen.StartsWith($unidadDestino, [StringComparison]::OrdinalIgnoreCase)) { Escribir-Registro "${nombre}: ya está en $unidadDestino ($origen). Nada que hacer." -Nivel OK; continue }
    if (-not (Test-Path -LiteralPath $origen)) { Escribir-Registro "${nombre}: la ruta $origen no existe." -Nivel AVISO; continue }

    $medida = Medir-Carpeta $origen
    $libre = [double](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$unidadDestino'").FreeSpace
    $necesario = $medida.Bytes * 1.05 + 1GB
    Escribir-Registro "${nombre}: $origen -> $destinoCarpeta · $($medida.Archivos) archivos, $(Formatear-Tamano $medida.Bytes)"
    if ($libre -lt $necesario) { Escribir-Registro "${nombre}: no alcanza el espacio en $unidadDestino (libre $(Formatear-Tamano $libre), hacen falta ~$(Formatear-Tamano $necesario))." -Nivel ERROR; continue }
    if ((Test-Path -LiteralPath $destinoCarpeta) -and (Get-ChildItem -LiteralPath $destinoCarpeta -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Escribir-Registro "${nombre}: $destinoCarpeta ya tiene archivos. Elige una carpeta de destino vacía para no mezclar ni sobrescribir nada." -Nivel ERROR; continue
    }
    if ($tipoDestino -eq 'HDD' -and $medida.Archivos -ge 50000) {
        Escribir-Registro "${nombre}: tiene $($medida.Archivos) archivos y $unidadDestino es un disco mecánico (HDD). Si son proyectos de programación, bases de datos o archivos que se abren a diario, irán más lentos allá. Para archivos que solo se guardan (fotos, videos, instaladores) no hay problema." -Nivel AVISO
    }
    if (-not $Aplicar) { Escribir-Registro "${nombre}: se puede mover." -Nivel SIMULACION; continue }

    $logRobocopy = Join-Path (Split-Path $registro) ("robocopy-{0}-{1}.txt" -f $nombre, (Get-Date -Format 'HHmmss'))
    $opciones = @('/E', '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1', '/XJ', '/NP', '/NFL', '/NDL', "/UNILOG+:$logRobocopy")

    # 1-2. Copiar sin borrar.
    New-Item -ItemType Directory -Force -Path $destinoCarpeta | Out-Null
    & robocopy.exe $origen $destinoCarpeta @opciones | Out-Null
    $codigo = $LASTEXITCODE
    if ($codigo -ge 8) { Escribir-Registro "${nombre}: la copia falló (robocopy $codigo, ver $logRobocopy). No se cambió nada." -Nivel ERROR; continue }

    # 3. Verificar.
    $copia = Medir-Carpeta $destinoCarpeta
    if ($copia.Archivos -lt $medida.Archivos -or $copia.Bytes -lt $medida.Bytes) {
        Escribir-Registro "${nombre}: la copia está incompleta ($($copia.Archivos)/$($medida.Archivos) archivos). No se cambió la carpeta; el original sigue intacto." -Nivel ERROR; continue
    }

    # 4. Redirigir.
    Set-ItemProperty -Path $clavesUsf -Name $m.Valor -Value $destinoCarpeta -Type ExpandString
    Set-ItemProperty -Path $clavesSf -Name $m.Valor -Value $destinoCarpeta
    $huboCambios = $true
    Escribir-Registro "${nombre}: Windows ahora usa $destinoCarpeta" -Nivel OK

    # 5. Pasar lo que cambió entretanto y borrar el original.
    if ($ConservarOrigen) {
        Escribir-Registro "${nombre}: el original queda en $origen como respaldo (bórralo a mano para liberar el espacio)." -Nivel AVISO
    } else {
        & robocopy.exe $origen $destinoCarpeta @opciones '/MOVE' | Out-Null
        $codigo = $LASTEXITCODE
        $resto = Medir-Carpeta $origen
        if ($codigo -ge 8 -or $resto.Archivos -gt 0) {
            Escribir-Registro "${nombre}: quedaron $($resto.Archivos) archivos en $origen (en uso o bloqueados). Ciérralos y muévelos a mano." -Nivel AVISO
        } else {
            # Se deja la carpeta original vacía: algunos programas viejos la buscan por la ruta fija.
            New-Item -ItemType Directory -Force -Path $origen | Out-Null
            Escribir-Registro "${nombre}: original vaciado; liberados $(Formatear-Tamano $medida.Bytes) en $($origen.Substring(0,2))" -Nivel OK
        }
    }
}

if ($huboCambios) {
    # El Explorador lee estas rutas al arrancar.
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Escribir-Registro 'Explorador reiniciado. Para volver atrás: Propiedades de la carpeta > Ubicación > Restaurar valores predeterminados.' -Nivel OK
}
Write-Output "Registro: $registro"
