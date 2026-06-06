#requires -version 5.1
<#
Setup a fresh Windows 10/11 PC for personal/dev use.
This script prefers winget, avoids registry/system-file hacks, and keeps failures isolated.
#>

$ErrorActionPreference = 'Continue'

$script:Summary = [ordered]@{
    Apps       = [ordered]@{}
    Extensions = [ordered]@{}
    Git        = [ordered]@{
        Checked              = $false
        UserName             = ''
        UserEmail            = ''
        DefaultBranch        = ''
        CoreEditor           = ''
        AutoCrlf             = ''
        CredentialHelper     = ''
        GitHubCliAuthStatus  = 'Not checked'
        SshKey               = 'Not checked'
    }
    Spotify    = [ordered]@{
        SpotifyInstalled     = 'Not checked'
        SpicetifyInstalled   = 'Not checked'
        UpdateFreeze         = 'Not run'
        BackupApply          = 'Not run'
        MarketplaceInstalled = 'Not selected'
        LastApply            = 'Not run'
        Restore              = 'Not run'
    }
}

$script:WingetAvailable = $null

$Apps = @(
    @{ Name = 'Git';              Id = 'Git.Git';                         StrictSource = $false },
    @{ Name = 'Node.js LTS';      Id = 'OpenJS.NodeJS.LTS';               StrictSource = $false },
    @{ Name = 'VS Code';          Id = 'Microsoft.VisualStudioCode';      StrictSource = $false },
    @{ Name = 'Google Chrome';    Id = 'Google.Chrome';                   StrictSource = $false },
    @{ Name = 'GitHub CLI';       Id = 'GitHub.cli';                      StrictSource = $false },
    @{ Name = 'JDK 25 Temurin';   Id = 'EclipseAdoptium.Temurin.25.JDK';  StrictSource = $false },
    @{ Name = 'Python 3.13';      Id = 'Python.Python.3.13';              StrictSource = $false },
    @{ Name = 'UltraViewer';      Id = 'DucFabulous.UltraViewer';         StrictSource = $true  },
    @{ Name = 'PowerToys';        Id = 'Microsoft.PowerToys';             StrictSource = $false },
    @{ Name = 'Windows Terminal'; Id = 'Microsoft.WindowsTerminal';       StrictSource = $false },
    @{ Name = '7-Zip';            Id = '7zip.7zip';                       StrictSource = $false },
    @{ Name = 'WinRAR';           Id = 'RARLab.WinRAR';                   StrictSource = $true  },
    @{ Name = 'UniKey';           Id = 'UniKey.UniKey';                   StrictSource = $true  },
    @{ Name = 'Everything';       Id = 'voidtools.Everything';            StrictSource = $false },
    @{ Name = 'Notepad++';        Id = 'Notepad++.Notepad++';             StrictSource = $false },
    @{ Name = 'Discord';          Id = 'Discord.Discord';                 StrictSource = $false },
    @{ Name = 'Steam';            Id = 'Valve.Steam';                     StrictSource = $false },
    @{ Name = 'Spotify';          Id = 'Spotify.Spotify';                 StrictSource = $false }
)

$VSCodeExtensions = @(
    'esbenp.prettier-vscode',
    'dbaeumer.vscode-eslint',
    'bradlc.vscode-tailwindcss',
    'Prisma.prisma',
    'eamodio.gitlens',
    'PKief.material-icon-theme',
    'formulahendry.auto-rename-tag'
)

function Write-Info {
    param([string]$Message)
    Write-Host '  INFO ' -NoNewline -ForegroundColor Black -BackgroundColor Cyan
    Write-Host " $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host '  OK   ' -NoNewline -ForegroundColor Black -BackgroundColor Green
    Write-Host " $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host '  SKIP ' -NoNewline -ForegroundColor Black -BackgroundColor Yellow
    Write-Host " $Message" -ForegroundColor Yellow
}

function Write-Warn {
    param([string]$Message)
    Write-Host '  WARN ' -NoNewline -ForegroundColor Black -BackgroundColor Magenta
    Write-Host " $Message" -ForegroundColor Magenta
}

function Write-Fail {
    param([string]$Message)
    Write-Host '  FAIL ' -NoNewline -ForegroundColor White -BackgroundColor Red
    Write-Host " $Message" -ForegroundColor Red
}

