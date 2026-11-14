<#
.SYNOPSIS
  Borra temporales y cachés que Windows vuelve a generar. Sin -Aplicar solo mide.

.DESCRIPTION
  Siempre seguro: temporales del usuario (de más de 1 día), temporales de Windows, descargas ya
  instaladas de Windows Update y caché de Optimización de distribución. Los archivos en uso se
  saltan. Opcional: -Papelera (vacía la papelera: son archivos del usuario, pregunta antes) y
  -Componentes (DISM: limpia versiones viejas de actualizaciones; tarda 5-30 min).
  Las tres últimas rutas necesitan administrador; sin permisos se saltan con aviso.

.EXAMPLE
  .\limpiar.ps1                 # mide cuánto se liberaría
  .\limpiar.ps1 -Aplicar        # limpia
#>
[CmdletBinding()]
param(
    [switch]$Aplicar,
    [switch]$Papelera,
    [switch]$Componentes
)

. (Join-Path $PSScriptRoot 'comun.ps1')
$ErrorActionPreference = 'Continue'
$registro = Iniciar-Registro 'limpiar'
if (-not $Aplicar) { Escribir-Registro 'MODO SIMULACIÓN: solo se mide. Agrega -Aplicar para borrar.' -Nivel SIMULACION }
$admin = Test-Administrador
$libreAntes = (Get-PSDrive ($env:SystemDrive.TrimEnd(':'))).Free

function Vaciar-Carpeta {
    param([string]$Que, [string]$Ruta, [int]$DiasMinimos = 0, [switch]$RequiereAdmin)
    if ($RequiereAdmin -and -not $admin) { Escribir-Registro "$Que`: se salta (necesita administrador)." -Nivel AVISO; return }
    try { if (-not (Test-Path -LiteralPath $Ruta -ErrorAction Stop)) { return } }
    catch { Escribir-Registro "$Que`: sin permiso para entrar a la carpeta." -Nivel AVISO; return }
    $tamano = (Medir-Carpeta $Ruta).Bytes
    if (-not $Aplicar) { Escribir-Registro "$Que`: se liberarían hasta $(Formatear-Tamano $tamano)" -Nivel SIMULACION; return }
    $limite = (Get-Date).AddDays(-$DiasMinimos)
    $fallidos = 0
    Get-ChildItem -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.LastWriteTime -gt $limite) { return }
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }  # nunca seguir enlaces fuera de la carpeta
        try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { $fallidos++ }
    }
    $quedan = (Medir-Carpeta $Ruta).Bytes
    Escribir-Registro "$Que`: liberado $(Formatear-Tamano ([math]::Max(0, $tamano - $quedan)))$(if ($fallidos) { " ($fallidos elementos en uso se dejaron)" })" -Nivel OK
}

Vaciar-Carpeta 'Temporales del usuario' $env:TEMP -DiasMinimos 1
Vaciar-Carpeta 'Temporales de Windows' (Join-Path $env:windir 'Temp') -DiasMinimos 1 -RequiereAdmin

# Windows Update: se detienen los servicios para que suelten los archivos y se vuelven a iniciar siempre.
$wu = Join-Path $env:windir 'SoftwareDistribution\Download'
if ($Aplicar -and $admin -and (Test-Path $wu)) {
    $servicios = 'wuauserv', 'bits'
    try {
        foreach ($s in $servicios) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
        Vaciar-Carpeta 'Descargas de Windows Update' $wu -RequiereAdmin
    } finally {
        foreach ($s in $servicios) { Start-Service $s -ErrorAction SilentlyContinue }
    }
} else { Vaciar-Carpeta 'Descargas de Windows Update' $wu -RequiereAdmin }

$doCache = Join-Path $env:windir 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
if ($Aplicar -and $admin -and (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) {
    $t = (Medir-Carpeta $doCache).Bytes
    try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Escribir-Registro "Optimización de distribución: liberado ~$(Formatear-Tamano $t)" -Nivel OK }
    catch { Escribir-Registro "Optimización de distribución: $($_.Exception.Message)" -Nivel AVISO }
} else { Vaciar-Carpeta 'Optimización de distribución' $doCache -RequiereAdmin }

if ($Papelera) {
    if ($Aplicar) {
        try { Clear-RecycleBin -Force -ErrorAction Stop; Escribir-Registro 'Papelera vaciada.' -Nivel OK }
        catch { Escribir-Registro "Papelera: $($_.Exception.Message)" -Nivel AVISO }
    } else { Escribir-Registro 'Se vaciaría la papelera (archivos del usuario: confírmalo antes).' -Nivel SIMULACION }
}

if ($Componentes) {
    if (-not $admin) { Escribir-Registro 'Limpieza de componentes: se salta (necesita administrador).' -Nivel AVISO }
    elseif (-not $Aplicar) { Escribir-Registro 'Se ejecutaría DISM /StartComponentCleanup (tarda 5-30 min).' -Nivel SIMULACION }
    else {
        Escribir-Registro 'DISM /StartComponentCleanup en curso (puede tardar)...'
        & dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null
        Escribir-Registro "DISM terminó con código $LASTEXITCODE" -Nivel $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'AVISO' })
    }
}

if ($Aplicar) {
    $libreDespues = (Get-PSDrive ($env:SystemDrive.TrimEnd(':'))).Free
    Escribir-Registro "Espacio libre en $env:SystemDrive`: $(Formatear-Tamano $libreAntes) -> $(Formatear-Tamano $libreDespues)" -Nivel OK
}
Write-Output "Registro: $registro"
