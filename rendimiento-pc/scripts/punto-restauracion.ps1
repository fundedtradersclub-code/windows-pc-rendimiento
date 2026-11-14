<#
.SYNOPSIS
  Crea un punto de restauración antes de hacer cambios. Necesita administrador.

.DESCRIPTION
  Permite deshacer desinstalaciones y cambios del registro desde
  Panel de control > Recuperación > Abrir Restaurar sistema. Activa Restaurar sistema en la
  unidad del sistema si estaba apagado. Windows crea como máximo uno cada 24 h: si ya existe
  uno reciente, se usa ese.
#>
[CmdletBinding()]
param([string]$Descripcion = "Antes de rendimiento-pc $(Get-Date -Format 'yyyy-MM-dd HH:mm')")

. (Join-Path $PSScriptRoot 'comun.ps1')
Iniciar-Registro 'punto-restauracion' | Out-Null
if (-not (Nuevo-PuntoRestauracion $Descripcion)) { exit 1 }
Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Select-Object -Last 3 |
    Format-Table @{n = 'Fecha'; e = { $_.ConvertToDateTime($_.CreationTime) } }, Description -AutoSize
