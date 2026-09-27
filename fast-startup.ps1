#requires -version 5.1

$ErrorActionPreference = "Continue"

# ============================================================
# CONFIG
# ============================================================

$DownloadRoot = Join-Path $env:LOCALAPPDATA "WindowsQuickSetup"
$UniKeyDir    = Join-Path $DownloadRoot "UniKey"

$Apps = @(
    @{
        Name     = "WinRAR"
        Type     = "exe"
        # Link từ WinRAR.es (hướng dẫn PowerShell chính thức), còn sống
        Url      = "https://www.rarlab.com/rar/winrar-x64-712es.exe"
        Args     = "/S"
        RegName  = "WinRAR"
    },
    @{
        Name     = "Zalo"
        Type     = "exe"
        Url      = "https://zalo.me/pc"
        Args     = "/S"
        RegName  = "Zalo"
    },
    @{
        Name     = "UniKey"
        Type     = "portable"
        Url      = "https://www.unikey.org/assets/release/unikey46RC2-230919-win64.zip"
        ExeName  = "UniKeyNT.exe"
        RegName  = "UniKey"
        DesktopShortcut = $true
        StartupWithWindows = $true
    },
    @{
        Name     = "UltraViewer"
        Type     = "exe"
        # Link tải trực tiếp từ ultraviewer.net, ổn định
        Url      = "https://www.ultraviewer.net/download/UltraViewer_setup_6.6.124_vi.exe"
        Args     = "/S"
        RegName  = "UltraViewer"
    },
    @{
        Name     = "Google Chrome"
        Type     = "exe"
        # Link Chrome standalone offline installer, chính thức
        Url      = "https://dl.google.com/chrome/install/standalone/ChromeStandaloneSetup64.exe"
        Args     = "/silent /install"
        RegName  = "Google Chrome"
    }
)

$TotalApps = $Apps.Count


# ============================================================
# UI
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
# TIMER
# ============================================================

function Format-Time {
    param ([TimeSpan]$Time)
    return $Time.ToString("hh\:mm\:ss")
}


# ============================================================
# CHECK INSTALLED (REGISTRY)
# ============================================================

function Test-AppInstalled {
    param ([string]$Name)

    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($p in $paths) {
        $found = Get-ItemProperty $p -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -and $_.DisplayName -like "*$Name*" }
        if ($found) { return $true }
    }
    return $false
}


# ============================================================
# SHORTCUT HELPERS
# ============================================================

function New-DesktopShortcut {
    param (
        [string]$TargetPath,
        [string]$ShortcutName,
        [string]$WorkingDir = ""
    )

    $Desktop = [Environment]::GetFolderPath("Desktop")
    $LnkPath = Join-Path $Desktop "$ShortcutName.lnk"

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($LnkPath)
    $Shortcut.TargetPath       = $TargetPath
    if ($WorkingDir) { $Shortcut.WorkingDirectory = $WorkingDir }
    $Shortcut.IconLocation     = "$TargetPath,0"
    $Shortcut.Save()

    return $LnkPath
}

function Add-StartupShortcut {
    param (
        [string]$TargetPath,
        [string]$ShortcutName,
        [string]$WorkingDir = ""
    )

    $Startup = [Environment]::GetFolderPath("Startup")
    $LnkPath = Join-Path $Startup "$ShortcutName.lnk"

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($LnkPath)
    $Shortcut.TargetPath = $TargetPath
    if ($WorkingDir) { $Shortcut.WorkingDirectory = $WorkingDir }
    $Shortcut.Save()

    return $LnkPath
}


# ============================================================
# INSTALL APP
# ============================================================

