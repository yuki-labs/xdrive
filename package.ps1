# Package Flutter Windows app for distribution
# This script creates a self-contained distribution folder

Write-Host "Packaging Spacedrive Clone for Windows..." -ForegroundColor Green

# Define paths
$buildPath = "build\windows\x64\runner\Release"
$outputPath = "dist\SpacedriveClone"

# Clean previous dist
if (Test-Path "dist") {
    Remove-Item -Recurse -Force "dist"
}

# Create output directory
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

# Copy executable
Copy-Item "$buildPath\spacedrive_attempt.exe" "$outputPath\SpacedriveClone.exe"

# Copy all DLL files
Get-ChildItem "$buildPath\*.dll" | ForEach-Object {
    Copy-Item $_.FullName $outputPath
}

# Copy data folder
if (Test-Path "$buildPath\data") {
    Copy-Item -Recurse "$buildPath\data" $outputPath
}

Write-Host "`nPackaging complete!" -ForegroundColor Green
Write-Host "Output location: $outputPath" -ForegroundColor Cyan
Write-Host "`nContents:" -ForegroundColor Yellow
Get-ChildItem $outputPath -Recurse | Select-Object FullName

Write-Host "`nYou can now distribute the entire '$outputPath' folder." -ForegroundColor Green
Write-Host "Users should run SpacedriveClone.exe from this folder." -ForegroundColor Green