function Write-Rule {
    param([int]$Width = 72)
    Write-Host ('-' * $Width) -ForegroundColor DarkGray
}

function Write-Header {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Subtitle = ''
    )

    $width = 72
    $innerWidth = $width - 4
    Write-Host ''
    Write-Host ('=' * $width) -ForegroundColor DarkCyan
    Write-Host ('| ' + $Title.PadRight($innerWidth) + ' |') -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host ('| ' + $Subtitle.PadRight($innerWidth) + ' |') -ForegroundColor DarkGray
    }
    Write-Host ('=' * $width) -ForegroundColor DarkCyan
}

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Host ''
    Write-Host $Title -ForegroundColor White
    Write-Rule
}

function Write-MenuItem {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$Hint = ''
    )

    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $Key -NoNewline -ForegroundColor Yellow
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Label -NoNewline -ForegroundColor White
    if ($Hint) {
        Write-Host " - $Hint" -ForegroundColor DarkGray
    } else {
        Write-Host ''
    }
}

function Read-MenuChoice {
    param([string]$Prompt = 'Choose an option')

    Write-Host ''
    Write-Host '> ' -NoNewline -ForegroundColor Yellow
    return (Read-Host $Prompt).Trim()
}

function Get-StatusColor {
    param([string]$Status)

    switch ($Status) {
        'OK' { 'Green' }
        'SKIP' { 'Yellow' }
        'FAILED' { 'Red' }
        'Not run' { 'DarkGray' }
        'Not checked' { 'DarkGray' }
        'Skipped' { 'Yellow' }
        default {
            if ($Status -match 'FAILED|fail') { 'Red' }
            elseif ($Status -match 'OK|Created|Existing') { 'Green' }
            elseif ($Status -match 'SKIP|Skipped') { 'Yellow' }
            else { 'Gray' }
        }
    }
}

function Write-SummaryRow {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Status
    )

    if ([string]::IsNullOrWhiteSpace($Status)) { $Status = 'Not set' }
    Write-Host ('  {0,-32}' -f $Name) -NoNewline -ForegroundColor Gray
    Write-Host $Status -ForegroundColor (Get-StatusColor -Status $Status)
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [ValidateSet('Y', 'N', '')][string]$Default = ''
    )

    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { ' [Y/N]' }
        $value = (Read-Host "$Prompt$suffix").Trim()
        if ([string]::IsNullOrWhiteSpace($value) -and $Default) {
            return $Default -eq 'Y'
        }
        switch ($value.ToUpperInvariant()) {
            'Y' { return $true }
            'YES' { return $true }
            'N' { return $false }
            'NO' { return $false }
            default { Write-Warn 'Please enter Y or N.' }
        }
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        Write-Ok 'Running as Administrator.'
        return $true
    }

    Write-Warn 'Script is not running as Administrator. Some installs may fail.'
    if (-not (Read-YesNo -Prompt 'Continue anyway?' -Default 'N')) {
        Write-Info 'Exiting.'
        exit 1
    }
    return $false
}

function Test-Winget {
    if (Test-CommandExists 'winget') {
        $version = (& winget --version 2>$null)
        Write-Ok "winget found: $version"
        $script:WingetAvailable = $true
        return $true
    }

    Write-Warn 'winget was not found. Install App Installer from Microsoft Store.'
    Write-Warn 'App installation will be skipped, but other sections can still run.'
    $script:WingetAvailable = $false
    return $false
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $FilePath @Arguments
    return $LASTEXITCODE
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$Id)

    $output = (& winget list --id $Id -e --source winget 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { return $false }
    return $output -match [regex]::Escape($Id)
}

