<#
.SYNOPSIS
    Add your MEGA cloud storage to Windows like a Drive.

.DESCRIPTION
    This PowerShell script automates the installation, login, and mounting of a MEGA FUSE drive on Windows. 
    It ensures that MEGAcmd and WinFSP are installed, securely handles credentials, logs actions, and verifies that the MEGA drive is successfully mounted.

    On first execution you will be prompted to enter credentials and 2FA if enabled. Watch the console during first run. Variables do not need changing unless desired.

.AUTHOR
    James Vincent

.EXAMPLE
    PS C:\> .\Mega-Mount.ps1

.NOTES
    URL: https://www.jamesvincent.co.uk
    Created: 2026-02-20
    Version: 1.3

.CHANGELOG
    1.3 - 2026-02-20
        Added an initial check to ensure the log file exists, to avoid errors on first run

    1.2 - 2026-02-06
        Fixed a bug in which MEGAcmdServer.exe launched within the process keeping the script alive
    
    1.1 - 2026-02-05
        Added additional checks and logging to catch failures.
        Enhanced security around the credentials.

    1.0 - 2026-02-02
        First release
#>

# ================================
# Configuration
# ================================
$MEGAcmdDir = Join-Path $env:LOCALAPPDATA 'MEGAcmd'
$MegaRemote = '/'
$CredFile   = Join-Path $MEGAcmdDir 'mega.cred'
$LogFile    = Join-Path $MEGAcmdDir 'MegaMount.log'

# ================================
# Logging
# ================================
function Write-Log {
    param([string]$Message)

    # Log file format: timestamp + message
    $line = "{0} - {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Out-File -FilePath $LogFile -Append -Encoding utf8
}

function Write-LogHost {
    param(
        [string]$Message,
        [ConsoleColor]$Color = 'White',
        [switch]$ShowTimestampInHost  # optional timestamp in host
    )

    # Format host output
    if ($ShowTimestampInHost) {
        $hostLine = $Message
    } else {
        $hostLine = $Message
    }

    # Display in host
    Write-Host $hostLine -ForegroundColor $Color

    # Always write full timestamp to log file
    Write-Log $Message
}

# ================================
# Create Log file if it does not exist
# ================================

if (!(Test-Path "$LogFile")) {
    New-Item -ItemType File -Path "$LogFile" | Out-Null
}

# ================================
# Admin / Install Check
# ================================
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($IsAdmin) {
    Write-LogHost "Running in administrative context" Red
} else {
    Write-LogHost "Running in standard context" Green
}

if (-not (Test-Path $MEGAcmdDir)) {
    New-Item -ItemType Directory -Path $MEGAcmdDir -Force | Out-Null
    Write-LogHost "Created directory: $MEGAcmdDir" Green
} else {
 # nada
}

$InstalledExe = Get-ChildItem `
    -Path "$env:ProgramFiles\MEGAcmd\MEGAcmd*.exe", "$env:LOCALAPPDATA\MEGAcmd\MEGAcmd*.exe" `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

# Check for mega.cred file
$CredFile = Join-Path $env:LOCALAPPDATA "MEGAcmd\mega.cred"
$CredExists = Test-Path $CredFile

if ($InstalledExe -and $CredExists) {
    $Installed = 1
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$MEGAcmdDir\MEGAcmdServer.exe"
    $psi.Arguments = "--silent"
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false

    [System.Diagnostics.Process]::Start($psi)
} elseif ($InstalledExe -and -not $CredExists) {
    $Installed = 1
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$MEGAcmdDir\MEGAcmdServer.exe"
    $psi.Arguments = "--silent"
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false

    [System.Diagnostics.Process]::Start($psi)
} else {
    $Installed = 0
}

if (-not $Installed -and -not $IsAdmin) {
    Write-LogHost 'First-time installation requires Administrator rights.' Red
    Write-Host "Press any key to exit..."

    $timeout = 15
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.Elapsed.TotalSeconds -lt $timeout) {
        if ([Console]::KeyAvailable) {
            [Console]::ReadKey($true) | Out-Null
            break
        }
        Start-Sleep -Milliseconds 200
    }
    exit 1
}

