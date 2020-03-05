##########################################
# Control Intel Display Refresh Rate Switching (DRRS)
#
#
# References:
#   - https://github.com/orev/dpst-control
#
##########################################

# Get command-line parameters
Param(
    [switch]$Enable,
    [switch]$Disable,
    [switch]$Debug
)

# Enforce strict mode
Set-StrictMode -Version Latest

# Stop on any error
$ErrorActionPreference = "Stop"

##########################################
### Variables

$usage = @"
Usage (must Run as Administrator):
    Get current state of DRRS (default if no option is given)
        drrs-control.ps1

    Enable DRRS
        drrs-control.ps1 -enable

    Disable DRRS
        drrs-control.ps1 -disable

    Other Options:
        -debug
            Enable debug output
"@

# Path to display adapter ClassGuid
$regBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'

# Name of registry key holding FRRS data
$userPolicy = "DCUserPreferencePolicy"
$powerPolicy = "PowerDcPolicy"

##########################################
### Functions

# Check if running as administrator
# Returns True if Admin, False if not
Function RunningAsAdmin() {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent() )
    Return $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator )
}

# Locate registry value
# Returns:
#   If found: Full path to given FTC/DRRS registry value
#   If not:   $false
Function LocateRegVal() {
    Param(
        [parameter(Mandatory=$true)]$regPath,
        [parameter(Mandatory=$true)]$regVal
    )
    ForEach( $key in
        $( Get-ChildItem -ErrorAction SilentlyContinue -LiteralPath "${regPath}" |
            Where-Object { $_.Name -match '\\\d{4}$' } )
    ) {
        If( $key.GetValue( $regVal, $null ) -ne $null ) {
            Return $key.Name
        }
    }
    Return $false
}

# Backup current value before changing it
Function BackupVal() {
    Param(
        [parameter(Mandatory=$true)]$regPath,
        [parameter(Mandatory=$true)]$regName,
        [parameter(Mandatory=$true)]$regValue
    )
    $bkFile = "backup-${regName}-$(Get-Date -Format FileDateTime).reg"
    $r  = "Windows Registry Editor Version 5.00`n`n"
    $r += "[$($regPath)]`n"
    $r += '"' + "${regName}" + '"=dword:'
    $r += "$(([Convert]::ToString( $regValue, 16 )).PadLeft(8, '0'))`n`n"
    $r | Out-File $bkFile -NoNewLine
}

# Check if DRRS feature is enabled
# Returns: 0: Disabled; 1: Enabled
Function FeatureEnabled() {
    Param(
        [parameter(Mandatory=$true)]$regVal,
        [parameter(Mandatory=$true)]$bitMask
    )
    $enabled = $regVal -band $bitMask
    Write-Debug( "  State (bin): $(([Convert]::ToString( $enabled, 2 )).PadLeft(32, '0'))" )
    If( $enabled ) { Return 1 }
    Else           { Return 0 }
}

##########################################
### Main

If( $Debug ) {
    $DebugPreference = "Continue"   # Enable debug output
}

# This script must run as admin
If( !(RunningAsAdmin) ) {
    Write-Error "Must run as Administrator!"
    Exit 255
}

# Search registry for power saving policy
$userPolPath = LocateRegVal -regPath ${regBase} -regVal $userPolicy
If( $userPolPath -eq $false ) {
    Write-Error "Cannot locate ${userPolPath} in registry"
    Exit 1
}
$powerPolPath = LocateRegVal -regPath ${regBase} -regVal $powerPolicy
If( $userPolPath -eq $false ) {
    Write-Error "Cannot locate ${powerPolPath} in registry"
    Exit 1
}

# Get current value from registry
$userPolCur = (Get-Item -LiteralPath "Registry::${userPolPath}").GetValue($userPolicy)
Write-Debug( "Current user policy (hex): 0x$(([Convert]::ToString( $userPolCur, 16 )))" )
Write-Debug( "Current user policy (bin): $(([Convert]::ToString( $userPolCur, 2 )).PadLeft(32, '0'))" )
$powerPolCur = (Get-Item -LiteralPath "Registry::${powerPolPath}").GetValue($powerPolicy)
Write-Debug( "Current DC power policy (hex): 0x$(([Convert]::ToString( $powerPolCur, 16 )))" )
Write-Debug( "Current DC power policy (bin): $(([Convert]::ToString( $powerPolCur, 2 )).PadLeft(32, '0'))" )

