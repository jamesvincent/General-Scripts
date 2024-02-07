# Download latest sabnzbd/sabnzbd release from github
$ProgressPreference = 'SilentlyContinue'
$repo = "sabnzbd/sabnzbd"
$releases = "https://api.github.com/repos/$repo/releases"

# Calculate the latest release
Write-Host Determining latest release
$tag = (Invoke-WebRequest $releases | ConvertFrom-Json)[0].tag_name

$download = "https://github.com/$repo/releases/download/$tag/SABnzbd-$tag-win-setup.exe"
$zip = "SABnzbd-$tag-win-setup.exe"
$dir = "$name-$tag"

# Download the latest release
Write-Host "Downloading $zip..."
Invoke-WebRequest $download -Out $zip

# Stop the SAB service
stop-service -name "SABnzbd" -Force

# Perform a silent install of the download
Start-Process -Wait -FilePath "$zip" -ArgumentList "/S" -PassThru

# Restart the SAB service
start-service -name "SABnzbd"

# Removing temp files
Remove-Item $zip -Force
