#requires -version 5.1

$ErrorActionPreference = "Continue"

# ============================================================
# CONFIG
# ============================================================

$DownloadRoot = Join-Path $env:LOCALAPPDATA "WindowsQuickSetup"
$UniKeyDir    = Join-Path $DownloadRoot "UniKey"

# ---- GitHub Releases base URL (ONLINE) ----
$GhBase = "https://github.com/Tunaa-11342/probable-engine/releases/download/v5.0.5"

# ---- OFFLINE: tên thư mục chứa bộ cài trên USB ----
$OfflineFolderName = "app can cai"

# Post-setup cmd (dùng cho cả online & offline)
$PostSetupUrl = "https://raw.githubusercontent.com/Tunaa-11342/probable-engine/refs/heads/main/active.cmd"

$Apps = @(
    @{
        Name     = "WinRAR"
        Type     = "exe"
        FileName = "winrar-x64-723.exe"
        Url      = "$GhBase/winrar-x64-723.exe"
        Args     = "/S"
        RegName  = "WinRAR"
    },
    @{
        Name     = "Zalo"
        Type     = "exe"
        FileName = "ZaloSetup-26.8.20.exe"
        Url      = "$GhBase/ZaloSetup-26.9.10.exe"
        Args     = "/S"
        RegName  = "Zalo"
    },
    @{
        Name     = "UniKey"
        Type     = "exe-portable"
        FileName = "UniKeyNT.exe"
        Url      = "$GhBase/UniKeyNT.exe"
        ExeName  = "UniKeyNT.exe"
        RegName  = "UniKey"
        DesktopShortcut    = $true
        StartupWithWindows = $true
    },
    @{
        Name     = "UltraViewer"
        Type     = "exe"
        FileName = "UltraViewer_setup_6.6.133_vi.exe"
        Url      = "$GhBase/UltraViewer_setup_6.6.133_vi.exe"
        Args     = "/S"
        RegName  = "UltraViewer"
    },
    @{
        Name     = "Google Chrome"
        Type     = "exe"
        FileName = "ChromeSetup.exe"
        Url      = "$GhBase/ChromeSetup.exe"
        Args     = "/silent /install"
        RegName  = "Google Chrome"
    }
)

$TotalApps = $Apps.Count


# ============================================================
# TÌM THƯ MỤC OFFLINE TRÊN USB (auto-detect ổ đĩa)
# ============================================================

function Find-OfflineDir {
    param ([string]$FolderName)

    # Quét D: -> Z:, bỏ qua C: (hệ thống)
    $Drives = 68..90 | ForEach-Object { "$([char]$_)`:\" }

    foreach ($Drive in $Drives) {
        if (-not (Test-Path $Drive)) { continue }

        $Candidate = Join-Path $Drive $FolderName
        if (Test-Path $Candidate) {
            # Xác nhận có ít nhất 1 file .exe trong đó
            $HasExe = Get-ChildItem -Path $Candidate -Filter *.exe -ErrorAction SilentlyContinue |
                      Select-Object -First 1
            if ($HasExe) {
                return $Candidate
            }
        }
    }
    return $null
}


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
    Write-Host " [1] 1 Click Setup Online"  -ForegroundColor White
    Write-Host " [2] 1 Click Setup Offline" -ForegroundColor White
    Write-Host " [0] Exit"                  -ForegroundColor White
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

    $Desktop  = [Environment]::GetFolderPath("Desktop")
    $LnkPath  = Join-Path $Desktop "$ShortcutName.lnk"

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($LnkPath)
    $Shortcut.TargetPath   = $TargetPath
    if ($WorkingDir) { $Shortcut.WorkingDirectory = $WorkingDir }
    $Shortcut.IconLocation = "$TargetPath,0"
    $Shortcut.Save()

    return $LnkPath
}