function Test-WingetPackageAvailable {
    param([Parameter(Mandatory = $true)][string]$Id)

    $output = (& winget show --id $Id -e --source winget 2>$null) -join "`n"
    return ($LASTEXITCODE -eq 0 -and $output -match [regex]::Escape($Id))
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Id,
        [bool]$StrictSource = $false
    )

    if ($null -eq $script:WingetAvailable) { [void](Test-Winget) }
    if (-not $script:WingetAvailable) {
        Write-Warn "$Name skipped because winget is unavailable."
        $script:Summary.Apps[$Name] = 'FAILED'
        return
    }

    Write-Info "Checking $Name ($Id)..."

    if (-not (Test-WingetPackageAvailable -Id $Id)) {
        Write-Warn "$Name package ID not found in winget: $Id"
        if ($StrictSource) {
            Write-Warn "$Name requires a clear trusted winget source. Skipping."
        }
        $script:Summary.Apps[$Name] = 'FAILED'
        return
    }

    if (Test-WingetPackageInstalled -Id $Id) {
        Write-Skip "$Name already installed"
        $script:Summary.Apps[$Name] = 'SKIP'
        return
    }

    Write-Info "Installing $Name..."
    $args = @(
        'install', '--id', $Id, '-e',
        '--source', 'winget',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )
    $exitCode = Invoke-NativeCommand -FilePath 'winget' -Arguments $args

    if ($exitCode -eq 0) {
        Write-Ok "$Name installed"
        $script:Summary.Apps[$Name] = 'OK'
    } else {
        Write-Warn "$Name install failed with exit code $exitCode"
        $script:Summary.Apps[$Name] = 'FAILED'
    }
}

function Install-Apps {
    Write-Section 'Install Apps'

    [void](Test-Winget)
    if (-not $script:WingetAvailable) { return }

    foreach ($app in $Apps) {
        Install-WingetPackage -Name $app.Name -Id $app.Id -StrictSource $app.StrictSource
    }
}

function Get-VSCodeCommand {
    $command = Get-Command 'code' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

function Install-VSCodeExtension {
    param(
        [Parameter(Mandatory = $true)][string]$CodeCommand,
        [Parameter(Mandatory = $true)][string]$ExtensionId
    )

    $installed = (& $CodeCommand --list-extensions 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Could not read VS Code extension list.'
        $script:Summary.Extensions[$ExtensionId] = 'FAILED'
        return
    }

    if ($installed -contains $ExtensionId) {
        Write-Skip "$ExtensionId already installed"
        $script:Summary.Extensions[$ExtensionId] = 'SKIP'
        return
    }

    Write-Info "Installing VS Code extension $ExtensionId..."
    & $CodeCommand --install-extension $ExtensionId
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$ExtensionId installed"
        $script:Summary.Extensions[$ExtensionId] = 'OK'
    } else {
        Write-Warn "$ExtensionId install failed"
        $script:Summary.Extensions[$ExtensionId] = 'FAILED'
    }
}

function Install-VSCodeExtensions {
    Write-Section 'VS Code Extensions'

    $codeCommand = Get-VSCodeCommand
    if (-not $codeCommand) {
        Write-Warn 'VS Code command not found. Open a new terminal or add VS Code to PATH.'
        foreach ($extension in $VSCodeExtensions) {
            $script:Summary.Extensions[$extension] = 'FAILED'
        }
        return
    }

    Write-Ok "Using VS Code command: $codeCommand"
    foreach ($extension in $VSCodeExtensions) {
        Install-VSCodeExtension -CodeCommand $codeCommand -ExtensionId $extension
    }
}

function Read-GitConfigValue {
    param([Parameter(Mandatory = $true)][string]$Key)

    $value = (& git config --global $Key 2>$null) -join ''
    if ($LASTEXITCODE -ne 0) { return '' }
    return $value.Trim()
}

function Set-GitConfigValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    & git config --global $Key $Value
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Set $Key = $Value"
        return $true
    }

    Write-Warn "Failed to set $Key"
    return $false
}

function Read-GitRequiredValue {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$CurrentValue = ''
    )

    if ($CurrentValue) {
        Write-Info "Current value: $CurrentValue"
    }

    while ($true) {
        $inputValue = (Read-Host $Prompt).Trim()
        if ($inputValue) { return $inputValue }
        if ($CurrentValue) { return $CurrentValue }

        Write-Warn 'Value is empty.'
        if (Read-YesNo -Prompt 'Skip this value?' -Default 'N') {
            Write-Warn "$Prompt skipped."
            return ''
        }
    }
}

