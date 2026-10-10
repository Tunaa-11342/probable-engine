#requires -version 5.1

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"   # tăng tốc Invoke-WebRequest

# ============================================================
# CONFIG
# ============================================================

$DownloadRoot = Join-Path $env:LOCALAPPDATA "WindowsQuickSetup"
$UniKeyDir    = Join-Path $DownloadRoot "UniKey"

# ---- GitHub Releases base URL (ONLINE) ----
$GhBase = "https://github.com/Tunaa-11342/probable-engine/releases/download/v5.0.5"

# ---- OFFLINE: tên thư mục chứa bộ cài trên USB ----
$OfflineFolderName = "app can cai"

# ---- OFFICE ----
$OfficeIsoUrl  = ""                          # <- ONLINE: tự dán link direct ISO vào đây (trống = bỏ qua Office)
$OfficeIsoName = "O365ProPlusRetail.iso"     # <- OFFLINE: tên file ISO trong thư mục $OfflineFolderName

# ---- WIFI (menu [4]) - điền SSID / mật khẩu vào đây, thêm bao nhiêu WiFi cũng được ----
# Mật khẩu để trống = mạng mở (không mật khẩu). SSID để trống = bỏ qua dòng đó.
$WifiList = @(
    @{ Ssid = ""; Password = "" }
    # @{ Ssid = "WIFI_DU_PHONG"; Password = "matkhau" }
)

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
        Args     = "/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
        RegName  = "UltraViewer"
    },
    @{
        Name     = "Google Chrome"
        Type     = "exe"
        FileName = "ChromeSetup.exe"
        Url      = "$GhBase/ChromeSetup.exe"
        Args     = "/silent /install"
        RegName  = "Google Chrome"
    },
    @{
        Name     = "Microsoft Office"
        Type     = "iso"
        FileName = $OfficeIsoName
        Url      = $OfficeIsoUrl
        RegNames = @("Microsoft 365", "Microsoft Office")
        RegName  = "Microsoft Office"
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
    Write-Host " [1] 1 Click Setup Online"      -ForegroundColor White
    Write-Host " [2] 1 Click Setup Offline"     -ForegroundColor White
    Write-Host " [3] Surface Driver Setup (USB)" -ForegroundColor White
    Write-Host " [4] Connect WiFi (Offline)"     -ForegroundColor White
    Write-Host " [0] Exit"                      -ForegroundColor White
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
    param ([string[]]$Names)

    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Name in $Names) {
        foreach ($p in $paths) {
            $found = Get-ItemProperty $p -ErrorAction SilentlyContinue |
                     Where-Object { $_.DisplayName -and $_.DisplayName -like "*$Name*" }
            if ($found) { return $true }
        }
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
# INSTALL ISO APP (Office): copy/tải -> mount -> setup.exe -> dismount -> xoá
# ============================================================

function Install-IsoApp {
    param (
        [hashtable]$App,
        [string]$OfflineSourceDir = ""
    )

    $IsOffline = -not [string]::IsNullOrWhiteSpace($OfflineSourceDir)

    # ONLINE mà chưa có link -> bỏ qua
    if (-not $IsOffline -and [string]::IsNullOrWhiteSpace($App.Url)) {
        Write-Host "[=] Chưa cấu hình link ISO - SKIPPED" -ForegroundColor Yellow
        return "SKIPPED"
    }

    if (-not (Test-Path $DownloadRoot)) {
        New-Item -ItemType Directory -Path $DownloadRoot -Force | Out-Null
    }

    $IsoPath   = Join-Path $DownloadRoot "$($App.Name -replace '\s','_').iso"
    $StartTime = Get-Date
    $Mounted   = $false

    try {
        # ---------- Lấy file ISO + check dung lượng ----------
        if ($IsOffline) {
            $SrcIso = Join-Path $OfflineSourceDir $App.FileName
            if (-not (Test-Path $SrcIso)) {
                throw "Không tìm thấy file ISO: $SrcIso"
            }
            $Need = (Get-Item $SrcIso).Length + 4GB
        }
        else {
            $Need = 12GB
        }

        $SysLetter = $env:SystemDrive.TrimEnd(':')
        $Free      = (Get-PSDrive -Name $SysLetter).Free
        if ($Free -lt $Need) {
            throw ("Không đủ dung lượng ổ {0}: (cần ~{1} GB, còn {2} GB)" -f $SysLetter, [math]::Ceiling($Need / 1GB), [math]::Floor($Free / 1GB))
        }

        if ($IsOffline) {
            Write-Host "[>] Copying ISO from USB to disk..." -ForegroundColor Cyan
            Copy-Item -Path $SrcIso -Destination $IsoPath -Force -ErrorAction Stop
            Write-Host "[+] Copied" -ForegroundColor Green
        }
        else {
            Write-Host "[>] Downloading ISO..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $App.Url -OutFile $IsoPath -UseBasicParsing -ErrorAction Stop
            Write-Host "[+] Downloaded" -ForegroundColor Green
        }

        # ---------- Mount ----------
        Write-Host "[>] Mounting..." -ForegroundColor Cyan
        Mount-DiskImage -ImagePath $IsoPath -ErrorAction Stop | Out-Null
        $Mounted = $true

        $Letter = $null
        for ($i = 0; $i -lt 15 -and -not $Letter; $i++) {
            $Vol = Get-DiskImage -ImagePath $IsoPath | Get-Volume -ErrorAction SilentlyContinue
            if ($Vol -and $Vol.DriveLetter) { $Letter = $Vol.DriveLetter } else { Start-Sleep -Seconds 1 }
        }
        if (-not $Letter) { throw "Không lấy được ký tự ổ đĩa sau khi mount ISO" }

        $Setup = "${Letter}:\setup.exe"
        if (-not (Test-Path $Setup)) { throw "Không thấy setup.exe trong ISO ($Setup)" }
        Write-Host "[+] Mounted at drive ${Letter}:" -ForegroundColor Green

        # ---------- Run setup ----------
        Write-Host "[>] Running setup.exe..." -ForegroundColor Cyan
        $Proc = Start-Process -FilePath $Setup -WorkingDirectory "${Letter}:\" -Wait -PassThru

        # Chờ thêm nếu setup còn tiến trình con chạy từ ổ ISO (tránh dismount sớm)
        while ($true) {
            $Still = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                try { $_.Path -and $_.Path.StartsWith("${Letter}:\", [StringComparison]::OrdinalIgnoreCase) } catch { $false }
            }
            if (-not $Still) { break }
            Start-Sleep -Seconds 5
        }

        $Elapsed = (Get-Date) - $StartTime
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
        Write-Host ""
        Write-Host "[X] $($App.Name) - ERROR" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        return "FAILED"
    }
    finally {
        if ($Mounted) {
            Write-Host "[>] Dismounting & cleaning up..." -ForegroundColor DarkGray
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
        }
        Remove-Item $IsoPath -Force -ErrorAction SilentlyContinue
    }
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
    $RegList = if ($App.RegNames) { $App.RegNames } else { @($App.RegName) }
    if (Test-AppInstalled -Names $RegList) {
        Write-Host ""
        Write-Host "[=] Already installed - SKIPPED" -ForegroundColor Green
        return "SKIPPED"
    }
    Write-Host "[+] Not installed." -ForegroundColor Gray
    Write-Host ""

    # ---------- ISO (Office) ----------
    if ($App.Type -eq "iso") {
        return (Install-IsoApp -App $App -OfflineSourceDir $OfflineSourceDir)
    }

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

        Write-Host "[>] Running silent installer..." -ForegroundColor Cyan
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
# SURFACE DRIVER (MSI trên USB)
# ============================================================

function Find-SurfaceMsi {
    param ([string]$Model)

    # "Surface Laptop 4" -> "surfacelaptop4"
    $Norm    = ($Model -replace '\s', '').ToLower()
    # Không cho khớp tiếp số hoặc dấu + (tránh Pro 7 khớp nhầm Pro 7+ / Pro 70...)
    $Pattern = [regex]::Escape($Norm) + '(?![0-9+])'
    $OsTag   = if ([Environment]::OSVersion.Version.Build -ge 22000) { 'win11' } else { 'win10' }

    $Drives = 68..90 | ForEach-Object { "$([char]$_)`:\" }

    foreach ($Drive in $Drives) {
        if (-not (Test-Path $Drive)) { continue }

        $Files = @(Get-ChildItem -Path $Drive -Filter *.msi -Recurse -Depth 2 -File -ErrorAction SilentlyContinue |
                   Where-Object { (($_.Name -replace '\s', '').ToLower()) -match $Pattern })

        if ($Files.Count -gt 0) {
            $Pick = $Files | Where-Object { $_.Name.ToLower() -match $OsTag } |
                    Sort-Object Name -Descending | Select-Object -First 1
            if (-not $Pick) {
                $Pick = $Files | Sort-Object Name -Descending | Select-Object -First 1
            }
            return $Pick.FullName
        }
    }
    return $null
}

function Start-SurfaceDriverSetup {
    Clear-Host
    Write-Host ""
    Write-Line
    Write-Host "         SURFACE DRIVER SETUP" -ForegroundColor Cyan
    Write-Line
    Write-Host ""

    # ---------- Đọc thông tin máy ----------
    try {
        $Cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    }
    catch {
        Write-Host "[X] Không đọc được thông tin máy: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to return to menu"
        return
    }

    $Manufacturer = "$($Cs.Manufacturer)".Trim()
    $Model        = "$($Cs.Model)".Trim()

    if ($Manufacturer -notlike "*Microsoft*" -or $Model -notlike "*Surface*") {
        Write-Host "[X] Không phải máy Surface" -ForegroundColor Red
        Write-Host "    ($Manufacturer - $Model)" -ForegroundColor DarkGray
        Write-Host ""
        Read-Host "Press Enter to return to menu"
        return
    }

    Write-Host "[*] Model: $Model" -ForegroundColor White

    # ---------- Tìm MSI ----------
    $Msi = Find-SurfaceMsi -Model $Model

    if (-not $Msi) {
        $AnyDrive = 68..90 | Where-Object { Test-Path "$([char]$_)`:\" }
        if (-not $AnyDrive) {
            Write-Host "[X] Không tìm thấy USB driver" -ForegroundColor Red
        }
        else {
            Write-Host "[X] Không có driver cho $Model" -ForegroundColor Red
        }
        Write-Host ""
        Read-Host "Press Enter to return to menu"
        return
    }

    Write-Host "[*] Driver: $(Split-Path $Msi -Leaf)" -ForegroundColor White
    Write-Host "[>] Installing silent..." -ForegroundColor Cyan

    # ---------- Cài ----------
    try {
        $Proc = Start-Process -FilePath "msiexec.exe" `
                              -ArgumentList "/i `"$Msi`" /qn /norestart" `
                              -Wait -PassThru -ErrorAction Stop

        if ($Proc.ExitCode -eq 0) {
            Write-Host "[+] $Model - SUCCESS" -ForegroundColor Green
        }
        elseif ($Proc.ExitCode -eq 3010) {
            Write-Host "[+] $Model - SUCCESS" -ForegroundColor Green
            Write-Host "[!] Cần restart máy để hoàn tất" -ForegroundColor Yellow
        }
        else {
            Write-Host "[X] Install failed - Exit code: $($Proc.ExitCode)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[X] Install failed - $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to return to menu"
}


# ============================================================
# WIFI (nạp profile bằng netsh, không cần nhập tay)
# ============================================================

function Start-WifiSetup {
    Clear-Host
    Write-Host ""
    Write-Line
    Write-Host "              CONNECT WIFI" -ForegroundColor Cyan
    Write-Line
    Write-Host ""

    $List = @($WifiList | Where-Object { $_.Ssid })
    if ($List.Count -eq 0) {
        Write-Host "[X] Chưa cấu hình WiFi (sửa `$WifiList ở phần CONFIG)" -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to return to menu"
        return
    }

    # ---------- Kiểm tra card WiFi ----------
    $Wlan = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.PhysicalMediaType -match '802\.11' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN' }

    if (-not $Wlan) {
        Write-Host "[X] Không thấy card WiFi (cài driver Surface trước - menu [3])" -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to return to menu"
        return
    }

    $Svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if ($Svc -and $Svc.Status -ne "Running") {
        Start-Service -Name WlanSvc -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # ---------- Nạp profile ----------
    $TempXml = Join-Path $env:TEMP "wifi_profile.xml"
    $Added   = @()

    foreach ($W in $List) {
        $Ssid = "$($W.Ssid)"
        $Pw   = "$($W.Password)"
        $SsidX = [System.Security.SecurityElement]::Escape($Ssid)

        if ($Pw) {
            $PwX      = [System.Security.SecurityElement]::Escape($Pw)
            $Auth     = "WPA2PSK"
            $Enc      = "AES"
            $KeyBlock = "<sharedKey><keyType>passphrase</keyType><protected>false</protected><keyMaterial>$PwX</keyMaterial></sharedKey>"
        }
        else {
            $Auth     = "open"
            $Enc      = "none"
            $KeyBlock = ""
        }

        $Xml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$SsidX</name>
  <SSIDConfig><SSID><name>$SsidX</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM><security><authEncryption><authentication>$Auth</authentication><encryption>$Enc</encryption><useOneX>false</useOneX></authEncryption>$KeyBlock</security></MSM>
</WLANProfile>
"@

        try {
            Set-Content -Path $TempXml -Value $Xml -Encoding UTF8
            netsh wlan add profile filename="$TempXml" user=all | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Đã nạp WiFi: $Ssid" -ForegroundColor Green
                $Added += $Ssid
            }
            else {
                Write-Host "[X] Nạp WiFi thất bại: $Ssid" -ForegroundColor Red
            }
        }
        finally {
            Remove-Item $TempXml -Force -ErrorAction SilentlyContinue   # file chứa mật khẩu, xoá ngay
        }
    }

    if ($Added.Count -eq 0) {
        Write-Host ""
        Read-Host "Press Enter to return to menu"
        return
    }

    # ---------- Kết nối ----------
    $Online = $false
    foreach ($Ssid in $Added) {
        Write-Host "[>] Connecting: $Ssid..." -ForegroundColor Cyan
        netsh wlan connect name="$Ssid" | Out-Null

        for ($i = 0; $i -lt 15 -and -not $Online; $i++) {
            Start-Sleep -Seconds 1
            $Online = Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
        }

        if ($Online) {
            Write-Host "[+] Connected: $Ssid - SUCCESS" -ForegroundColor Green
            break
        }
        Write-Host "[!] Chưa kết nối được $Ssid" -ForegroundColor Yellow
    }

    if (-not $Online) {
        Write-Host "[X] Chưa có internet (sai mật khẩu hoặc ngoài vùng phủ sóng)" -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to return to menu"
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
                Write-Host "    Skipped (already installed / no link)" -ForegroundColor DarkGray
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
        "3" { Start-SurfaceDriverSetup }    # Surface driver (USB)
        "4" { Start-WifiSetup }             # WiFi (offline)
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
