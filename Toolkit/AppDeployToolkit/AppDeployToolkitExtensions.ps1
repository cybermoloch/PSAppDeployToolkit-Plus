<#
.SYNOPSIS
	This script is a template that allows you to extend the toolkit with your own custom functions.
    # LICENSE #
    PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
    Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is automatically dot-sourced by the AppDeployToolkitMain.ps1 script.
.NOTES
    Toolkit Exit Code Ranges:
    60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
    69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
    70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]
Param (
)

##*===============================================
##* VARIABLE DECLARATION
##*===============================================

# Variables: Script
[string]$appDeployToolkitExtName = 'PSAppDeployToolkitExt'
[string]$appDeployExtScriptFriendlyName = 'App Deploy Toolkit Extensions'
[version]$appDeployExtScriptVersion = [version]'3.8.2'
[string]$appDeployExtScriptDate = '2020-05-06'
[hashtable]$appDeployExtScriptParameters = $PSBoundParameters

##*===============================================
##* FUNCTION LISTINGS
##*===============================================

# <Your custom functions go here>
# Import all PowerShell Modules from Modules directory
Get-ChildItem -Path ($scriptRoot + '\Modules') -Recurse | Unblock-File
Get-ChildItem -Path ($scriptRoot + '\Modules') | Foreach-Object {Import-Module $_.FullName}