function Setup-GitProfile {
    Write-Section 'Setup Git'

    $script:Summary.Git.Checked = $true

    if (-not (Test-CommandExists 'git')) {
        Write-Warn 'Git was not found. Skipping Git setup.'
        return
    }

    & git --version
    $currentName = Read-GitConfigValue -Key 'user.name'
    $name = Read-GitRequiredValue -Prompt 'Enter Git user.name' -CurrentValue $currentName
    if ($name) { [void](Set-GitConfigValue -Key 'user.name' -Value $name) }

    $currentEmail = Read-GitConfigValue -Key 'user.email'
    $email = Read-GitRequiredValue -Prompt 'Enter Git user.email' -CurrentValue $currentEmail
    if ($email) { [void](Set-GitConfigValue -Key 'user.email' -Value $email) }

    $branch = (Read-Host 'Default branch name? [main]').Trim()
    if (-not $branch) { $branch = 'main' }
    [void](Set-GitConfigValue -Key 'init.defaultBranch' -Value $branch)

    $codeCommand = Get-VSCodeCommand
    if ($codeCommand) {
        if (Read-YesNo -Prompt 'Use VS Code as Git editor?' -Default 'Y') {
            [void](Set-GitConfigValue -Key 'core.editor' -Value 'code --wait')
        }
    } else {
        Write-Warn 'VS Code command not found. Skipping Git editor setup.'
    }

    if (Read-YesNo -Prompt 'Enable Windows line ending handling core.autocrlf=true?' -Default 'Y') {
        [void](Set-GitConfigValue -Key 'core.autocrlf' -Value 'true')
    }

    if (Read-YesNo -Prompt 'Use Git Credential Manager?' -Default 'Y') {
        [void](Set-GitConfigValue -Key 'credential.helper' -Value 'manager')
    }

    if (Test-CommandExists 'gh') {
        & gh --version
        if (Read-YesNo -Prompt 'Login to GitHub now using GitHub CLI?' -Default 'N') {
            & gh auth login
            & gh auth status
            $script:Summary.Git.GitHubCliAuthStatus = if ($LASTEXITCODE -eq 0) { 'OK' } else { 'FAILED' }
        } else {
            $script:Summary.Git.GitHubCliAuthStatus = 'Skipped'
        }
    } else {
        Write-Warn 'GitHub CLI was not found.'
        $script:Summary.Git.GitHubCliAuthStatus = 'gh not found'
    }

    $sshPublicKey = Join-Path $HOME '.ssh\id_ed25519.pub'
    $sshPrivateKey = Join-Path $HOME '.ssh\id_ed25519'
    if (Test-Path -LiteralPath $sshPublicKey) {
        Write-Ok "SSH key already exists: $sshPublicKey"
        $script:Summary.Git.SshKey = 'Existing'
    } elseif (Read-YesNo -Prompt 'Create SSH key for GitHub?' -Default 'N') {
        if (-not $email) {
            Write-Warn 'Git email is empty. SSH key creation skipped.'
            $script:Summary.Git.SshKey = 'Skipped: no email'
        } else {
            New-Item -ItemType Directory -Path (Join-Path $HOME '.ssh') -Force | Out-Null
            & ssh-keygen -t ed25519 -C $email -f $sshPrivateKey
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $sshPublicKey)) {
                $publicKey = Get-Content -LiteralPath $sshPublicKey -Raw
                Write-Host ''
                Write-Host 'Public SSH key:' -ForegroundColor White
                Write-Host $publicKey -ForegroundColor Green
                try {
                    $publicKey | Set-Clipboard
                    Write-Ok 'Public key copied to clipboard.'
                } catch {
                    Write-Warn 'Could not copy public key to clipboard.'
                }
                Write-Host 'Add it in GitHub -> Settings -> SSH and GPG keys -> New SSH key' -ForegroundColor Cyan
                $script:Summary.Git.SshKey = 'Created'
            } else {
                Write-Warn 'SSH key creation failed.'
                $script:Summary.Git.SshKey = 'FAILED'
            }
        }
    } else {
        $script:Summary.Git.SshKey = 'Skipped'
    }

    $script:Summary.Git.UserName = Read-GitConfigValue -Key 'user.name'
    $script:Summary.Git.UserEmail = Read-GitConfigValue -Key 'user.email'
    $script:Summary.Git.DefaultBranch = Read-GitConfigValue -Key 'init.defaultBranch'
    $script:Summary.Git.CoreEditor = Read-GitConfigValue -Key 'core.editor'
    $script:Summary.Git.AutoCrlf = Read-GitConfigValue -Key 'core.autocrlf'
    $script:Summary.Git.CredentialHelper = Read-GitConfigValue -Key 'credential.helper'

    Write-Host ''
    Write-Host 'Git config summary' -ForegroundColor White
    Write-Host "user.name:         $($script:Summary.Git.UserName)"
    Write-Host "user.email:        $($script:Summary.Git.UserEmail)"
    Write-Host "init.defaultBranch:$($script:Summary.Git.DefaultBranch)"
    Write-Host "core.editor:       $($script:Summary.Git.CoreEditor)"
    Write-Host "core.autocrlf:     $($script:Summary.Git.AutoCrlf)"
    Write-Host "credential.helper: $($script:Summary.Git.CredentialHelper)"

    Write-Host ''
    Write-Host 'Quick Git test:' -ForegroundColor White
    Write-Host 'mkdir test-git'
    Write-Host 'cd test-git'
    Write-Host 'git init'
    Write-Host 'echo "# test" > README.md'
    Write-Host 'git add .'
    Write-Host 'git commit -m "initial commit"'
}

