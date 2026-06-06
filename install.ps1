$ErrorActionPreference = "Stop"

$ExeUrl = "https://github.com/OWNER/REPO/releases/download/TAG/FILE.exe"
$ExpectedSha256 = ""

$AppName = "tuna-tool"
$FileName = "FILE.exe"

$TempDir = Join-Path $env:TEMP $AppName
$ExePath = Join-Path $TempDir $FileName

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

Write-Host "Downloading $AppName..."
Invoke-WebRequest -Uri $ExeUrl -OutFile $ExePath -UseBasicParsing

if ($ExpectedSha256 -ne "") {
    Write-Host "Verifying SHA256..."
    $ActualSha256 = (Get-FileHash -Path $ExePath -Algorithm SHA256).Hash

    if ($ActualSha256.ToLower() -ne $ExpectedSha256.ToLower()) {
        Remove-Item -Path $ExePath -Force -ErrorAction SilentlyContinue
        throw "SHA256 mismatch."
    }
}

Write-Host "Starting $AppName..."
Start-Process -FilePath $ExePath -Verb RunAs
