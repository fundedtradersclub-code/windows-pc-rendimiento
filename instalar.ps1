# Instala la skill rendimiento-pc para Claude Code en el perfil del usuario.
# Uso: powershell -ExecutionPolicy Bypass -File .\instalar.ps1
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$origen = Join-Path $PSScriptRoot 'rendimiento-pc'
$destino = Join-Path $env:USERPROFILE '.claude\skills\rendimiento-pc'

if (-not (Test-Path (Join-Path $origen 'SKILL.md'))) { throw "No se encontró $origen\SKILL.md. Ejecuta este script desde la carpeta del repositorio." }
if (Test-Path $destino) {
    # Fuera de .claude\skills: si quedara ahí, Claude la cargaría como una segunda skill.
    $carpetaRespaldos = Join-Path $env:USERPROFILE '.claude\skills-respaldos'
    New-Item -ItemType Directory -Force -Path $carpetaRespaldos | Out-Null
    $respaldo = Join-Path $carpetaRespaldos "rendimiento-pc-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item $destino $respaldo
    Write-Host "Había una versión anterior; quedó en $respaldo"
}
New-Item -ItemType Directory -Force -Path (Split-Path $destino) | Out-Null
Copy-Item $origen $destino -Recurse
Write-Host "Skill instalada en $destino"
Write-Host 'Abre Claude Code y escribe, por ejemplo: "mi computadora está lenta, ¿me ayudas?"'
