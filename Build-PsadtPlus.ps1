[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

If (${env:build_type} -eq 'master') {
    $PsadtUri = 'https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/archive/master.zip'
}
else {
    $PsadtUri = 'https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases/download/3.8.2/PSAppDeployToolkit_v3.8.2.zip'    
}
$NtfsSecurityUri = 'https://github.com/raandree/NTFSSecurity/releases/download/4.2.6/NTFSSecurity.zip'
$VcRedistUri = 'https://github.com/aaronparker/VcRedist/archive/v2.0.163.zip'
$SetUserFtaUri = 'https://kolbi.cz/SetUserFTA.zip'

Write-Output 'Downloading upstream PSAppDeployToolkit...'
Invoke-WebRequest -Uri $PsadtUri -OutFile 'PSAppDeployToolkit.zip' -UseBasicParsing
Write-Output 'Downloading upstream NTFSSecurity Module...'
Invoke-WebRequest -Uri $NtfsSecurityUri -OutFile 'NTFSSecurity.zip'-UseBasicParsing
Write-Output 'Downloading upstream VcRedist Module...'
Invoke-WebRequest -Uri $VcRedistUri -OutFile 'VcRedist.zip' -UseBasicParsing
Write-Output 'Downloading upstream SetUserFTA...'
Invoke-WebRequest -Uri $SetUserFtaUri -OutFile 'SetUserFTA.zip' -UseBasicParsing

Unblock-File -Path '*.zip'

$toolkitPath = 'PSADTPlus\AppDeployToolkit'
$modulesPath = 'PSADTPlus\AppDeployToolkit\Modules'
$extrasPath = 'PSADTPlus\AppDeployToolkit\Extras'

Write-Output ('Creating directions: ' + $modulesPath + ' and ' + $extrasPath)
@($modulesPath, $extrasPath) | ForEach-Object -Process { New-Item -Path $PSItem -ItemType Directory -Force  | Out-Null }

Write-Output 'Extracting archives...'
Get-ChildItem -Path '*.zip' | ForEach-Object -Process { Expand-Archive -Path $PSItem -Force }

Write-Output 'Copying upstream PSApplDeployToolkit files...'
If (${env:build_type} -eq 'master') {
    Copy-Item -Path 'PSAppDeployToolkit\PSAppDeployToolkit-master\Toolkit\*' -Destination 'PSADTPlus' -Recurse -Force
}
else {
    Copy-Item -Path 'PSAppDeployToolkit\Toolkit\*' -Destination 'PSADTPlus' -Recurse -Force    
}
$PsadtLicenseUri = 'https://raw.githubusercontent.com/PSAppDeployToolkit/PSAppDeployToolkit/master/LICENSE'
Invoke-WebRequest -Uri $PsadtLicenseUri -OutFile 'PSADTPlus\LICENSE'

Write-Output 'Copying NTFSSecurity Module files...'
Copy-Item -Path 'NTFSSecurity\NTFSSecurity' -Destination ($modulesPath + '\NTFSSecurity') -Recurse -Force
$NtfsSecurityLicenseUri = 'https://raw.githubusercontent.com/raandree/NTFSSecurity/master/LICENSE'
Invoke-WebRequest -Uri $NtfsSecurityLicenseUri -OutFile ($modulesPath + '\NTFSSecurity\LICENSE')

Write-Output 'Copying VcRedist Module files...'
$vcRedistSrcPath = Get-ChildItem -Path 'VcRedist' -Directory | Get-ChildItem -Filter 'VcRedist' -Directory
Copy-Item -Path $vcRedistSrcPath.FullName -Destination ($modulesPath + '\VcRedist') -Recurse -Force
$VcRedistLicenseUri = 'https://raw.githubusercontent.com/aaronparker/VcRedist/master/LICENSE'
Invoke-WebRequest -Uri $VcRedistLicenseUri -OutFile ($modulesPath + '\VcRedist\LICENSE')

Write-Output 'Copying SetUserFTA files...'
Copy-Item -Path 'SetUserFTA\SetUserFTA\SetUserFTA.exe' -Destination ($extrasPath + '\SetUserFTA.exe') -Force
Copy-Item -Path 'SetUserFTA\SetUserFTA\EULA.txt' -Destination ($extrasPath + '\SetUserFTA-EULA.txt') -Force

Write-Output 'Copying PSAppDeployToolkit-Plus files...'
Copy-Item -Path 'Toolkit\Deploy-Application.ps1' -Destination 'PSADTPlus\Deploy-Application.ps1' -Force
Copy-Item -Path 'Toolkit\AppDeployToolkit\AppDeployToolkitExtensions.ps1' -Destination ($toolkitPath + '\AppDeployToolkitExtensions.ps1') -Force
Copy-Item -Path 'Toolkit\AppDeployToolkit\AppDeployToolkitBanner.png' -Destination ($toolkitPath + '\AppDeployToolkitBanner.png') -Force
Copy-Item -Path 'Toolkit\AppDeployToolkit\AppDeployToolkitLogo.ico' -Destination ($toolkitPath + '\AppDeployToolkitLogo.ico') -Force

If (Test-Path -Path Env:\GITHUB_REFG) {
    $PsadtPlusFilename = ('PSADTPlus-' + ${env:GITHUB_REF} + '.zip')
}
elseIf (Test-Path -Path Env:\GITHUB_SHA) {
    $PsadtPlusFilename = ('PSADTPlus-' + ${env:GITHUB_SHA}.Substring(0,7) + '.zip')
}
else {
    $PsadtPlusFilename = 'PSADTPlus.zip'
}

Write-Output ('Building zip package: ' + $PsadtPlusFilename)
Compress-Archive -Path 'PSADTPlus\*' -DestinationPath $PsadtPlusFilename -Force
