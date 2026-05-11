# VeloxClip — Windows

The Windows 11 port of [VeloxClip](../README.md). Functional parity with the macOS app, native Fluent / WinUI 3 visuals.

## Status

P0 (scaffolding) — see `docs/superpowers/specs/2026-05-08-windows-port-p0-scaffold-design.md`.

## Requirements

- Windows 11 22H2 (x64) for runtime
- Visual Studio 2022 17.10+ with "Windows application development" workload, **or** the .NET 8 SDK (8.0.x) on the command line
- Windows App SDK 1.6 runtime (installer ships with MSIX; for unpackaged dev VS handles it)

## Build

```pwsh
cd windows
dotnet restore VeloxClip.Windows.sln
dotnet build VeloxClip.Windows.sln -c Release
```

## Run (F5 equivalent)

```pwsh
dotnet run --project src/VeloxClip.App -c Debug
```

The first launch opens the placeholder main window and registers a tray icon. Closing the window hides it but keeps the tray alive. Right-click tray → **Quit** to exit.

## Test

```pwsh
dotnet test tests/VeloxClip.Core.Tests
```

`VeloxClip.Core` is pure .NET and also tests cleanly on macOS/Linux.

## Local packaging

```pwsh
pwsh build/package.ps1
```

Produces `windows/dist/VeloxClip-<version>-x64.msix` and `windows/dist/VeloxClip-<version>-x64-portable.zip`.

## CI

`.github/workflows/build-windows.yml` runs on push to `main`, PRs, and version tags. Tags additionally upload MSIX + portable zip to the matching GitHub Release.