# ================================
# Install MEGAcmd + WinFsp
# ================================
if (-not $InstalledExe) {
    Write-LogHost 'MEGAcmd not found. Installing...' Yellow

    try {
        $winfsp = Invoke-RestMethod 'https://api.github.com/repos/winfsp/winfsp/releases/latest' `
            -Headers @{ 'User-Agent' = 'PowerShell' }

        $msi = $winfsp.assets |
            Where-Object browser_download_url -match '\.msi$' |
            Select-Object -First 1

        if (-not $msi) { throw 'WinFsp MSI not found.' }

        $msiPath = Join-Path $env:TEMP (Split-Path $msi.browser_download_url -Leaf)
        Invoke-WebRequest $msi.browser_download_url -OutFile $msiPath

        Start-Process msiexec.exe `
            -ArgumentList "/i `"$msiPath`" /qn /norestart" `
            -Wait

        $megaSetup = Join-Path $env:TEMP 'MEGAcmdSetup.exe'
        Invoke-WebRequest 'https://mega.nz/MEGAcmdSetup.exe' -OutFile $megaSetup

        Start-Process $megaSetup -ArgumentList '/S' -Wait

        $env:PATH =
            [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('PATH','User')

        Write-LogHost 'MEGAcmd installed successfully.' Green
    }
    catch {
        Write-LogHost "Installation failed: $_" Red
        throw
    }
}

# ================================
# Credential Handling
# ================================
function Get-MegaCredential {
    param(
        [string]$Path,
        [switch]$Force
    )

    if (-not $Force -and (Test-Path $Path)) {
        try {
            $cred = Import-Clixml $Path
            if ($cred -is [PSCredential]) {
                return $cred
            }
            else {
                Write-LogHost 'Stored credential is invalid. Re-prompting.' Yellow
            }
        }
        catch {
            Write-LogHost 'Stored credential corrupt. Re-prompting.' Yellow
        }
    }

    if (-not $CredExists) {
        Write-LogHost "Credentials not found" Red    
            $cred = Get-Credential -Message 'Enter your MEGA credentials'
            $cred | Export-Clixml $Path
            Write-LogHost "Credential securely stored at $Path" Green
            Write-LogHost "Please now re-run the script as a standard user" Green
            return $cred
        exit 0
    }
}

$MegaCred = Get-MegaCredential -Path $CredFile

# ================================
# MEGAcmd Helpers
# ================================
function Get-MegaLoginStatus {
    # Run mega-whoami and capture all output
    $out = & "$MEGAcmdDir\mega-whoami" 2>&1

    # Check for failure keywords
    if ($out -match "ERR" -or $out -match "Not logged in") {
        return 0
    }

    # Check for success
    if ($out -match "Account e-mail") {
        return 1
    }

    # Default fallback (unexpected output)
    return 0
}

# ================================
# Login
# ================================

if (-not (Get-MegaLoginStatus)) {
    Write-LogHost 'Not logged into MEGA.' Yellow
    & "$MEGAcmdDir\mega-login" `
        $MegaCred.UserName `
        $MegaCred.GetNetworkCredential().Password
}

if (-not (Get-MegaLoginStatus)) {
    Write-LogHost 'MEGA login failed.' Red
    throw 'MEGA login failed'
    exit 1
} else {
    Write-LogHost 'MEGA login successful.' Green
}

# ================================
# Map MEGA Drive
# ================================
#Start-Process "$MEGAcmdDir\MEGAcmdServer.exe" -PassThru
& "$MEGAcmdDir\MEGAclient.exe" fuse-add $MegaRemote | Out-Null

$driveInfo = & "$MEGAcmdDir\MEGAclient.exe" fuse-show MEGA 2>&1
$enabled = ($driveInfo |
    Where-Object { $_ -match '^\s*Enabled:' }) -split ':' |
    Select-Object -Last 1

if ($enabled -notlike '*YES*') {
    Write-LogHost 'MEGA mount is NOT enabled.' Red
    return
}

Write-LogHost "MEGA drive mounted at $MegaRemote" Green

# ================================
# Cleanup
# ================================
Remove-Variable MegaCred -Force
[GC]::Collect()

Write-LogHost 'Script completed successfully.' Green
exit 0


