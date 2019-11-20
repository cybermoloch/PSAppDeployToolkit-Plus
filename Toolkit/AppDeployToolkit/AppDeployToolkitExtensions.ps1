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
[version]$appDeployExtScriptVersion = [version]'3.8.0'
[string]$appDeployExtScriptDate = '2019-11-19'
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

        $uriCount = 0
        do {
            If (-not ($Uri[$uriCount]) ) {
				Write-Log -Message ('No more URIs to try; cannot download ' + $uriFilename)
				return ($false)
            }
            
            $dlStartTime = Get-Date
            Start-BitsTransfer -Source $Uri[$uriCount] -Destination $Destination
            
            If ($?) {
                Write-Log -Message ($Uri[$uriCount] + ' BITS download completed in ' + $((Get-Date).Subtract($dlStartTime).Seconds) + ' second(s)')
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
                        #Delete wrong file to prevent usage of corrupt or malicious file
                        Remove-Item -Path $Destination -Force
                        $dlSuccess = $false
                    }

                }
                else {
                    Write-Log -Message ('BITS download completed successfully. No SHA256 to compare.')
                    $dlSuccess = $true
                }
            }

            else {
                Write-Log -Message ('Error with BITS download.')
                $dlSuccess = $false
            }
            $uriCount++
        }
        until ($dlSuccess -eq $true) # Download is successful

        return ($dlSuccess)
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
