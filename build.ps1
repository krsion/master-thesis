#!/usr/bin/env pwsh
# Build thesis on Windows
# Usage: .\build.ps1

$ErrorActionPreference = "Stop"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$buildDir = "build"

# Clean and create build dir
if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
New-Item -ItemType Directory $buildDir | Out-Null

Write-Host "Converting markdown to LaTeX..." -ForegroundColor Cyan

# Convert chapters
Get-ChildItem *.md | Where-Object { $_.Name -ne "README.md" } | ForEach-Object {
    $out = "$buildDir/$($_.BaseName).tex"
    & pandoc --top-level-division=chapter --listings --lua-filter crossref-gen.lua --lua-filter table-attr.lua --biblatex -f markdown -t latex --metadata-file=metadata.yaml -o $out $_.Name 2>&1 | ForEach-Object {
        if ($_ -notmatch "Deprecated") { Write-Host "  $_" -ForegroundColor Yellow }
    }
    Write-Host "  $($_.Name) -> $out" -ForegroundColor Green
}

# Build latex templates
Write-Host "Building LaTeX templates..." -ForegroundColor Cyan
Get-ChildItem latex_template\*.tex, latex_template\*.xmpdata | ForEach-Object {
    $out = "$buildDir/$($_.Name)"
    "" | & pandoc -t latex -o $out --metadata-file=metadata.yaml "--template=$($_.FullName)" 2>&1 | Out-Null
    Write-Host "  $($_.Name)" -ForegroundColor Green
}

# Copy supporting files
Write-Host "Copying resources..." -ForegroundColor Cyan
Copy-Item refs.bib $buildDir\ -Force
Copy-Item macros.tex $buildDir\ -Force
if (Test-Path img) {
    Copy-Item img $buildDir\ -Recurse -Force
} else {
    New-Item -ItemType Directory "$buildDir\img" | Out-Null
}
if (Test-Path latex_template\latex_img) {
    Copy-Item latex_template\latex_img $buildDir\ -Recurse -Force
}

# Run latexmk (multiple passes to resolve references and citations)
Write-Host "Running latexmk..." -ForegroundColor Cyan
Push-Location $buildDir
try {
    # First pass + bibtex
    & latexmk -pdflua -interaction=nonstopmode thesis 2>&1 | Out-Null
    # Force extra passes to resolve all cross-references
    & lualatex -interaction=nonstopmode thesis 2>&1 | Out-Null
    & lualatex -interaction=nonstopmode thesis 2>&1 | Out-Null
    if (Test-Path thesis.pdf) {
        $size = [math]::Round((Get-Item thesis.pdf).Length / 1024)
        Write-Host "`nSuccess! thesis.pdf ($size KB)" -ForegroundColor Green
    } else {
        Write-Host "`nFailed - no PDF generated. Check build/thesis.log" -ForegroundColor Red
    }
} finally {
    Pop-Location
}
