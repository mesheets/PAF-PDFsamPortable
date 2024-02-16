
using namespace System.IO

param([DriveInfo]$PortableDrive = "E:")
echo "Using portable drive $PortableDrive"


#[DriveInfo]$portableDrive = [DriveInfo]::new("E:")
[FileInfo]$PAcInstallerGeneratorPath = [FileInfo]::new("$PortableDrive\\PortableApps\\PortableApps.comInstaller\\PortableApps.comInstaller.exe")
[FileInfo]$PAcLauncherGeneratorPath = [FileInfo]::new("$PortableDrive\\PortableApps\\PortableApps.comLauncher\\PortableApps.comLauncherGenerator.exe")

[string]$sourceOwnerName = "torakiki"
[string]$sourceProjectName = "PDFsam"
[string]$sourceRepo = "$sourceOwnerName/$sourceProjectName"

[DirectoryInfo]$appPackagingFolder = [DirectoryInfo]::new([Path]::Combine($PSScriptRoot, "App", $sourceProjectName))
[FileInfo]$appInfoFile = [FileInfo]::new([Path]::Combine($PSScriptRoot, "App", "AppInfo", "AppInfo.ini"))


# Import the PsIni module, installing if necessary
# To avoid the need for administrative permissions, installation is for the current user
$ErrorActionPreference = 'Stop'
try
{
   Import-Module PsIni
} catch {
   Install-Module -Scope CurrentUser PsIni
   Import-Module PsIni
}

# Determine the latest portable release tag version
[string]$latestPortableVersionTag = gh release view --json tagName --jq ".tagName" 2> $null
echo "Latest portable version: $latestPortableVersionTag"

# Determine the latest source release tag and version number
[string]$latestSourceVersionTag = gh release view --repo "$sourceRepo" --json tagName --jq ".tagName" 2> $null
[Version]$latestSourceVersion = [Version]::new($latestSourceVersionTag -replace 'v')
[Version]$latestSourceVersionFull = [Version]::new($latestSourceVersion.Major, $latestSourceVersion.Minor, $latestSourceVersion.Build -ge 0 ? $latestSourceVersion.Build : 0, $latestSourceVersion.Revision -ge 0 ? $latestSourceVersion.Revision : 0)
[string]$releaseArtifactName = "pdfsam-$latestSourceVersion-windows"
[string]$releaseArtifactFile = "$releaseArtifactName.zip"
echo "Latest  source  version: $latestSourceVersionTag"

if ($latestPortableVersionTag -eq $latestSourceVersionTag)
{
   echo "The latest source and portable versions are the same; skipping update."
}
else
{
   try
   {
      # Clear any non-version control files and force-sync the repository
      echo "Cleaning up and syncing local repository"
      if ([Directory]::Exists($appPackagingFolder))
      {
         [Directory]::Delete($appPackagingFolder, $true)
      }
      # If there are uncommitted local changes, sync will not run (but it also will not block further execution),
      # so there should not be an issue with losing work in progress that has not yet been committed (e.g. during testing).
      gh repo sync --force
      
      # Download into a temporary folder the portable version of the latest release
      echo "Downloading and extracting latest release"
      [DirectoryInfo]$tempDirectory = [Directory]::CreateTempSubdirectory(".gh-")
      gh release download --repo "$sourceRepo" --pattern "$releaseArtifactFile" --dir "$tempDirectory"
      [FileInfo]$releaseArtifactFilePath = [Path]::Combine($tempDirectory, $releaseArtifactFile)
      Expand-Archive -LiteralPath "$releaseArtifactFilePath" -DestinationPath "$tempDirectory"

      # Prepare for generating the new package
      echo "Prepare the new app version for packaging as a portable"
      [DirectoryInfo]$extractedPortableAppPath = [Path]::Combine($tempDirectory, $releaseArtifactName, $sourceProjectName)
      Move-Item -LiteralPath $extractedPortableAppPath -Destination $appPackagingFolder

      # Update the AppInfo INI file
      echo "Update the config file for the portable app generator"
      $appInfoContent = Get-IniContent $appInfoFile
      $appInfoContent["Version"]["PackageVersion"] = $latestSourceVersionFull.ToString()
      $appInfoContent["Version"]["DisplayVersion"] = "$latestSourceVersionFull Release 1"
      $appInfoContent | Out-IniFile -FilePath $appInfoFile -Force -Pretty

      # Run the PortableApp.com packaging
      echo "Run the PortableApps.com Launcher Generator"
      Start-Process "$PAcLauncherGeneratorPath" -ArgumentList "$PSScriptRoot" -Wait
      echo "Run the PortableApps.com Installer Generator"
      Start-Process "$PAcInstallerGeneratorPath" -ArgumentList "$PSScriptRoot" -Wait
      [FileInfo]$pafAppInstaller = [Path]::Combine(([DirectoryInfo]::new($PSScriptRoot)).Parent, $appInfoContent["Details"]["AppID"] + "_" + $appInfoContent["Version"]["DisplayVersion"].Replace(' ', '_') + ".paf.exe")

      # Publish the release and check in the updated files
      echo "Publish the new portable app release"
      [string]$releaseName = "{0} {1}" -f $appInfoContent["Details"]["Name"], $appInfoContent["Version"]["DisplayVersion"]
      gh release create "$latestSourceVersionTag" "$pafAppInstaller" --title $releaseName --notes $releaseName
   }
   catch
   {
      echo "Error creating portable release"
   }
   finally
   {
      # Cleanup
      echo "Cleanup temporary files"
      [Directory]::Delete($appPackagingFolder, $true)
      [Directory]::Delete($tempDirectory, $true)
   }
}
