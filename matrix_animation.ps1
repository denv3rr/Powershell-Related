# Ensure UTF-8 out
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$PSStyle.OutputRendering = 'Ansi'


# Ensure ANSI is honored (Windows Terminal is fine, but this makes it explicit)
$PSStyle.OutputRendering = 'Ansi'

# Optional: store once per session so $windowSize is available before the call
$windowSize = $Host.UI.RawUI.WindowSize

function Show-Matrix {
  param(
    [int]$Cols = $Host.UI.RawUI.WindowSize.Width,
    [int]$Rows = $Host.UI.RawUI.WindowSize.Height,
    [int]$FPS  = 45,
    [int]$Trail = 12,     # length of the fading tail per column
    [switch]$Infinite    # run until Ctrl+C
  )

  $esc = [char]27

  $katakana = @(
  'ア','イ','ウ','エ','オ',
  'カ','キ','ク','ケ','コ',
  'サ','シ','ス','セ','ソ',
  'タ','チ','ツ','テ','ト',
  'ナ','ニ','ヌ','ネ','ノ',
  'ハ','ヒ','フ','ヘ','ホ',
  'マ','ミ','ム','メ','モ',
  'ヤ','ユ','ヨ',
  'ラ','リ','ル','レ','ロ',
  'ワ','ヲ','ン'
  )

  # Heads & speeds per column (independent “rain”)
  $Cols   = [math]::Max(1, $Cols)
  $Rows   = [math]::Max(2, $Rows)
  $heads  = New-Object int[] $Cols
  $speeds = New-Object int[] $Cols
  for ($c=0; $c -lt $Cols; $c++) {
    $heads[$c]  = Get-Random -Min 1 -Max $Rows
    $speeds[$c] = Get-Random -Min 1 -Max 2  # 1–2 rows/frame, gives variance
  }

  # Small helper: compute a green shade that fades with distance i from head
  function Get-GreenRGB([int]$i, [int]$trail) {
    # Bright head, exponential fade; clamp to byte range
    $t = if ($trail -gt 0) { [double]$i / $trail } else { 1.0 }
    $g = [int]([math]::Round(220 * [math]::Exp(-2.2 * $t)) + 35)  # 35..255
    $r = [int]([math]::Round(12  * [math]::Exp(-2.2 * $t)))       # 0..12
    $b = $r
    return @($r,$g,$b)
  }

  # Hide cursor
  [Console]::Write("$esc[?25l")

  $frameMs = [math]::Max(1, [int](1000 / $FPS))

  try {
    while ($true) {
      # Handle resize on the fly
      $curW = [Console]::WindowWidth
      $curH = [Console]::WindowHeight
      if ($curW -gt 0 -and $curH -gt 1 -and ($curW -ne $Cols -or $curH -ne $Rows)) {
        $Cols = $curW; $Rows = $curH
        $heads  = New-Object int[] $Cols
        $speeds = New-Object int[] $Cols
        for ($c=0; $c -lt $Cols; $c++) {
          $heads[$c]  = Get-Random -Min 1 -Max $Rows
          $speeds[$c] = Get-Random -Min 1 -Max 2
        }
      }

      # Save cursor
      [Console]::Write("$esc[s")

      # For each column, draw head + fading trail
      for ($col=1; $col -le $Cols; $col++) {
        # advance head
        $heads[$col-1] = (($heads[$col-1] + $speeds[$col-1] - 1) % $Rows) + 1

        for ($i=0; $i -le $Trail; $i++) {
          $row = $heads[$col-1] - $i
          if ($row -lt 1) { $row += $Rows }   # wrap upwards

          $rgb = Get-GreenRGB $i $Trail
          $ch  = if ($i -eq 0 -or (Get-Random -Min 0 -Max 100) -lt 15) {
                   # head always new; trail occasionally changes (15%)
                   $katakana | Get-Random
                 } else {
                   # reuse a “dot” so the visual looks like fading, not noise
                   '･'
                 }

          # Color + move + draw (38;2;r;g;b = truecolor foreground)
          [Console]::Write( ("$esc[38;2;{0};{1};{2}m$esc[{3};{4}H{5}" -f $rgb[0],$rgb[1],$rgb[2],$row,$col,$ch) )
        }
      }

      # Reset color & restore cursor
      [Console]::Write("$esc[0m$esc[u")

      Start-Sleep -Milliseconds $frameMs

      if (-not $Infinite) { break }  # single frame (for testing) unless -Infinite
    }

    # If you wanted time-bounded behavior, loop with a stopwatch here.
    # For truly indefinite, rely on Ctrl+C to break out of the try{}.
    if ($Infinite) {
      while ($true) {
        # (same body as above)
        # advance heads, draw trails, sleep; duplicated for clarity
        $curW = [Console]::WindowWidth
        $curH = [Console]::WindowHeight
        if ($curW -gt 0 -and $curH -gt 1 -and ($curW -ne $Cols -or $curH -ne $Rows)) {
          $Cols = $curW; $Rows = $curH
          $heads  = New-Object int[] $Cols
          $speeds = New-Object int[] $Cols
          for ($c=0; $c -lt $Cols; $c++) {
            $heads[$c]  = Get-Random -Min 1 -Max $Rows
            $speeds[$c] = Get-Random -Min 1 -Max 2
          }
        }

        [Console]::Write("$esc[s")
        for ($col=1; $col -le $Cols; $col++) {
          $heads[$col-1] = (($heads[$col-1] + $speeds[$col-1] - 1) % $Rows) + 1
          for ($i=0; $i -le $Trail; $i++) {
            $row = $heads[$col-1] - $i
            if ($row -lt 1) { $row += $Rows }
            $rgb = Get-GreenRGB $i $Trail
            $ch  = if ($i -eq 0 -or (Get-Random -Min 0 -Max 100) -lt 15) { $katakana | Get-Random } else { '･' }
            [Console]::Write( ("$esc[38;2;{0};{1};{2}m$esc[{3};{4}H{5}" -f $rgb[0],$rgb[1],$rgb[2],$row,$col,$ch) )
          }
        }
        [Console]::Write("$esc[0m$esc[u")
        Start-Sleep -Milliseconds $frameMs
      }
    }
  }
  catch {
    # Swallow Ctrl+C / transient write errors
  }
  finally {
    # Clear color, show cursor again (don’t clear the screen)
    [Console]::Write("$esc[0m$esc[?25h")
  }
}


Show-Matrix -FPS 60 -Trail 14 -Infinite
