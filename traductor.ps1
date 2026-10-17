
param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = "Continue"
$Root = [IO.Path]::GetFullPath($Root)

function Get-OutputName([string]$File) {
    $relative = [IO.Path]::GetRelativePath($Root, $File)
    $dir = Split-Path $relative -Parent
    $base = [IO.Path]::GetFileNameWithoutExtension($relative)

    $parts = @()
    if ($dir -and $dir -ne ".") {
        $parts += ($dir -split '[\\/]')
    }
    $parts += $base

    $name = ($parts -join "_") -replace '[^a-zA-Z0-9_-]', "_"
    return $name
}

function Escape-Html([string]$s) {
    return [System.Net.WebUtility]::HtmlEncode($s)
}

function Translate-Cha([string]$File, [string]$Name) {
    $lines = Get-Content -LiteralPath $File
    $body = New-Object System.Collections.Generic.List[string]
    $title = $Name

    foreach ($line in $lines) {
        $s = $line.Trim()
        if (!$s -or $s.StartsWith("#")) { continue }

        if ($s -match '^TITULO\s+"(.*)"$') {
            $title = $Matches[1]
        }
        elseif ($s -match '^ENCABEZADO\s+([1-6])\s*\|\s*"(.*)"$') {
            $n = $Matches[1]
            $body.Add("<h$n>$($Matches[2])</h$n>")
        }
        elseif ($s -match '^TEXTO_ID\s+(\w+)\s*\|\s*"(.*)"$') {
            $id = $Matches[1]
            $value = $Matches[2]
            $body.Add("<p id=`"$id`">$value</p>")
        }
        elseif ($s -match '^TEXTO\s+"(.*)"$') {
            $body.Add("<p>$($Matches[1])</p>")
        }
        elseif ($s -match '^ENTRADA\s+(\w+)\s*\|\s*"(.*)"$') {
            $id = $Matches[1]
            $value = $Matches[2]
            $body.Add("<input id=`"$id`" value=`"$value`" />")
        }
        elseif ($s -match '^BOTON\s+(\w+)\s*\|\s*"(.*)"$') {
            $id = $Matches[1]
            $label = $Matches[2]
            $body.Add("<button id=`"$id`" type=`"button`">$label</button>")
        }
        elseif ($s -match '^IMAGEN\s+(\S+)$') {
            $body.Add("<img src=`"$($Matches[1])`" alt=`"Imagen`" />")
        }
        elseif ($s -match '^ENLACE\s+"(.*)"\s*\|\s*"(.*)"$') {
            $url = $Matches[1]
            $label = $Matches[2]
            $body.Add("<a href=`"$url`">$label</a>")
        }
        elseif ($s -match '^LINEA$') {
            $body.Add("<hr />")
        }
        else {
            Write-Host "Aviso .cha: comando no reconocido: $s" -ForegroundColor Yellow
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
$($body -join "`r`n")
<script src="$jsName"></script>
</body>
</html>
"@

    return $html
}

function Translate-Chb([string]$File) {
    $lines = Get-Content -LiteralPath $File
    $js = New-Object System.Collections.Generic.List[string]

    $js.Add("'use strict';")
    $js.Add("document.addEventListener('DOMContentLoaded', function () {")

    foreach ($line in $lines) {
        $s = $line.Trim()
        if (!$s -or $s.StartsWith("#")) { continue }

        if ($s -match '^AVISAR\s+"(.*)"$') {
            $msg = $Matches[1].Replace("\", "\\").Replace("'", "\'")
            $js.Add("alert('$msg');")
        }
        elseif ($s -match '^CONSOLA\s+"(.*)"$') {
            $msg = $Matches[1].Replace("\", "\\").Replace("'", "\'")
            $js.Add("console.log('$msg');")
        }
        elseif ($s -match '^ESPERAR\s+(\d+)$') {
            $ms = [int]$Matches[1]
            $js.Add("setTimeout(function () { console.log('CHX: espera terminada'); }, $ms);")
        }
        elseif ($s -match '^AL_CLIC\s+(\w+)\s*\|\s*"([^"]*)"$') {
            $id = $Matches[1]
            $msg = $Matches[2].Replace("\", "\\").Replace("'", "\'")
            $js.Add("document.getElementById('$id')?.addEventListener('click', function () { alert('$msg'); });")
        }
        elseif ($s -match '^CALCULADORA\s+(\w+)\s*\|\s*(\w+)\s*\|\s*(\w+)$') {
            $a = $Matches[1]; $b = $Matches[2]; $r = $Matches[3]
            $js.Add("const chxA = document.getElementById('$a');")
            $js.Add("const chxB = document.getElementById('$b');")
            $js.Add("const chxR = document.getElementById('$r');")
        }
        elseif ($s -match '^OPERACION\s+(\w+)\s*\|\s*([+\-*/])$') {
            $id = $Matches[1]
            $op = $Matches[2]
            $expr = switch ($op) {
                "+" { "a + b" }
                "-" { "a - b" }
                "*" { "a * b" }
                "/" { "a / b" }
            }
            $js.Add(@"
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
        }
        elseif ($s -match '^LIMPIAR\s+(\w+)\s*\|\s*(.+)$') {
            $button = $Matches[1]
            $ids = $Matches[2] -split ','
            $safeIds = @()
            foreach ($id in $ids) {
                $safeIds += "'" + $id.Trim() + "'"
            }
            $list = $safeIds -join ","
            $js.Add("document.getElementById('$button')?.addEventListener('click', function () {")
            $js.Add("[$list].forEach(function(id) { const el = document.getElementById(id); if (el) { if ('value' in el) el.value = ''; else el.textContent = '0'; } });")
            $js.Add("});")
        }
        else {
            Write-Host "Aviso .chb: comando no reconocido: $s" -ForegroundColor Yellow
        }
    }

    $js.Add("});")
    return ($js -join "`r`n")
}

function Translate-Chc([string]$File) {
    $lines = Get-Content -LiteralPath $File
    $css = New-Object System.Collections.Generic.List[string]
    $css.Add("body { font-family: Arial, sans-serif; padding: 20px; }")

    foreach ($line in $lines) {
        $s = $line.Trim()
        if (!$s -or $s.StartsWith("#")) { continue }

        if ($s -match '^FONDO\s+"?([^"]+)"?$') {
            $css.Add("body { background: $($Matches[1]); }")
        }
        elseif ($s -match '^COLOR\s+"?([^"]+)"?$') {
            $css.Add("body { color: $($Matches[1]); }")
        }
        elseif ($s -match '^TIPO_LETRA\s+"(.*)"$') {
            $css.Add("body { font-family: '$($Matches[1])', sans-serif; }")
        }
        elseif ($s -match '^TAMANO_TEXTO\s+(\d+)$') {
            $css.Add("body { font-size: $($Matches[1])px; }")
        }
        elseif ($s -match '^BOTONES_FONDO\s+"?([^"]+)"?$') {
            $css.Add("button { background: $($Matches[1]); }")
        }
        elseif ($s -match '^BOTONES_COLOR\s+"?([^"]+)"?$') {
            $css.Add("button { color: $($Matches[1]); }")
        }
        elseif ($s -match '^MARGEN\s+(\d+)$') {
            $css.Add("body { margin: $($Matches[1])px; }")
        }
        else {
            Write-Host "Aviso .chc: comando no reconocido: $s" -ForegroundColor Yellow
        }
    }

    $css.Add("button { padding: 8px 14px; margin: 4px; cursor: pointer; }")
    $css.Add("input { padding: 8px; margin: 4px; max-width: 100%; }")
    return ($css -join "`r`n")
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
Write-Host "Deja esta ventana abierta. Pulsa Ctrl+C para detener."
Write-Host ""

# Traducir todos los archivos existentes al iniciar.
Get-ChildItem -LiteralPath $Root -Recurse -File |
    Where-Object {
        @(".cha", ".chb", ".chc") -contains $_.Extension.ToLowerInvariant()
    } |
    ForEach-Object { Translate-File $_.FullName }

# Vigilar las subcarpetas en busca de cambios.
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $Root
$watcher.Filter = "*.*"
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
$watcher.EnableRaisingEvents = $true

$action = {
    $path = $Event.SourceEventArgs.FullPath
    $change = $Event.SourceEventArgs.ChangeType

    if (@(".cha", ".chb", ".chc") -contains [IO.Path]::GetExtension($path).ToLowerInvariant()) {
        Start-Sleep -Milliseconds 300
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Translate-File $path
        }
    }
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null
Register-ObjectEvent $watcher Renamed -Action $action | Out-Null

while ($true) {
    Wait-Event -Timeout 1 | Out-Null
}
