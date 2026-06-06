# install.ps1

$ErrorActionPreference = "Stop"

$ExeUrl = "https://github.com/Tunaa-11342/probable-engine/releases/download/v4.0.4/ADB-v4.0.4.exe"
$ExpectedSha256 = "90E2480E64B36089A12A521DF13F519E462DF942EE432157664360BF73E066F4" 

$AppName = "ADB-Patcher"
$TempDir = Join-Path $env:TEMP $AppName
$ExePath = Join-Path $TempDir "ADB-v4.0.4.exe"

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

Write-Host "Downloading..."
Invoke-WebRequest -Uri $ExeUrl -OutFile $ExePath -UseBasicParsing

if ($ExpectedSha256 -ne "") {
    Write-Host "Verifying SHA256..."
    $ActualSha256 = (Get-FileHash -Path $ExePath -Algorithm SHA256).Hash.Trim()
    $ExpectedSha256 = $ExpectedSha256.Trim()

    Write-Host "Expected: [$ExpectedSha256]"
    Write-Host "Actual:   [$ActualSha256]"
    Write-Host "ExePath:  [$ExePath]"
    Write-Host "Size:     $((Get-Item $ExePath).Length) bytes"

    if ($ActualSha256.ToUpperInvariant() -ne $ExpectedSha256.ToUpperInvariant()) {
        Remove-Item -Path $ExePath -Force -ErrorAction SilentlyContinue
        throw "SHA256 mismatch. Download may be corrupted or replaced."
    }
}

Write-Host "Starting..."
Start-Process -FilePath $ExePath -Verb RunAs
