# Messing with terminal animations with Pwsh
# To change text shown, edit it in the first section under the CmdletBinding() params area.

function Show-RainbowScrollingText {
    <#
    .DESCRIPTION
        Creates a scrolling animation of the provided text with rainbow color transitions.
    .PARAMETER Text
        The text to display in the animation. Default includes both the Gothic font and Japanese text.
    .PARAMETER Duration
        Duration of the animation in seconds. Default is 10 seconds.
    .PARAMETER Speed
        Speed of the animation (1-10). Default is 5.


    .EXAMPLE
        Show-RainbowScrollingText
    .EXAMPLE
        Show-RainbowScrollingText -Duration 5 -Speed 8
    #>
    [CmdletBinding()]
    param (
        [string]$Text = "𝔰𝔢𝔭𝔢𝔯𝔢𝔱.𝔠𝔬𝔪 𝔰𝔢𝔭𝔢𝔯𝔢𝔱.𝔠𝔬𝔪 𝔰𝔢𝔭𝔢𝔯𝔢𝔱.𝔠𝔬𝔪 𝔰𝔢𝔭𝔢𝔯𝔢𝔱.𝔠𝔬𝔪 𝔰𝔢𝔭𝔢𝔯𝔢𝔱.𝔠𝔬𝔪 𝔰𝔢𝔭𝔢𝔯𝔢𝔱.𝔠𝔬𝔪`nセペレト セペレト セペレト セペレト セペレト セペレト セペレト セペレト",
        [int]$Duration = 10,
        [ValidateRange(1, 10)]
        [int]$Speed = 5
    )

    # ANSI escape code for cursor control and colors
    $ESC = [char]27
    $clearLine = "$ESC[2K"
    $returnToStart = "$ESC[G"

    # Define rainbow colors using ANSI escape codes
    $rainbowColors = @(
        "$ESC[38;2;255;0;0m",    # Red
        "$ESC[38;2;255;127;0m",  # Orange
        "$ESC[38;2;255;255;0m",  # Yellow
        "$ESC[38;2;0;255;0m",    # Green
        "$ESC[38;2;0;0;255m",    # Blue
        "$ESC[38;2;75;0;130m",   # Indigo
        "$ESC[38;2;148;0;211m"   # Violet
    )
    $resetColor = "$ESC[0m"

    # Calculate delay between frames based on speed
    $delay = [math]::Max(1, 100 - ($Speed * 10))

    # Get console width
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width

    # Prepare the text for scrolling by adding padding
    $paddedText = " " * $consoleWidth + $Text + " " * $consoleWidth

    # Calculate total frames based on duration and delay
    $totalFrames = ($Duration * 1000) / $delay

    # Save cursor position
    $originalCursorVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false

    try {
        # Split text into lines
        $lines = $paddedText -split "`n"
        $maxLength = ($lines | Measure-Object -Property Length -Maximum).Maximum

        # Ensure all lines have the same length for consistent scrolling
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Length -lt $maxLength) {
                $lines[$i] = $lines[$i] + " " * ($maxLength - $lines[$i].Length)
            }
        }

        # Animation loop
        $startTime = Get-Date
        $colorIndex = 0
        $position = 0

        while ((Get-Date) -lt $startTime.AddSeconds($Duration)) {
            # Clear previous output
            Write-Host "`r$clearLine" -NoNewline

            # Display each line with scrolling effect
            foreach ($line in $lines) {
                # Calculate the visible portion of the text
                $visibleText = $line.Substring($position % $line.Length, [Math]::Min($consoleWidth, $line.Length - ($position % $line.Length)))
                
                # If we need more characters to fill the console width
                if ($visibleText.Length -lt $consoleWidth) {
                    $visibleText += $line.Substring(0, $consoleWidth - $visibleText.Length)
                }

                # Apply rainbow colors to the text
                $coloredText = ""
                for ($i = 0; $i -lt $visibleText.Length; $i++) {
                    $currentColorIndex = ($colorIndex + $i) % $rainbowColors.Count
                    $coloredText += "$($rainbowColors[$currentColorIndex])$($visibleText[$i])"
                }

                # Output the colored text
                Write-Host "$coloredText$resetColor"
            }

            # Move cursor back up to overwrite the same lines
            Write-Host "$ESC[${lines.Count}A$returnToStart" -NoNewline

            # Update position and color for next frame
            $position++
            $colorIndex = ($colorIndex + 1) % $rainbowColors.Count

            # Delay between frames
            Start-Sleep -Milliseconds $delay
        }

        # Clear the animation at the end
        foreach ($line in $lines) {
            Write-Host "$clearLine"
        }
        Write-Host "$ESC[${lines.Count}A$returnToStart" -NoNewline
    }
    finally {
        # Restore cursor visibility
        [Console]::CursorVisible = $originalCursorVisible
    }
}

# Example usage:
Show-RainbowScrollingText # Comment out or add specified speed and duration params
# Show-RainbowScrollingText -Duration 5 -Speed 8
# Show-RainbowScrollingText -Text "Custom text to scroll" -Duration 3 -Speed 10