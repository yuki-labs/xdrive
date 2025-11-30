# Build and Package Instructions

## For Development

### Build
```powershell
flutter build windows
```

### Run from source
```powershell
flutter run -d windows
```

## For Distribution

### Create self-contained package
```powershell
.\package.ps1
```

This creates `dist\SpacedriveClone\` with everything needed to run the app.

### Distribute
1. Zip the `dist\SpacedriveClone` folder
2. Share the zip file
3. Users extract and run `SpacedriveClone.exe`

No Flutter SDK or other dependencies required on user machines!

## Package Contents
- `SpacedriveClone.exe` - Main executable
- `flutter_windows.dll` - Flutter engine
- `nsd_windows_plugin.dll` - Network discovery
- `permission_handler_windows_plugin.dll` - Permissions
- `window_manager_plugin.dll` - Window management  
- `data/` - App resources (icons, fonts, etc.)

Keep all files together in the same folder.
