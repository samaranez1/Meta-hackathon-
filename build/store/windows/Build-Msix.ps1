<#
.SYNOPSIS
    Packages the Windows export of Space Shooters as an MSIX for the Microsoft Store.
.DESCRIPTION
    1. Validates the Godot Windows export folder (needs space-shooters.exe + .pck).
    2. Generates Store image assets from SourceIcon.png (1024x1024 PNG) via System.Drawing.
    3. Stamps Package.appxmanifest tokens and builds the .msix with MakeAppx.exe.
    Requires: Windows 10/11 + Windows SDK (for MakeAppx.exe).
.EXAMPLE
    .\Build-Msix.ps1 -ExportDir ..\space-shooters-win -IdentityName "YourCompany.SpaceShooters" `
        -Publisher "CN=YourPublisher" -Version "1.0.1.0"
#>
param(
    [string]$ExportDir = "..\space-shooters-win",
    [string]$IdentityName = "__IDENTITY_NAME__",
    [string]$Publisher = "__PUBLISHER__",
    [string]$PublisherDisplay = "Your Publisher Name",
    [string]$Version = "1.0.0.0",
    [string]$SourceIcon = "SourceIcon.png",
    [string]$OutMsix = "..\SpaceShooters.msix"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Find-MakeAppx {
    $kits = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (Test-Path $kits) {
        $exe = Get-ChildItem -Path $kits -Recurse -Filter "makeappx.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    $cmd = Get-Command "makeappx.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function New-ResizedPng([string]$Src, [string]$Dst, [int]$W, [int]$H) {
    Add-Type -AssemblyName System.Drawing
    $srcImg = [System.Drawing.Image]::FromFile($Src)
    try {
        $bmp = New-Object System.Drawing.Bitmap($W, $H)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.Clear([System.Drawing.Color]::FromArgb(10, 10, 36))
            # Contain-fit the square icon.
            $s = [Math]::Min($W, $H)
            $x = [int](($W - $s) / 2); $y = [int](($H - $s) / 2)
            $g.DrawImage($srcImg, $x, $y, $s, $s)
        } finally { $g.Dispose() }
        $bmp.Save($Dst, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    } finally { $srcImg.Dispose() }
}

function New-SplashPng([string]$Src, [string]$Dst) {
    Add-Type -AssemblyName System.Drawing
    $srcImg = [System.Drawing.Image]::FromFile($Src)
    try {
        $bmp = New-Object System.Drawing.Bitmap(620, 300)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.Clear([System.Drawing.Color]::FromArgb(10, 10, 36))
            $g.DrawImage($srcImg, 30, 65, 170, 170)
            $font = New-Object System.Drawing.Font("Arial", 44, [System.Drawing.FontStyle]::Bold)
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 230, 255))
            try {
                $g.DrawString("SPACE", $font, $brush, 225, 70)
                $g.DrawString("SHOOTERS", $font, $brush, 225, 140)
            } finally { $font.Dispose(); $brush.Dispose() }
        } finally { $g.Dispose() }
        $bmp.Save($Dst, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    } finally { $srcImg.Dispose() }
}

# --- 1. Validate export ---
$ExportFull = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $ExportDir))
$exe = Get-ChildItem -Path $ExportFull -Filter "*.exe" | Select-Object -First 1
if (-not $exe) { throw "No .exe found in $ExportFull. Export the 'Windows Desktop' preset first." }
$pck = Get-ChildItem -Path $ExportFull -Filter "*.pck" | Select-Object -First 1
if (-not $pck) { Write-Warning "No .pck found next to $($exe.Name); continuing anyway." }
Write-Host "Export: $($exe.Name)" -ForegroundColor Green

# --- 2. Assets ---
$assets = Join-Path $ScriptDir "Assets"
New-Item -ItemType Directory -Force -Path $assets | Out-Null
$iconPath = Join-Path $ScriptDir $SourceIcon
if (-not (Test-Path $iconPath)) {
    throw "Missing $iconPath. Export icon.svg to a 1024x1024 PNG once (any browser/image tool can do this) and save it as $SourceIcon next to this script."
}
New-ResizedPng $iconPath (Join-Path $assets "StoreLogo.png") 50 50
New-ResizedPng $iconPath (Join-Path $assets "Square44x44Logo.png") 44 44
New-ResizedPng $iconPath (Join-Path $assets "Square150x150Logo.png") 150 150
New-ResizedPng $iconPath (Join-Path $assets "Square310x310Logo.png") 310 310
New-ResizedPng $iconPath (Join-Path $assets "Wide310x150Logo.png") 310 150
New-SplashPng $iconPath (Join-Path $assets "SplashScreen.png")
Write-Host "Assets generated in $assets" -ForegroundColor Green

# --- 3. Stage + manifest ---
$stage = Join-Path $ScriptDir "_stage"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $ExportFull "*") $stage -Recurse -Force
Copy-Item $assets (Join-Path $stage "Assets") -Recurse -Force
$manifest = Get-Content (Join-Path $ScriptDir "Package.appxmanifest") -Raw
$manifest = $manifest.Replace("__IDENTITY_NAME__", $IdentityName)
$manifest = $manifest.Replace("__PUBLISHER__", $Publisher)
$manifest = $manifest.Replace("__PUBLISHER_DISPLAY__", $PublisherDisplay)
$manifest = $manifest.Replace("__VERSION__", $Version)
$manifest = $manifest.Replace("__EXE_NAME__", $exe.Name)
$manifest | Set-Content (Join-Path $stage "AppxManifest.xml") -Encoding UTF8
if ($IdentityName.StartsWith("__") -or $Publisher.StartsWith("__")) {
    Write-Warning "Identity/Publisher still placeholders - fine for a local test MSIX, but Partner Center needs your real values."
}

# --- 4. Pack ---
$makeappx = Find-MakeAppx
if (-not $makeappx) { throw "makeappx.exe not found. Install the Windows SDK (https://developer.microsoft.com/windows/downloads/windows-sdk/) or use the MSIX Packaging Tool from the Store." }
$outFull = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $OutMsix))
& $makeappx pack /d $stage /p $outFull /nv | Out-Null
Write-Host "Built: $outFull" -ForegroundColor Green
Write-Host "Next: sign the MSIX (Partner Center signs Store submissions automatically; for sideload testing use signtool with a dev cert), then upload to Partner Center."