# Function for testing internet connectivity
# Uses same parameters as NCSI
Function Test-InternetConnection {
    [cmdletbinding()]
    Param ()
    Process {
        $activeWebProbeHost = ((Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveWebProbeHost)
        $activeWebProbePath = ((Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveWebProbePath)
        $activeWebProbeContent = ((Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveWebProbeContent)
        $activeDnsProbeIpAddress = (((Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveDnsProbeHost).IPAddress)
        $activeDnsProbeContent = ((Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveDnsProbeContent)
        $webRequest = (Invoke-Webrequest ('http://'+ $activeWebProbeHost+ '/'+ $activeWebProbePath) -UseBasicParsing)
        If ($webRequest.content -eq $activeWebProbeContent) {
            return ([bool]$true)
        }
        If ($activeDnsProbeIpAddress -and $activeWebProbeContent) {
            If (Resolve-DnsName -Type A -ErrorAction SilentlyContinue $activeDnsProbeIpAddress -eq $activeDnsProbeContent) {
                return ([bool]$true)
            }
        }
        return ([bool]$false)
    }
}

# Function for downloading files from URIs (http,https,ftp,file)
# URIs are tried in order and optionally verified via SHA256 hash
# If no destination is specified, gets the filename and saves to $dirSupportFiles
Function Get-FileFromUri {
    [cmdletbinding()]
    Param (
        [Parameter(Position=0,Mandatory=$true)]
        [string[]]$Uri,
        [Parameter(Position=1,Mandatory=$false)]
        [AllowEmptyString()]
        [string]$Destination,
        [Parameter(Position=2,Mandatory=$false)]
        [AllowEmptyString()]
        [string]$Sha256
    )
    #End of parameters
    Process {
        If (-not ($Destination)) {
			# Get filename from the URI
			$uriFilename = (Split-Path -Path $Uri -Leaf)
			
			# Strip any part of filename after ? (query strings for protected downloads)
			If ($uriFilename -match '\?') {
				$uriFilename = $uriFilename.Substring(0, $uriFilename.IndexOf('?'))    
			}            
            $Destination = ($dirSupportFiles + '\' + $uriFilename)
        }

        If (-not (Split-Path -Path $Destination -IsAbsolute)) {
            throw ('Destination invalid; an abolsute path is required')
        }
        
        # Force TLS1.2 seems to help with some websites
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # Speeds up Invoke-WebRequest when downloading files
        $ProgressPreference = 'SilentlyContinue'

        $uriCount = 0
        do {
            If (-not ($Uri[$uriCount]) ) {
				Write-Log -Message ('No more URIs to try; cannot download ' + $uriFilename)
				return ($false)
            }
            
            Try {
                $dlStartTime = Get-Date
                $download = Invoke-WebRequest -Uri $Uri[$uriCount] -OutFile $Destination -UseBasicParsing -ErrorAction 'Continue'

                    If ($?) {
                        Write-Log -Message ($Uri[$uriCount] + ' download completed in ' + $((Get-Date).Subtract($dlStartTime).Seconds) + ' second(s)')

                        # Verify SHA256 Hash if provided
                        If ($Sha256) {
                            $DestinationSha256 = (Get-FileHash -Path $Destination -Algorithm 'SHA256')
                            Write-Log -Message ('Checking hash of downloaded file')
                            $hashMatch = ($DestinationSha256.Hash -eq $Sha256)
    
                            If ($hashMatch) {
                                Write-Log -Message ('Downloaded file matached expected hash.')
                                $dlSuccess = $true
                            } else {
                                Write-Log -Message ('Downloaded file did not match expected hash.')
                                Write-Log -Message ('Expected hash was: ' + $Sha256)
                                Write-Log -Message ('Downloaded hash was: ' + $DestinationSha256.Hash)
                                # Delete wrong file to prevent usage of corrupt or malicious file
                                Remove-Item -Path $Destination -Force
                                $dlSuccess = $false
                            }
                        } else {
                            Write-Log -Message ('Download completed successfully. No SHA256 to compare.')
                            $dlSuccess = $true
                        }
                    } else {
                        # This else is redundant?
                        Write-Log -Message ('Error with download.')
                        $dlSuccess = $false
                    }

            } Catch {
                $download = $_.Exception
                Write-Log -Message ($download)
            }

            $uriCount++
        }
        until ($dlSuccess -eq $true) # Download is successful
        return ($dlSuccess)
    }
}

# Checks if .NET Framework 3.5 is installed
Function Test-DotNet35 {
    [cmdletbinding()]
    Param ()
    #End of parameters
    Process {
        If (Test-Path -Path ('HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5')) {
            $dotNet45RegistryKey = (Get-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5')
            If (($dotNet45RegistryKey.Installed) -eq 1) {
                Write-Log -Message ('.NET Framework 3.5 found.')
                return ([bool]$true)
            }
        }
        Write-Log -Message ('.NET Framework 3.5 not found.')
        return ([bool]$false)
    }
}

# Downloads and installs .NET Framework 3.5
Function Install-DotNet35 {
    [cmdletbinding()]
    Param ()
    #End of parameters
    Process {
        Write-Log -Message ('Downloading .NET Framework 3.5')
        $dotNetDownload = @{
            Uri = 'https://download.microsoft.com/download/2/0/E/20E90413-712F-438C-988E-FDAA79A8AC3D/dotnetfx35.exe';
            Destination = ($dirSupportFiles + '\' + 'dotnetfx35.exe');
            Sha256 = '0582515BDE321E072F8673E829E175ED2E7A53E803127C50253AF76528E66BC1'
        }
        If (Get-FileFromUri @dotNetDownload) {
            Write-Log -Message ('Installing .NET Framework 3.5')
            If (Execute-Process -Path ($dirSupportFiles + '\' + 'dotnetfx35.exe') -Parameters ('/q /norestart')) {
                Write-Log -Message ('.NET Framework 3.5 installed')
                return ([bool]$true)
            }
            else {
                Write-Log -Message ('Error installing .NET Framework 3.5')
                return ([bool]$false)
            }
        }
        else {
            Write-Log -Message ('Error downloading .NET Framework 3.5')
            return ([bool]$false)
        }        
        
    }
}

# Checks if .NET Framework 4.x is installed
Function Test-DotNet4x {
    [cmdletbinding()]
    Param (
        [Parameter(Position=0,Mandatory=$true)]
        [string]$MinVersion
    )
    #End of parameters
    Process {
        Switch ($MinVersion) {
            [version]'4.5' {$minRelease = 378389}
            [version]'4.5.1' {$minRelease = 378675}
            [version]'4.5.2' {$minRelease = 379893}
            [version]'4.6' {$minRelease = 393295}
            [version]'4.6.1' {$minRelease = 394254}
            [version]'4.6.2' {$minRelease = 394802}
            [version]'4.7' {$minRelease = 460798}
            [version]'4.7.1' {$minRelease = 461308}
            [version]'4.7.2' {$minRelease = 461808}
            [version]'4.8' {$minRelease = 528040}
        }
        
        If (Test-Path -Path ('HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full')) {
            $dotNet45RegistryKey = (Get-RegistryKey -Key ('HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'))
            If (($dotNet45RegistryKey.Release) -ge $minRelease) {
                Write-Log -Message ('.NET Framework ' + $Version + ' found.')
                return ([bool]$true)
            }
            else {
                Write-Log -Message ('.NET Framework ' + $Version + ' or higher not found')
                return ([bool]$false)
            }
        }
        else {
            Write-Log -Message ('.NET Framework ' + $Version + ' not installed')
            return ([bool]$false)
        }
    }
}

# Downloads and installs .NET Framework 4.8 (newest as of 2019-11-19)
# .NET 4.8 is backwards compatible so why install older versions?
Function Install-DotNet4x {
    [cmdletbinding()]
    Param ()
    Process {
        Write-Log -Message ('Downloading .NET Framework 4.8')
        $dotNetDownload = @{
            Uri = 'https://download.visualstudio.microsoft.com/download/pr/014120d7-d689-4305-befd-3cb711108212/0fd66638cde16859462a6243a4629a50/ndp48-x86-x64-allos-enu.exe';
            Destination = ($dirSupportFiles + '\' + 'NDP48-x86-x64-AllOS-ENU.exe');
            Sha256 = '9B1F71CD1B86BB6EE6303F7BE6FBBE71807A51BB913844C85FC235D5978F3A0F'
        }
        If (Get-FileFromUri @dotNetDownload) {
            Write-Log -Message ('Installing .NET Framework 4.8')
            If (Execute-Process -Path ($dirSupportFiles + '\' + 'NDP48-x86-x64-AllOS-ENU.exe') -Parameters ('/q /norestart')) {
                Write-Log -Message ('.NET Framework 4.8 installed')
                return ([bool]$true)
            }
            else {
                Write-Log -Message ('Error installing .NET Framework 4.8')
                return ([bool]$false)
            }
        }
        else {
            Write-Log -Message ('Error downloading .NET Framework 4.8')
            return ([bool]$false)
        }
    }
}

# Checks for installed Visual Studio Redistributables
# Requires VcRedist PowerShell Module
# Simplifies command to return $true/$false for specified version 
Function Test-VcRedist {
    [cmdletbinding()]
    Param (
        [Parameter(Position=0,Mandatory=$true)]
        [string]$Release,
        [Parameter(Position=1,Mandatory=$true)]
        [ValidateSet('x86','x64')]
        [string]$Architecture,
        [Parameter(Position=2)]
        [AllowEmptyString()]
        [string]$MinVersion
    )
    #End of parameters
    Process {
        If (-not (Get-Module -Name 'VcRedist')) {retun ('Error: VcRedist Module Not found')}
        #If no MinVersion specified, set minumum to 0.0.0.0
        If (-not ($MinVersion)) {$MinVersion = '0.0.0.0'}
        #If MinVersion is a single integer, append .0.0.0 for SemVer
        If ($MinVesion -match "^\d+$") {$MinVersion = ($MinVersion + '.0.0.0')}
        #Still possible version parsing issues with "x.0"; maybe should just check if valid version and error if not
        If (Get-InstalledVcRedist | Where-Object {$_.Release -match $Release -and $_.Architecture -match $Architecture -and [version]$_.Version -ge [version]$MinVersion}) {
		return ([bool]$true)
		} else {
		return ([bool]$false)
		}
	}
}

# Downloads and installs specified Visual Studio Redistributable
# Requires VcRedist PowerShell Module
# Simplifies the install into one command to align with Test-VcRedist
Function Install-VcRedistByRelease {
    [cmdletbinding()]
    Param (
        [Parameter(Position=0,Mandatory=$true)]
        [string]$Release,
        [Parameter(Position=1,Mandatory=$true)]
        [ValidateSet('x86','x64')]
        [string]$Architecture
    )
    #End of parameters
    Process {
    If (-not (Get-Module -Name 'VcRedist')) { retun ('Error: VcRedist Module Not found') }
    
    $vcRedistReq = (Get-VcList -Release $Release -Architecture $Architecture)
    Write-Log -Message ('Downloading ' + $vcRedistReq)
    Save-VcRedist -Path ($dirSupportFiles) -VcList $vcRedistReq
    Write-Log -Message ('Installing ' + $vcRedistReq)
    Install-VcRedist -Path ($dirSupportFiles) -VcList $vcRedistReq -Silent
	}
}

# Function to set file association for logged in user
# Requires external tool SetUserFTA.exe (should be in Tools subdirectory)
Function Set-UserFta {
    [CmdletBinding()]
    param (
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
        [string]$Extension,
        [Parameter(Position=1,Mandatory=$true,ValueFromPipeline=$true)]
        [string]$ApplicationId,
        [Parameter(Mandatory=$false)]
        [switch]$Prompt
            
    )
        
    begin {
        $progSetUserFTA = ($scriptRoot + '\Tools\SetUserFTA.exe')
        If (-not (Test-Path -Path $progSetUserFTA)) {
            Write-Log -Message 'ERROR: Unable to set file type associaion; SetUserFTA was not found.'
            return ('Error: ' + $progSetUserFTA + ' not found.')
        }
    }
        
    process {
        If ($Prompt.IsPresent) {
            $promptSetFTA = (Show-InstallationPrompt -Message ('Would you like to set ' + $appName + ' as the default program for ' + $Extension + '?') -Icon 'Question' -ButtonLeftText 'No' -ButtonRightText 'Yes' -Timeout 60 -ExitOnTimeout $false)
            If ($promptSetFTA -notlike 'Yes') {
                Write-Log -Message ('User selected "No" or timeout on the FTA prompt.')
                return ($false)
            }
        }
        Write-Log -Message ($appName + ' set as the default program for ' + $Extension + 'for' + ($CurrentLoggedOnUserSession.NTAccount))
        Show-BalloonTip -BalloonTipText ($appName + ' set as the default program for ' + $Extension) -BalloonTipIcon 'Info'
        Execute-ProcessAsUser -Path $progSetUserFTA -Parameters ($Extension + ' ' + $ApplicationId) -Wait
    }
     
}

##*===============================================
##* END FUNCTION LISTINGS
##*===============================================

##*===============================================
##* SCRIPT BODY
##*===============================================

If ($scriptParentPath) {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] dot-source invoked by [$(((Get-Variable -Name MyInvocation).Value).ScriptName)]" -Source $appDeployToolkitExtName
} Else {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] invoked directly" -Source $appDeployToolkitExtName
}

##*===============================================
##* END SCRIPT BODY
##*===============================================
