<#
.SYNOPSIS
    Sets up a new Windows OS environment by installing necessary modules, updating Windows, and setting up essential tools.

.DESCRIPTION
    This script installs the NuGet package provider, PSWindowsUpdate module, and all available Windows updates. It also ensures the necessary tools like winget are installed. The script follows best practices for PowerShell scripting in an RMM context, including error handling, logging, and checking for internet connectivity.

.NOTES
    Author: [Your Name]
    Date: [Current Date]
    Version: 1.4

.PARAMETERS
    None
#>

# Temporarily set the execution policy to Bypass for this session to allow script execution
$originalExecutionPolicy = Get-ExecutionPolicy
Set-ExecutionPolicy Bypass -Scope Process -Force

# Function to install a NuGet package provider
function Install-NuGetPackageProvider {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$MinimumVersion
    )

    try {
        $provider = Get-PackageProvider -Name $Name -ErrorAction SilentlyContinue
        if ($provider -and [version]$provider.Version -ge [version]$MinimumVersion) {
            Write-Host "$Name package provider is already installed and up-to-date."
        } else {
            Install-PackageProvider -Name $Name -MinimumVersion $MinimumVersion -Force -ErrorAction Stop
            Write-Host "$Name package provider installed successfully."
        }
    } catch {
        Write-Error "Failed to install $Name package provider: $_"
        exit 1
    }
}

# Function to install the PSWindowsUpdate module
function Install-PSWindowsUpdateModule {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName,
        [Parameter(Mandatory=$true)]
        [string]$MinimumVersion
    )

    try {
        $module = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue
        if ($module -and [version]$module.Version -ge [version]$MinimumVersion) {
            Write-Host "$ModuleName module is already installed and up-to-date."
        } else {
            Install-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-Host "$ModuleName module installed successfully."
        }
    } catch {
        Write-Error "Failed to install $ModuleName module: $_"
        exit 1
    }
}

# Function to import the PSWindowsUpdate module
function Import-PSWindowsUpdateModule {
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Write-Host "PSWindowsUpdate module imported successfully."
    } catch {
        Write-Error "Failed to import PSWindowsUpdate module: $_"
        exit 1
    }
}

# Function to install all Windows updates
function Install-WindowsUpdates {
    try {
        $updates = Install-WindowsUpdate -AcceptAll -Install -ErrorAction Stop
        if ($updates) {
            foreach ($update in $updates) {
                Write-Host "Installed update: $($update.KB) - $($update.Size) - $($update.Result)"
            }
            return $true
        } else {
            Write-Host "No updates downloaded and staged."
            return $false
        }
    } catch {
        Write-Error "Failed to install Windows updates: $_"
        exit 1
    }
}

# Function to install the winget package manager
function Install-Winget {
    try {
        $wingetPath = "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
        if (Test-Path $wingetPath) {
            $wingetVersion = (& $wingetPath --version) -match "v([\d\.]+)" | Out-Null ; $Matches[1]
            $latestVersion = (Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest").tag_name.TrimStart('v')
            if ([version]$wingetVersion -ge [version]$latestVersion) {
                Write-Host "winget is already installed and up-to-date."
                return
            }
        }
        Install-Script winget-install -Force -ErrorAction Stop
        Write-Host "winget installed successfully."
    } catch {
        Write-Error "Failed to install winget: $_"
        exit 1
    }
}

# Function to check for internet connectivity
function Test-InternetConnectivity {
    try {
        $request = [System.Net.WebRequest]::Create("http://www.google.com")
        $response = $request.GetResponse()
        if ($response.StatusCode -eq 200) {
            Write-Host "Internet connection detected."
            return $true
        } else {
            Write-Warning "No internet connection detected."
            return $false
        }
    } catch {
        Write-Warning "Failed to check internet connectivity: $_"
        return $false
    }
}

# Main script execution
try {
    if (!(Test-InternetConnectivity)) {
        Write-Warning "No internet connection detected. Skipping online operations."
    } else {
        Install-NuGetPackageProvider -Name NuGet -MinimumVersion 2.8.5.201
        Install-Winget
        Install-PSWindowsUpdateModule -ModuleName PSWindowsUpdate -MinimumVersion 2.2.0.2
        Import-PSWindowsUpdateModule
        
        $updatesInstalled = Install-WindowsUpdates
        if ($updatesInstalled) {
            Write-Host "Windows updates have been downloaded and staged."

            # Prompt user to confirm manual reboot
            $confirmReboot = Read-Host "Do you want to proceed with a manual reboot to complete the update installation? (y/n)"
            if ($confirmReboot -eq "y" -or $confirmReboot -eq "yes") {
                Write-Host "Please reboot the system to complete the update installation."
            } else {
                Write-Host "Reboot cancelled."
            }
        } else {
            Write-Host "Process complete. No updates were downloaded or installed."
        }
    }
} catch {
    Write-Error "An unexpected error occurred: $_"
} finally {
    # Reset the execution policy to its original state
    Set-ExecutionPolicy $originalExecutionPolicy -Scope Process -Force
}

Write-Host "Script completed."