# Generate bitmask to be used for manipulating DRRS bit
#   Start with 1 which sets the right-most bit to 1,
#   Then shift that bit left X number of times
#   DRRS bit is the 7th bit from the right.
#   Shift 6 times since "1" is in the 1st position
$bitMask = 1 -shl 6
Write-Debug( "DRRS Bitmask (bin): $(([Convert]::ToString( $bitMask, 2 )).PadLeft(32, '0'))" )

$userPolNew = 0
$powerPolNew = 0
$opStr = ''
# Enable DRRS (to enable, DRRS bit needs to be 1)
If( $Enable ) {
    $opStr = "enable"
    If( ! (FeatureEnabled -regVal $userPolCur -bitMask $bitMask) ) {
        Write-Output "DRRS user policy is currently disabled"
        # Set DRRS bit (enable)
        $userPolNew = $userPolCur -bor $bitMask
    }
    If( ! (FeatureEnabled -regVal $powerPolCur -bitMask $bitMask) ) {
        Write-Output "DRRS power policy is currently disabled"
        # Set DRRS bit (enable)
        $powerPolNew = $powerPolCur -bor $bitMask
    }
}
# Disable DRRS (to disable, DRRS bit needs to be 0)
ElseIf( $Disable ) {
    $opStr = "disable"
    If( (FeatureEnabled -regVal $userPolCur -bitMask $bitMask) ) {
        Write-Output "DRRS user policy is currently enabled"
        # Clear DRRS bit (disable)
        $userPolNew = $userPolCur -band ( -bnot $bitMask )
    }
    If( (FeatureEnabled -regVal $powerPolCur -bitMask $bitMask) ) {
        Write-Output "DRRS power policy is currently enabled"
        # Clear DRRS bit (disable)
        $powerPolNew = $powerPolCur -band ( -bnot $bitMask )
    }
}
# Default - Report on DRRS state and exit
Else {
    Write-Output "Checking current Display Refresh Rate Switching (DRRS) status"
    If( (FeatureEnabled -regVal $userPolCur -bitMask $bitMask) ) {
        Write-Output "DRRS user policy is enabled"
    }
    Else {
        Write-Output "DRRS user policy is disabled"   
    }
    If( (FeatureEnabled -regVal $powerPolCur -bitMask $bitMask) ) {
        Write-Output "DRRS power policy is enabled"
    }
    Else {
        Write-Output "DRRS power policy is disabled"   
    }
    Exit 0
}

# Write new value to registry and report results
If( $userPolNew ) {
    Write-Debug( "    New user policy (hex): 0x$(([Convert]::ToString( $userPolNew, 16 )))" )
    Write-Debug( "    New user policy (bin): $(([Convert]::ToString( $userPolNew, 2 )).PadLeft(32, '0'))" )

    # Backup current value
    BackupVal -regPath $userPolPath -regName $userPolicy -regValue $userPolCur

    # Write new value to registry
    Set-ItemProperty -Path "Registry::${userPolPath}" -Name $userPolicy -Value $userPolNew | Out-Null

    Write-Output "DRRS user policy is now $($opStr)d.`n"
    Write-Warning "-> Reboot is required for changes to take effect. <-"
}
Else {
    Write-Output "DRRS user policy is already $($opStr)d"
}
If( $powerPolNew ) {
    Write-Debug( "    New power policy (hex): 0x$(([Convert]::ToString( $powerPolNew, 16 )))" )
    Write-Debug( "    New power policy (bin): $(([Convert]::ToString( $powerPolNew, 2 )).PadLeft(32, '0'))" )

    # Backup current value
    BackupVal -regPath $powerPolPath -regName $powerPolicy -regValue $powerPolCur

    # Write new value to registry
    Set-ItemProperty -Path "Registry::${powerPolPath}" -Name $powerPolicy -Value $powerPolNew | Out-Null

    Write-Output "DRRS power policy is now $($opStr)d.`n"
    Write-Warning "-> Reboot is required for changes to take effect. <-"
}
Else {
    Write-Output "DRRS power policy is already $($opStr)d"
}

