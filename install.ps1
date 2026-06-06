# install.ps1

$ErrorActionPreference = "Stop"

$ExeUrl = "https://github.com/Tunaa-11342/probable-engine/releases/download/v4.0.4/ADB-v4.0.4.exe"
$ExpectedSha256 = "sha256:90e2480e64b36089a12a521df13f519e462df942ee432157664360bf73e066f4" 

$AppName = "ADB-Patcher"
$TempDir = Join-Path $env:TEMP $AppName
$ExePath = Join-Path $TempDir "ADB-v4.0.4.exe"

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

Write-Host "Downloading..."
Invoke-WebRequest -Uri $ExeUrl -OutFile $ExePath -UseBasicParsing

if ($ExpectedSha256 -ne "") {
    Write-Host "Verifying SHA256..."
    $ActualSha256 = (Get-FileHash -Path $ExePath -Algorithm SHA256).Hash

    if ($ActualSha256.ToLower() -ne $ExpectedSha256.ToLower()) {
        Remove-Item -Path $ExePath -Force -ErrorAction SilentlyContinue
        throw "SHA256 mismatch. Download may be corrupted or replaced."
    }
}

Write-Host "Starting..."
Start-Process -FilePath $ExePath -Verb RunAs
