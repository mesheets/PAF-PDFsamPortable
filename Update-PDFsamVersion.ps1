
using namespace System.IO

# Parameter declaration
[CmdletBinding()]
param(
   #[Parameter(Mandatory)]
   [string]$sourceOrgName,

   #[Parameter(Mandatory)]
   [string]$sourceProjectName,

   #[Parameter(Mandatory)]
   [string]$releaseArtifactFile,

   [DirectoryInfo]$PortableAppsRoot
)

# Constants
[string]$VERSION_STRING_PLACEHOLDER = "<VERSION>"
[string]$PORTABLE_APPS_INSTALLER_GENERATOR_PATH = "PortableApps\\PortableApps.comInstaller\\PortableApps.comInstaller.exe"
[string]$PORTABLE_APPS_LAUNCHER_GENERATOR_PATH = "PortableApps\\PortableApps.comLauncher\\PortableApps.comLauncherGenerator.exe"

# Variable initialization
$sourceOrgName = "torakiki"
$sourceProjectName = "PDFsam"
[string]$releaseArtifactFile = "pdfsam-$VERSION_STRING_PLACEHOLDER-windows.zip"

[string]$sourceRepo = "$sourceOrgName/$sourceProjectName"

if (! $PortableAppsRoot)
{
   [string]$PAcPlatformProcessName = "PortableAppsPlatform"
   [string]$PAcPlatformRelativeAppPath =  "PortableApps\\PortableApps.com\\PortableAppsPlatform.exe"
   
   # Check for a running instance of the PortableApps.com platform and determine the root path from that
   [string]$PAcPlatformPath = Get-Process $PAcPlatformProcessName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
   
   if ($PAcPlatformPath) {
      echo "Portable apps platform path: $PAcPlatformPath"
      [DirectoryInfo]$PortableAppsRoot = [DirectoryInfo]::new($PAcPlatformPath -replace $PAcPlatformRelativeAppPath)
   }
   else
   {
      echo "No running ""$PAcPlatformProcessName"" processes found"
      exit 1
   }
}
elseif (!$PortableAppsRoot.Exists)
{
   echo "Provided path not found: $PortableAppsRoot"
   exit 1
}
echo "Using PortableApps platform root $PortableAppsRoot"


[FileInfo]$PAcInstallerGeneratorPath = [FileInfo]::new([Path]::Combine($PortableAppsRoot, $PORTABLE_APPS_INSTALLER_GENERATOR_PATH))
[FileInfo]$PAcLauncherGeneratorPath = [FileInfo]::new([Path]::Combine($PortableAppsRoot, $PORTABLE_APPS_LAUNCHER_GENERATOR_PATH))

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
echo "Latest  source  version: $latestSourceVersionTag"

# Update the release artifact file name (if it embeds a version number)
$releaseArtifactFile = $releaseArtifactFile.Replace($VERSION_STRING_PLACEHOLDER, $latestSourceVersion)

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
      
      # If the release file is a standalone executable, skip the extract steps
      if (".exe" -ieq $releaseArtifactFilePath.Extension)
      {
         [FileInfo]$extractedPortableAppPath = $releaseArtifactFilePath
      }
      else
      {
         # Extract the contents of the release archive
         [DirectoryInfo]$extractDirectory = [Path]::Combine($tempDirectory, "$sourceOrgName-$latestSourceVersion")
         Expand-Archive -LiteralPath "$releaseArtifactFilePath" -DestinationPath "$extractDirectory"

         # Prepare for generating the new package
         echo "Prepare the new app version for packaging as a portable"
         [string]$releaseArtifactName = [Path]::GetFileNameWithoutExtension($releaseArtifactFile)
         
         # Get the main content of the portable app
         [DirectoryInfo]$extractedPortableAppPath = [Path]::Combine($extractDirectory, $releaseArtifactName, $sourceProjectName)
      }
      
      # Move to the packaging location the file or folder of the app that is to be packaged as a portable app
      Move-Item -LiteralPath $extractedPortableAppPath -Destination $appPackagingFolder

      # Update the AppInfo INI file
      echo "Update the config file for the portable app generator"
      $appInfoContent = Get-IniContent $appInfoFile
      $appInfoContent["Version"]["PackageVersion"] = $latestSourceVersionFull.ToString()
      $appInfoContent["Version"]["DisplayVersion"] = "$latestSourceVersion Release 1"
      $appInfoContent | Out-IniFile -FilePath $appInfoFile -Force -Pretty

      # Run the PortableApp.com packaging
      echo "Run the PortableApps.com Launcher Generator"
      Start-Process "$PAcLauncherGeneratorPath" -ArgumentList "$PSScriptRoot" -Wait
      echo "Run the PortableApps.com Installer Generator"
      Start-Process "$PAcInstallerGeneratorPath" -ArgumentList "$PSScriptRoot" -Wait
      [FileInfo]$pafAppInstaller = [Path]::Combine(([DirectoryInfo]::new($PSScriptRoot)).Parent, $appInfoContent["Details"]["AppID"] + "_" + $appInfoContent["Version"]["DisplayVersion"].Replace(' ', '_') + ".paf.exe")

      # Commit and push the updated AppInfo.ini file
      echo "Commit and push the updates for $releaseName"
      git commit -m "Updates for $releaseName" "$appInfoFile"
      git push

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
