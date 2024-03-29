﻿<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
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
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall','Repair')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Import JSON deployment details and RMM environment variables
	## Need validation of file exists and valid JSON
	$deploySettings = Get-Content -Path ($PSScriptRoot + '\Deploy-Application.json')  | ConvertFrom-Json

	## Variables: Application

	[string]$appVendor = $deploySettings.psadtVariables.appVendor
	[string]$appName = $deploySettings.psadtVariables.appName
	[string]$appVersion = $deploySettings.psadtVariables.appVersion
	[string]$appArch = $deploySettings.psadtVariables.appArch
	[string]$appLang = $deploySettings.psadtVariables.appLang
	[string]$appRevision = $deploySettings.psadtVariables.appRevision
	[string]$appScriptVersion = '3.5.0.5'
	[string]$appScriptDate = $deploySettings.psadtVariables.appScriptDate
	[string]$appScriptAuthor = $deploySettings.psadtVariables.appScriptAuthor

	## Additional metadata from PSADT-Plus
	[string]$appId = $deploySettings.psadtVariables.appId
	[string]$appDesc = $deploySettings.psadtVariables.appDesc

	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = $deploySettings.psadtVariables.installName
	[string]$installTitle = $deploySettings.psadtVariables.installTitle

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.8.2'
	[string]$deployAppScriptDate = '08/05/2020'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above

	# Get exported environment variables from RMM platform and convert to single variables
	if ($dirSupportFiles + '\rmmEnv.json') {
		$rmmEnv =  Get-Content -Path ($dirSupportFiles + '\rmmEnv.json') | ConvertFrom-Json

		$rmmEnvHash = @{}
		foreach ($property in $rmmEnv.PSObject.Properties) {
			$rmmEnvHash[$property.Name] = $property.Value
		}
	
		$rmmEnvHash.GetEnumerator() | ForEach-Object {
			If (!(Test-Path $_.Name)) {
				New-Variable -Name ($_.Name) -Value ($_.Value)
			}
		}
	}
	
	If ($deploySettings.appDetails.executables) { $closeApps = ($deploySettings.appDetails.executables -Join ',') }
	$requiredDiskSpace = ($deploySettings.appDetails.reqSpaceMb)

	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if required, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt
		
		If ($closeApps) {
			Show-InstallationWelcome -CloseApps $closeApps -CheckDiskSpace -RequiredDiskSpace $requiredDiskSpace
		}
		Else {
			Show-InstallationWelcome -CheckDiskSpace -RequiredDiskSpace $requiredDiskSpace
		}
		
		
		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Installation tasks here>

		# $appArch isn't validated so could be prone to false positives?
		If ( ($appArch -eq 'x64') -and (-Not $Is64Bit) ) {
			Show-InstallationPrompt -Message 'This application requires an x64 (64-bit) operating system. Please contact your system administrator for assistance.' -Icon Error -Timeout 60
			Exit-Script -ExitCode -1
		}

		If ( ($deploySettings.appDetails.downloadInfo.x86.uri) -or ($deploySettings.appDetails.downloadInfo.x64.uri) ) {
			# If no x86 download is specified and the OS is 32-bit, presents error and exits
			If ( (-Not $deploySettings.appDetails.downloadInfo.x86.uri ) -and ( -Not $Is64Bit ) ) {
				Show-InstallationPrompt -Message 'This application requires an x64 (64-bit) operating system. Please contact your system administrator for assistance.' -Icon Error -Timeout 60
				Exit-Script -ExitCode -1
			}

			# Checks for and waits for internet connectivity before proceeding
			# If not internet connection is detected, presents user with an message that internet is required
			If (-Not (Test-InternetConnection)) {
				$cancelInstall = Show-InstallationPrompt -Message "No internet connection detected. Please connect to the internet to continue.`nAn internet connection is required to download the installation package.`nIf you would like to cancel the installation to try again later, please click the `"Cancel`" button." -Icon Information -ButtonRightText 'Cancel'
					If ($cancelInstall -eq 'Cancel') {
						Write-Log -Message 'Internet connection not detected and the user cancelled the install.'
						Exit-Script -ExitCode -1
					}
				Do {
					Start-Sleep -Seconds 5
				} Until (Test-InternetConnection)			
			}

			# Downloads the installer package for the correct architecture
			Show-InstallationProgress -StatusMessage 'Downloading installation package... Please wait.'

			# Set URI based on download settings and OS architecture
			If (($deploySettings.appDetails.downloadInfo.x64.uri) -and ($Is64Bit)) {
				$packageUri = ($deploySettings.appDetails.downloadInfo.x64.uri)
				$installerSha256 = ($deploySettings.appDetails.downloadInfo.x64.sha256)
				$appArch = 'x64'
			}
			else {
				$packageUri = ($deploySettings.appDetails.downloadInfo.x86.uri)
				$installerSha256 = ($deploySettings.appDetails.downloadInfo.x86.sha256)
				$appArch = 'x86'
			}

			# Expand variables in URIs
			$uriCount = 0
        	do {
	            $packageUri[$uriCount] = ($ExecutionContext.InvokeCommand.ExpandString($packageUri[$uriCount]))
            	$uriCount++
        	}
        	while ($packageUri[$uriCount])

            If ($deploySettings.appDetails.downloadInfo.packageFilename) {
				$packageFilename = $deploySettings.appDetails.downloadInfo.packageFilename
			} Else {
				# Get filename from the URI
				$packageFilename = (Split-Path -Path $packageUri[0] -Leaf)

				# Strip any part of filename after ? (query strings for protected downloads)
				If ($packageFilename -match '\?') {
					$packageFilename = $packageFilename.Substring(0, $packageFilename.IndexOf('?'))    
				}
			}

			If ($PSADT_MirrorURI) {
				Write-Log -Message 'Mirror Base URI found'
				$vendor
				$appMirrorPath = ($appVendor.ToLower().Replace(' ','-') + '/' + $appId + '/' + $appVersion + '/' + $appArch + '/' + $packageFilename)
				If ($PSADT_MirrorURISAS) {
					Write-Log -Message 'Mirror URI SAS found'
					$appMirrorUri = ($PSADT_MirrorURI + $appMirrorPath + $PSADT_MirrorURISAS)
				} else {
					$appMirrorUri = ($PSADT_MirrorURI + $appMirrorPath)
				}
				Write-Log -Message ('Adding '+ $appMirrorUri + ' to download URIs')
				$packageUri += $appMirrorUri
			}

			# Get extension of file
			$packageFileType = (($packageFilename).Split('.')[-1])

			# Set download destination to $dirFiles if exe or msi file, $dirSUpportFiles if zip file
			Switch -exact ($packageFileType)
			{
				'msi' { $destinationPath = $dirFiles }
				'msix' { $destinationPath = $dirFiles }
				'msixbundle' { $destinationPath = $dirFiles }
				'appx' { $destinationPath = $dirFiles }
				'appxbundle' { $destinationPath = $dirFiles }
				'exe' { $destinationPath = $dirFiles }
				'zip' { $destinationPath = $dirSupportFiles }
				default {
					Write-Log -Message 'The installer package type was unknown. (Not an .msi, .msix(bundle), .appx(bundle) .exe, or .zip file.)'
					Show-InstallationPrompt -Message 'Invalid installer package filetype specified. Please contact your system adminstrator for assistance.' -Icon Error -Timeout 60 -ButtonRight 'OK'
					Exit-Script -ExitCode -1
				}
			}

			Write-Log -Message ('Attempting to download ' + $packageFilename)

			If (Get-FileFromUri -Uri $packageUri -Destination ($destinationPath + '\' + $packageFilename) -Sha256 $installerSha256) {
				Write-Log -Message ($packageFilename + ' sucessfully downloaded to ' + $destinationPath)
			}
			else {
				Write-Log -Message ($packageFilename + ' failed to download')
				Show-InstallationPrompt -Message 'Error downloading installer. Please try again later.' -Icon Error -Timeout 60 -ButtonRight 'OK'
				Exit-Script -ExitCode -1
			}

			# Extract contents of archive to $dirFiles
			If ($packageFileType -like 'zip') {
				Write-Log -Message ('Extracting ' + $packageFilename + ' to ' + $dirFiles)
				Show-InstallationProgress -StatusMessage 'Extracting installation package... Please wait.'
				Expand-Archive -Path ($dirSupportFiles + '\' + $packageFilename) -DestinationPath $dirFiles -Force
			}
		}
		else {
			Write-Log -Message ('Download URIs not found. Using install files already in ' + $dirFiles)
		}
		
		# dotNet and vcRedist Prequisites check and install
		# should add failure messages to user and exit script if fails
		Show-InstallationProgress -StatusMessage ('Checking for dependencies')
		
		If ($deploySettings.appDetails.prerequisites)  {
			Write-Log -Message ('Following prerequisites specified:')
			Write-Log -Message $deploySettings.appDetails.prerequisites
			$deploySettings.appDetails.prerequisites | ForEach-Object -Process {
				$prereq = $PSItem
				Switch -exact ($prereq.type)
				{
					'dotNet35' {
						Write-Log -Message ('.NET Framework 3.5 required')
						If ( -Not (Test-DotNet35) ) {
							Write-Log -Message ('.NET Framework 3.5 was not found. Attempting to install it.')
							Show-InstallationProgress -StatusMessage ('Installing .NET Framework 3.5')
							Install-DotNet35
						}
						else {
							Write-Log -Message ('.NET Framework 3.5 is installed.')
						}
					}
					'dotNet4x' {
						Write-Log -Message ('.NET Framework ' + ($prereq.minVersion) + ' required')
						If ( -Not (Test-DotNet4x -MinVersion $prereq.minVersion) ) {
							Write-Log -Message ('.NET Framework ' + ($prereq.minVersion) + ' was not found. Attempting to install .NET Framwork 4.8')
							Show-InstallationProgress -StatusMessage ('Installing .NET Framework 4.8')
							Install-DotNet4x
						}
						else {
							Write-Log -Message ('.NET Framework ' + ($prereq.MinVersion) + ' is installed')
						}
					}
					'dotNetCore' {
						Write-Log -Message ('.NET Core Runtime ' + ($prereq.minVersion) + ' required')
						If ( -Not (Test-DotNetCore -MinVersion $prereq.minVersion) ) {
							Write-Log -Message ('.NET Core Runtime ' + ($prereq.minVersion) + ' was not found. Attempting to install .NET Core')
							Show-InstallationProgress -StatusMessage ('Installing .NET Core Runtime')
							Install-DotNetCore
						}
						else {
							Write-Log -Message ('.NET Core Runtime ' + ($prereq.MinVersion) + ' is already installed')
						}
					}
					'vcRedist' {
						$vcRedistParams = @{
							Release = $prereq.release
							Architecture = $appArch
							MinVersion = $prereq.minVersion
						}
						# Checking for Visual Studio Redistributables
						If ( -Not (Test-VcRedist @vcRedistParams) ) {
							Write-Log -Message ('The required vcRedist was not found. Attempting to install.')
							Install-VcRedistByRelease -Release ($prereq.release) -Architecture ($appArch)
						}
					}
					default {
						Write-Log -Message ('Unknown prequisite type: ' + $prereq.type)
					}
				}
			}

		}
		
		If ($deploySettings.tasks.preinstallation) {
			Show-InstallationProgress -StatusMessage ('Performing pre-installation tasks')
			$deploySettings.tasks.preinstallation | ForEach-Object -Process {Invoke-Expression $_}
		}

		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>
		Show-InstallationProgress -StatusMessage 'Performing background installation...'

		If ($deploySettings.tasks.installation) {
			$deploySettings.tasks.installation | ForEach-Object -Process {Invoke-Expression $_}
		}

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>
		# Sets permissions to All USERS Desktop Items to Modify to they can by deleted by normal users
		If ($deploySettings.appDetails.desktopItems) {
			$deploySettings.appDetails.desktopItems | ForEach-Object -Process {
				$itemName = ($ExecutionContext.InvokeCommand.ExpandString($PSItem))
				$ntfsAccessParams = @{
					Path = ($envCommonDesktop + '\' + $itemName)
					Account = 'NT AUTHORITY\Authenticated Users'
					AccessRights = 'Modify'
				}
				Add-NTFSAccess @ntfsAccessParams
			}
		}

		If ( ($deploySettings.appDetails.associations) -and ($deploySettings.appDetails.associations[0].application -ine '') -and ($IsProcessUserInteractive)) {
			$deploySettings.appDetails.associations | ForEach-Object -Process {Set-UserFta -Extension $_.extension -ApplicationId $_.application -Prompt}
		}

		Show-InstallationProgress -StatusMessage ('Performing post-installation tasks')
		
		If ($deploySettings.tasks.postinstallation) {
			$deploySettings.tasks.postinstallation | ForEach-Object -Process {Invoke-Expression $_}
		}

		## Display a message at the end of the install
		If (-not $useDefaultMsi) { Show-InstallationPrompt -Message ($appName + ' sucessfully installated.') -ButtonRightText 'OK' -Icon Information -NoWait }
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		If ($closeApps) {
			Show-InstallationWelcome -CloseApps $closeApps -CloseAppsCountdown 60
		}
		Else {
			Show-InstallationWelcome
		}

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>
		If ($deploySettings.tasks.preuninstallation) {
			Show-InstallationProgress -StatusMessage ('Performing pre-uninstallation tasks')
			$deploySettings.tasks.preuninstallation | ForEach-Object  -Process {Invoke-Expression $_}
		}
		
		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>
		If ($deploySettings.tasks.uninstallation) {
			Show-InstallationProgress -StatusMessage ('Performing uninstallation tasks')
			$deploySettings.tasks.uninstallation | ForEach-Object  -Process {Invoke-Expression $_}
		}
		
		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>
		If ($deploySettings.tasks.postuninstallation) {
			Show-InstallationProgress -StatusMessage ('Performing post-uninstallation tasks')
			$deploySettings.tasks.postuninstallation | ForEach-Object  -Process {Invoke-Expression $_}
		}

	}
	ElseIf ($deploymentType -ieq 'Repair')
	{
		##*===============================================
		##* PRE-REPAIR
		##*===============================================
		[string]$installPhase = 'Pre-Repair'

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Repair tasks here>

		##*===============================================
		##* REPAIR
		##*===============================================
		[string]$installPhase = 'Repair'

		## Handle Zero-Config MSI Repairs
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
		Execute-MSI @ExecuteDefaultMSISplat
		}
		# <Perform Repair tasks here>

		##*===============================================
		##* POST-REPAIR
		##*===============================================
		[string]$installPhase = 'Post-Repair'

		## <Perform Post-Repair tasks here>


    }
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}
