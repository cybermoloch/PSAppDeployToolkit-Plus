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
[string]$appDeployExtScriptDate = '16/06/2020'
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
                Write-Log -Message ('Trying to download from: ' + $Uri[$uriCount])
                $dlStartTime = Get-Date
                $download = Invoke-WebRequest -Uri $Uri[$uriCount] -OutFile $Destination -UseBasicParsing -ErrorAction 'Continue'

                    If ($?) {
                        Write-Log -Message ('Download completed in ' + $((Get-Date).Subtract($dlStartTime).Seconds) + ' second(s)')

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
            If (($dotNet45RegistryKey.Install) -eq 1) {
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
        Execute-Process -Path 'DISM.exe' -Parameters ('/Online /Enable-Feature /FeatureName:NetFx3 /All')
        If ($?) {
            Write-Log -Message ('.NET Framework 3.5 installed')
        }
        else {
            Write-Log -Message ('Error installing .NET Framework 3.5')
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

Function Test-DotNetCore {
    [cmdletbinding()]
    Param (
        [Parameter(Position=0,Mandatory=$true)]
        [string]$MinVersion
    )
    #End of parameters
    Process {
        If ($appArch -eq 'x86') {
            # PSAppDeployKit always populates $envProgramFilesX86 even on 32-bit
            $dotNetCorePath = ($envProgramFilesX86 + '\dotnet\shared\Microsoft.NETCore.App')
        }
        else {
            $dotNetCorePath = ($envProgramFiles + '\dotnet\shared\Microsoft.NETCore.App')
        }
        If (Test-Path -Path $dotNetCorePath) {
            $dotNetCoreVersions = ( Get-ChildItem -Path $dotNetCorePath -Directory )
            If ([version]$dotNetCoreVersions[-1].Name -ge [version]$MinVersion) {
                Write-Log -Message ('.NET Core ' + $dotNetCoreVersions[-1] + ' installed')
                return ([bool]$true)
            }
            else {
                Write-Log -Message ('.NET Core ' + $MinVersion + ' not installed')
                return ([bool]$false)                
            }
        }
        else {
            Write-Log -Message ('.NET Core not installed')
            return ([bool]$false)
        }
    }
}

Function Install-DotNetCore {
    [cmdletbinding()]
    Param ()
    Process {
        Write-Log -Message ('Downloading .NET Core Desktop Runtime')
        
        $dotNetCoreDownloadx86 = @{
            Uri = 'https://download.visualstudio.microsoft.com/download/pr/df7b90d9-b93e-4974-85ef-c1de418bc186/e380e58bbd8505ebaee6c3abb23baade/windowsdesktop-runtime-3.1.5-win-x86.exe';
            Destination = ($dirSupportFiles + '\' + 'windowsdesktop-runtime-3.1.5-win-x86.exe');
            Sha256 = 'C314832BB5E090B40DC1CC2EEFEE664051F1A5D7DC8A9C4C61E9E2378656581F'
        }

        $dotNetCoreDownloadx64 = @{
            Uri = 'https://download.visualstudio.microsoft.com/download/pr/86835fe4-93b5-4f4e-a7ad-c0b0532e407b/f4f2b1239f1203a05b9952028d54fc13/windowsdesktop-runtime-3.1.5-win-x64.exe';
            Destination = ($dirSupportFiles + '\' + 'windowsdesktop-runtime-3.1.5-win-x64.exe');
            Sha256 = 'A73148AC46C64F8217F3EBC6F2F9A873A9243BE692829691314B921838F0C05B'
        }

        If ($AppArch -eq 'x64') {
            $dotNetCoreDownload = $dotNetCoreDownloadx64
        }
        Elseif ($AppArch -eq 'x86') {
            $dotNetCoreDownload = $dotNetCoreDownloadx86
        }
        Else {
            Write-Log -Message ('Unknown $AppArch: ' + $AppArch + ' Cannot install .NET Core')
        }

        If (Get-FileFromUri @dotNetCoreDownload) {
            Write-Log -Message ('Installing .NET Core 3.1.5')
            If (Execute-Process -Path ($dirSupportFiles + '\windowsdesktop-runtime-3.1.5-win-' + $appArch + '.exe') -Parameters ('/install /quiet /norestart')) {
                Write-Log -Message ('.NET Framework Core Desktop Runtime installed')
                return ([bool]$true)
            }
            else {
                Write-Log -Message ('Error installing .NET Core Desktop Runtime')
                return ([bool]$false)
            }
        }
        else {
            Write-Log -Message ('Error downloading .NET Core Desktop Runtime')
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

Function Set-WindowState {

	[CmdletBinding(DefaultParameterSetName = 'ByName')]
	param(
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'ByName')]
        [String[]] $Name,

        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'ByParentProcessMainWindowHandle')]
		[IntPtr[]] $ParentProcessMainWindowHandle,

		[Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'ByProcess')]
		[Int[]] $Id,
	
		[Parameter(Position = 1, Mandatory = $true)]
		[ValidateSet('FORCEMINIMIZE', 'HIDE', 'MAXIMIZE', 'MINIMIZE', 'RESTORE',
					 'SHOW', 'SHOWDEFAULT', 'SHOWMAXIMIZED', 'SHOWMINIMIZED',
					 'SHOWMINNOACTIVE', 'SHOWNA', 'SHOWNOACTIVATE', 'SHOWNORMAL')]
		[string] $State
	)

	Begin {
		$WindowStates = @{
			'FORCEMINIMIZE'		= 11
			'HIDE'				= 0
			'MAXIMIZE'			= 3
			'MINIMIZE'			= 6
			'RESTORE'			= 9
			'SHOW'				= 5
			'SHOWDEFAULT'		= 10
			'SHOWMAXIMIZED'		= 3
			'SHOWMINIMIZED'		= 2
			'SHOWMINNOACTIVE'	= 7
			'SHOWNA'			= 8
			'SHOWNOACTIVATE'	= 4
			'SHOWNORMAL'		= 1
		}

		$Win32ShowWindowAsync = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
		$ApiShowWindowAsync = Add-Type -MemberDefinition $Win32ShowWindowAsync -Name 'WindowApi' -PassThru
	}

	Process {
        # When pipelined an array of names or a single name as a parameter
		If ($PSCmdlet.ParameterSetName -eq 'ByName') {
			Write-Log -Message ('Attempting to "' + $State +'" window: ' + $Name)
               Try {
				# Restringify for Get-WindowTitle because it needs a clean regex string?
				$sName = $ExecutionContext.InvokeCommand.ExpandString($Name)
                $FoundWindow = Get-WindowTitle -WindowTitle $sName
                If ($FoundWindow.Count) {
					Write-Log -Message ($sName + ' found ' + $FoundWindow.Count + ' times.')
				}
				Elseif ($FoundWindow) {
					Write-Log -Message ($sName + ' found.')
				}
                Try {
                    $FoundWindow | ForEach-Object {
						$ApiShowWindowAsync::ShowWindowAsync($PSItem.ParentProcessMainWindowHandle, $WindowStates[$State]) | Out-Null
                   		Write-Log -Message ('Window State "' + $State + '" set for "' + $PSItem.WindowTitle + '" (Process Name: ' + $PSItem.ParentProcess + ', Id: ' + $PSItem.ParentProcessId + ')')
                    }
                }
                Catch {
            	    Write-Log -Message ($Error)
                }
            }
            Catch {
                Write-Log -Message ($Error)
            }
        }

        # Pipeline from Get-WindowTitle
		If ($PSCmdlet.ParameterSetName -eq 'ByParentProcessMainWindowHandle') {
			Write-Log -Message ('Attempting to "' + $State +'" window: ' + $PSItem.WindowTitle)
			If ($PSItem.ParentProcessMainWindowHandle -eq 0) {
				Write-Log -Message ('Could not set Window State for "' + $PSItem.WindowTitle + '"; MainWindowHandle is 0 (Hidden)')
			}
			Else {
               	$ApiShowWindowAsync::ShowWindowAsync($PSItem.ParentProcessMainWindowHandle, $WindowStates[$State]) | Out-Null
               	Write-Log -Message ('Window State "' + $State + ' set for ' + $PSItem.WindowTitle + ' (Process Name: ' + $PSItem.ParentProcess + ', Id: ' + $PSItem.ParentProcessId + ')')
			}
        }

		# When pipelined Get-Process
		If ($PSCmdlet.ParameterSetName -eq 'ByProcess') {
			Write-Log -Message ('Attempting to "' + $State +'" windows belong to process: ' + $PSItem.Name + ' (Id: ' + $PSItem.Id + ')')
			If ($PSItem.MainWindowHandle -eq 0) {
				Write-Log -Message ('Could not set Window State for "' + $PSItem.Name + ' (Id: ' + $PSItem.Id + ')"; MainWindowHandle is 0 (Hidden)')
			}
			Else {
            	$ApiShowWindowAsync::ShowWindowAsync($PSItem.MainWindowHandle, $WindowStates[$State]) | Out-Null
                Write-Log -Message ('Window State "' + $State + ' set for ' + $PSItem.MainWindowTitle + ' (Process Name: ' + $PSItem.Name + ', Id: ' + $PSItem.Id + ')')
			}
        }

	}
}

Function Close-Window {
	<#
    .SYNOPSIS
    Request that a process gracefully closes.

	.DESCRIPTION
	Can take process object to close by PID incase the window gets hidden
	#>

	[CmdletBinding(DefaultParameterSetName = 'ByName')]
	param(
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'ByName')]
        [String[]] $Name,

        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'ByWindowParentProcessId')]
		[Int[]] $ParentProcessId,

        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'ByProcess')]
		[Int[]] $Id
	)

	Process {
		# When pipelined an array of names or a single name as a parameter
        If ($PSCmdlet.ParameterSetName -eq 'ByName') {
			Write-Log -Message ('Attempting to close window: ' + $Name)
               Try {
				# Restringify for Get-WindowTitle because it needs a clean regex string?
				$sName = $ExecutionContext.InvokeCommand.ExpandString($Name)
                $FoundWindow = Get-WindowTitle -WindowTitle $sName
                If ($FoundWindow.Count) {
					Write-Log -Message ($sName + ' found ' + $FoundWindow.Count + ' times.')
				}
				Elseif ($FoundWindow) {
					Write-Log -Message ($sName + ' found.')
				}
                Try {
                    $FoundWindow | ForEach-Object {
                    	$windowProcess = Get-Process -Id $PSItem.ParentProcessId
						Try {
							$windowProcess.CloseMainWindow() | Out-Null
							# Sometimes cannot display MainWindowTitle with multiple matches?
                    		Write-Log -Message ('Closed "' + $windowProcess.MainWindowTitle + '" (Process Name: ' + $windowProcess.Processname + ', Id: ' + $windowProcess.Id + ')')
						}
						Catch {
							Write-Log -Message ($Error)
						}
                    }
                }
                Catch {
            	    Write-Log -Message ($Error)
                }
            }
            Catch {
                Write-Log -Message ($Error)
            }
        }

        # Pipeline from Get-WindowTitle
		If ($PSCmdlet.ParameterSetName -eq 'ByWindowParentProcessId') {
			Write-Log -Message ('Attempting to close window [' + $PSItem.WindowTitle + '] [' + $PSItem.ParentProcess + ',' + $PSItem.ParentProcessId + ']')
            Try {
            	$windowParentProcess = Get-Process -Id $PSItem.ParentProcessId -ErrorAction 'Stop'
				Write-Log -Message ($PSItem.WindowTitle + ' found.')
				$windowParentProcess.CloseMainWindow() | Out-Null
				If ($windowParentProcess.HasExited) {
					Write-Log -Message ('Closed "' + $windowParentProcess.MainWindowTitle + '" (Process Name: ' + $windowParentProcess.Name + ', Id: ' + $windowParentProcess.Id + ')')
				}
				Else {
					Write-Log -Message ('Unable to close "' + $windowParentProcess.MainWindowTitle + '" (Process Name: ' + $windowParentProcess.Name + ', Id: ' + $windowParentProcess.Id + ')')
				}
			}
            Catch {
                Write-Log -Message ($PSItem.Exception.Message)
            }
        }

        # Pipeline from Get-Process
		If ($PSCmdlet.ParameterSetName -eq 'ByProcess') {
			Write-Log -Message ('Attempting to close window: ' + $PSItem.MainWindowTitle)
            $PSItem.CloseMainWindow() | Out-Null
            If ($PSItem.HasExited) {
				Write-Log -Message ('Closed: ' + $PSItem.MainWindowTitle + ' (Process Name: ' + $PSItem.Processname + ', Id: ' + $PSItem.Id + ')')
			}
			Else {
				Write-Log -Message ('Unable to close: ' + $PSItem.MainWindowTitle + ' (Process Name: ' + $PSItem.Processname + ', Id: ' + $PSItem.Id + ')')
			}
        }
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
