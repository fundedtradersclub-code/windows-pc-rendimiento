# Funciones compartidas por los scripts de rendimiento-pc.
# Compatible con Windows PowerShell 5.1 y PowerShell 7.

$ErrorActionPreference = 'Stop'
# Sin esto la consola de Windows muestra mal las tildes y la eñe.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:CarpetaDatos = Join-Path $env:LOCALAPPDATA 'rendimiento-pc'
$script:ArchivoRegistro = $null

function Iniciar-Registro {
    param([Parameter(Mandatory)][string]$Nombre)
    $carpeta = Join-Path $script:CarpetaDatos 'registros'
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
    $script:ArchivoRegistro = Join-Path $carpeta ("{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Nombre)
    Escribir-Registro "Inicio: $Nombre (PowerShell $($PSVersionTable.PSVersion))"
    return $script:ArchivoRegistro
}

function Escribir-Registro {
    param([Parameter(Mandatory)][string]$Texto, [ValidateSet('INFO', 'AVISO', 'ERROR', 'OK', 'SIMULACION')][string]$Nivel = 'INFO')
    $linea = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Texto
    # Write-Host y no Write-Output: así el texto no se mezcla con lo que devuelven las funciones.
    Write-Host $linea
    if ($script:ArchivoRegistro) {
        # UTF-8 explícito: Out-File en PowerShell 5.1 escribe UTF-16 y el registro se ve con espacios entre letras.
        [System.IO.File]::AppendAllText($script:ArchivoRegistro, $linea + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    }
}

function Dividir-Lista {
    # Con "powershell -File script.ps1 -Nombres a,b" la lista llega como UN texto "a,b".
    # Se separa aquí para que funcione igual desde una terminal de PowerShell o desde -File.
    param([string[]]$Valores)
    @($Valores | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
}

function Test-Administrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Exigir-Administrador {
    if (-not (Test-Administrador)) {
        throw 'Este paso necesita permisos de administrador. Abre PowerShell con "Ejecutar como administrador" y vuelve a intentarlo.'
    }
}

function Formatear-Tamano {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return '{0:N0} B' -f $Bytes
}

function Medir-Carpeta {
    # Tamaño total sin seguir enlaces (junctions) para no contar dos veces ni entrar en bucles.
    param([Parameter(Mandatory)][string]$Ruta)
    # Algunas carpetas del sistema no se pueden ni consultar sin ser administrador: se informa SinPermiso.
    try { $existe = Test-Path -LiteralPath $Ruta -ErrorAction Stop } catch { return [pscustomobject]@{ Bytes = 0; Archivos = 0; SinPermiso = $true } }
    if (-not $existe) { return [pscustomobject]@{ Bytes = 0; Archivos = 0; SinPermiso = $false } }
    $bytes = 0L; $archivos = 0L
    $pendientes = New-Object System.Collections.Generic.Stack[string]
    $pendientes.Push($Ruta)
    while ($pendientes.Count -gt 0) {
        $actual = $pendientes.Pop()
        try { $dir = New-Object System.IO.DirectoryInfo $actual; $hijos = $dir.GetFileSystemInfos() } catch { continue }
        foreach ($h in $hijos) {
            if ($h.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($h -is [IO.DirectoryInfo]) { $pendientes.Push($h.FullName) }
            else { $bytes += $h.Length; $archivos++ }
        }
    }
    return [pscustomobject]@{ Bytes = $bytes; Archivos = $archivos; SinPermiso = $false }
}

function Nuevo-PuntoRestauracion {
    # Un punto de restauración permite deshacer desinstalaciones y cambios de registro desde
    # "Recuperación > Abrir Restaurar sistema". Windows solo crea uno cada 24 h por defecto.
    param([Parameter(Mandatory)][string]$Descripcion)
    Exigir-Administrador
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        $antes = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
        Checkpoint-Computer -Description $Descripcion -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue
        $despues = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
        if ($despues -gt $antes) { Escribir-Registro "Punto de restauración creado: $Descripcion" -Nivel OK; return $true }
        Escribir-Registro 'Windows no creó un punto nuevo (ya hay uno de las últimas 24 h). Se puede usar ese.' -Nivel AVISO
        return $true
    } catch {
        Escribir-Registro "No se pudo crear el punto de restauración: $($_.Exception.Message)" -Nivel ERROR
        return $false
    }
}

function Separar-Comando {
    # Divide una línea como "C:\Program Files\X\unins.exe" /S en ejecutable y argumentos.
    param([Parameter(Mandatory)][string]$Linea)
    $l = [Environment]::ExpandEnvironmentVariables($Linea.Trim())
    if ($l.StartsWith('"')) {
        $fin = $l.IndexOf('"', 1)
        if ($fin -gt 0) { return @($l.Substring(1, $fin - 1), $l.Substring($fin + 1).Trim()) }
    }
    $m = [regex]::Match($l, '^(.+?\.exe)(\s+.*)?$', 'IgnoreCase')
    if ($m.Success) { return @($m.Groups[1].Value, $m.Groups[2].Value.Trim()) }
    $partes = $l.Split(' ', 2)
    return @($partes[0], $(if ($partes.Count -gt 1) { $partes[1] } else { '' }))
}

function Obtener-ProgramasInstalados {
    # Lee las mismas claves que "Aplicaciones instaladas" de Configuración (64 bits, 32 bits y del usuario).
    $claves = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($c in $claves) {
        Get-ItemProperty -Path $c -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName } |
            ForEach-Object {
                [pscustomobject]@{
                    Nombre        = $_.DisplayName.Trim()
                    Editor        = $_.Publisher
                    Version       = $_.DisplayVersion
                    TamanoMB      = if ($_.EstimatedSize) { [math]::Round($_.EstimatedSize / 1024) } else { $null }
                    Instalado     = $_.InstallDate
                    Desinstalar   = $_.UninstallString
                    Silencioso    = $_.QuietUninstallString
                    CodigoMsi     = if ($_.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$' -and $_.UninstallString -match 'msiexec') { $_.PSChildName } else { $null }
                    Clave         = $_.PSPath
                }
            }
    }
}