function Test-SpotifyInstalled {
    $paths = @(
        (Join-Path $env:APPDATA 'Spotify\Spotify.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\Spotify.exe')
    )

    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) { return $true }
    }

    if ($script:WingetAvailable -or (Test-Winget)) {
        return (Test-WingetPackageInstalled -Id 'Spotify.Spotify')
    }

    return $false
}

function Ensure-SpotifyInstalled {
    if (Test-SpotifyInstalled) {
        Write-Skip 'Spotify already installed'
        $script:Summary.Spotify.SpotifyInstalled = 'SKIP'
        return $true
    }

    Install-WingetPackage -Name 'Spotify' -Id 'Spotify.Spotify'
    $result = $script:Summary.Apps['Spotify']
    $script:Summary.Spotify.SpotifyInstalled = $result
    return ($result -eq 'OK' -or $result -eq 'SKIP')
}

function Stop-SpotifyIfRequested {
    $processes = Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue
    if (-not $processes) { return }

    if (Read-YesNo -Prompt 'Spotify is running. Close Spotify now?' -Default 'Y') {
        $processes | Stop-Process -Force
        Write-Ok 'Spotify stopped.'
    } else {
        Write-Warn 'Spicetify apply may fail while Spotify is running.'
    }
}

function Disable-SpotifyAutoUpdate {
    Write-Section 'Freeze Spotify Updates'

    $spotifyDir = Join-Path $env:LOCALAPPDATA 'Spotify'
    $updatePath = Join-Path $spotifyDir 'Update'

    if (-not (Test-Path -LiteralPath $spotifyDir)) {
        Write-Warn "Spotify folder was not found: $spotifyDir"
        $script:Summary.Spotify.UpdateFreeze = 'FAILED'
        return $false
    }

    Stop-SpotifyIfRequested

    try {
        if (Test-Path -LiteralPath $updatePath) {
            $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
            $backupPath = Join-Path $spotifyDir "Update.backup-$timestamp"
            Move-Item -LiteralPath $updatePath -Destination $backupPath -Force
            Write-Ok "Existing Update folder moved to: $backupPath"
        }

        New-Item -ItemType Directory -Path $updatePath -Force | Out-Null

        $principal = "$env:USERDOMAIN\$env:USERNAME"
        $denyRule = "${principal}:(OI)(CI)(W,M)"

        & icacls $updatePath /inheritance:r | Out-Null
        & icacls $updatePath /deny $denyRule | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'Spotify updates are frozen for the current Windows user.'
            $script:Summary.Spotify.UpdateFreeze = 'OK'
            return $true
        }

        Write-Warn 'icacls failed while applying the deny rule.'
        $script:Summary.Spotify.UpdateFreeze = 'FAILED'
        return $false
    } catch {
        Write-Warn "Could not freeze Spotify updates: $($_.Exception.Message)"
        $script:Summary.Spotify.UpdateFreeze = 'FAILED'
        return $false
    }
}

