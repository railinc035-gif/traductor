param(
    [string]$Root = $PSScriptRoot,
    [switch]$NoWatch
)

$ErrorActionPreference = "Continue"
if ($Root) {
    $Root = [IO.Path]::GetFullPath($Root)
}

function Get-OutputName([string]$File) {
    $relative = [IO.Path]::GetRelativePath($Root, $File)
    $dir = Split-Path $relative -Parent
    $base = [IO.Path]::GetFileNameWithoutExtension($relative)

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($dir -and $dir -ne ".") {
        $parts.AddRange(($dir -split '[\\/]'))
    }
    $parts.Add($base)

    $name = ($parts -join "_") -replace '[^a-zA-Z0-9_-]', "_"
    return $name
}

function Escape-Html([string]$s) {
    return [System.Net.WebUtility]::HtmlEncode($s)
}

function Translate-Rin([string]$File, [string]$Name) {
    $lines = [System.IO.File]::ReadAllLines($File)
    $body = [System.Text.StringBuilder]::new()
    $title = $Name

    switch -Regex ($lines) {
        '^\s*$' { continue }
        '^\s*#' { continue }
        '^\s*TITULO\s+"(.*)"$' {
            $title = $Matches[1]
            continue
        }
        '^\s*ENCABEZADO\s+([1-6])\s*\|\s*"(.*)"$' {
            [void]$body.AppendLine("<h$($Matches[1])>$($Matches[2])</h$($Matches[1])>")
            continue
        }
        '^\s*TEXTO_ID\s+(\w+)\s*\|\s*"(.*)"$' {
            [void]$body.AppendLine("<p id=`"$($Matches[1])`">$($Matches[2])</p>")
            continue
        }
        '^\s*TEXTO\s+"(.*)"$' {
            [void]$body.AppendLine("<p>$($Matches[1])</p>")
            continue
        }
        '^\s*ENTRADA\s+(\w+)\s*\|\s*"(.*)"$' {
            [void]$body.AppendLine("<input id=`"$($Matches[1])`" value=`"$($Matches[2])`" />")
            continue
        }
        '^\s*BOTON\s+(\w+)\s*\|\s*"(.*)"$' {
            [void]$body.AppendLine("<button id=`"$($Matches[1])`" type=`"button`">$($Matches[2])</button>")
            continue
        }
        '^\s*IMAGEN\s+(\S+)$' {
            [void]$body.AppendLine("<img src=`"$($Matches[1])`" alt=`"Imagen`" />")
            continue
        }
        '^\s*ENLACE\s+"?([^"\s|]+)"?\s*\|\s*"(.*)"$' {
            [void]$body.AppendLine("<a href=`"$($Matches[1])`">$($Matches[2])</a>")
            continue
        }
        '^\s*LINEA$' {
            [void]$body.AppendLine("<hr />")
            continue
        }
        default {
            Write-Host "Aviso .rin: comando no reconocido: $_" -ForegroundColor Yellow
        }
    }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$title</title>
</head>
<body>
$($body.ToString().TrimEnd())
</body>
</html>
"@

    return $html
}

function Translate-File([string]$File) {
    $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
    if ($ext -ne ".rin") {
        return
    }

    $name = Get-OutputName $File
    $output = Join-Path $Root ($name + ".html")

    try {
        $content = Translate-Rin $File $name
        [IO.File]::WriteAllText($output, [string]$content, [Text.UTF8Encoding]::new($false))
        Write-Host "Traducido: $([IO.Path]::GetFileName($File)) -> $([IO.Path]::GetFileName($output))" -ForegroundColor Green
    }
    catch {
        Write-Host "Error al traducir $File : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "       CHX - TRADUCTOR ACTIVO      " -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Carpeta principal: $Root"
Write-Host "Busca archivos .rin en las subcarpetas."
Write-Host "Los resultados (.html) se guardan aquí, junto al traductor."
if (-not $NoWatch) {
    Write-Host "Deja esta ventana abierta. Pulsa Ctrl+C para detener."
}
Write-Host ""

# Traducir todos los archivos .rin existentes al iniciar.
Get-ChildItem -LiteralPath $Root -Recurse -File |
    Where-Object {
        $_.Extension.ToLowerInvariant() -eq ".rin"
    } |
    ForEach-Object { Translate-File $_.FullName }

if ($NoWatch) {
    return
}

# Vigilar las subcarpetas en busca de cambios.
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $Root
$watcher.Filter = "*.*"
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
$watcher.EnableRaisingEvents = $true

$lastEvents = [System.Collections.Concurrent.ConcurrentDictionary[string, datetime]]::new()

$action = {
    $path = $Event.SourceEventArgs.FullPath

    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($ext -eq ".rin") {
        $now = [datetime]::Now
        $lastTime = [datetime]::MinValue
        if ($lastEvents.TryGetValue($path, [ref]$lastTime)) {
            if (($now - $lastTime).TotalMilliseconds -lt 200) {
                return
            }
        }
        $lastEvents[$path] = $now

        Start-Sleep -Milliseconds 100
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Translate-File $path
        }
    }
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null
Register-ObjectEvent $watcher Renamed -Action $action | Out-Null

while ($true) {
    Start-Sleep -Milliseconds 500
}
