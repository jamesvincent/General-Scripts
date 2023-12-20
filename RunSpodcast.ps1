#Dirty Wrapper for heywoodlh/spodcast Docker Image on Windows
$Stamp = (Get-Date).toString("yyyy-MM-dd__ HH-mm-ss")
Start-Transcript -Path "C:\ProgramData\spodcast\html\Spodcast_$Stamp.log" -Append
Write-Output "Check for older files and remove them"
Get-ChildItem -Path  "C:\ProgramData\spodcast\html" -Recurse -include *.log | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-14) } | Remove-Item
Write-Output "Stop any existing/stale containers"
docker stop $(docker ps -a -q)
docker container prune -f
Write-Output "Check for new Image updates"
docker pull heywoodlh/spodcast:latest
docker pull heywoodlh/spodcast-web:latest
docker pull heywoodlh/spodcast-cron:latest
Write-Output "Run Spodcast and check for latest episodes"
docker run --rm -it -v c:\ProgramData\spodcast:/data heywoodlh/spodcast -c /data/spodcast.json --log-level debug --transcode yes --root-path /data/html --rss-feed yes --max-episodes 8 https://open.spotify.com/show/XXXSHOWIDHEREXXX https://open.spotify.com/show/XXXSHOWIDHEREXXX
docker container prune -f
Write-Output "Complete"
Write-Output "Killing Docker Desktop Sessions"
Start-Sleep -Seconds 10
taskkill /F /IM "Docker Desktop.exe"
docker image prune -f
Stop-Transcript
