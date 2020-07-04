[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$PsadtUri = 'https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases/download/3.8.2/PSAppDeployToolkit_v3.8.2.zip'
$NtfsSecurityUri = 'https://github.com/raandree/NTFSSecurity/releases/download/4.2.6/NTFSSecurity.zip'
$VcRedistUri = 'https://github.com/aaronparker/VcRedist/archive/v2.0.163.zip'
$SetUserFtaUri = 'https://kolbi.cz/SetUserFTA.zip'

Invoke-WebRequest -Uri $PsadtUri -OutFile 'PSAppDeployToolkit.zip' -UseBasicParsing
Invoke-WebRequest -Uri $NtfsSecurityUri -OutFile 'NTFSSecurity.zip'-UseBasicParsing
Invoke-WebRequest -Uri $VcRedistUri -OutFile 'VcRedist.zip' -UseBasicParsing
Invoke-WebRequest -Uri $SetUserFtaUri -OutFile 'SetUserFTA.zip' -UseBasicParsing

Unblock-File -Path '*.zip'

$toolkitPath = 'PSADTPlus\AppDeployToolkit'
$modulesPath = 'PSADTPlus\AppDeployToolkit\Modules'
$extrasPath = 'PSADTPlus\AppDeployToolkit\Extras'

@($modulesPath, $extrasPath) | ForEach-Object -Process { New-Item -Path $PSItem -ItemType Directory -Force }

Get-ChildItem -Path '*.zip' | ForEach-Object -Process { Expand-Archive -Path $PSItem -Force }

Copy-Item -Path 'PSAppDeployToolkit\Toolkit\*' -Destination 'PSADTPlus' -Recurse -Force
$PsadtLicenseUri = 'https://raw.githubusercontent.com/PSAppDeployToolkit/PSAppDeployToolkit/master/LICENSE'
Invoke-WebRequest -Uri $PsadtLicenseUri -OutFile 'PSADTPlus\LICENSE'

Copy-Item -Path 'NTFSSecurity' -Destination $modulesPath -Recurse -Force
$NtfsSecurityLicenseUri = 'https://raw.githubusercontent.com/raandree/NTFSSecurity/master/LICENSE'
Invoke-WebRequest -Uri $NtfsSecurityLicenseUri -OutFile ($modulesPath + '\NTFSSecurity\LICENSE')

$vcRedistSrcPath = Get-ChildItem -Path 'VcRedist' -Directory | Get-ChildItem -Filter 'VcRedist' -Directory
Copy-Item -Path $vcRedistSrcPath.FullName -Destination ($modulesPath + '\VcRedist') -Recurse -Force
$VcRedistLicenseUri = 'https://raw.githubusercontent.com/aaronparker/VcRedist/master/LICENSE'
Invoke-WebRequest -Uri $VcRedistLicenseUri -OutFile ($modulesPath + '\VcRedist\LICENSE')

Copy-Item -Path 'SetUserFTA\SetUserFTA\SetUserFTA.exe' -Destination ($extrasPath + '\SetUserFTA.exe') -Force
Copy-Item -Path 'SetUserFTA\SetUserFTA\EULA.txt' -Destination ($extrasPath + '\SetUserFTA-EULA.txt') -Force

Copy-Item -Path 'Toolkit\Deploy-Application.ps1' -Destination 'PSADTPlus\Deploy-Application.ps1' -Force
Copy-Item -Path 'Toolkit\AppDeployToolkit\AppDeployToolkitExtensions.ps1' -Destination ($toolkitPath + '\AppDeployToolkitExtensions.ps1') -Force
Copy-Item -Path 'Toolkit\AppDeployToolkit\AppDeployToolkitBanner.png' -Destination ($toolkitPath + '\AppDeployToolkitBanner.png') -Force
Copy-Item -Path 'Toolkit\AppDeployToolkit\AppDeployToolkitLogo.ico' -Destination ($toolkitPath + '\AppDeployToolkitLogo.ico') -Force

If (Test-Path -Path Env:\CI_COMMIT_SHORT_SHA) {
    $PsadtPlusFilename = ('PSADTPlus-' + ${env:CI_COMMIT)CI_COMMIT_SHORT_SHA} + '.zip')
} else {
    $PsadtPlusFilename = 'PSADTPlus.zip'
}

Compress-Archive -Path 'PSADTPlus\*' -DestinationPath $PsadtPlusFilename -Force