[CmdletBinding()]
Param(
    [Parameter(Mandatory = $False)] 
    [ValidateSet('Soft', 'Hard', 'None', 'Delayed')] 
    [String] $Reboot = 'Soft',

    [Parameter(Mandatory = $False)] 
    [Int32] $RebootTimeout = 120,

    [Parameter(Mandatory = $False)] 
    [switch] $ExcludeDrivers,

    [Parameter(Mandatory = $False)] 
    [switch] $ExcludeUpdates
)

Add-Type -AssemblyName PresentationFramework

function Show-MessageBox {
    param (
        [string] $Message,
        [string] $Title = "Progress"
    )
    [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information')
}

function Set-TagFile {
    param (
        [string] $Path
    )
    if (-not (Test-Path $Path)) {
        Mkdir $Path
    }
    Set-Content -Path "$Path\UpdateOS.ps1.tag" -Value "Installed"
}

function Opt-InToMicrosoftUpdate {
    Write-Log "Opting into Microsoft Update"
    Show-MessageBox -Message "Opting into Microsoft Update..."
    try {
        $ServiceManager = New-Object -ComObject "Microsoft.Update.ServiceManager"
        $ServiceID = "7971f918-a847-4430-9279-4a52d1efe18d"
        $ServiceManager.AddService2($ServiceId, 7, "") | Out-Null
    } catch {
        Write-Log "Failed to opt into Microsoft Update: $_"
        throw $_
    }
}

function Get-Updates {
    param (
        [array] $Queries
    )
    $WUUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($query in $Queries) {
        Write-Log "Getting updates for query: $query"
        Show-MessageBox -Message "Getting updates for query: $query..."
        try {
            $updates = (New-Object -ComObject Microsoft.Update.Session).CreateupdateSearcher().Search($query).Updates
            foreach ($update in $updates) {
                if (!$update.EulaAccepted) { $update.EulaAccepted = $true }
                if ($update.Title -notmatch "Preview") { [void]$WUUpdates.Add($update) }
            }
        } catch {
            Write-Log "Failed to get updates: $_"
            throw $_
        }
    }
    return $WUUpdates
}

function Install-Updates {
    param (
        [ComObject] $WUUpdates
    )
    if ($WUUpdates.Count -ge 1) {
        Write-Log "Downloading and installing $($WUUpdates.Count) updates"
        Show-MessageBox -Message "Downloading and installing $($WUUpdates.Count) updates..."
        try {
            $WUDownloader = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateDownloader()
            $WUInstaller = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateInstaller()
            $WUInstaller.ForceQuiet = $true
            $WUInstaller.Updates = $WUUpdates
            $WUDownloader.Updates = $WUUpdates
            $WUDownloader.Download() | Out-Null
            $Install = $WUInstaller.Install()
            $script:needReboot = $Install.RebootRequired
        } catch {
            Write-Log "Failed to install updates: $_"
            throw $_
        }
    } else {
        Write-Log "No updates found"
        Show-MessageBox -Message "No updates found."
    }
}

function Install-WinGet {
    Write-Log "Checking and installing NuGet package provider if not present"
    Show-MessageBox -Message "Checking and installing NuGet package provider if not present..."

    # Check if NuGet package provider is already installed
    $NuGetInstalled = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore

    if (-not $NuGetInstalled) {
        Write-Log "NuGet package provider not found. Installing..."
        Show-MessageBox -Message "NuGet package provider not found. Installing..."
        # Install NuGet package provider
        try {
            $null = Install-PackageProvider -Name NuGet -Force -ErrorAction Stop
            Write-Log "NuGet package provider installed successfully."
        } catch {
            Write-Log "Failed to install NuGet package provider. Error: $_"
            Show-MessageBox -Message "Failed to install NuGet package provider. Error: $_"
            throw "Failed to install NuGet package provider. Error: $_"
        }
    } else {
        Write-Log "NuGet package provider is already installed."
        Show-MessageBox -Message "NuGet package provider is already installed."
    }

    Write-Log "Installing and updating winget"
    Show-MessageBox -Message "Installing and updating winget..."
    try {
        Install-Module microsoft.winget.client -Force -AllowClobber
        Import-Module microsoft.winget.client
        repair-wingetpackagemanager
        install-wingetpackage 9WZDNCRFJ3PZ -source msstore
        Write-Log "winget installed and updated successfully."
    } catch {
        Write-Log "Failed to install winget. Error: $_"
        Show-MessageBox -Message "Failed to install winget. Error: $_"
        throw "Failed to install winget. Error: $_"
    }
}

function Write-Log {
    param (
        [string] $Message
    )
    $timestamp = Get-Date -Format "yyyy/MM/dd hh:mm:ss tt"
    Write-Output "$timestamp $Message"
}

function Perform-Reboot {
    param (
        [string] $RebootType,
        [int] $RebootTimeout
    )
    switch ($RebootType) {
        "Hard" {
            Write-Log "Exiting with return code 1641 to indicate a hard reboot is needed."
            Show-MessageBox -Message "Exiting with return code 1641 to indicate a hard reboot is needed."
            Set-ScriptState -State "HardReboot"
            Stop-Transcript
            Exit 1641
        }
        "Soft" {
            Write-Log "Exiting with return code 3010 to indicate a soft reboot is needed."
            Show-MessageBox -Message "Exiting with return code 3010 to indicate a soft reboot is needed."
            Set-ScriptState -State "SoftReboot"
            Stop-Transcript
            Exit 3010
        }
        "Delayed" {
            Write-Log "Rebooting with a $RebootTimeout second delay"
            Show-MessageBox -Message "Rebooting with a $RebootTimeout second delay..."
            Set-ScriptState -State "DelayedReboot"
            shutdown.exe /r /t $RebootTimeout /c "Rebooting to complete the installation of Windows updates."
            Stop-Transcript
            Exit 0
        }
        "None" {
            Write-Log "Skipping reboot based on Reboot parameter (None)"
            Show-MessageBox -Message "Skipping reboot based on Reboot parameter (None)."
            Set-ScriptState -State "None"
            Stop-Transcript
            Exit 0
        }
    }
}

function Set-ScriptState {
    param (
        [string] $State
    )
    $statePath = "$env:ProgramData\Microsoft\UpdateOS\scriptState.json"
    $stateObject = @{
        Timestamp = Get-Date -Format "yyyy/MM/dd hh:mm:ss tt"
        State = $State
    }
    $stateObject | ConvertTo-Json | Set-Content -Path $statePath
}

function Get-ScriptState {
    $statePath = "$env:ProgramData\Microsoft\UpdateOS\scriptState.json"
    if (Test-Path $statePath) {
        $stateObject = Get-Content -Path $statePath | ConvertFrom-Json
        return $stateObject.State
    }
    return $null
}

function Check-OOBE {
    try {
        $oobeStatus = Get-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name 'OOBEInProgress' -ErrorAction SilentlyContinue
        if ($null -ne $oobeStatus) {
            return $oobeStatus.OOBEInProgress -eq 1
        }
    } catch {
        Write-Log "Error checking OOBE status: $_"
    }
    return $false
}

Process {
    Start-Transcript "$($env:ProgramData)\Microsoft\UpdateOS\UpdateOS.log"

    if (Check-OOBE) {
        Write-Log "OOBE is in progress. Exiting script to avoid conflicts."
        Show-MessageBox -Message "OOBE is in progress. Exiting script to avoid conflicts."
        Stop-Transcript
        Exit 0
    }

    $scriptState = Get-ScriptState
    if ($scriptState) {
        Write-Log "Resuming script from state: $scriptState"
        Show-MessageBox -Message "Resuming script from state: $scriptState"
        switch ($scriptState) {
            "HardReboot" { $Reboot = "Hard" }
            "SoftReboot" { $Reboot = "Soft" }
            "DelayedReboot" { $Reboot = "Delayed" }
            "None" { $Reboot = "None" }
        }
    }

    # Re-launch as 64-bit process if running as a 32-bit process on an x64 system
    if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64" -and Test-Path "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
        & "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -NoProfile -File "$PSCommandPath" -Reboot $Reboot -RebootTimeout $RebootTimeout -ExcludeDrivers:$ExcludeDrivers -ExcludeUpdates:$ExcludeUpdates
        Exit $lastexitcode
    }

    # Create tag file
    Set-TagFile -Path "$env:ProgramData\Microsoft\UpdateOS"

    # Opt into Microsoft Update
    Opt-InToMicrosoftUpdate

    # Determine update queries
    $queries = @()
    if ($ExcludeDrivers) {
        $queries += "IsInstalled=0 and Type='Software'"
    } elseif ($ExcludeUpdates) {
        $queries += "IsInstalled=0 and Type='Driver'"
    } else {
        $queries += "IsInstalled=0 and Type='Software'"
        $queries += "IsInstalled=0 and Type='Driver'"
    }

    # Get and install updates
    $WUUpdates = Get-Updates -Queries $queries
    Install-Updates -WUUpdates $WUUpdates

    # Install and update winget
    Install-WinGet

    # Log reboot requirement
    if ($script:needReboot) {
        Write-Log "Windows Update indicated that a reboot is needed."
        Show-MessageBox -Message "Windows Update indicated that a reboot is needed."
    } else {
        Write-Log "Windows Update indicated that no reboot is required."
        Show-MessageBox -Message "Windows Update indicated that no reboot is required."
    }

    # Perform reboot if necessary
    Perform-Reboot -RebootType $Reboot -RebootTimeout $RebootTimeout

    Stop-Transcript
}
