function Start-Spinner {
  param([int]$Duration=3,[int]$FPS=15,[string[]]$Frames=@('|','/','-','\'))
  $end=(Get-Date).AddSeconds($Duration); $i=0
  while((Get-Date) -lt $end){
    $f=$Frames[$i++%$Frames.Count]
    Write-Host "`r$f Loading..." -NoNewline
    Start-Sleep -Milliseconds (1000/$FPS)
  }; Write-Host "`r Done!     "
}

# Set duration to an env timer var to control duration of animation
Start-Spinner -Duration 5 -FPS 10