function Add-StartupShortcut {
    param (
        [string]$TargetPath,
        [string]$ShortcutName,
        [string]$WorkingDir = ""
    )

    $Startup  = [Environment]::GetFolderPath("Startup")
    $LnkPath  = Join-Path $Startup "$ShortcutName.lnk"

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
        [int]$Number,
        [string]$OfflineSourceDir = ""   # rỗng = chạy online
    )

    $IsOffline = -not [string]::IsNullOrWhiteSpace($OfflineSourceDir)

    Write-Host ""
    Write-Line
    Write-Host "[$Number/$TotalApps] $($App.Name)" -ForegroundColor Cyan
    Write-Host "Type: $($App.Type)  |  Mode: $(if ($IsOffline) {'OFFLINE'} else {'ONLINE'})" -ForegroundColor DarkGray
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

    # ---------- EXE-PORTABLE (UniKey) ----------
    if ($App.Type -eq "exe-portable") {
        try {
            if (-not (Test-Path $UniKeyDir)) {
                New-Item -ItemType Directory -Path $UniKeyDir -Force | Out-Null
            }

            $ExePath = Join-Path $UniKeyDir $App.ExeName

            if ($IsOffline) {
                $SrcExe = Join-Path $OfflineSourceDir $App.FileName
                if (-not (Test-Path $SrcExe)) {
                    throw "Không tìm thấy file offline: $SrcExe"
                }
                Write-Host "[>] Copying $($App.Name) from USB..." -ForegroundColor Cyan
                Copy-Item -Path $SrcExe -Destination $ExePath -Force
                Write-Host "[+] Copied to: $ExePath" -ForegroundColor Green
            }
            else {
                Write-Host "[>] Downloading $($App.Name)..." -ForegroundColor Cyan
                Invoke-WebRequest -Uri $App.Url -OutFile $ExePath -UseBasicParsing -ErrorAction Stop
                Write-Host "[+] Saved to: $ExePath" -ForegroundColor Green
            }

            if ($App.DesktopShortcut) {
                $lnk = New-DesktopShortcut -TargetPath $ExePath -ShortcutName $App.Name -WorkingDir $UniKeyDir
                Write-Host "[+] Desktop shortcut: $lnk" -ForegroundColor Green
            }

            if ($App.StartupWithWindows) {
                $lnk2 = Add-StartupShortcut -TargetPath $ExePath -ShortcutName $App.Name -WorkingDir $UniKeyDir
                Write-Host "[+] Startup shortcut: $lnk2" -ForegroundColor Green
            }

            Write-Host "[>] Launching $($App.Name)..." -ForegroundColor Cyan
            Start-Process -FilePath $ExePath -WorkingDirectory $UniKeyDir

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
    if (-not (Test-Path $DownloadRoot)) {
        New-Item -ItemType Directory -Path $DownloadRoot -Force | Out-Null
    }

    $TempFileName = "$($App.Name -replace '\s','_')_setup.exe"
    $FilePath     = Join-Path $DownloadRoot $TempFileName

    $StartTime = Get-Date

    try {
        if ($IsOffline) {
            $SrcExe = Join-Path $OfflineSourceDir $App.FileName
            if (-not (Test-Path $SrcExe)) {
                throw "Không tìm thấy file offline: $SrcExe"
            }
            Write-Host "[>] Copying installer from USB..." -ForegroundColor Cyan
            Copy-Item -Path $SrcExe -Destination $FilePath -Force
            Write-Host "[+] Ready: $FilePath" -ForegroundColor Green
        }
        else {
            Write-Host "[>] Downloading..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $App.Url -OutFile $FilePath -UseBasicParsing -ErrorAction Stop
        }

        Write-Host "[>] Running installer..." -ForegroundColor Cyan
        Write-Host ""

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

    Write-Host "[>] Downloading active.cmd..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $CmdUrl -OutFile $TempCmd -UseBasicParsing -ErrorAction Stop
        Write-Host "[+] CMD downloaded." -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "[X] Failed to download active.cmd" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "[>] Running active.cmd..." -ForegroundColor Cyan
    Write-Host ""
    try {
        $Process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$TempCmd`"" -Wait -PassThru
        if ($Process.ExitCode -eq 0) {
            Write-Host ""
            Write-Host "[+] active.cmd completed." -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "[X] active.cmd exit code $($Process.ExitCode)." -ForegroundColor Red
        }
    }
    catch {
        Write-Host ""
        Write-Host "[X] Failed to execute active.cmd" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Remove-Item $TempCmd -Force -ErrorAction SilentlyContinue
}


# ============================================================
# QUICK SETUP (ONLINE / OFFLINE)
# ============================================================

function Start-QuickSetup {
    param ([switch]$Offline)

    $OfflineSourceDir = ""

    # ---------- Nếu Offline: tự dò thư mục trên USB ----------
    if ($Offline) {
        Clear-Host
        Write-Host ""
        Write-Line
        Write-Host "         ĐANG TÌM BỘ CÀI TRÊN USB..." -ForegroundColor Cyan
        Write-Line
        Write-Host ""

        $OfflineSourceDir = Find-OfflineDir -FolderName $OfflineFolderName

        if (-not $OfflineSourceDir) {
            Write-Host "[X] Không tìm thấy thư mục '$OfflineFolderName' trên ổ đĩa nào (D: -> Z:)." -ForegroundColor Red
            Write-Host ""
            Write-Host "Kiểm tra lại:" -ForegroundColor Yellow
            Write-Host "  - USB đã cắm chưa?" -ForegroundColor Yellow
            Write-Host "  - Thư mục tên đúng '$OfflineFolderName' chưa?" -ForegroundColor Yellow
            Write-Host "  - Trong thư mục có file .exe không?" -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter to return to menu"
            return
        }

        Write-Host "[+] Tìm thấy: $OfflineSourceDir" -ForegroundColor Green
        Start-Sleep -Milliseconds 800

        # Kiểm tra sơ bộ các file cần thiết
        $Missing = @()
        foreach ($App in $Apps) {
            $Src = Join-Path $OfflineSourceDir $App.FileName
            if (-not (Test-Path $Src)) { $Missing += $App.FileName }
        }

        if ($Missing.Count -gt 0) {
            Write-Host ""
            Write-Host "[!] Các file sau không tìm thấy trong thư mục offline:" -ForegroundColor Yellow
            foreach ($m in $Missing) {
                Write-Host "    - $m" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "Vẫn tiếp tục? Những app thiếu file sẽ bị đánh dấu FAILED." -ForegroundColor Yellow
            $confirm = Read-Host "Tiếp tục? (y/n)"
            if ($confirm -notmatch '^[yY]') { return }
        }
    }

    $ModeLabel = if ($Offline) { "OFFLINE (USB)" } else { "ONLINE (GitHub)" }

    Clear-Host
    Write-Host ""
    Write-Line
    Write-Host "              QUICK SETUP STARTED" -ForegroundColor Cyan
    Write-Host "              Mode: $ModeLabel" -ForegroundColor Cyan
    if ($Offline) {
        Write-Host "              Source: $OfflineSourceDir" -ForegroundColor DarkGray
    }
    Write-Line
    Write-Host ""

    $Results    = @()
    $Current    = 0
    $SetupStart = Get-Date

    foreach ($App in $Apps) {
        $Current++
        Show-OverallProgress -Current ($Current - 1) -Total $TotalApps
        $Status = Install-App -App $App -Number $Current -OfflineSourceDir $OfflineSourceDir
        $Results += [PSCustomObject]@{ Name = $App.Name; Status = $Status }
        Show-OverallProgress -Current $Current -Total $TotalApps
    }

    # ---- POST SETUP (luôn tải active.cmd từ GitHub) ----
    Start-PostSetupCMD -CmdUrl $PostSetupUrl

    $SetupEnd  = Get-Date
    $TotalTime = $SetupEnd - $SetupStart

    # ---- SUMMARY ----
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
    Write-Host "Mode       : $ModeLabel" -ForegroundColor White
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
        "1" { Start-QuickSetup }            # Online
        "2" { Start-QuickSetup -Offline }   # Offline
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
