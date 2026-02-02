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
    Created: 2026-02-02
    Version: 1.0
#>

# ================================
# Configuration
# ================================
$MEGAcmdDir  = "$env:LOCALAPPDATA\MEGAcmd"
$MegaRemote  = "/"
$UsrFile     = Join-Path $MEGAcmdDir "mega.usr"
$PwdFile     = Join-Path $MEGAcmdDir "mega.pwd"
$LogFile     = Join-Path $MEGAcmdDir "MegaMount.log"

# ================================
# Logging Function (Host + Log)
# ================================
function Write-Log {
    param([string]$Message)
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $Message" |
        Tee-Object -FilePath $LogFile -Append
}

function Write-LogHost {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
    Write-Log $Message
}

# ================================
# Check Admin Rights
# ================================
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ================================
# Check if MEGAcmd is installed
# ================================
$Installed = Get-ChildItem -Path "$env:ProgramFiles\MEGAcmd\MEGAcmd*.exe","$env:LOCALAPPDATA\MEGAcmd\MEGAcmd*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $Installed -and -not $IsAdmin) {
    Write-LogHost "First-time installation requires Administrator rights." Red
    exit 1
} elseif ($Installed -and $IsAdmin) {
    Write-LogHost "Run this script as a standard user after installation." Yellow
    exit 1
}

# ================================
# Install MEGAcmd and WinFSP if needed
# ================================
if (-not $Installed) {
    Write-LogHost "MEGAcmd not found. Installing..." Yellow

    try {
        # --- WinFSP Installation ---
        $WinFspApiUrl = "https://api.github.com/repos/winfsp/winfsp/releases/latest"
        $WinFspAsset = (Invoke-RestMethod -Uri $WinFspApiUrl -Headers @{ "User-Agent" = "PowerShell" }).assets |
                        Where-Object { $_.browser_download_url -match "\.msi$" } |
                        Select-Object -First 1
        if (-not $WinFspAsset) { throw "Unable to locate WinFsp MSI." }

        $WinFspFile = Join-Path $env:TEMP ([IO.Path]::GetFileName($WinFspAsset.browser_download_url))
        Write-LogHost "Downloading WinFsp from $($WinFspAsset.browser_download_url)" Yellow
        Invoke-WebRequest -Uri $WinFspAsset.browser_download_url -OutFile $WinFspFile

        Write-LogHost "Installing WinFsp silently..." Yellow
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$WinFspFile`" /qn /norestart" -Wait -NoNewWindow

        # --- MEGAcmd Installation ---
        $MEGADownloadUrl = "https://mega.nz/MEGAcmdSetup.exe"
        $InstallerPath = Join-Path $env:TEMP "MEGAcmdSetup.exe"
        Invoke-WebRequest -Uri $MEGADownloadUrl -OutFile $InstallerPath

        Write-LogHost "Installing MEGAcmd..." Green
        Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait

        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")

        # Verify installation
        $Installed = Get-ChildItem -Path "$env:ProgramFiles\MEGAcmd\MEGAcmd*.exe","$env:LOCALAPPDATA\MEGAcmd\MEGAcmd*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Installed) {
            Write-LogHost "MEGAcmd installed successfully (WinFsp included)." Green
        } else {
            throw "MEGAcmd installation failed."
        }
    } catch {
        Write-LogHost "Installation failed: $_" Red
        throw $_
    }
}

# ================================
# Credential Management
# ================================
function Get-MegaCredentials {
    param ($UsrFile, $PwdFile)

    if (-not (Test-Path (Split-Path $UsrFile))) { New-Item -ItemType Directory -Path (Split-Path $UsrFile) | Out-Null }

    function LoadOrPrompt($file, $prompt) {
        if (Test-Path $file) {
            Get-Content $file | ConvertTo-SecureString
        } else {
            $secure = Read-Host $prompt -AsSecureString
            $secure | ConvertFrom-SecureString | Set-Content $file
            Write-LogHost "Encrypted credential saved at $file" Green
            $secure
        }
    }

    $SecureUsr = LoadOrPrompt $UsrFile "Enter your MEGA username (email)"
    $SecurePwd = LoadOrPrompt $PwdFile "Enter your MEGA password"

    return @(
        [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureUsr)),
        [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePwd))
    )
}

$credentials = Get-MegaCredentials -UsrFile $UsrFile -PwdFile $PwdFile
$PlainUsr = $credentials[0]
$PlainPwd = $credentials[1]

# ================================
# Add MEGAcmd to PATH if missing
# ================================
$megaCmdPath = Join-Path $env:LOCALAPPDATA "MEGAcmd"

if ($env:PATH -notlike "*$megaCmdPath*") {
    $env:PATH = "$megaCmdPath;" + $env:PATH
    Write-LogHost "Added MEGAcmd path to the environment variables." Green
} else {
    Write-LogHost "MEGAcmd path is already in the PATH." White
}

# ================================
# MEGAcmd Login
# ================================

if (-not (Start-Process `
    -FilePath "$MEGAcmdDir\mega-whoami" `
    -NoNewWindow `
    -PassThru).ExitCode)
{
    Write-LogHost "Logging in..." White

    $loginProc = Start-Process `
        -FilePath "$MEGAcmdDir\mega-login" `
        -ArgumentList $PlainUsr, $PlainPwd `
        -NoNewWindow `
        -Wait `
        -PassThru

    if ($loginProc.ExitCode -ne 0) {
        throw "MEGA login failed"
    }

    Write-LogHost "MEGA login successful" Green
}
else {
    Write-LogHost "Already logged in" White
}

# Clear plaintext credentials ASAP
$PlainUsr = $null
$PlainPwd = $null

# ================================
# Map MEGA Drive
# ================================
$proc = Start-Process -FilePath "$MEGAcmdDir\MEGAcmdServer.exe" -PassThru
& "$MEGAcmdDir\MegaClient.exe" fuse-add $MegaRemote
Write-Host "Process started with PID $($proc.Id)"

$drive = & ".\MEGAclient.exe" fuse-show MEGA 2>&1

if (-not $drive) {
    throw "No output from MEGAclient.exe"
    Write-LogHost "No output from MEGAclient.exe" Red
    exit 1
}

$enabledLine = $drive | Where-Object { $_ -match '^\s*Enabled:' }

if (-not $enabledLine) {
    throw "Could not find 'Enabled:' line in output"
    Write-LogHost "Could not find 'Enabled:' line in output" Red
    exit 1    
}

$enabledValue = ($enabledLine -split ':')[1].Trim()

if ($enabledValue -eq 'YES') {
    Write-Host "MEGA mount is enabled"
    Write-LogHost "MEGA drive is mapped to $MegaRemote" Green
    exit 0
} else {
    Write-Host "MEGA mount is NOT enabled"
    Write-LogHost "MEGA mount is NOT mounted" Red
    exit 1
}

$loveyou = @"
  ******       ******
 ********     ********
**********   **********
*********** ***********
***********************
 *********************
  *******************
   *****************
    ***************
     *************
      ***********
       *********
        *******
         *****
          ***
           *
"@

Write-LogHost "Script completed." Green
exit 0