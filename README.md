# What is PowerShell App Deployment Toolkit Plus?

The PowerShell App Deployment Toolkit Plus (PSADT+) is a modication to the original PSAppDeployToolkit to allow streamlined deployment of new packages and bring additional consistency to the deployment process. (Please see the Wiki for more details of additions and deployment flow/options.)

## What are the main additions to PSADT+?

- **Consisntent Deployment:** All typical and necessary commandss for application deployment are already built in to Deploy-Application.ps1
- **Simple JSON per App:** All required details are containted within a single JSON file
- **Custom Commands:** JSON configuration allows any command to be inserted without modification of Deploy-Application.ps1
- **Addtional Modules:** Added two PowerShell Modules: VcRedist and NTFSSecurity
- **Addtional Functions:** Added additional functions to facilitate commands for easier use in the JSON
- **Prequisite Checks and Installation:** Standardized functions for checking for .NET frameworks and Visual Studio Redistributables
- **Bootstrap Script:** Includes a bootstrap script for use with RMM tools (Uses PSExec and ServiceUI)
- **Logging to stdout:** Takes the PSADT log and outputs it to stdout so visible from RMM task log
- **Separate Repository for Apps:** Maintenance of JSON configurations and others assets for common applications [1]

[1]: https://gitlab.com/cybermoloch/psappdeploytoolkit-apps

## Standard Deployment Flow

The simplified version of deployment tasks:

1. Determine if interactive or non-interactive install
2. Determine x86 or x64
3. Download deployment package
4. Silent install if possible or without user input at minimum
5. Set permissions for any "All User Desktop" items (instead of removing items, change permissions so any user can delete them)
6. Prompt user for any related file associations

## Usage

1. Create ZIP file of the Toolkit directory and name the file PSAppDeployToolkit.zip
2. Add PsExec and ServiceUI executables (both x86 and x64) to the Tools sub-directory (in the zip file).
3. In your deployment tool, have it run the command.ps1 and attach the PSAppDeployToolkit.zip, Deploy-Application.json and optionally a new banner image.
4. If there are additional supporting files attach them in a zip file named SupportFiles.zip.
5. Run the task.

### System Requirements

* Powershell 2.0+
* .NET Framework 3.5+

### Links

**-> [Homepage](https://psappdeploytoolkit.com)<br>
-> [Community Forums](https://discourse.psappdeploytoolkit.com/)<br>
-> [Releases](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases)<br>
-> [Screenshots](https://psappdeploytoolkit.com/screenshots/)<br>
-> [About Us](https://psappdeploytoolkit.com/about/)**<br>

### License

PSADT+ follows the same license as the original PowerShell App Deployment Toolkit: GPLv3. Both PowerShell modules are under the MIT license as per their original authors.

## Links

### PSAppDeployToolkit

- [Homepage](https://psappdeploytoolkit.com)
- [GitHub](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit)

### VcRedist PowerShell Module

- [Homepage](https://docs.stealthpuppy.com/vcredist/)
- [GitHub](https://github.com/aaronparker/VcRedist)
- [PowerShell Gallery](https://www.powershellgallery.com/packages/VcRedist/)

### NTFS Security PowerShell Module

- [Tutorial 1](http://blogs.technet.com/b/fieldcoding/archive/2014/12/05/ntfssecurity-tutorial-1-getting-adding-and-removing-permissions.aspx)
- [Tutorial 2](http://blogs.technet.com/b/fieldcoding/archive/2014/12/05/ntfssecurity-tutorial-2-managing-ntfs-inheritance-and-using-privileges.aspx)
- [GitHub](https://github.com/raandree/NTFSSecurity)
- [PowerShell Gallery](https://www.powershellgallery.com/packages/NTFSSecurity)

### SetUserFTA

- [Homepage](https://kolbi.cz/blog/2017/10/25/setuserfta-userchoice-hash-defeated-set-file-type-associations-per-user/)

## PsExec

- [Homepage](https://docs.microsoft.com/en-us/sysinternals/downloads/psexec)
- Download from above and place PsExec.exe (and PsExec64.exe) in .\Tools\

## ServiceUI
- [Download](https://www.microsoft.com/en-us/download/details.aspx?id=54259)
- Copy ServiceUI.exe from below path after installation
- C:\Program Files\Microsoft Deployment Toolkit\Templates\Distribution\Tools\(x86|x64)\