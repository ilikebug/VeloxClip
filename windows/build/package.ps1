[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string]$Version = '0.1.0',
    [string]$OutDir = "$PSScriptRoot/../dist"
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path "$PSScriptRoot/.."
Set-Location $repoRoot

Write-Host "==> Restore" -ForegroundColor Cyan
dotnet restore VeloxClip.Windows.sln

Write-Host "==> Build" -ForegroundColor Cyan
dotnet build VeloxClip.Windows.sln -c $Configuration --nologo

Write-Host "==> Test" -ForegroundColor Cyan
dotnet test tests/VeloxClip.Core.Tests -c $Configuration --no-build --nologo

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$msixPublishDir  = "$repoRoot/src/VeloxClip.App/bin/$Configuration/net8.0-windows10.0.22621.0/win-x64/MsixPublish"
$portablePublishDir = "$repoRoot/src/VeloxClip.App/bin/$Configuration/net8.0-windows10.0.22621.0/win-x64/PortablePublish"

Write-Host "==> Publish MSIX (unsigned)" -ForegroundColor Cyan
dotnet publish src/VeloxClip.App `
    -c $Configuration `
    -p:Platform=x64 `
    -p:WindowsPackageType=MSIX `
    -p:GenerateAppxPackageOnBuild=true `
    -p:AppxPackageDir="$msixPublishDir/" `
    -p:AppxPackageSigningEnabled=false `
    -p:UapAppxPackageBuildMode=SideloadOnly

$msix = Get-ChildItem -Path $msixPublishDir -Filter *.msix -Recurse | Select-Object -First 1
if (-not $msix) { throw "MSIX not produced under $msixPublishDir" }
Copy-Item $msix.FullName -Destination "$OutDir/VeloxClip-$Version-x64.msix"

Write-Host "==> Publish portable" -ForegroundColor Cyan
dotnet publish src/VeloxClip.App `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:WindowsPackageType=None `
    -p:PublishSingleFile=false `
    -p:PublishReadyToRun=false `
    -p:WindowsAppSDKSelfContained=true `
    -o $portablePublishDir

Compress-Archive -Path "$portablePublishDir/*" `
    -DestinationPath "$OutDir/VeloxClip-$Version-x64-portable.zip" -Force

Write-Host "==> Done. Artifacts:" -ForegroundColor Green
Get-ChildItem $OutDir | Format-Table Name, Length
