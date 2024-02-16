
using namespace System.IO

[DriveInfo]$portableDrive = [DriveInfo]::new("E:")
[FileInfo]$PAcInstallerGeneratorPath = [FileInfo]::new("$portableDrive\\PortableApps\\PortableApps.comInstaller\\PortableApps.comInstaller.exe")
[FileInfo]$PAcLauncherGeneratorPath = [FileInfo]::new("$portableDrive\\PortableApps\\PortableApps.comLauncher\\PortableApps.comLauncherGenerator.exe")

[string]$sourceOwnerName = "torakiki"
[string]$sourceProjectName = "PDFsam"
[string]$sourceRepo = "$sourceOwnerName/$sourceProjectName"

[DirectoryInfo]$appPackagingFolder = [DirectoryInfo]::new([Path]::Combine($PSScriptRoot, "App", $sourceProjectName))
[FileInfo]$appInfoFile = [FileInfo]::new([Path]::Combine($PSScriptRoot, "App", "AppInfo", "AppInfo.ini"))


# Import the PsIni module, installing if necessary
# To avoid the need for administrative permissions, installation is for the current user
$ErrorActionPreference = 'Stop'
try {
  Import-Module PsIni
} catch {
  Install-Module -Scope CurrentUser PsIni
  Import-Module PsIni
}

# Determine the latest release tag and version number
[string]$latestVersionTag = gh release view --repo "$sourceRepo" --json tagName --jq ".tagName" 2> $null
[Version]$latestVersion = [Version]::new($latestVersionTag -replace 'v')
[Version]$latestVersionFull = [Version]::new($latestVersion.Major, $latestVersion.Minor, $latestVersion.Build -ge 0 ? $latestVersion.Build : 0, $latestVersion.Revision -ge 0 ? $latestVersion.Revision : 0)
[string]$releaseArtifactName = "pdfsam-$latestVersion-windows"
[string]$releaseArtifactFile = "$releaseArtifactName.zip"


# Download into a temporary folder the portable version of the latest release
[DirectoryInfo]$tempDirectory = [Directory]::CreateTempSubdirectory(".gh-")
gh release download --repo "$sourceRepo" --pattern "$releaseArtifactFile" --dir "$tempDirectory"
[FileInfo]$releaseArtifactFilePath = [Path]::Combine($tempDirectory, $releaseArtifactFile)
Expand-Archive -LiteralPath "$releaseArtifactFilePath" -DestinationPath "$tempDirectory"

# Prepare for generating the new package
if ([Directory]::Exists($appPackagingFolder))
{
   [Directory]::Delete($appPackagingFolder, $true)
}
[DirectoryInfo]$extractedPortableAppPath = [Path]::Combine($tempDirectory, $releaseArtifactName, $sourceProjectName)
Move-Item -LiteralPath $extractedPortableAppPath -Destination $appPackagingFolder

# Update the AppInfo INI file
$appInfoContent = Get-IniContent $appInfoFile
$appInfoContent["Version"]["PackageVersion"] = $latestVersionFull.ToString()
$appInfoContent["Version"]["DisplayVersion"] = "$latestVersionFull Release 1"
$appInfoContent | Out-IniFile -FilePath $appInfoFile -Force -Pretty

# Run the PortableApp.com packaging
Start-Process "$PAcLauncherGeneratorPath" -ArgumentList "$PSScriptRoot" -Wait
Start-Process "$PAcInstallerGeneratorPath" -ArgumentList "$PSScriptRoot" -Wait
[FileInfo]$pafAppInstaller = [Path]::Combine(([DirectoryInfo]::new($PSScriptRoot)).Parent, $appInfoContent["Details"]["AppID"] + "_" + $appInfoContent["Version"]["DisplayVersion"].Replace(' ', '_') + ".paf.exe")

# Publish the release and check in the updated files
[string]$releaseName = "{0} {1}" -f $appInfoContent["Details"]["AppID"], $appInfoContent["Version"]["DisplayVersion"]
gh release create "$latestVersionTag" "$pafAppInstaller" --title $releaseName --notes $releaseName

# Cleanup
[Directory]::Delete($appPackagingFolder, $true)
[Directory]::Delete($tempDirectory, $true)
