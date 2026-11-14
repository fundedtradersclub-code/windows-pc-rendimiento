<#
.SYNOPSIS
  Lista, desactiva o reactiva programas que arrancan con Windows. Sin -Aplicar solo muestra.

.DESCRIPTION
  Usa el mismo mecanismo que la pestaña "Aplicaciones de arranque" del Administrador de tareas
  (claves StartupApproved): no borra la entrada ni el programa, solo la marca como desactivada,
  así que se revierte con -Reactivar o desde el Administrador de tareas. Las entradas "de equipo"
  necesitan administrador.

.EXAMPLE
  .\inicio.ps1                                   # lista
  .\inicio.ps1 -Desactivar Steam, "EpicGamesLauncher" -Aplicar
  .\inicio.ps1 -Reactivar Steam -Aplicar
#>
[CmdletBinding()]
param(
    [string[]]$Desactivar = @(),
    [string[]]$Reactivar = @(),
    [switch]$Aplicar
)

. (Join-Path $PSScriptRoot 'comun.ps1')

$Desactivar = Dividir-Lista $Desactivar
$Reactivar = Dividir-Lista $Reactivar

$fuentes = @(
    @{ Ruta = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Aprobado = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Ambito = 'usuario'; Carpeta = $null },
    @{ Ruta = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Aprobado = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Ambito = 'equipo'; Carpeta = $null },
    @{ Ruta = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprobado = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Ambito = 'equipo'; Carpeta = $null },
    @{ Ruta = $null; Aprobado = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Ambito = 'usuario'; Carpeta = [Environment]::GetFolderPath('Startup') },
    @{ Ruta = $null; Aprobado = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Ambito = 'equipo'; Carpeta = [Environment]::GetFolderPath('CommonStartup') }
)

function Leer-Entradas {
    foreach ($f in $fuentes) {
        $nombres = @()
        if ($f.Ruta) {
            $p = Get-ItemProperty -Path $f.Ruta -ErrorAction SilentlyContinue
            if ($p) { $nombres = @($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { @{ N = $_.Name; C = "$($_.Value)" } }) }
        } elseif ($f.Carpeta) {
            $nombres = @(Get-ChildItem -LiteralPath $f.Carpeta -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini' | ForEach-Object { @{ N = $_.Name; C = $_.FullName } })
        }
        foreach ($n in $nombres) {
            $v = (Get-ItemProperty -Path $f.Aprobado -Name $n.N -ErrorAction SilentlyContinue).($n.N)
            $desactivado = ($v -is [byte[]]) -and $v.Length -gt 0 -and ($v[0] -band 1)
            [pscustomobject]@{ Nombre = $n.N; Ambito = $f.Ambito; Estado = $(if ($desactivado) { 'desactivado' } else { 'activo' }); Comando = $n.C; ClaveAprobado = $f.Aprobado }
        }
    }
}

function Cambiar-Estado {
    param($Entrada, [bool]$Activar)
    if ($Entrada.Ambito -eq 'equipo' -and -not (Test-Administrador)) {
        Escribir-Registro "'$($Entrada.Nombre)': es de equipo, necesita administrador." -Nivel AVISO; return
    }
    $accion = if ($Activar) { 'reactivaría' } else { 'desactivaría' }
    if (-not $Aplicar) { Escribir-Registro "Se $accion '$($Entrada.Nombre)' ($($Entrada.Ambito))" -Nivel SIMULACION; return }
    # 12 bytes: el primero 02 = activo, 03 = desactivado; los 8 últimos, la fecha del cambio (FILETIME).
    $bytes = New-Object byte[] 12
    $bytes[0] = if ($Activar) { 2 } else { 3 }
    if (-not $Activar) { [BitConverter]::GetBytes((Get-Date).ToFileTime()).CopyTo($bytes, 4) }
    if (-not (Test-Path $Entrada.ClaveAprobado)) { New-Item -Path $Entrada.ClaveAprobado -Force | Out-Null }
    Set-ItemProperty -Path $Entrada.ClaveAprobado -Name $Entrada.Nombre -Value $bytes -Type Binary
    Escribir-Registro "'$($Entrada.Nombre)': $(if ($Activar) { 'reactivado' } else { 'desactivado' }) (se nota en el próximo inicio de sesión)" -Nivel OK
}

$entradas = @(Leer-Entradas)
if ($Desactivar.Count -eq 0 -and $Reactivar.Count -eq 0) {
    Write-Output ($entradas | Select-Object Nombre, Ambito, Estado, Comando | Format-Table -AutoSize -Wrap | Out-String -Width 220)
    return
}

$registro = Iniciar-Registro 'inicio'
if (-not $Aplicar) { Escribir-Registro 'MODO SIMULACIÓN: no se cambia nada. Agrega -Aplicar.' -Nivel SIMULACION }
foreach ($par in @(@{ Lista = $Desactivar; Activar = $false }, @{ Lista = $Reactivar; Activar = $true })) {
    foreach ($nombre in $par.Lista) {
        $coinciden = @($entradas | Where-Object { $_.Nombre -like "*$nombre*" })
        if ($coinciden.Count -eq 0) { Escribir-Registro "'$nombre': no está entre los programas de inicio." -Nivel AVISO; continue }
        foreach ($e in $coinciden) { Cambiar-Estado $e $par.Activar }
    }
}
Write-Output "Registro: $registro"
