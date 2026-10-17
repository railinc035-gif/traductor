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

function Translate-Cha([string]$File, [string]$Name) {
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
            Write-Host "Aviso .cha: comando no reconocido: $_" -ForegroundColor Yellow
        }
    }

    $cssName = "$Name.css"
    $jsName = "$Name.js"

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$title</title>
<link rel="stylesheet" href="$cssName">
</head>
<body>
$($body.ToString().TrimEnd())
<script src="$jsName"></script>
</body>
</html>
"@

    return $html
}

function Translate-Chb([string]$File) {
    $lines = [System.IO.File]::ReadAllLines($File)
    $js = [System.Text.StringBuilder]::new()

    [void]$js.AppendLine("'use strict';")
    [void]$js.AppendLine("document.addEventListener('DOMContentLoaded', function () {")

    switch -Regex ($lines) {
        '^\s*$' { continue }
        '^\s*#' { continue }
        '^\s*AVISAR\s+"(.*)"$' {
            $msg = $Matches[1].Replace("\", "\\").Replace("'", "\'")
            [void]$js.AppendLine("alert('$msg');")
            continue
        }
        '^\s*CONSOLA\s+"(.*)"$' {
            $msg = $Matches[1].Replace("\", "\\").Replace("'", "\'")
            [void]$js.AppendLine("console.log('$msg');")
            continue
        }
        '^\s*ESPERAR\s+(\d+)$' {
            $ms = [int]$Matches[1]
            [void]$js.AppendLine("setTimeout(function () { console.log('CHX: espera terminada'); }, $ms);")
            continue
        }
        '^\s*AL_CLIC\s+(\w+)\s*\|\s*"([^"]*)"$' {
            $id = $Matches[1]
            $msg = $Matches[2].Replace("\", "\\").Replace("'", "\'")
            [void]$js.AppendLine("document.getElementById('$id')?.addEventListener('click', function () { alert('$msg'); });")
            continue
        }
        '^\s*CALCULADORA\s+(\w+)\s*\|\s*(\w+)\s*\|\s*(\w+)$' {
            $a = $Matches[1]; $b = $Matches[2]; $r = $Matches[3]
            [void]$js.AppendLine("const chxA = document.getElementById('$a');")
            [void]$js.AppendLine("const chxB = document.getElementById('$b');")
            [void]$js.AppendLine("const chxR = document.getElementById('$r');")
            continue
        }
        '^\s*OPERACION\s+(\w+)\s*\|\s*([+\-*/])$' {
            $id = $Matches[1]
            $op = $Matches[2]
            $expr = switch ($op) {
                "+" { "a + b" }
                "-" { "a - b" }
                "*" { "a * b" }
                "/" { "a / b" }
            }
            [void]$js.AppendLine(@"
document.getElementById('$id')?.addEventListener('click', function () {
    const a = Number(chxA?.value);
    const b = Number(chxB?.value);
    if (!chxA || !chxB || !chxR || !Number.isFinite(a) || !Number.isFinite(b)) {
        alert('Introduce dos números válidos.');
        return;
    }
    if ('$op' === '/' && b === 0) {
        chxR.textContent = 'No se puede dividir entre cero';
        return;
    }
    chxR.textContent = $expr;
});
"@)
            continue
        }
        '^\s*LIMPIAR\s+(\w+)\s*\|\s*(.+)$' {
            $button = $Matches[1]
            $ids = $Matches[2] -split ','
            $safeIds = foreach ($id in $ids) {
                "'" + $id.Trim() + "'"
            }
            $list = $safeIds -join ","
            [void]$js.AppendLine("document.getElementById('$button')?.addEventListener('click', function () {")
            [void]$js.AppendLine("[$list].forEach(function(id) { const el = document.getElementById(id); if (el) { if ('value' in el) el.value = ''; else el.textContent = '0'; } });")
            [void]$js.AppendLine("});")
            continue
        }
        default {
            Write-Host "Aviso .chb: comando no reconocido: $_" -ForegroundColor Yellow
        }
    }

    [void]$js.AppendLine("});")
    return $js.ToString()
}

function Translate-Chc([string]$File) {
    $lines = [System.IO.File]::ReadAllLines($File)
    $css = [System.Text.StringBuilder]::new()
    [void]$css.AppendLine("body { font-family: Arial, sans-serif; padding: 20px; }")

    switch -Regex ($lines) {
        '^\s*$' { continue }
        '^\s*#' { continue }
        '^\s*FONDO\s+"?([^"]+)"?$' {
            [void]$css.AppendLine("body { background: $($Matches[1]); }")
            continue
        }
        '^\s*COLOR\s+"?([^"]+)"?$' {
            [void]$css.AppendLine("body { color: $($Matches[1]); }")
            continue
        }
        '^\s*TIPO_LETRA\s+"?(.*?)"?$' {
            [void]$css.AppendLine("body { font-family: '$($Matches[1])', sans-serif; }")
            continue
        }
        '^\s*TAMANO_TEXTO\s+(\d+)$' {
            [void]$css.AppendLine("body { font-size: $($Matches[1])px; }")
            continue
        }
        '^\s*BOTONES_FONDO\s+"?([^"]+)"?$' {
            [void]$css.AppendLine("button { background: $($Matches[1]); }")
            continue
        }
        '^\s*BOTONES_COLOR\s+"?([^"]+)"?$' {
            [void]$css.AppendLine("button { color: $($Matches[1]); }")
            continue
        }
        '^\s*MARGEN\s+(\d+)$' {
            [void]$css.AppendLine("body { margin: $($Matches[1])px; }")
            continue
        }
        default {
            Write-Host "Aviso .chc: comando no reconocido: $_" -ForegroundColor Yellow
        }
    }

    [void]$css.AppendLine("button { padding: 8px 14px; margin: 4px; cursor: pointer; }")
    [void]$css.AppendLine("input { padding: 8px; margin: 4px; max-width: 100%; }")
    return $css.ToString()
}

function Translate-File([string]$File) {
    $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
    $name = Get-OutputName $File
    $outExt = switch ($ext) {
        ".cha" { ".html" }
        ".chb" { ".js" }
        ".chc" { ".css" }
        default { return }
    }

    $output = Join-Path $Root ($name + $outExt)

    try {
        $content = switch ($ext) {
            ".cha" { Translate-Cha $File $name }
            ".chb" { Translate-Chb $File }
            ".chc" { Translate-Chc $File }
        }
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
Write-Host "Busca .cha, .chb y .chc en las subcarpetas."
Write-Host "Los resultados se guardan aquí, junto al traductor."
if (-not $NoWatch) {
    Write-Host "Deja esta ventana abierta. Pulsa Ctrl+C para detener."
}
Write-Host ""

# Traducir todos los archivos existentes al iniciar.
Get-ChildItem -LiteralPath $Root -Recurse -File |
    Where-Object {
        @(".cha", ".chb", ".chc") -contains $_.Extension.ToLowerInvariant()
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
    if (@(".cha", ".chb", ".chc") -contains $ext) {
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
