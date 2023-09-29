# PortableApps.com Packaging for PDF Split and Merge (PDFsam)
A [PortableApps.com](https://portableapps.com/) package bundler for the [PDFsam project](https://pdfsam.org/) ([GitHub](https://github.com/torakiki/pdfsam))

## Packaging Steps
1. Copy icons and icon images to .\App\AppInfo
2. Create a .\Help.html file, with file dependencies under .\Other\Help
3. Copy the app distribution itself to .\App\PDFsam
4. Create the PortableApps.com configuration files
   1. .\App\AppInfo\AppInfo.ini
   2. .\App\AppInfo\Launcher\PDFsamPortable.ini
5. Run the PortableApps.com Launcher to create the portable app launcher
6. Capture desired default configuration from folder Data and copy to App\DefaultData
7. Run the PortableApps.com Installer to create the portable app installer
