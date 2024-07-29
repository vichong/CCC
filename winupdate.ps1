<#
.SYNOPSIS
    Sets up a new Windows OS environment by installing necessary modules, updating Windows, and setting up essential tools.

.DESCRIPTION
    This script installs the NuGet package provider, PSWindowsUpdate module, and all available Windows updates. It also ensures the necessary tools like winget are installed. The script follows best practices for PowerShell scripting in an RMM context, including error handling, logging, and checking for internet connectivity.

.NOTES
    Author: [Your Name]
    Date: [Current Date]
    Version: 1.1

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
        Install-PackageProvider -Name $Name -MinimumVersion $MinimumVersion -Force -ErrorAction Stop
        Write-Host "$Name package provider installed successfully."
    } catch {
        Write-Error "Failed to install $Name package provider: $_"
        exit 1
    }
}

# Function to install the PSWindowsUpdate module
function Install-PSWindowsUpdateModule {
    try {
        Install-Module PSWindowsUpdate -Force -ErrorAction Stop
        Write-Host "PSWindowsUpdate module installed successfully."
    } catch {
        Write-Error "Failed to install PSWindowsUpdate module: $_"
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
        Install-WindowsUpdate -AcceptAll -Install -ErrorAction Stop
        Write-Host "Windows updates have been downloaded and staged."
    } catch {
        Write-Error "Failed to install Windows updates: $_"
        exit 1
    }
}

# Function to install the winget-install script
function Install-WingetInstallScript {
    try {
        Install-Script winget-install -Force -ErrorAction Stop
        Write-Host "winget-install script installed successfully."
    } catch {
        Write-Error "Failed to install winget-install script: $_"
        exit 1
    }
}

# Function to check for internet connectivity
function Test-InternetConnectivity {
    try {
        if (Test-NetConnection www.google.com -Quiet) {
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
        Install-PSWindowsUpdateModule
        Import-PSWindowsUpdateModule
        Install-WindowsUpdates

        Write-Host "Windows updates have been downloaded and staged."

        # Prompt user to confirm manual reboot
        $confirmReboot = Read-Host "Do you want to proceed with a manual reboot to complete the update installation? (y/n)"
        if ($confirmReboot -eq "y" -or $confirmReboot -eq "yes") {
            Write-Host "Please reboot the system to complete the update installation."
        } else {
            Write-Host "Reboot cancelled."
        }

        # Uncomment the next line if winget-install script is needed
        # Install-WingetInstallScript
    }
} catch {
    Write-Error "An unexpected error occurred: $_"
} finally {
    # Reset the execution policy to its original state
    Set-ExecutionPolicy $originalExecutionPolicy -Scope Process -Force
}

Write-Host "Script completed."
