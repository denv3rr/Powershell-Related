# Messing around with pwsh...
# Work in progress and still buggy
# Shoutout dylanaraps

function Get-PSNeofetch {
    <#
    A PowerShell-native system information display tool inspired by Neofetch.
    .DESCRIPTION
        Displays system information with ASCII art in a PowerShell console.
        Faster than the original Neofetch as it's native to PowerShell and focuses on main OS types.
    .EXAMPLE
        Get-PSNeofetch
    #>

    # ANSI color codes for colorful output
    $ESC = [char]27
    $colors = @{
        Reset = "$ESC[0m"
        Bold = "$ESC[1m"
        Red = "$ESC[31m"
        Green = "$ESC[32m"
        Yellow = "$ESC[33m"
        Blue = "$ESC[34m"
        Magenta = "$ESC[35m"
        Cyan = "$ESC[36m"
        White = "$ESC[37m"
        BrightRed = "$ESC[91m"
        BrightGreen = "$ESC[92m"
        BrightYellow = "$ESC[93m"
        BrightBlue = "$ESC[94m"
        BrightMagenta = "$ESC[95m"
        BrightCyan = "$ESC[96m"
        BrightWhite = "$ESC[97m"
    }

    # Get system information
    function Get-SystemInfo {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $cpu = Get-CimInstance Win32_Processor
        $gpu = Get-CimInstance Win32_VideoController
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $ram = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        $usedRam = [math]::Round(($cs.TotalPhysicalMemory - (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB) / 1GB, 2)
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $uptimeStr = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
        $diskTotal = [math]::Round($disk.Size / 1GB, 2)
        $diskFree = [math]::Round($disk.FreeSpace / 1GB, 2)
        $diskUsed = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
        $diskPercentage = [math]::Round(($disk.Size - $disk.FreeSpace) / $disk.Size * 100, 0)
        $windowsVersion = $os.Caption
        $windowsBuild = $os.BuildNumber
        $terminalTheme = Get-TerminalTheme
        $psVersion = $PSVersionTable.PSVersion.ToString()
        $shellVersion = "PowerShell $psVersion"
        $resolution = "$($gpu.CurrentHorizontalResolution) x $($gpu.CurrentVerticalResolution)"
        $username = [System.Environment]::UserName
        $hostname = [System.Environment]::MachineName
        $arch = if ([System.Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
        $packages = Get-InstalledPackages
        $wm = "Explorer"
        $de = "Aero"
        $wmTheme = Get-WindowsTheme

        return @{
            Username = $username
            Hostname = $hostname
            OS = "$windowsVersion $arch"
            Host = $cs.Manufacturer + " " + $cs.Model
            Kernel = (Get-CimInstance Win32_OperatingSystem).Version
            Uptime = $uptimeStr
            Packages = $packages
            Shell = $shellVersion
            Resolution = $resolution
            DE = $de
            WM = $wm
            WMTheme = $wmTheme
            Terminal = "Windows Terminal"
            TerminalTheme = $terminalTheme
            CPU = $cpu.Name -replace '\s+', ' '
            GPU = $gpu.Name
            Memory = "$usedRam GB / $ram GB"
            Disk = "$diskUsed GB / $diskTotal GB ($diskPercentage%)"
        }
    }

    # Get installed packages count
    function Get-InstalledPackages {
        $count = 0
        
        # Check for Scoop
        if (Test-Path "$env:USERPROFILE\scoop") {
            $scoopApps = (Get-ChildItem "$env:USERPROFILE\scoop\apps" -Directory).Count
            if ($scoopApps -gt 0) {
                $count += $scoopApps
                return "$count (scoop)"
            }
        }
        
        # Check for Chocolatey
        if (Test-Path "$env:ProgramData\chocolatey") {
            $chocoApps = (Get-ChildItem "$env:ProgramData\chocolatey\lib" -Directory).Count
            if ($chocoApps -gt 0) {
                $count += $chocoApps
                return "$count (choco)"
            }
        }
        
        # Check for Winget
        try {
            $wingetApps = (winget list --count 2>$null)
            if ($wingetApps -match '\d+') {
                $count = [int]($Matches[0])
                return "$count (winget)"
            }
        } catch {}
        
        # Fallback
        return "N/A"
    }

    # Get Windows theme information
    function Get-WindowsTheme {
        try {
            $personalize = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -ErrorAction SilentlyContinue
            if ($personalize) {
                if ($personalize.AppsUseLightTheme -eq 0) {
                    return "Dark"
                } else {
                    return "Light"
                }
            }
            return "Custom"
        } catch {
            return "Custom"
        }
    }

    # Get terminal theme information
    function Get-TerminalTheme {
        try {
            # Try to detect Windows Terminal theme
            $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
            if (Test-Path $terminalSettingsPath) {
                $settings = Get-Content $terminalSettingsPath -Raw | ConvertFrom-Json
                if ($settings.profiles.defaults.colorScheme) {
                    return $settings.profiles.defaults.colorScheme
                }
            }
            
            # Fallback to PowerShell console colors
            return "PowerShell Default"
        }
        catch {
            return "Unknown"
        }
    }

    # Get ASCII art for the current OS
    function Get-AsciiArt {
        $windowsAscii = @"
$($colors.BrightCyan)        ,.=:!!t3Z3z.,                  
$($colors.BrightCyan)       :tt:::tt333EE3                  
$($colors.BrightCyan)       Et:::ztt33EEEL $($colors.BrightBlue)@Ee.,      ..,   
$($colors.BrightCyan)      ;tt:::tt333EE7 $($colors.BrightBlue);EEEEEEttttt33#   
$($colors.BrightCyan)     :Et:::zt333EEQ. $($colors.BrightBlue)$EEEEEttttt33QL   
$($colors.BrightCyan)     it::::tt333EEF $($colors.BrightBlue)@EEEEEEttttt33F    
$($colors.BrightCyan)    ;3=*^```"*4EEV $($colors.BrightBlue):EEEEEEttttt33@.    
$($colors.BrightCyan)    ,.=::::!t=., $($colors.BrightBlue)` @EEEEEEtttz33QF     
$($colors.BrightCyan)   ;::::::::zt33)   $($colors.BrightBlue)"4EEEtttji3P*      
$($colors.BrightCyan)  :t::::::::tt33.$($colors.BrightBlue):Z3z..  `` ,..g.      
$($colors.BrightCyan)  i::::::::zt33F $($colors.BrightBlue)AEEEtttt::::ztF       
$($colors.BrightCyan) ;:::::::::t33V $($colors.BrightBlue);EEEttttt::::t3        
$($colors.BrightCyan) E::::::::zt33L $($colors.BrightBlue)@EEEtttt::::z3F        
$($colors.BrightCyan){3=*^```"*4E3) $($colors.BrightBlue);EEEtttt:::::tZ`        
$($colors.BrightCyan)             ` $($colors.BrightBlue):EEEEtttt::::z7         
$($colors.BrightCyan)                 "VEzjt:;;z>*`         
"@

        $ubuntuAscii = @"
$($colors.BrightRed)            .-/+oossssoo+/-.
$($colors.BrightRed)        `:+ssssssssssssssssss+:`
$($colors.BrightRed)      -+ssssssssssssssssssyyssss+-
$($colors.BrightRed)    .ossssssssssssssssss$($colors.BrightYellow)dMMMNy$($colors.BrightRed)sssso.
$($colors.BrightRed)   /sssssssssss$($colors.BrightYellow)hdmmNNmmyNMMMMh$($colors.BrightRed)ssssss/
$($colors.BrightRed)  +sssssssss$($colors.BrightYellow)hm$($colors.BrightRed)yd$($colors.BrightYellow)MMMMMMMNddddy$($colors.BrightRed)ssssssss+
$($colors.BrightRed) /ssssssss$($colors.BrightYellow)hNMMM$($colors.BrightRed)yh$($colors.BrightYellow)hyyyyhmNMMMNh$($colors.BrightRed)ssssssss/
$($colors.BrightRed).ssssssss$($colors.BrightYellow)dMMMNh$($colors.BrightRed)ssssssssss$($colors.BrightYellow)hNMMMd$($colors.BrightRed)ssssssss.
$($colors.BrightRed)+ssss$($colors.BrightYellow)hhhyNMMNy$($colors.BrightRed)ssssssssssss$($colors.BrightYellow)yNMMMy$($colors.BrightRed)sssssss+
$($colors.BrightRed)oss$($colors.BrightYellow)yNMMMNyMMh$($colors.BrightRed)ssssssssssssss$($colors.BrightYellow)hmmmh$($colors.BrightRed)ssssssso
$($colors.BrightRed)oss$($colors.BrightYellow)yNMMMNyMMh$($colors.BrightRed)sssssssssssssshmmmh$($colors.BrightRed)ssssssso
$($colors.BrightRed)+ssss$($colors.BrightYellow)hhhyNMMNy$($colors.BrightRed)ssssssssssss$($colors.BrightYellow)yNMMMy$($colors.BrightRed)sssssss+
$($colors.BrightRed).ssssssss$($colors.BrightYellow)dMMMNh$($colors.BrightRed)ssssssssss$($colors.BrightYellow)hNMMMd$($colors.BrightRed)ssssssss.
$($colors.BrightRed) /ssssssss$($colors.BrightYellow)hNMMM$($colors.BrightRed)yh$($colors.BrightYellow)hyyyyhdNMMMNh$($colors.BrightRed)ssssssss/
$($colors.BrightRed)  +sssssssss$($colors.BrightYellow)dm$($colors.BrightRed)yd$($colors.BrightYellow)MMMMMMMMddddy$($colors.BrightRed)ssssssss+
$($colors.BrightRed)   /sssssssssss$($colors.BrightYellow)hdmNNNNmyNMMMMh$($colors.BrightRed)ssssss/
$($colors.BrightRed)    .ossssssssssssssssss$($colors.BrightYellow)dMMMNy$($colors.BrightRed)sssso.
$($colors.BrightRed)      -+sssssssssssssssss$($colors.BrightYellow)yyy$($colors.BrightRed)ssss+-
$($colors.BrightRed)        `:+ssssssssssssssssss+:`
$($colors.BrightRed)            .-/+oossssoo+/-.
"@

        $macosAscii = @"
$($colors.Green)                    'c.
$($colors.Green)                 ,xNMM.
$($colors.Green)               .OMMMMo
$($colors.Green)               OMMM0,
$($colors.Green)     .;loddo:' loolloddol;.
$($colors.Green)   cKMMMMMMMMMMNWMMMMMMMMMM0:
$($colors.Green) .KMMMMMMMMMMMMMMMMMMMMMMMWd.
$($colors.Green) XMMMMMMMMMMMMMMMMMMMMMMMX.
$($colors.Green);MMMMMMMMMMMMMMMMMMMMMMMM:
$($colors.Green):MMMMMMMMMMMMMMMMMMMMMMMM:
$($colors.Green).MMMMMMMMMMMMMMMMMMMMMMMMX.
$($colors.Green) kMMMMMMMMMMMMMMMMMMMMMMMMWd.
$($colors.Green) .XMMMMMMMMMMMMMMMMMMMMMMMMMMk
$($colors.Green)  .XMMMMMMMMMMMMMMMMMMMMMMMMK.
$($colors.Green)    kMMMMMMMMMMMMMMMMMMMMMMd
$($colors.Green)     ;KMMMMMMMWXXWMMMMMMMk.
$($colors.Green)       .cooc,.    .,coo:.
"@

        $linuxAscii = @"
$($colors.White)        #####
$($colors.White)       #######
$($colors.White)       ##$($colors.BrightRed)O$($colors.White)#$($colors.BrightRed)O$($colors.White)##
$($colors.White)       #$($colors.Yellow)#####$($colors.White)#
$($colors.White)     ##$($colors.White)##$($colors.Yellow)###$($colors.White)##$($colors.White)##
$($colors.White)    #$($colors.White)##########$($colors.White)##
$($colors.White)   #$($colors.White)############$($colors.White)##
$($colors.White)   #$($colors.White)############$($colors.White)###
$($colors.Yellow)  ##$($colors.White)#############$($colors.Yellow)##
$($colors.Yellow)######$($colors.White)#########$($colors.Yellow)######
$($colors.Yellow)#######$($colors.White)#######$($colors.Yellow)#######
$($colors.Yellow)  #####$($colors.White)#####$($colors.Yellow)#####
"@

        # Detect OS and return appropriate ASCII art
        $os = (Get-CimInstance Win32_OperatingSystem).Caption
        if ($os -match "Windows") {
            return $windowsAscii
        }
        elseif ($os -match "Ubuntu") {
            return $ubuntuAscii
        }
        elseif ($os -match "Mac") {
            return $macosAscii
        }
        else {
            return $linuxAscii
        }
    }

    # Format and display the output
    function Format-Output {
        param (
            [Parameter(Mandatory = $true)]
            [hashtable]$SystemInfo
        )

        $asciiArt = Get-AsciiArt
        $asciiLines = $asciiArt -split "`n"
        
        # Create the info lines with proper formatting
        $infoLines = @(
            "$($colors.BrightCyan)$($SystemInfo.Username)$($colors.Reset)@$($colors.BrightCyan)$($SystemInfo.Hostname)$($colors.Reset)",
            "$($colors.BrightYellow)---------$($colors.Reset)",
            "$($colors.BrightYellow)OS:$($colors.Reset) $($SystemInfo.OS)",
            "$($colors.BrightYellow)Host:$($colors.Reset) $($SystemInfo.Host)",
            "$($colors.BrightYellow)Kernel:$($colors.Reset) $($SystemInfo.Kernel)",
            "$($colors.BrightYellow)Uptime:$($colors.Reset) $($SystemInfo.Uptime)",
            "$($colors.BrightYellow)Packages:$($colors.Reset) $($SystemInfo.Packages)",
            "$($colors.BrightYellow)Shell:$($colors.Reset) $($SystemInfo.Shell)",
            "$($colors.BrightYellow)Resolution:$($colors.Reset) $($SystemInfo.Resolution)",
            "$($colors.BrightYellow)DE:$($colors.Reset) $($SystemInfo.DE)",
            "$($colors.BrightYellow)WM:$($colors.Reset) $($SystemInfo.WM)",
            "$($colors.BrightYellow)WM Theme:$($colors.Reset) $($SystemInfo.WMTheme)",
            "$($colors.BrightYellow)Terminal:$($colors.Reset) $($SystemInfo.Terminal)",
            "$($colors.BrightYellow)Terminal Theme:$($colors.Reset) $($SystemInfo.TerminalTheme)",
            "$($colors.BrightYellow)CPU:$($colors.Reset) $($SystemInfo.CPU)",
            "$($colors.BrightYellow)GPU:$($colors.Reset) $($SystemInfo.GPU)",
            "$($colors.BrightYellow)Memory:$($colors.Reset) $($SystemInfo.Memory)"
        )

        # Calculate the maximum length of ASCII art lines
        $maxAsciiLength = ($asciiLines | Measure-Object -Property Length -Maximum).Maximum

        # Display the output with ASCII art and system information side by side
        $maxLines = [Math]::Max($asciiLines.Count, $infoLines.Count)
        
        # First, display the color blocks at the bottom
        for ($i = 0; $i -lt $maxLines; $i++) {
            $asciiLine = if ($i -lt $asciiLines.Count) { $asciiLines[$i] } else { " " * $maxAsciiLength }
            $infoLine = if ($i -lt $infoLines.Count) { $infoLines[$i] } else { "" }
            
            # Add padding between ASCII art and info
            $padding = "  "
            Write-Host "$asciiLine$padding$infoLine"
        }
        
        # Add color blocks at the bottom
        Write-Host ""
        Write-Host "$($colors.Red)$($colors.Bold)██$($colors.Reset) $($colors.Green)$($colors.Bold)██$($colors.Reset) $($colors.Yellow)$($colors.Bold)██$($colors.Reset) $($colors.Blue)$($colors.Bold)██$($colors.Reset) $($colors.Magenta)$($colors.Bold)██$($colors.Reset) $($colors.Cyan)$($colors.Bold)██$($colors.Reset) $($colors.White)$($colors.Bold)██$($colors.Reset)"
        Write-Host "$($colors.BrightRed)$($colors.Bold)██$($colors.Reset) $($colors.BrightGreen)$($colors.Bold)██$($colors.Reset) $($colors.BrightYellow)$($colors.Bold)██$($colors.Reset) $($colors.BrightBlue)$($colors.Bold)██$($colors.Reset) $($colors.BrightMagenta)$($colors.Bold)██$($colors.Reset) $($colors.BrightCyan)$($colors.Bold)██$($colors.Reset) $($colors.BrightWhite)$($colors.Bold)██$($colors.Reset)"
        
        # Reset colors at the end
        Write-Host $colors.Reset
    }

    # Main execution
    $systemInfo = Get-SystemInfo
    Format-Output -SystemInfo $systemInfo
}

# Note: This line should be removed when using as a script file (.ps1)
# Only keep this line if saving as a module file (.psm1)
# Export-ModuleMember -Function Get-PSNeofetch