function Get-SpicetifyCommand {
    $command = Get-Command 'spicetify' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'),
        (Join-Path $env:APPDATA 'spicetify\spicetify.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

function Ensure-SpicetifyInstalled {
    $spicetify = Get-SpicetifyCommand
    if ($spicetify) {
        & $spicetify --version
        $script:Summary.Spotify.SpicetifyInstalled = 'SKIP'
        return $spicetify
    }

    Write-Info 'Installing Spicetify CLI using the official installer...'
    try {
        Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/spicetify/cli/main/install.ps1' | Invoke-Expression
    } catch {
        Write-Warn "Spicetify install failed: $($_.Exception.Message)"
        $script:Summary.Spotify.SpicetifyInstalled = 'FAILED'
        return $null
    }

    Refresh-ProcessPath
    $spicetify = Get-SpicetifyCommand
    if ($spicetify) {
        Write-Ok 'Spicetify installed.'
        $script:Summary.Spotify.SpicetifyInstalled = 'OK'
        return $spicetify
    }

    Write-Warn 'Spicetify installed, but command was not found. Open a new terminal and try again.'
    $script:Summary.Spotify.SpicetifyInstalled = 'FAILED'
    return $null
}

function Invoke-Spicetify {
    param(
        [Parameter(Mandatory = $true)][string]$ActionName,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $spicetify = Get-SpicetifyCommand
    if (-not $spicetify) {
        Write-Warn 'Spicetify command not found.'
        return $false
    }

    Write-Info "Running spicetify $($Arguments -join ' ')..."
    & $spicetify @Arguments
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$ActionName completed."
        return $true
    }

    Write-Warn "$ActionName failed. Spotify may be running, unsupported, or recently updated."
    return $false
}

function Install-SpicetifyMarketplace {
    Write-Info 'Installing Spicetify Marketplace using the official installer...'
    try {
        Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1' | Invoke-Expression
        $script:Summary.Spotify.MarketplaceInstalled = 'OK'
        Write-Ok 'Marketplace install command completed.'
    } catch {
        Write-Warn "Marketplace install failed: $($_.Exception.Message)"
        $script:Summary.Spotify.MarketplaceInstalled = 'FAILED'
        return
    }

    $success = Invoke-Spicetify -ActionName 'spicetify apply' -Arguments @('apply')
    $script:Summary.Spotify.LastApply = if ($success) { 'OK' } else { 'FAILED' }
}

function Install-SetupSpicetify {
    Write-Section 'Install/Setup Spicetify'

    [void](Ensure-SpotifyInstalled)
    Stop-SpotifyIfRequested

    if (Read-YesNo -Prompt 'Freeze Spotify updates?' -Default 'Y') {
        [void](Disable-SpotifyAutoUpdate)
    } else {
        $script:Summary.Spotify.UpdateFreeze = 'Skipped'
    }

    $spicetify = Ensure-SpicetifyInstalled
    if (-not $spicetify) { return }

    $success = Invoke-Spicetify -ActionName 'spicetify backup apply' -Arguments @('backup', 'apply')
    $script:Summary.Spotify.BackupApply = if ($success) { 'OK' } else { 'FAILED' }
    $script:Summary.Spotify.LastApply = $script:Summary.Spotify.BackupApply

    if (Read-YesNo -Prompt 'Install Spicetify Marketplace?' -Default 'N') {
        Install-SpicetifyMarketplace
    } else {
        $script:Summary.Spotify.MarketplaceInstalled = 'Skipped'
    }
}

function Setup-SpotifyCustomization {
    while ($true) {
        Write-Header -Title 'Spotify Customization' -Subtitle 'Spicetify setup, apply, restore, and update freeze'
        Write-MenuItem -Key '1' -Label 'Install/Setup Spicetify' -Hint 'Install Spotify, Spicetify, backup/apply'
        Write-MenuItem -Key '2' -Label 'Re-apply Spicetify' -Hint 'Run spicetify apply'
        Write-MenuItem -Key '3' -Label 'Restore Spotify backup' -Hint 'Run spicetify restore'
        Write-MenuItem -Key '4' -Label 'Freeze Spotify updates' -Hint 'Lock the Spotify Update folder'
        Write-MenuItem -Key '0' -Label 'Back'

        $choice = Read-MenuChoice
        switch ($choice) {
            '1' { Install-SetupSpicetify }
            '2' {
                Stop-SpotifyIfRequested
                $success = Invoke-Spicetify -ActionName 'spicetify apply' -Arguments @('apply')
                $script:Summary.Spotify.LastApply = if ($success) { 'OK' } else { 'FAILED' }
            }
            '3' {
                Stop-SpotifyIfRequested
                $success = Invoke-Spicetify -ActionName 'spicetify restore' -Arguments @('restore')
                $script:Summary.Spotify.Restore = if ($success) { 'OK' } else { 'FAILED' }
            }
            '4' { [void](Disable-SpotifyAutoUpdate) }
            '0' { return }
            default { Write-Warn 'Invalid option.' }
        }
    }
}

function Print-FinalSummary {
    Write-Header -Title 'Setup Summary' -Subtitle 'Final status from this run'

    Write-Section 'Apps'
    foreach ($app in $Apps) {
        $status = if ($script:Summary.Apps.Contains($app.Name)) { $script:Summary.Apps[$app.Name] } else { 'Not run' }
        Write-SummaryRow -Name $app.Name -Status $status
    }

    Write-Section 'VS Code Extensions'
    foreach ($extension in $VSCodeExtensions) {
        $status = if ($script:Summary.Extensions.Contains($extension)) { $script:Summary.Extensions[$extension] } else { 'Not run' }
        Write-SummaryRow -Name $extension -Status $status
    }

    Write-Section 'Git'
    Write-SummaryRow -Name 'user.name' -Status $script:Summary.Git.UserName
    Write-SummaryRow -Name 'user.email' -Status $script:Summary.Git.UserEmail
    Write-SummaryRow -Name 'default branch' -Status $script:Summary.Git.DefaultBranch
    Write-SummaryRow -Name 'credential helper' -Status $script:Summary.Git.CredentialHelper
    Write-SummaryRow -Name 'GitHub CLI auth status' -Status $script:Summary.Git.GitHubCliAuthStatus
    Write-SummaryRow -Name 'SSH key' -Status $script:Summary.Git.SshKey

    Write-Section 'Spotify'
    Write-SummaryRow -Name 'Spotify installed' -Status $script:Summary.Spotify.SpotifyInstalled
    Write-SummaryRow -Name 'Spicetify installed' -Status $script:Summary.Spotify.SpicetifyInstalled
    Write-SummaryRow -Name 'Update freeze' -Status $script:Summary.Spotify.UpdateFreeze
    Write-SummaryRow -Name 'Backup/apply' -Status $script:Summary.Spotify.BackupApply
    Write-SummaryRow -Name 'Marketplace installed' -Status $script:Summary.Spotify.MarketplaceInstalled
    Write-SummaryRow -Name 'Last apply status' -Status $script:Summary.Spotify.LastApply
    Write-SummaryRow -Name 'Restore status' -Status $script:Summary.Spotify.Restore

    Write-Host ''
    Write-Host 'If some commands are not recognized, open a new terminal window and try again.' -ForegroundColor Cyan
}

function Invoke-FullSetup {
    Test-IsAdmin | Out-Null
    Test-Winget | Out-Null
    Install-Apps
    Install-VSCodeExtensions
    Setup-GitProfile
    Setup-SpotifyCustomization
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Header -Title 'Setup New PC' -Subtitle 'Windows dev and personal bootstrap tool'
        Write-MenuItem -Key '1' -Label 'Full setup' -Hint 'Apps, VS Code extensions, Git, Spotify'
        Write-MenuItem -Key '2' -Label 'Install apps only' -Hint 'winget packages'
        Write-MenuItem -Key '3' -Label 'Install VS Code extensions only'
        Write-MenuItem -Key '4' -Label 'Setup Git only' -Hint 'profile, editor, credentials, SSH'
        Write-MenuItem -Key '5' -Label 'Setup Spotify Customization' -Hint 'Spicetify and update freeze'
        Write-MenuItem -Key '0' -Label 'Exit'

        $choice = Read-MenuChoice
        switch ($choice) {
            '1' { Invoke-FullSetup; Print-FinalSummary }
            '2' { Test-IsAdmin | Out-Null; Test-Winget | Out-Null; Install-Apps; Print-FinalSummary }
            '3' { Install-VSCodeExtensions; Print-FinalSummary }
            '4' { Setup-GitProfile; Print-FinalSummary }
            '5' { Setup-SpotifyCustomization; Print-FinalSummary }
            '0' { Print-FinalSummary; return }
            default { Write-Warn 'Invalid option.' }
        }
    }
}

Show-MainMenu
