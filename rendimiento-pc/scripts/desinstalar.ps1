<#
.SYNOPSIS
  Desinstala programas por nombre. Sin -Aplicar solo muestra lo que haría.

.DESCRIPTION
  Busca cada nombre en "Aplicaciones instaladas" (registro de Windows), sin rutas ni códigos fijos.
  Modo por defecto: abre el desinstalador de cada programa, uno por uno, para que la persona
  acepte o cancele en la ventana. Con -Silencioso usa la desinstalación sin ventanas cuando el
  programa la ofrece (MSI o QuietUninstallString); si no la ofrece, abre la ventana igual.

.PARAMETER Nombres
  Textos a buscar en el nombre del programa (ejemplo: "BlueStacks", "Epic Games Launcher").

.PARAMETER CerrarProcesos
  Nombres de procesos a cerrar antes (ejemplo: "HD-Player", "EpicGamesLauncher").

.EXAMPLE
  .\desinstalar.ps1 -Nombres BlueStacks, "Epic Games Launcher"            # simulación
  .\desinstalar.ps1 -Nombres BlueStacks -CerrarProcesos HD-Player -Aplicar
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Nombres,
    [string[]]$CerrarProcesos = @(),
    [switch]$Silencioso,
    [switch]$Aplicar,
    [int]$MinutosMaximos = 15
)

. (Join-Path $PSScriptRoot 'comun.ps1')
$Nombres = Dividir-Lista $Nombres
$CerrarProcesos = Dividir-Lista $CerrarProcesos
$registro = Iniciar-Registro 'desinstalar'
if (-not $Aplicar) { Escribir-Registro 'MODO SIMULACIÓN: no se desinstala nada. Agrega -Aplicar para hacerlo.' -Nivel SIMULACION }

$instalados = @(Obtener-ProgramasInstalados)
$codigos = @{
    0    = 'desinstalado'
    1605 = 'ya no estaba instalado'
    1614 = 'ya no estaba instalado'
    1641 = 'desinstalado; Windows se reiniciará'
    3010 = 'desinstalado; falta reiniciar'
    1602 = 'cancelado por la persona'
    1223 = 'cancelado por la persona'
}
$resumen = New-Object System.Collections.Generic.List[object]

foreach ($nombre in $Nombres) {
    $patron = [regex]::Escape($nombre)
    $encontrados = @($instalados | Where-Object { $_.Nombre -match $patron })
    if ($encontrados.Count -eq 0) {
        Escribir-Registro "'$nombre': no aparece en Aplicaciones instaladas (puede que ya no esté)." -Nivel AVISO
        $resumen.Add([pscustomobject]@{ Programa = $nombre; Resultado = 'no encontrado' }); continue
    }
    foreach ($p in $encontrados) {
        if ($p.CodigoMsi) {
            $exe = 'msiexec.exe'
            $args_ = if ($Silencioso) { "/x $($p.CodigoMsi) /qn /norestart" } else { "/x $($p.CodigoMsi) /norestart" }
        } elseif ($Silencioso -and $p.Silencioso) {
            $exe, $args_ = Separar-Comando $p.Silencioso
        } elseif ($p.Desinstalar) {
            $exe, $args_ = Separar-Comando $p.Desinstalar
        } else {
            Escribir-Registro "'$($p.Nombre)': Windows no tiene comando de desinstalación. Quítalo desde Configuración > Aplicaciones." -Nivel AVISO
            $resumen.Add([pscustomobject]@{ Programa = $p.Nombre; Resultado = 'sin desinstalador' }); continue
        }
        $modo = if ($Silencioso -and ($p.CodigoMsi -or $p.Silencioso)) { 'sin ventanas' } else { 'con ventana (acepta en el asistente)' }

        if (-not $Aplicar) {
            Escribir-Registro "Se desinstalaría '$($p.Nombre)' $($p.Version) [$modo]: $exe $args_" -Nivel SIMULACION
            $resumen.Add([pscustomobject]@{ Programa = $p.Nombre; Resultado = 'simulado' }); continue
        }
        if ($exe -ne 'msiexec.exe' -and -not (Test-Path -LiteralPath $exe)) {
            Escribir-Registro "'$($p.Nombre)': no existe el desinstalador $exe (instalación rota). Usa Configuración > Aplicaciones o la herramienta del fabricante." -Nivel ERROR
            $resumen.Add([pscustomobject]@{ Programa = $p.Nombre; Resultado = 'desinstalador no encontrado' }); continue
        }

        foreach ($proc in $CerrarProcesos) {
            Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
                Escribir-Registro "Cerrando proceso $($_.ProcessName) ($($_.Id))"
                $_ | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }

        Escribir-Registro "Desinstalando '$($p.Nombre)' [$modo]"
        try {
            $proceso = if ($args_) { Start-Process -FilePath $exe -ArgumentList $args_ -PassThru } else { Start-Process -FilePath $exe -PassThru }
            if (-not $proceso.WaitForExit($MinutosMaximos * 60000)) {
                Escribir-Registro "'$($p.Nombre)': sigue abierto tras $MinutosMaximos min. Revisa si hay una ventana esperando respuesta." -Nivel AVISO
                $resumen.Add([pscustomobject]@{ Programa = $p.Nombre; Resultado = 'sigue en curso' }); continue
            }
            $codigo = $proceso.ExitCode
            $texto = if ($codigos.ContainsKey($codigo)) { $codigos[$codigo] } else { "terminó con código $codigo" }
            # Varios desinstaladores (Inno Setup, NSIS) lanzan una copia de sí mismos y salen con 0 enseguida:
            # se confirma mirando si el programa sigue en la lista.
            Start-Sleep -Seconds 3
            $sigue = @(Obtener-ProgramasInstalados | Where-Object { $_.Clave -eq $p.Clave }).Count -gt 0
            if ($codigo -eq 0 -and $sigue) { $texto = 'el asistente sigue abierto o se canceló: aún aparece instalado' }
            $nivel = if ($sigue) { 'AVISO' } else { 'OK' }
            Escribir-Registro "'$($p.Nombre)': $texto" -Nivel $nivel
            $resumen.Add([pscustomobject]@{ Programa = $p.Nombre; Resultado = $texto })
        } catch {
            Escribir-Registro "'$($p.Nombre)': ERROR $($_.Exception.Message)" -Nivel ERROR
            $resumen.Add([pscustomobject]@{ Programa = $p.Nombre; Resultado = 'error' })
        }
    }
}

Write-Output ''
Write-Output ($resumen | Format-Table -AutoSize | Out-String)
Write-Output "Registro: $registro"