function Install-App {
    param (
        [hashtable]$App,
        [int]$Number
    )

    Write-Host ""
    Write-Line
    Write-Host "[$Number/$TotalApps] $($App.Name)" -ForegroundColor Cyan
    Write-Host "Type: $($App.Type)" -ForegroundColor DarkGray
    Write-Host ""

    # ---------- CHECK ----------
    Write-Host "[*] Checking..." -ForegroundColor Yellow
    if (Test-AppInstalled -Name $App.RegName) {
        Write-Host ""
        Write-Host "[=] Already installed - SKIPPED" -ForegroundColor Green
        return "SKIPPED"
    }
    Write-Host "[+] Not installed." -ForegroundColor Gray
    Write-Host ""

    # ---------- PORTABLE (UniKey) ----------
    if ($App.Type -eq "portable") {
        try {
            if (-not (Test-Path $UniKeyDir)) {
                New-Item -ItemType Directory -Path $UniKeyDir -Force | Out-Null
            }

            $ZipPath = Join-Path $env:TEMP "$($App.Name).zip"

            Write-Host "[>] Downloading $($App.Name)..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $App.Url -OutFile $ZipPath -UseBasicParsing -ErrorAction Stop

            Write-Host "[>] Extracting..." -ForegroundColor Cyan
            Expand-Archive -Path $ZipPath -DestinationPath $UniKeyDir -Force -ErrorAction Stop
            Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue

            $Exe = Get-ChildItem -Path $UniKeyDir -Filter $App.ExeName -Recurse -ErrorAction SilentlyContinue |
                   Select-Object -First 1

            if (-not $Exe) {
                throw "Không tìm thấy $($App.ExeName) sau khi giải nén."
            }

            $ExePath = $Exe.FullName
            $ExeDir  = $Exe.DirectoryName

            Write-Host "[+] Extracted to: $ExePath" -ForegroundColor Green

            if ($App.DesktopShortcut) {
                $lnk = New-DesktopShortcut -TargetPath $ExePath -ShortcutName $App.Name -WorkingDir $ExeDir
                Write-Host "[+] Desktop shortcut: $lnk" -ForegroundColor Green
            }

            if ($App.StartupWithWindows) {
                $lnk2 = Add-StartupShortcut -TargetPath $ExePath -ShortcutName $App.Name -WorkingDir $ExeDir
                Write-Host "[+] Startup shortcut: $lnk2" -ForegroundColor Green
            }

            Write-Host "[>] Launching $($App.Name)..." -ForegroundColor Cyan
            Start-Process -FilePath $ExePath -WorkingDirectory $ExeDir

            Write-Host ""
            Write-Host "[+] $($App.Name) - SUCCESS (portable)" -ForegroundColor Green
            return "SUCCESS"
        }
        catch {
            Write-Host ""
            Write-Host "[X] $($App.Name) - FAILED" -ForegroundColor Red
            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
            return "FAILED"
        }
    }

    # ---------- EXE INSTALLER ----------
    Write-Host "[>] Starting download / installation..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Please wait..." -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path $DownloadRoot)) {
        New-Item -ItemType Directory -Path $DownloadRoot -Force | Out-Null
    }

    $FileName = "$($App.Name -replace '\s','_')_setup.exe"
    $FilePath = Join-Path $DownloadRoot $FileName

    $StartTime = Get-Date

    try {
        Write-Host "[>] Downloading..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $App.Url -OutFile $FilePath -UseBasicParsing -ErrorAction Stop

        Write-Host "[>] Running installer..." -ForegroundColor Cyan

        $Proc = Start-Process -FilePath $FilePath -ArgumentList $App.Args -Wait -PassThru

        $EndTime = Get-Date
        $Elapsed = $EndTime - $StartTime

        Write-Host ""
        Write-Host "    Finished in $(Format-Time $Elapsed)" -ForegroundColor DarkGray

        if ($Proc.ExitCode -eq 0 -or $Proc.ExitCode -eq 3010) {
            Write-Host ""
            Write-Host "[+] $($App.Name) - SUCCESS" -ForegroundColor Green
            return "SUCCESS"
        }

        Write-Host ""
        Write-Host "[X] $($App.Name) - FAILED" -ForegroundColor Red
        Write-Host "    Exit code: $($Proc.ExitCode)" -ForegroundColor Red
        return "FAILED"
    }
    catch {
        $EndTime = Get-Date
        $Elapsed = $EndTime - $StartTime

        Write-Host ""
        Write-Host "[X] $($App.Name) - ERROR" -ForegroundColor Red
        Write-Host "    Time: $(Format-Time $Elapsed)" -ForegroundColor DarkGray
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        return "FAILED"
    }
    finally {
        Remove-Item $FilePath -Force -ErrorAction SilentlyContinue
    }
}


# ============================================================
# PROGRESS
# ============================================================

function Show-OverallProgress {
    param ([int]$Current, [int]$Total)
    if ($Total -le 0) { return }

    $Percent = [math]::Floor(($Current / $Total) * 100)
    $Width   = 40
    $Filled  = [math]::Floor(($Percent / 100) * $Width)
    $Empty   = $Width - $Filled
    $Bar     = ("#" * $Filled) + ("-" * $Empty)

    Write-Host ""
    Write-Host "Overall: [$Bar] $Percent%  ($Current/$Total)" -ForegroundColor Cyan
}


# ============================================================
# POST SETUP
# ============================================================

function Start-PostSetupCMD {
    param ([string]$CmdUrl)
    if ([string]::IsNullOrWhiteSpace($CmdUrl)) { return }

    Write-Host ""
    Write-Line
    Write-Host "              POST SETUP" -ForegroundColor Cyan
    Write-Line
    Write-Host ""

    $TempCmd = Join-Path $env:TEMP "windows-quick-setup-post.cmd"

    Write-Host "[>] Downloading post-setup.cmd..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $CmdUrl -OutFile $TempCmd -UseBasicParsing -ErrorAction Stop
        Write-Host "[+] CMD downloaded." -ForegroundColor Green
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
        $Process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$TempCmd`"" -Wait -PassThru
        if ($Process.ExitCode -eq 0) {
            Write-Host ""
            Write-Host "[+] post-setup.cmd completed." -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "[X] post-setup.cmd exit code $($Process.ExitCode)." -ForegroundColor Red
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

    $Results  = @()
    $Current  = 0
    $SetupStart = Get-Date

    foreach ($App in $Apps) {
        $Current++
        Show-OverallProgress -Current ($Current - 1) -Total $TotalApps
        $Status = Install-App -App $App -Number $Current
        $Results += [PSCustomObject]@{ Name = $App.Name; Status = $Status }
        Show-OverallProgress -Current $Current -Total $TotalApps
    }

    # POST SETUP
    $PostSetupUrl = "https://raw.githubusercontent.com/Tunaa-11342/probable-engine/refs/heads/main/active.cmd"
    Start-PostSetupCMD -CmdUrl $PostSetupUrl

    $SetupEnd  = Get-Date
    $TotalTime = $SetupEnd - $SetupStart

    # SUMMARY
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

    $SuccessCount = @($Results | Where-Object { $_.Status -eq "SUCCESS" }).Count
    $SkippedCount = @($Results | Where-Object { $_.Status -eq "SKIPPED" }).Count
    $FailedCount  = @($Results | Where-Object { $_.Status -eq "FAILED"  }).Count

    Write-Line
    Write-Host "Total time : $(Format-Time $TotalTime)" -ForegroundColor White
    Write-Host "Installed  : $SuccessCount" -ForegroundColor Green
    Write-Host "Skipped    : $SkippedCount" -ForegroundColor Yellow
    Write-Host "Failed     : $FailedCount"  -ForegroundColor Red
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
        "1" { Start-QuickSetup }
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
