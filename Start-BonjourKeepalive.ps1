# A probably overconvoluted way of attempting to keep the Bonjour service alive so that you can go for lunch, and still have Shairport work after not connecting for a while.
# James Vincent - June 2025

while ($true) {
    # Define the service type and expected instance name
    $serviceType = "_raop._tcp."
    $targetInstance = "0068F1D7BA84@VINI-OFFICE"
    $shairportPath = "C:\Users\James\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Shairport4wx64.exe"

    # Define paths
    $inputFile = "$env:TEMP\dns-sd_output.txt"
    $outputFile = "$env:TEMP\dns-sd_output.csv"

    $process = Start-Process -FilePath "dns-sd" -ArgumentList "-B $serviceType" -RedirectStandardOutput $inputFile -NoNewWindow -PassThru

    # Wait for 10 seconds to allow discovery
    Start-Sleep -Seconds 10

    # Stop the dns-sd process
    try {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Failed to stop dns-sd process: $_"
    }

    # Read the file content
    $lines = Get-Content $inputFile

    # Skip lines that aren't data
    $dataLines = $lines | Where-Object {
        $_ -and ($_ -notmatch "^Browsing") -and ($_ -notmatch "^Timestamp\s+A/R")
    }

    # Parse lines into objects
    $objects = foreach ($line in $dataLines) {
        # Use regex to parse fields
        if ($line -match '^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)$') {
            [PSCustomObject]@{
                Timestamp      = $matches[1]
                'A/R'          = $matches[2]
                'Flags'        = $matches[3]
                'Interface'    = $matches[4]
                'Domain'       = $matches[5]
                'Service Type' = $matches[6]
                'Instance Name'= $matches[7]
            }
        }
    }

    # Keep only the latest entry for each instance name (based on timestamp)
    $latestInstances = $objects | Sort-Object 'Instance Name', Timestamp -Descending |
                    Group-Object 'Instance Name' |
                    ForEach-Object { $_.Group | Select-Object -First 1 }

    # Export to CSV
    $latestInstances | Export-Csv -Path $outputFile -NoTypeInformation

    #Write-Host "Conversion completed. Output saved to $outputFile"

    # Re-import the CSV to query it
    $csvData = Import-Csv -Path $outputFile

    # Find the target instance
    $matchingEntries = $csvData | Where-Object {
        $_.'Instance Name' -eq $targetInstance
    }

    if ($matchingEntries.Count -eq 0) {
        Write-Host "❌ Instance '$targetInstance' not found in the CSV."
    } else {
        # Check if the interface is 24 (Assumed Playing/Connectable)
        $invalidFlags = $matchingEntries | Where-Object {
            [int]$_.'Interface' -notin 24
        }

        if ($invalidFlags.Count -gt 0) {
            Write-Host "❌ Instance '$targetInstance' has invalid Interface (Not 24, So, assume not playing)."
            # Start the application if not active
                if (Test-Path $shairportPath) {
                    if (-not (Get-Process -Name "Shairport4wx64" -ErrorAction SilentlyContinue)) {
                        Start-Process -FilePath $shairportPath
                        Write-Host "🚀 Started Shairport4wx64.exe and refreshed DNS-SD." -ForegroundColor Cyan
                        $process = Start-Process -FilePath "dns-sd" -ArgumentList "-B $serviceType" -NoNewWindow -PassThru
                    } else {
                        Write-Host "ℹ️ Shairport4wx64.exe is already running. DNS-SD refreshed." -ForegroundColor Gray
                        $process = Start-Process -FilePath "dns-sd" -ArgumentList "-B $serviceType" -NoNewWindow -PassThru
                    }
                } else {
                    Write-Warning "Shairport executable not found at: $shairportPath"
                }
        } else {
            Write-Host "✅ Instance '$targetInstance' found with valid Interface (24, Assumed Playing)."
            $process = Start-Process -FilePath "dns-sd" -ArgumentList "-B $serviceType" -NoNewWindow -PassThru
        }
    }

    # Wait for 10 
    Start-Sleep -Seconds 10

    # Stop the dns-sd process
    try {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Failed to stop dns-sd process: $_"
    }

    # Wait for 10 seconds before repeating
    Start-Sleep -Seconds 40
}