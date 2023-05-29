<#PSScriptInfo

.VERSION 3.3.4

.AUTHOR cybermoloch@magitekai.com

.COPYRIGHT 2020 CyberMoloch. All Rights Reserved.

.LICENSEURI https://gitlab.com/cybermoloch/psappdeploytoolkit-plus/-/blob/master/LICENSE

.PROJECTURI https://gitlab.com/cybermoloch/psappdeploytoolkit-plus/

.RELEASENOTES
    Added auto-mirror URI

#>

<#
.SYNOPSIS
    Bootstrap script for Datto RMM to launch PSAppDeployToolkit-Plus

.DESCRIPTION
    Bootstrap script for Datto RMM to launch PSAppDeployToolkit-Plus
    
.NOTES

.LINK
    https://gitlab.com/cybermoloch/psappdeploytoolkit-plus/

.LINK
    https://www.magitekai.com/#/blog/psadt-plus/2020/psadt-plus-introduction/
#>

# Workaround for running as User Task
# https://www.magitekai.com/#/blog/datto-rmm/2020/workaround-missing-variables
If (-not (Test-Path -Path Env:\CS_ONLINETASK) ) {
    $envRegPath = 'HKLM:\SOFTWARE\CentraStage\Env'
    # Exclude Environment Variables that are pulled when using PSDrive to read Registry
    $excludeEnv = @('PSChildName','PSDrive','PSParentPath','PSPath','PSProvider')
    (Get-ItemProperty $envRegPath).PSObject.Properties |
        Where-Object -FilterScript { -not ($PSItem.Name -in $excludeEnv) } |
        ForEach-Object -Process { Set-Item -Path ('Env:\' + $PSItem.Name) -Value $PSItem.Value }
}

# REQUIRED PSADT files
$psadtArchiveUri = ${Env:\PSADT_ArchiveURI}
$psadtArchive = 'PSAppDeployToolkit.zip'
$psadtExtrasUri = ${Env:\PSADT_ExtrasURI}
$psadtExtras = 'PSADTExtras.zip'
$psadtSettings = 'Deploy-Application.json'
# OPTIONAL PSADT files
$psadtBanner = 'AppDeployToolkitBanner.png'
$psadtScript = 'Deploy-Application.ps1'
$psadtSupport = 'SupportFiles.zip'
$psadtFiles = 'Files.zip'
$psadtCustomUri = ${Env:\PSADT_CustomURI}
$psadtCustom = 'PSADTCustom.zip'

# Will push these log locations to the XML configuration
# By default, PSADT log files are saved to $envWinDir\Logs\Software which doesn't exist here
# Even if it did, since the logs are read and deleted by default, it would interfere with non-PSADT logs
# Recommended to change location to ${Env:WINDIR}\Logs\Software\PSAppDeployToolkit
# Using ${Env:\} for environment variables will work here and PSADT
$psadtLogPath = '${Env:WINDIR}\Logs\Software\PSAppDeployToolkit'
$psadtLogPathNoAdmin = '${Env:ProgramData}\PSAppDeployToolkit\Logs'
$msiLogPath = '${Env:WINDIR}\Logs\Software\PSAppDeployToolkit'

$psadtHomePath = (${Env:\ProgramData} + '\PSAppDeployToolkit')

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

If ( (-Not (Test-Path -Path $psadtArchive) ) -and ($psadtArchiveUri) ) {
    Write-Output ('Downloading ' + $psadtArchiveUri)
    Invoke-WebRequest -Uri $psadtArchiveUri -OutFile $psadtArchive -UseBasicParsing
    Copy-Item -Path $psadtArchive -Destination ($psadtHomePath + '\' + $psadtArchive) -Force
}

If ( (-Not (Test-Path -Path $psadtExtras) ) -and ($psadtExtrasUri) ) {
    Write-Output ('Downloading ' + $psadtExtrasUri)
    Invoke-WebRequest -Uri $psadtExtrasUri -OutFile $psadtExtras -UseBasicParsing
    Copy-Item -Path $psadtExtras -Destination ($psadtHomePath + '\' + $psadtExtras) -Force
}

If ( (-Not (Test-Path -Path $psadtCustom) ) -and ($psadtCustomUri) ) {
    Write-Output ('Downloading ' + $psadtCustomUri)
    Invoke-WebRequest -Uri $psadtCustomUri -OutFile $psadtCustom -UseBasicParsing
    Copy-Item -Path $psadtCustom -Destination ($psadtHomePath + '\' + $psadtCustom) -Force
}

# Set temporary install directory; Deploy-Application.exe doesn't work if in
# the component subdirectory (C:\ProgramData\CentraStage\Packages\{GUID}#)
If (Test-Path -Path $psadtSettings) {
    $deploymentSettings = Get-Content -Path $psadtSettings | ConvertFrom-Json
    If ($deploymentSettings.psadtVariables.appId) {
        $appId = $deploymentSettings.psadtVariables.appId
        $installPath = ($psadtHomePath + '\' + $appId)
    }
    Else {
        $installPath = ($psadtHomePath + '\InstallTemp')
    }
}
Else {
    If (Test-Path -Path $psadtScript) {
        Write-Warning -Message ($psadtSettings + ' not found; Using ' + $psadtScript)
        $installPath = ($psadtHomePath + '\InstallTemp')
    }
    else {
        Write-Error -Message ($psadtSettings + ' and ' + $psadtScript + ' file is missing. Cannot continue.')
        Exit -1   
    }
}

$psadtPath = ($installPath + '\AppDeployToolkit')
$psadtExtrasPath = ($psadtPath + '\Extras')
$psadtSupportPath = ($installPath + '\SupportFiles')
$psadtFilesPath = ($installPath + '\Files')

# Runs PsExec.exe with -i so PSADT has more magic
$psExecPath = ($psadtPath + '\Extras\PsExec.exe')
# C:\Program Files\Microsoft Deployment Toolkit\Templates\Distribution\Tools\{x86,x64}
$serviceUIPath = ($psadtPath + '\Extras\ServiceUI.exe')
$psExecArgs = '-s -i -accepteula -nobanner "'

# Remove installation directory to ensure old installations don't cause issues
# This might happen if a previous install did exit cleanly
if (Test-Path $installPath) {
    Write-Warning ('Previous ' + $installPath + ' found. Attempting force delete.')
    Remove-Item -Path $installPath -Force -Recurse
}

# Creates the Files and SupportFiles directories in case the archive does not have them
# (Windows' built-in archive management won't add empty directories but 7-Zip does..)
@($psadtFilesPath, $psadtSupportPath, $psadtExtrasPath) | ForEach-Object -Process {
    If ( -not (Test-Path -Path $PSItem) ) {
        Write-Output ('Creating directory: '+ $PSItem)
        New-Item -Path $PSItem -ItemType Directory -Force | Out-Null
    }
}

foreach ($psadtItem in @($psadtArchive,$psadtExtras,$psadtCustom,$psadtSettings,$psadtBanner,$psadtScript,$psadtSupport,$psadtFiles)) {
    If (Test-Path -Path $psadtItem) {
        Switch -exact ($psadtItem) {
            $psadtArchive { Expand-Archive -Path $psadtArchive -DestinationPath $installPath -Force }
            $psadtExtras { Expand-Archive -Path $psadtExtras -DestinationPath $psadtExtrasPath -Force }
            $psadtCustom { Expand-Archive -Path $psadtCustom -DestinationPath $psadtPath -Force }
            $psadtSettings {Copy-Item -Path $psadtSettings -Destination $installPath -Force}
            $psadtBanner {Copy-Item -Path $psadtBanner -Destination $psadtPath -Force}
            $psadtScript {Copy-Item -Path $psadtScript -Destination $installPath -Force}
            $psadtSupport {Expand-Archive -Path $psadtSupport -DestinationPath $psadtSupportPath -Force}
            $psadtFiles {Expand-Archive -Path $psadtFiles -DestinationPath $psadtFilesPath -Force}
        }
        Write-Output ($psadtItem + ' was found')
    }
    Else {
        Write-Warning ($psadtItem + ' not found')
        If ( ($psadtItem -like $psadtArchive) -or ($psadtItem -like $psadtCustom) -or ($psadtItem -like $psadtExtras) ) {
            If ( Test-Path -Path ($psadtHomePath + '\' + $psadtItem) ) {
                Switch -exact ($psadtItem) {
                    $psadtArchive { Expand-Archive -Path ($psadtHomePath + '\' + $psadtArchive) -DestinationPath $installPath -Force }
                    $psadtExtras { Expand-Archive -Path ($psadtHomePath + '\' + $psadtExtras) -DestinationPath $psadtExtrasPath -Force }
                    $psadtCustom { Expand-Archive -Path ($psadtHomePath + '\' + $psadtCustom) -DestinationPath $psadtPath -Force }    
                }
                Write-Output ($psadtItem + ' was found in '+ $psadtHomePath)
                Else {
                    Write-Warning ($psadtItem + ' not found in ' + $psadtHomePath)
                    If (($psadtItem -like $psadtArchive) -or ($psadtItem -like $psadtExtras)) {
                        Write-Error ($psadtItem + ' is a required file. Exiting.')
                        Exit -1
                    }

                }
            }
        }
    }
}

# If logfile paths are specified at the top, push them to the config
# Forces logfile type to be Legacy
If (Test-Path -Path ($psadtPath + '\AppDeployToolkitConfig.xml')) {
    [xml]$psadtConfigXml = Get-Content -Path ($psadtPath + '\AppDeployToolkitConfig.xml')
    $psadtConfigXml.AppDeployToolkit_Config.Toolkit_Options.Toolkit_LogStyle = 'Legacy'
    If ($psadtLogPath) {
        Write-Output ('Push Log file location: ' + $psadtLogPath)
        $psadtConfigXml.AppDeployToolkit_Config.Toolkit_Options.Toolkit_LogPath = $psadtLogPath
    }   
    If ($psadtLogPathNoAdmin) {
        Write-Output ('Push NoAdmin Log file location: ' + $psadtLogPathNoAdmin)
        $psadtConfigXml.AppDeployToolkit_Config.Toolkit_Options.Toolkit_LogPathNoAdminRights = $psadtLogPathNoAdmin
    }
    If ($msiLogPath) {
        Write-Output ('Pushing MSI Log file location: ' + $msiLogPath)
        $psadtConfigXml.AppDeployToolkit_Config.MSI_Options.MSI_LogPath = $msiLogPath
    }
    $psadtConfigXml.Save($psadtPath + '\AppDeployToolkitConfig.xml')
}

# Reads the XML Configuration to confirm log locations; pushed or otherwise
$psadtLogPath = $ExecutionContext.InvokeCommand.ExpandString($psadtConfigXml.AppDeployToolkit_Config.Toolkit_Options.Toolkit_LogPath)
Write-Output ('PASADT Log file location: ' + $psadtLogPath)
$psadtLogPathNoAdmin = $ExecutionContext.InvokeCommand.ExpandString($psadtConfigXml.AppDeployToolkit_Config.Toolkit_Options.Toolkit_LogPathNoAdminRights)
Write-Output ('PASADT NoAdmin Log file location: ' + $psadtLogPathNoAdmin)
$msiLogPath = $ExecutionContext.InvokeCommand.ExpandString($psadtConfigXml.AppDeployToolkit_Config.MSI_Options.MSI_LogPath)
Write-Output ('MSI Log file location: ' + $msiLogPath)


If ( (Test-Path -Path 'Env:\PSADT_MirrorURI') -or ($deploymentSettings.rmmVariables) ) {
    $rmmEnv = New-Object -TypeName psobject

    # Export Mirror URI Variables if they exist
    If (Test-Path -Path 'Env:\PSADT_MirrorURI') {
        Write-Information -MessageData ('Env:\PSADT_MirrorURI found as a site or account variable')
        $envVar = (Get-Item -Path 'Env:\PSADT_MirrorURI' | Select-Object -Property Name,Value)
        $rmmEnv | Add-Member -MemberType NoteProperty -Name $envVar.Name -Value $envVar.Value
    } else {
        Write-Warning -Message 'Env:\PSADT_MirrorURI not found as a site or account variable'
    }
    If (Test-Path -Path 'Env:\PSADT_MirrorURISAS') {
        Write-Information -MessageData ('Env:\PSADT_MirrorURISAS found as a site or account variable')
        $envVar = (Get-Item -Path 'Env:\PSADT_MirrorURISAS' | Select-Object -Property Name,Value)
        $rmmEnv | Add-Member -MemberType NoteProperty -Name $envVar.Name -Value $envVar.Value
    } else {
        Write-Warning -Message 'Env:\PSADT_MirrorURISAS not found as a site or account variable'
    }

    # Export needed RMM Environment Variables to JSON for use in PSADT
    If ($deploymentSettings.rmmVariables) {
    Write-Output ('Attempting export of ' + ($deploymentSettings.rmmVariables -Join ',') + ' variables to JSON file.') 
    $deploymentSettings.rmmVariables | ForEach-Object -Process {
        # Check for same Variable with "or" prefix for override from component (vs inherited from site or account level)
        $override = ('Env:or' + $PSItem)
            If (Test-Path -Path $override) {
                Write-Information -MessageData (${Env:$PSItem} + ' found as an override variable')
                $envVar = (Get-Item -Path $override | Select-Object -Property Name,Value)
            }
            else {
                if ( Test-Path -Path ('Env:\' + $PSItem) ) {
                    Write-Information -MessageData (('Env:\' + $PSItem) + ' found as a site or account variable')
                    $envVar = (Get-Item -Path ('Env:\' + $PSItem) | Select-Object -Property Name,Value)
                    $rmmEnv | Add-Member -MemberType NoteProperty -Name $envVar.Name -Value $envVar.Value
                }
                else {
                    Write-Warning -Message ($PSItem + ' not found in site variables.')
                }
            }
        }
    }
    $rmmEnv | ConvertTo-Json | Out-File -FilePath ($psadtSupportPath + '\rmmEnv.json')
}

# Checking and setting options for INSTALL vs UNINSTALL
if (Test-Path ("Env:\Action")) {
    Switch -exact (${Env:\Action})
    {
        'INSTALL' {
            Write-Output ('Action set for INSTALL')
            $psadtType = '-DeploymentType \"Install\"'
        }
        'UNINSTALL' {
            Write-Output ('Action set for UNINSTALL')
            $psadtType = '-DeploymentType \"Uninstall\"'
        }
        'REPAIR' {
            Write-Output ('Action set for REPAIR')
            $psadtType = '-DeploymentType \"Repair\"'
        }
        default {
            # In case the action variable was created incorrectly
            Write-Error -Message ('Unknown action: ' + ${Env:\Action})
            Exit -1
        }
    }
} else {
    # In case the action was not created in the component, set action to INSTALL
    # (Also helps running directly from a PowerShell prompt to test install)
    Write-Output 'Missing "Action" command. Defaulting to INSTALL.'
    $psadtType = '-DeploymentType \"Install\"'
}

# Check for user session to push notifications and dialogs
# Sets installation program and parameters
if ((Get-WmiObject -Class win32_computersystem).UserName) {
    Write-Output ('User session found.')
    $psadtMode = '-DeployMode \"Interactive\"'
    # Adding ServiceUI.exe to interact with the user session
    $psExecArgs = ($psExecArgs + $serviceUIPath + '" -process:explorer.exe "')
} else {
    Write-Output ('User session not found.')
    $psadtMode = '-DeployMode \"NonInteractive\"'
}

# Setup complete commandline arguments to pass to PsExec.exe
$psExecArgs = ($psExecArgs + $installPath + '\Deploy-Application.exe" "' + $psadtType + ' ' + $psadtMode + '"')

# Beings the installtion Program
if (Test-Path $psExecPath) {
    Write-Output ('Starting installer program with the command: ' + $psExecPath + ' ' + $psExecArgs)
    $psExecProcess = Start-Process -FilePath $psExecPath -ArgumentList $psExecArgs -WorkingDirectory $installPath -Wait -PassThru
    }
else {
    Write-Warning ('Running installer failed. ' + $psExecPath + ' not found')
    Exit -1
}

$psadtExitCode = $psExecProcess.ExitCode

# Get log from PSADT and dump to stdout for RMM

$psadtLogFiles = @()

If (Test-Path ($psadtLogPath)) {
    $psadtLogFiles = (Get-ChildItem -Path $psadtLogPath -Filter '*.log')
}
else {
    Write-Error ('Unable to retreive log directory.')
}

If ( ($psadtLogPathNoAdmin -ne $psadtLogPath) -and ($psadtLogPathNoAdmin -ne $msiLogPath) ) {
    If (Test-Path -Path $psadtLogPathNoAdmin) {
        $psadtLogFiles += (Get-ChildItem -Path $psadtLogPathNoAdmin -Filter '*.log')
    }
    else {
        Write-Error ('Unable to retreive NoAdmin log directory.')
    }
}

If ( ($msiLogPath -ne $psadtLogPath) -and ($msiLogPath -ne $psadtLogPathNoAdmin) ) {
    If (Test-Path ($msiLogPath)) {
        $psadtLogFiles += (Get-ChildItem -Path $msiLogPath -Filter '*.log')
    }
    else {
        Write-Error ('Unable to retreive MSI log directory.')
    }
}

If ($psadtLogFiles) {
    $psadtLogFiles | ForEach-Object -Process { Write-Output ('Log file found: ' + $PSItem.Name) }
    $psadtLogFiles | ForEach-Object -Process {
        If (Test-Path ($PSItem.FullName)) {
            Write-Output ('')
            Write-Output ('*******************************************************************************')
            Write-Output ('*******************************************************************************')
            Write-Output (Split-Path -Path $PSItem.FullName -Leaf)
            Write-Output ('*******************************************************************************')
            Write-Output ('*******************************************************************************')
            Write-Output ('')
            Get-Content -Path ($PSItem.FullName)
            # Comment below to retain logs.
            Remove-Item -Path ($PSItem.FullName)
        }
        else {
            Write-Error ('Unable to read logfile: ' + $PSItem.Name)
        }
    }
} else {
    Write-Error ('Unable to retreive log directory.')
}

# Clean-up temporary installation directory
if (Test-Path $installPath) {
    Write-Output ('')
    Write-Output ('*******************************************************************************')
    Write-Output ('Removing temporary installation directory: ' + $installPath)
    Remove-Item -Path $installPath -Force -Recurse
}

if ($psadtExitCode) {
    Write-Output ('Exiting: ' + $psadtExitCode)
    Exit $psadtExitCode
}