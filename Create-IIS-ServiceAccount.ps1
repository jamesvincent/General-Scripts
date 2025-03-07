# James Vincent - March 2025
# Create a service account with a random, unknown password.
# Grant "Log on as a service" rights to the account.
# Check if IIS is enabled/installed, and if not, enable/install it.
# Configure the IIS Service (W3SVC) to run under the new service account.

$Timestamp = (Get-Date).toString("ddMMyyyy-HHmm")
$Logfile = "./Create-IIS-ServiceAccount-$Timestamp.log"
function Write-Log
{
Param ([string]$LogString)
    $Stamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
    $LogMessage = "$Stamp $LogString"
    Add-content $LogFile -value $LogMessage -Encoding UTF8
}

# Define Variables
$ServiceAccountName = "SvcIISAccount"

# Generate a random secure password
$Password = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 20 | ForEach-Object {[char]$_})
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# Create the service account if it doesn't exist
if (-not (Get-LocalUser -Name $ServiceAccountName -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $ServiceAccountName -Password $SecurePassword -Description "IIS Service Account" -PasswordNeverExpires:$true
    Write-Host "[+] Created service account: $ServiceAccountName"
    Write-Log "[+] Created service account: $ServiceAccountName"
} else {
    Write-Host "[!] Service account $ServiceAccountName already exists"
    Write-Log "[!] Service account $ServiceAccountName already exists"
}

# Add the account to "Log on as a service"
Write-Host "[!] Checking to see if $ServiceAccountName has 'Log on as a service' rights"
Write-Log "[!] Created service account: $ServiceAccountName has 'Log on as a service' rights"
Write-Host "[!] Gathering data..."
Write-Log "[!] Gathering data..."
$ServiceLogonRight = "SeServiceLogonRight"
$TempFile = "$env:TEMP\secpol.inf"

# Export the current security policy
secedit /export /cfg $TempFile /areas USER_RIGHTS

# Read the content of the security policy
$Policy = Get-Content $TempFile

# Find the Log on as a Service right
$ExistingEntry = $Policy | Where-Object { $_ -match "^$ServiceLogonRight" }

if ($ExistingEntry) {
    # If "SvcIISAccount" is already present
    if ($ExistingEntry -match "\b$ServiceAccountName\b") {
        Write-Host "[!] $ServiceAccountName already has 'Log on as a service' rights"
        Write-Log "[!] $ServiceAccountName already has 'Log on as a service' rights"
        Remove-Item $TempFile -Force
    }
} elseif (!$ExistingEntry) {  
    # Add a new entry if SeServiceLogonRight is not present
    $Policy += "`r`n$ServiceLogonRight = $env:COMPUTERNAME\$ServiceAccountName"

    # Save the modified policy
    $Policy | Set-Content $TempFile

    # Apply the updated security policy
    secedit /configure /db c:\windows\security\local.sdb /cfg $TempFile /areas USER_RIGHTS /quiet

    # Refresh Group Policy settings
    gpupdate /force

    # Cleanup
    Remove-Item $TempFile -Force
    Write-Host "[+] Added $ServiceAccountName to 'Log on as a service'"
    Write-Log "[+] Added $ServiceAccountName to 'Log on as a service'"
}

# Define the IIS optional features within Windows 11
$WindowsFeaturesList = @(
    "IIS-WebServerRole",
    "IIS-WebServer",
    "IIS-CommonHttpFeatures",
    "IIS-HttpErrors",
    "IIS-ApplicationDevelopment",
    "IIS-Security",
    "IIS-RequestFiltering",
    "IIS-NetFxExtensibility45",
    "IIS-HealthAndDiagnostics",
    "IIS-HttpLogging",
    "IIS-RequestMonitor",
    "IIS-Performance",
    "IIS-WebServerManagementTools",
    "IIS-StaticContent",
    "IIS-DefaultDocument",
    "IIS-DirectoryBrowsing",
    "IIS-ASPNET45",
    "IIS-ISAPIExtensions",
    "IIS-ISAPIFilter",
    "IIS-HttpCompressionStatic",
    "IIS-ManagementConsole",
    "NetFx4Extended-ASPNET45"
)

# Check if IIS is installed or enabled within Windows 11, install it if not.
$Feature = Get-WindowsOptionalFeature -Online -FeatureName "IIS-WebServer"

if ($Feature.State -eq "Enabled") {
    Write-Host "[!] IIS is already installed."
    Write-Log "[!] IIS is already installed."
} else {
    Write-Host "[!] IIS is not installed. Installing..."
    Write-Log "[!] IIS is not installed. Installing..."
    Enable-WindowsOptionalFeature -FeatureName $WindowsFeaturesList -Online -LogPath 'C:\Windows\Logs\Software\IIS_EnableWindowsFeatures.log'
    # Check again, to see if IIS is now installed or enabled within Windows 11
    $Feature = Get-WindowsOptionalFeature -Online -FeatureName "IIS-WebServer"
        if ($Feature.State -eq "Enabled") {
        Write-Host "[+] IIS installed successfully. A restart may be required."
        Write-Log "[+] IIS installed successfully. A restart may be required."
        } else {
        Write-Host "[!] IIS is not installed. Check IIS native logs for errors..."
        Write-Log "[!] IIS is not installed. Check IIS native logs for errors..."
        }
}

# # Stop IIS Service before modifying
# $service = Get-Service -Name W3SVC
# if ($service.Status -eq 'Running') {
#     Stop-Service -Name W3SVC -Force -ErrorAction SilentlyContinue
#     Write-Host "[+] Stopped IIS Service"
#     Write-Log "[+] Stopped IIS Service"
# } else {
#     Write-Host "[!] IIS Service is already stopped"
#     Write-Log "[!] IIS Service is already stopped"
# }


# # Check again to see if W3SVC is stopped
# $service = Get-Service -Name W3SVC

# if ($service.Status -eq 'Stopped') {
#     #perform check to see which account it's configured to run as and update if not SAN

#     # Configure the IIS Service to run under the new service account
#     $Service = Get-WmiObject Win32_Service -Filter "Name='W3SVC'"
#     $Service.Change($null, $null, $null, $null, $null, $null, "$env:COMPUTERNAME\$ServiceAccountName", $Password, $null, $null, $null)
#     Write-Host "[+] Configured IIS Service to run as $ServiceAccountName"
#     Write-Log "[+] Configured IIS Service to run as $ServiceAccountName"
# } else {
#     Write-Host "[!] IIS Service is still running. Check manually."
#     Write-Log "[!] IIS Service is still running. Check manually."
# }


# Start IIS Service after making changes.
$service = Get-Service -Name W3SVC

if ($service.Status -ne 'Running') {
    Write-Host "[!] W3SVC is not running. Attempting to start..."
    Write-Log "[!] W3SVC is not running. Attempting to start..."
    Start-Service -Name W3SVC
    $service = Get-Service -Name W3SVC
    if ($service.Status -eq 'Running') {
        Write-Host "[+] W3SVC has been started."
        Write-Log "[+] W3SVC has been started."
    } else {
    Write-Host "[!] W3SVC is not running. Check manually."
    Write-Log "[!] W3SVC is not running. Check manually."
    }
} else {
    Write-Host "[!] W3SVC is already running."
    Write-Log "[!] W3SVC is already running."
}
