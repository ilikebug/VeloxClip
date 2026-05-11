# VeloxClip Windows Port — P0 Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the minimum buildable, runnable, releasable Windows-side skeleton for VeloxClip — solution, three projects, DI/hosting/logging, single-instance, tray icon, empty main window, LocalAppData scaffold, and a GitHub Actions workflow that ships MSIX + portable zip on tags. No clipboard, AI, or business logic.

**Architecture:** Three .NET 8 projects under `windows/` enforce a one-way dependency arrow: `App` (WinUI 3 host, XAML, DI composition) → `Platform` (Win32 / WinRT system glue) → `Core` (pure .NET business logic and interfaces). `Core` has zero Windows references and is unit-testable cross-platform. `App` uses Microsoft.Extensions.Hosting for DI and `H.NotifyIcon.WinUI` for the tray. Single-instance uses Windows App SDK's `AppInstance`. CI on `windows-2022` produces unsigned MSIX via `dotnet publish -p:WindowsPackageType=MSIX` and a portable zip via unpackaged publish.

**Tech Stack:** C# 12, .NET 8, Windows App SDK 1.6 + WinUI 3, `net8.0-windows10.0.22621.0`, CommunityToolkit.Mvvm 8.3, Serilog 4 + Microsoft.Extensions.Hosting 8, H.NotifyIcon.WinUI 2.1, xUnit + FluentAssertions. Min runtime Windows 11 22H2 x64.

**Execution environment note:** `VeloxClip.Core` and its tests build and run on macOS/Linux via `dotnet test` — TDD steps for Core tasks are verified locally. `VeloxClip.Platform` and `VeloxClip.App` require Windows (or the GitHub Actions Windows runner) to build because they depend on WinUI 3 and the Windows SDK projection. Tasks that touch those projects rely on **CI** as the source of truth for "did it build" and on a **Windows machine smoke test** for runtime behavior. Each such task spells out the verification path explicitly.

---

## File Map

Files created or modified, grouped by responsibility:

**Repo-root config**
- `.gitignore` — append .NET / Visual Studio / MSIX patterns
- `README.md` — add Windows section pointer
- `CHANGELOG.md` — add "Windows port — P0 scaffold" entry

**`windows/` build infrastructure**
- `windows/.editorconfig` — C# style + nullable rules
- `windows/Directory.Build.props` — repo-wide MSBuild defaults (LangVersion, Nullable, TreatWarningsAsErrors)
- `windows/Directory.Packages.props` — Central Package Management (CPM), all NuGet versions live here
- `windows/global.json` — pin .NET SDK to 8.x
- `windows/NuGet.config` — explicit nuget.org source
- `windows/VeloxClip.Windows.sln` — solution containing all four projects
- `windows/README.md` — dev environment, build, run, package, CI overview
- `windows/build/package.ps1` — local one-shot script: build → test → publish MSIX → publish portable zip
- `windows/build/icons/app.ico` — multi-resolution icon (binary, generated from existing macOS icon)

**`VeloxClip.Core` (pure .NET 8, cross-platform)**
- `windows/src/VeloxClip.Core/VeloxClip.Core.csproj`
- `windows/src/VeloxClip.Core/AssemblyInfo.cs` — `InternalsVisibleTo("VeloxClip.Core.Tests")`
- `windows/src/VeloxClip.Core/Environment/IAppPaths.cs` — interface returning user-data directories
- `windows/src/VeloxClip.Core/Environment/AppPaths.cs` — default implementation rooted at `%LOCALAPPDATA%\VeloxClip\`
- `windows/src/VeloxClip.Core/Environment/AppEnvironmentBootstrapper.cs` — idempotent directory + settings.json creation

**`VeloxClip.Core.Tests`**
- `windows/tests/VeloxClip.Core.Tests/VeloxClip.Core.Tests.csproj`
- `windows/tests/VeloxClip.Core.Tests/Environment/AppPathsTests.cs`
- `windows/tests/VeloxClip.Core.Tests/Environment/AppEnvironmentBootstrapperTests.cs`

**`VeloxClip.Platform` (Windows-only, P0 stub)**
- `windows/src/VeloxClip.Platform/VeloxClip.Platform.csproj`
- `windows/src/VeloxClip.Platform/PlatformServiceCollectionExtensions.cs` — DI registration entry point (empty body in P0, populated in P1+)

**`VeloxClip.App` (WinUI 3 entry point, Windows-only)**
- `windows/src/VeloxClip.App/VeloxClip.App.csproj`
- `windows/src/VeloxClip.App/Package.appxmanifest` — MSIX manifest
- `windows/src/VeloxClip.App/app.manifest` — Win32 app manifest (DPI awareness, supportedOS)
- `windows/src/VeloxClip.App/Properties/launchSettings.json` — F5 launch profile
- `windows/src/VeloxClip.App/Assets/StoreLogo.png`, `Square150x150Logo.png`, `Square44x44Logo.png`, `Wide310x150Logo.png`, `SplashScreen.png` — MSIX-required asset placeholders
- `windows/src/VeloxClip.App/App.xaml` + `App.xaml.cs` — DI bootstrap, lifecycle, single-instance, tray host
- `windows/src/VeloxClip.App/MainWindow.xaml` + `MainWindow.xaml.cs` — placeholder window with "VeloxClip — coming soon" text and close-to-hide behavior
- `windows/src/VeloxClip.App/Hosting/HostBuilderExtensions.cs` — wraps `Host.CreateApplicationBuilder` with Serilog + config + DI registration
- `windows/src/VeloxClip.App/SingleInstance/SingleInstanceController.cs` — `AppInstance` wrapper
- `windows/src/VeloxClip.App/Tray/TrayIconHost.cs` — code-behind for tray icon and menu

**CI**
- `.github/workflows/build-windows.yml` — restore/build/test, MSIX publish, portable zip, tag-conditional upload to GitHub Release

---

## Task 1: Repository skeleton, .gitignore, MSBuild defaults

**Files:**
- Create: `windows/.editorconfig`
- Create: `windows/Directory.Build.props`
- Create: `windows/Directory.Packages.props`
- Create: `windows/global.json`
- Create: `windows/NuGet.config`
- Create: `windows/README.md`
- Modify: `.gitignore` (append a Windows-tools section at end of file)

This task lays down the static repo-level scaffolding. No code yet — pure config. Verifiable on macOS by inspecting files and running `dotnet --version` against the pinned SDK.

- [ ] **Step 1: Append a Windows / .NET ignore section to the root `.gitignore`**

Append exactly the following to the bottom of `.gitignore` (do not modify lines above):

```gitignore

# .NET / Visual Studio (Windows port)
windows/**/bin/
windows/**/obj/
windows/**/.vs/
windows/**/*.user
windows/**/*.suo
windows/**/TestResults/
windows/**/Generated Files/
windows/**/AppPackages/
windows/**/BundleArtifacts/
windows/**/*.appx
windows/**/*.appxbundle
windows/**/*.msix
windows/**/*.msixbundle
windows/**/PublishProfiles/local/
```

- [ ] **Step 2: Create `windows/global.json` to pin the .NET SDK**

```json
{
  "sdk": {
    "version": "8.0.0",
    "rollForward": "latestFeature",
    "allowPrerelease": false
  }
}
```

- [ ] **Step 3: Create `windows/NuGet.config` with an explicit nuget.org source**

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
  </packageSources>
</configuration>
```

- [ ] **Step 4: Create `windows/Directory.Build.props`**

```xml
<Project>
  <PropertyGroup>
    <LangVersion>12.0</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <WarningsNotAsErrors>NU1903</WarningsNotAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <AnalysisLevel>latest-recommended</AnalysisLevel>
    <NeutralLanguage>en-US</NeutralLanguage>
    <Company>VeloxClip</Company>
    <Authors>VeloxClip Contributors</Authors>
    <Product>VeloxClip</Product>
    <Copyright>Copyright (c) VeloxClip Contributors</Copyright>
    <Version>0.1.0</Version>
  </PropertyGroup>
</Project>
```

- [ ] **Step 5: Create `windows/Directory.Packages.props` (Central Package Management)**

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Microsoft.WindowsAppSDK" Version="1.6.241114003" />
    <PackageVersion Include="Microsoft.Windows.SDK.BuildTools" Version="10.0.22621.756" />
    <PackageVersion Include="H.NotifyIcon.WinUI" Version="2.1.4" />
    <PackageVersion Include="CommunityToolkit.Mvvm" Version="8.3.2" />
    <PackageVersion Include="Microsoft.Extensions.Hosting" Version="8.0.1" />
    <PackageVersion Include="Microsoft.Extensions.Configuration.Json" Version="8.0.1" />
    <PackageVersion Include="Microsoft.Extensions.Logging" Version="8.0.1" />
    <PackageVersion Include="Serilog" Version="4.0.2" />
    <PackageVersion Include="Serilog.Extensions.Hosting" Version="8.0.0" />
    <PackageVersion Include="Serilog.Settings.Configuration" Version="8.0.4" />
    <PackageVersion Include="Serilog.Sinks.File" Version="6.0.0" />
    <PackageVersion Include="Serilog.Sinks.Debug" Version="3.0.0" />
    <PackageVersion Include="xunit" Version="2.9.2" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="2.8.2" />
    <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageVersion Include="FluentAssertions" Version="6.12.1" />
    <PackageVersion Include="coverlet.collector" Version="6.0.2" />
  </ItemGroup>
</Project>
```

- [ ] **Step 6: Create `windows/.editorconfig`**

```ini
root = false

[*.{cs,xaml}]
indent_style = space
indent_size = 4
end_of_line = crlf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.cs]
dotnet_diagnostic.IDE0008.severity = none
dotnet_diagnostic.CA1062.severity = warning
csharp_style_namespace_declarations = file_scoped:warning
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_expression_bodied_methods = when_on_single_line:suggestion

[*.{json,yml,yaml,ps1}]
indent_size = 2
end_of_line = lf
```

- [ ] **Step 7: Create `windows/README.md`**

```markdown
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
```

- [ ] **Step 8: Verify the SDK pin resolves on the dev machine**

Run: `cd windows && dotnet --version`
Expected: `8.0.x` (any 8.0 feature band — `latestFeature` rollForward accepts that)
If a message like "A compatible installed .NET SDK for global.json version [8.0.0] was not found" appears, install .NET 8 SDK before proceeding.

- [ ] **Step 9: Commit**

```bash
git add .gitignore windows/.editorconfig windows/Directory.Build.props windows/Directory.Packages.props windows/global.json windows/NuGet.config windows/README.md
git commit -m "build(windows): scaffold MSBuild + CPM + global.json for Windows port"
```

---

## Task 2: VeloxClip.Core project + solution + sanity test (TDD start, runs on macOS)

**Files:**
- Create: `windows/VeloxClip.Windows.sln`
- Create: `windows/src/VeloxClip.Core/VeloxClip.Core.csproj`
- Create: `windows/src/VeloxClip.Core/AssemblyInfo.cs`
- Create: `windows/tests/VeloxClip.Core.Tests/VeloxClip.Core.Tests.csproj`
- Create: `windows/tests/VeloxClip.Core.Tests/SanityTests.cs`

The first project in the solution must be `VeloxClip.Core` so we can prove `dotnet build` / `dotnet test` work end-to-end cross-platform before adding any Windows-only project that won't build on macOS.

- [ ] **Step 1: Create the empty solution and add both projects (slnx? no — classic sln for VS 2022 compatibility)**

```bash
cd windows
dotnet new sln --name VeloxClip.Windows
mkdir -p src/VeloxClip.Core tests/VeloxClip.Core.Tests
```

- [ ] **Step 2: Create `windows/src/VeloxClip.Core/VeloxClip.Core.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <RootNamespace>VeloxClip.Core</RootNamespace>
    <AssemblyName>VeloxClip.Core</AssemblyName>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
    <NoWarn>$(NoWarn);CS1591</NoWarn>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="CommunityToolkit.Mvvm" />
    <PackageReference Include="Microsoft.Extensions.Logging" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Create `windows/src/VeloxClip.Core/AssemblyInfo.cs`**

```csharp
using System.Runtime.CompilerServices;

[assembly: InternalsVisibleTo("VeloxClip.Core.Tests")]
```

- [ ] **Step 4: Create `windows/tests/VeloxClip.Core.Tests/VeloxClip.Core.Tests.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <RootNamespace>VeloxClip.Core.Tests</RootNamespace>
    <AssemblyName>VeloxClip.Core.Tests</AssemblyName>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="coverlet.collector" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\VeloxClip.Core\VeloxClip.Core.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 5: Write the failing sanity test**

Create `windows/tests/VeloxClip.Core.Tests/SanityTests.cs`:

```csharp
using FluentAssertions;
using Xunit;

namespace VeloxClip.Core.Tests;

public class SanityTests
{
    [Fact]
    public void Toolchain_IsAlive()
    {
        // Proves: csproj resolves, xUnit discovers, FluentAssertions linked,
        // CPM pins resolved, project reference to Core works.
        (1 + 1).Should().Be(2);
    }
}
```

- [ ] **Step 6: Add both projects to the solution**

```bash
cd windows
dotnet sln VeloxClip.Windows.sln add src/VeloxClip.Core/VeloxClip.Core.csproj
dotnet sln VeloxClip.Windows.sln add tests/VeloxClip.Core.Tests/VeloxClip.Core.Tests.csproj
```

- [ ] **Step 7: Restore + run the sanity test**

```bash
cd windows
dotnet restore VeloxClip.Windows.sln
dotnet test tests/VeloxClip.Core.Tests -c Debug --nologo
```

Expected: `Passed!  - Failed: 0, Passed: 1, Skipped: 0, Total: 1`.

If restore fails with "no compatible SDK", recheck `global.json`. If CPM complains "Project cannot specify a version", verify no `Version=` attribute slipped into a `PackageReference` in either csproj.

- [ ] **Step 8: Commit**

```bash
git add windows/VeloxClip.Windows.sln windows/src/VeloxClip.Core windows/tests/VeloxClip.Core.Tests
git commit -m "feat(windows/core): add VeloxClip.Core project + xUnit sanity test"
```

---

## Task 3: `IAppPaths` — typed user-data path provider (TDD)

**Files:**
- Create: `windows/src/VeloxClip.Core/Environment/IAppPaths.cs`
- Create: `windows/src/VeloxClip.Core/Environment/AppPaths.cs`
- Create: `windows/tests/VeloxClip.Core.Tests/Environment/AppPathsTests.cs`

`AppPaths` centralises every disk location the app touches. Other layers depend on the interface, never on raw `Environment.SpecialFolder.LocalApplicationData` calls — this is what lets tests redirect to a temp dir and what will let P7 settings UI expose paths.

- [ ] **Step 1: Write failing tests**

Create `windows/tests/VeloxClip.Core.Tests/Environment/AppPathsTests.cs`:

```csharp
using System.IO;
using FluentAssertions;
using VeloxClip.Core.Environment;
using Xunit;

namespace VeloxClip.Core.Tests.Environment;

public class AppPathsTests
{
    [Fact]
    public void Root_IsBuiltFromGivenBaseDirectory()
    {
        var paths = new AppPaths(baseDirectory: @"C:\Base");

        paths.Root.Should().Be(@"C:\Base\VeloxClip");
    }

    [Fact]
    public void Subdirectories_AreRootedUnderRoot()
    {
        var paths = new AppPaths(baseDirectory: @"C:\Base");

        paths.Database.Should().Be(Path.Combine(paths.Root, "db"));
        paths.Cache.Should().Be(Path.Combine(paths.Root, "cache"));
        paths.Logs.Should().Be(Path.Combine(paths.Root, "logs"));
        paths.SettingsFile.Should().Be(Path.Combine(paths.Root, "settings.json"));
    }

    [Fact]
    public void Default_UsesLocalApplicationData()
    {
        var expectedBase = System.Environment.GetFolderPath(
            System.Environment.SpecialFolder.LocalApplicationData);

        var paths = AppPaths.Default;

        paths.Root.Should().Be(Path.Combine(expectedBase, "VeloxClip"));
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

```bash
cd windows
dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: build fails — `AppPaths` and `IAppPaths` don't exist yet.

- [ ] **Step 3: Create the interface `windows/src/VeloxClip.Core/Environment/IAppPaths.cs`**

```csharp
namespace VeloxClip.Core.Environment;

/// <summary>
/// Resolves the on-disk locations VeloxClip uses for state, cache, and logs.
/// Depend on this interface so tests and future platforms can substitute roots.
/// </summary>
public interface IAppPaths
{
    /// <summary>Root directory containing all subdirectories.</summary>
    string Root { get; }

    /// <summary>Directory holding the SQLite database (P1+).</summary>
    string Database { get; }

    /// <summary>Directory for caches (LLM responses, thumbnails, etc.).</summary>
    string Cache { get; }

    /// <summary>Directory for rolling log files.</summary>
    string Logs { get; }

    /// <summary>Absolute path to the user's settings.json.</summary>
    string SettingsFile { get; }
}
```

- [ ] **Step 4: Create the implementation `windows/src/VeloxClip.Core/Environment/AppPaths.cs`**

```csharp
using System.IO;

namespace VeloxClip.Core.Environment;

/// <summary>
/// Default <see cref="IAppPaths"/> implementation rooted at
/// <c>{baseDirectory}/VeloxClip</c>. <see cref="Default"/> uses
/// <see cref="System.Environment.SpecialFolder.LocalApplicationData"/>.
/// </summary>
public sealed class AppPaths : IAppPaths
{
    private const string AppFolderName = "VeloxClip";

    public AppPaths(string baseDirectory)
    {
        if (string.IsNullOrWhiteSpace(baseDirectory))
        {
            throw new System.ArgumentException(
                "Base directory must be non-empty.", nameof(baseDirectory));
        }

        Root = Path.Combine(baseDirectory, AppFolderName);
        Database = Path.Combine(Root, "db");
        Cache = Path.Combine(Root, "cache");
        Logs = Path.Combine(Root, "logs");
        SettingsFile = Path.Combine(Root, "settings.json");
    }

    public string Root { get; }
    public string Database { get; }
    public string Cache { get; }
    public string Logs { get; }
    public string SettingsFile { get; }

    /// <summary>Default instance rooted at <c>%LOCALAPPDATA%\VeloxClip</c>.</summary>
    public static AppPaths Default { get; } = new AppPaths(
        System.Environment.GetFolderPath(
            System.Environment.SpecialFolder.LocalApplicationData));
}
```

- [ ] **Step 5: Run tests, expect pass**

```bash
cd windows
dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: `Passed: 4, Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add windows/src/VeloxClip.Core/Environment windows/tests/VeloxClip.Core.Tests/Environment
git commit -m "feat(windows/core): add IAppPaths + AppPaths default resolver"
```

---

## Task 4: `AppEnvironmentBootstrapper` — idempotent disk scaffold (TDD)

**Files:**
- Create: `windows/src/VeloxClip.Core/Environment/AppEnvironmentBootstrapper.cs`
- Create: `windows/tests/VeloxClip.Core.Tests/Environment/AppEnvironmentBootstrapperTests.cs`

On every launch the App layer calls `AppEnvironmentBootstrapper.Ensure(paths)`. It creates `db/`, `cache/`, `logs/`, and writes an empty `settings.json` if absent. Safe to call repeatedly.

- [ ] **Step 1: Write failing tests**

Create `windows/tests/VeloxClip.Core.Tests/Environment/AppEnvironmentBootstrapperTests.cs`:

```csharp
using System;
using System.IO;
using FluentAssertions;
using VeloxClip.Core.Environment;
using Xunit;

namespace VeloxClip.Core.Tests.Environment;

public class AppEnvironmentBootstrapperTests : IDisposable
{
    private readonly string _tempBase;
    private readonly AppPaths _paths;

    public AppEnvironmentBootstrapperTests()
    {
        _tempBase = Path.Combine(Path.GetTempPath(),
            "veloxclip-test-" + Path.GetRandomFileName());
        Directory.CreateDirectory(_tempBase);
        _paths = new AppPaths(_tempBase);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempBase))
        {
            Directory.Delete(_tempBase, recursive: true);
        }
    }

    [Fact]
    public void Ensure_CreatesAllSubdirectories()
    {
        AppEnvironmentBootstrapper.Ensure(_paths);

        Directory.Exists(_paths.Root).Should().BeTrue();
        Directory.Exists(_paths.Database).Should().BeTrue();
        Directory.Exists(_paths.Cache).Should().BeTrue();
        Directory.Exists(_paths.Logs).Should().BeTrue();
    }

    [Fact]
    public void Ensure_WritesEmptyJsonObjectWhenSettingsAbsent()
    {
        AppEnvironmentBootstrapper.Ensure(_paths);

        File.Exists(_paths.SettingsFile).Should().BeTrue();
        File.ReadAllText(_paths.SettingsFile).Trim().Should().Be("{}");
    }

    [Fact]
    public void Ensure_PreservesExistingSettingsContent()
    {
        Directory.CreateDirectory(_paths.Root);
        const string existing = "{\"foo\":\"bar\"}";
        File.WriteAllText(_paths.SettingsFile, existing);

        AppEnvironmentBootstrapper.Ensure(_paths);

        File.ReadAllText(_paths.SettingsFile).Should().Be(existing);
    }

    [Fact]
    public void Ensure_IsIdempotent()
    {
        AppEnvironmentBootstrapper.Ensure(_paths);
        var firstWrite = File.GetLastWriteTimeUtc(_paths.SettingsFile);

        // Second call should not rewrite the settings file.
        AppEnvironmentBootstrapper.Ensure(_paths);

        File.GetLastWriteTimeUtc(_paths.SettingsFile).Should().Be(firstWrite);
    }
}
```

- [ ] **Step 2: Run, expect compile failure**

```bash
cd windows && dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: build fails — `AppEnvironmentBootstrapper` missing.

- [ ] **Step 3: Implement `windows/src/VeloxClip.Core/Environment/AppEnvironmentBootstrapper.cs`**

```csharp
using System.IO;

namespace VeloxClip.Core.Environment;

/// <summary>
/// Ensures every directory and seed file VeloxClip depends on exists.
/// Safe to invoke on every startup; idempotent.
/// </summary>
public static class AppEnvironmentBootstrapper
{
    private const string EmptyJsonObject = "{}";

    public static void Ensure(IAppPaths paths)
    {
        System.ArgumentNullException.ThrowIfNull(paths);

        Directory.CreateDirectory(paths.Root);
        Directory.CreateDirectory(paths.Database);
        Directory.CreateDirectory(paths.Cache);
        Directory.CreateDirectory(paths.Logs);

        if (!File.Exists(paths.SettingsFile))
        {
            File.WriteAllText(paths.SettingsFile, EmptyJsonObject);
        }
    }
}
```

- [ ] **Step 4: Run, expect pass**

```bash
cd windows && dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: `Passed: 8, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add windows/src/VeloxClip.Core/Environment/AppEnvironmentBootstrapper.cs windows/tests/VeloxClip.Core.Tests/Environment/AppEnvironmentBootstrapperTests.cs
git commit -m "feat(windows/core): add idempotent AppEnvironmentBootstrapper"
```

---

## Task 5: `VeloxClip.Platform` skeleton project (Windows-only, P0 stub)

**Files:**
- Create: `windows/src/VeloxClip.Platform/VeloxClip.Platform.csproj`
- Create: `windows/src/VeloxClip.Platform/PlatformServiceCollectionExtensions.cs`

Empty stub — exists so that the layering boundary is in place and P1's clipboard monitor has a place to land. References `Core` and `Microsoft.Extensions.DependencyInjection.Abstractions`. Builds only on Windows.

- [ ] **Step 1: Add `Microsoft.Extensions.DependencyInjection.Abstractions` to CPM**

Edit `windows/Directory.Packages.props` and insert into the `<ItemGroup>` (keep alphabetical-ish ordering near the other `Microsoft.Extensions` entries):

```xml
    <PackageVersion Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="8.0.2" />
```

- [ ] **Step 2: Create `windows/src/VeloxClip.Platform/VeloxClip.Platform.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0-windows10.0.22621.0</TargetFramework>
    <SupportedOSPlatformVersion>10.0.22621.0</SupportedOSPlatformVersion>
    <RootNamespace>VeloxClip.Platform</RootNamespace>
    <AssemblyName>VeloxClip.Platform</AssemblyName>
    <Platforms>x64</Platforms>
    <RuntimeIdentifiers>win-x64</RuntimeIdentifiers>
    <UseWindowsForms>false</UseWindowsForms>
    <UseWPF>false</UseWPF>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\VeloxClip.Core\VeloxClip.Core.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Create `windows/src/VeloxClip.Platform/PlatformServiceCollectionExtensions.cs`**

```csharp
using Microsoft.Extensions.DependencyInjection;

namespace VeloxClip.Platform;

/// <summary>
/// Entry point for registering Windows-specific service implementations
/// with the App-layer DI container.
///
/// P0: intentionally empty. P1+ will populate this with clipboard monitor,
/// global hotkey, paste-back, screenshot capture, and friends.
/// </summary>
public static class PlatformServiceCollectionExtensions
{
    public static IServiceCollection AddVeloxClipPlatform(this IServiceCollection services)
    {
        System.ArgumentNullException.ThrowIfNull(services);
        // No registrations yet.
        return services;
    }
}
```

- [ ] **Step 4: Add to solution**

```bash
cd windows
dotnet sln VeloxClip.Windows.sln add src/VeloxClip.Platform/VeloxClip.Platform.csproj
```

- [ ] **Step 5: Verify**

Because `Platform` targets `net8.0-windows10.0.22621.0`, restore works on macOS but **build** does not. Run:

```bash
cd windows
dotnet restore VeloxClip.Windows.sln
```

Expected: restore succeeds (NuGet resolves the Windows TFM packages without requiring Windows itself).

Skip `dotnet build` for this project on macOS — it will be verified in Task 12 via CI.

- [ ] **Step 6: Commit**

```bash
git add windows/Directory.Packages.props windows/src/VeloxClip.Platform windows/VeloxClip.Windows.sln
git commit -m "feat(windows/platform): add VeloxClip.Platform stub project"
```

---

## Task 6: `VeloxClip.App` — WinUI 3 project skeleton + placeholder MainWindow

**Files:**
- Create: `windows/src/VeloxClip.App/VeloxClip.App.csproj`
- Create: `windows/src/VeloxClip.App/Package.appxmanifest`
- Create: `windows/src/VeloxClip.App/app.manifest`
- Create: `windows/src/VeloxClip.App/Properties/launchSettings.json`
- Create: `windows/src/VeloxClip.App/App.xaml`
- Create: `windows/src/VeloxClip.App/App.xaml.cs`
- Create: `windows/src/VeloxClip.App/MainWindow.xaml`
- Create: `windows/src/VeloxClip.App/MainWindow.xaml.cs`
- Create: `windows/src/VeloxClip.App/Assets/.gitkeep`

This task creates the minimum WinUI 3 app that opens a window with a placeholder. Single instance, DI, tray, and Serilog come in the next tasks — we keep this commit narrow so any breakage points to one layer. Verification is on Windows (or CI).

- [ ] **Step 1: Create `windows/src/VeloxClip.App/VeloxClip.App.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows10.0.22621.0</TargetFramework>
    <TargetPlatformMinVersion>10.0.22621.0</TargetPlatformMinVersion>
    <SupportedOSPlatformVersion>10.0.22621.0</SupportedOSPlatformVersion>
    <RootNamespace>VeloxClip.App</RootNamespace>
    <AssemblyName>VeloxClip</AssemblyName>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <Platforms>x64</Platforms>
    <RuntimeIdentifiers>win-x64</RuntimeIdentifiers>
    <UseWinUI>true</UseWinUI>
    <EnableMsixTooling>true</EnableMsixTooling>
    <!-- Default to unpackaged so F5 dev works. CI overrides via -p:WindowsPackageType=MSIX. -->
    <WindowsPackageType>None</WindowsPackageType>
    <WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>
    <SelfContained>true</SelfContained>
    <PublishReadyToRun>false</PublishReadyToRun>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.WindowsAppSDK" />
    <PackageReference Include="Microsoft.Windows.SDK.BuildTools" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\VeloxClip.Core\VeloxClip.Core.csproj" />
    <ProjectReference Include="..\VeloxClip.Platform\VeloxClip.Platform.csproj" />
  </ItemGroup>
  <ItemGroup>
    <Manifest Include="$(ApplicationManifest)" />
  </ItemGroup>
  <ItemGroup>
    <None Include="Package.appxmanifest" />
  </ItemGroup>
</Project>
```

- [ ] **Step 2: Create `windows/src/VeloxClip.App/app.manifest`** (Win32 DPI + supported OS)

```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="0.1.0.0" name="VeloxClip" />
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
    </windowsSettings>
  </application>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <!-- Windows 10 / 11 -->
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
    </application>
  </compatibility>
</assembly>
```

- [ ] **Step 3: Create `windows/src/VeloxClip.App/Package.appxmanifest`** (MSIX manifest)

```xml
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap rescap">

  <Identity
    Name="com.veloxclip.windows"
    Publisher="CN=VeloxClip"
    Version="0.1.0.0" />

  <Properties>
    <DisplayName>VeloxClip</DisplayName>
    <PublisherDisplayName>VeloxClip Contributors</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>

  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.22621.0" MaxVersionTested="10.0.22621.0" />
  </Dependencies>

  <Resources>
    <Resource Language="en-US" />
  </Resources>

  <Applications>
    <Application Id="App" Executable="$targetnametoken$.exe" EntryPoint="$targetentrypoint$">
      <uap:VisualElements
        DisplayName="VeloxClip"
        Description="AI-enhanced clipboard manager"
        BackgroundColor="transparent"
        Square150x150Logo="Assets\Square150x150Logo.png"
        Square44x44Logo="Assets\Square44x44Logo.png">
        <uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" />
        <uap:SplashScreen Image="Assets\SplashScreen.png" />
      </uap:VisualElements>
    </Application>
  </Applications>

  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
```

- [ ] **Step 4: Create `windows/src/VeloxClip.App/Properties/launchSettings.json`**

```json
{
  "profiles": {
    "VeloxClip (Unpackaged)": {
      "commandName": "Project",
      "nativeDebugging": false
    }
  }
}
```

- [ ] **Step 5: Create `windows/src/VeloxClip.App/App.xaml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<Application
    x:Class="VeloxClip.App.App"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <XamlControlsResources xmlns="using:Microsoft.UI.Xaml.Controls" />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Application.Resources>
</Application>
```

- [ ] **Step 6: Create `windows/src/VeloxClip.App/App.xaml.cs`** (minimal, no DI / single-instance yet)

```csharp
using Microsoft.UI.Xaml;

namespace VeloxClip.App;

public partial class App : Application
{
    private Window? _mainWindow;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _mainWindow = new MainWindow();
        _mainWindow.Activate();
    }
}
```

- [ ] **Step 7: Create `windows/src/VeloxClip.App/MainWindow.xaml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<Window
    x:Class="VeloxClip.App.MainWindow"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Grid>
        <Grid.Background>
            <SolidColorBrush Color="{ThemeResource SolidBackgroundFillColorBase}" />
        </Grid.Background>
        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" Spacing="8">
            <TextBlock
                Text="VeloxClip"
                FontSize="36"
                FontWeight="SemiBold"
                HorizontalAlignment="Center" />
            <TextBlock
                Text="coming soon"
                FontSize="16"
                Opacity="0.7"
                HorizontalAlignment="Center" />
        </StackPanel>
    </Grid>
</Window>
```

- [ ] **Step 8: Create `windows/src/VeloxClip.App/MainWindow.xaml.cs`**

```csharp
using Microsoft.UI.Xaml;

namespace VeloxClip.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "VeloxClip";
    }
}
```

- [ ] **Step 9: Create placeholder asset directory**

```bash
mkdir -p windows/src/VeloxClip.App/Assets
touch windows/src/VeloxClip.App/Assets/.gitkeep
```

Real PNG assets ship in Task 11 — for now the manifest references files that won't yet resolve, but `dotnet build` doesn't require them; only `dotnet publish -p:WindowsPackageType=MSIX` does. We deliberately split that for incremental verification.

- [ ] **Step 10: Add to solution**

```bash
cd windows
dotnet sln VeloxClip.Windows.sln add src/VeloxClip.App/VeloxClip.App.csproj
```

- [ ] **Step 11: Restore**

```bash
cd windows
dotnet restore VeloxClip.Windows.sln
```

Expected: restore succeeds. `dotnet build` on macOS will fail because WinUI tooling requires the Windows SDK — that's expected and will be verified by CI in Task 12 and by Windows smoke test at end of plan.

- [ ] **Step 12: Commit**

```bash
git add windows/src/VeloxClip.App windows/VeloxClip.Windows.sln
git commit -m "feat(windows/app): scaffold WinUI 3 entry point with placeholder MainWindow"
```

---

## Task 7: DI / Hosting / Serilog wiring in `VeloxClip.App`

**Files:**
- Create: `windows/src/VeloxClip.App/Hosting/HostBuilderExtensions.cs`
- Modify: `windows/src/VeloxClip.App/App.xaml.cs`
- Modify: `windows/src/VeloxClip.App/VeloxClip.App.csproj` (add NuGet refs)

Builds the DI container via `Host.CreateApplicationBuilder`, registers `IAppPaths`, runs `AppEnvironmentBootstrapper.Ensure` synchronously during startup, configures Serilog with a rolling file sink in `paths.Logs`, and logs `"App starting"` / `"App stopping"`.

- [ ] **Step 1: Add hosting / Serilog package refs to `windows/src/VeloxClip.App/VeloxClip.App.csproj`**

Insert into the existing first `<ItemGroup>` containing `PackageReference` entries:

```xml
    <PackageReference Include="Microsoft.Extensions.Hosting" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Json" />
    <PackageReference Include="Microsoft.Extensions.Logging" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" />
    <PackageReference Include="Serilog" />
    <PackageReference Include="Serilog.Extensions.Hosting" />
    <PackageReference Include="Serilog.Settings.Configuration" />
    <PackageReference Include="Serilog.Sinks.File" />
    <PackageReference Include="Serilog.Sinks.Debug" />
```

- [ ] **Step 2: Create `windows/src/VeloxClip.App/Hosting/HostBuilderExtensions.cs`**

```csharp
using System.IO;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Serilog;
using VeloxClip.Core.Environment;
using VeloxClip.Platform;

namespace VeloxClip.App.Hosting;

internal static class HostBuilderExtensions
{
    /// <summary>
    /// Builds the application host: configures Serilog into the user's log
    /// directory, ensures the data scaffold exists, and registers DI services.
    /// </summary>
    public static IHost BuildAppHost()
    {
        var paths = AppPaths.Default;
        AppEnvironmentBootstrapper.Ensure(paths);

        var logPath = Path.Combine(paths.Logs, "veloxclip-.log");

        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Information()
            .Enrich.FromLogContext()
            .WriteTo.Debug()
            .WriteTo.File(
                path: logPath,
                rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 7,
                shared: true,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {SourceContext} :: {Message:lj}{NewLine}{Exception}")
            .CreateLogger();

        var builder = Host.CreateApplicationBuilder();

        builder.Logging.ClearProviders();
        builder.Services.AddLogging(lb => lb.AddSerilog(Log.Logger, dispose: true));

        builder.Services.AddSingleton<IAppPaths>(paths);
        builder.Services.AddVeloxClipPlatform();

        return builder.Build();
    }
}
```

- [ ] **Step 3: Rewrite `windows/src/VeloxClip.App/App.xaml.cs` to use the host**

Replace the entire file with:

```csharp
using System;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.UI.Xaml;
using Serilog;
using VeloxClip.App.Hosting;

namespace VeloxClip.App;

public partial class App : Application
{
    private IHost? _host;
    private ILogger<App>? _logger;
    private Window? _mainWindow;

    /// <summary>The DI container, available after <see cref="OnLaunched"/>.</summary>
    internal static IServiceProvider Services =>
        ((App)Current)._host?.Services
        ?? throw new InvalidOperationException("Host not built yet.");

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _host = HostBuilderExtensions.BuildAppHost();
        _logger = _host.Services.GetRequiredService<ILogger<App>>();
        _logger.LogInformation("App starting (pid={Pid})", System.Environment.ProcessId);

        _mainWindow = new MainWindow();
        _mainWindow.Activate();
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        _logger?.LogError(e.Exception, "Unhandled exception in UI thread");
        // Allow default WinUI handling to continue; we just record it.
    }

    /// <summary>Invoked by the tray "Quit" command. Flushes logs then exits.</summary>
    internal void Shutdown()
    {
        _logger?.LogInformation("App stopping");
        Log.CloseAndFlush();
        _host?.Dispose();
        Exit();
    }
}
```

- [ ] **Step 4: Verify Core layer still compiles + Core tests pass**

```bash
cd windows
dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: still `Passed: 8`. (Core didn't change.)

- [ ] **Step 5: Commit**

```bash
git add windows/src/VeloxClip.App
git commit -m "feat(windows/app): wire Microsoft.Extensions.Hosting + Serilog + DI"
```

---

## Task 8: Single-instance via Windows App SDK `AppInstance`

**Files:**
- Create: `windows/src/VeloxClip.App/SingleInstance/SingleInstanceController.cs`
- Modify: `windows/src/VeloxClip.App/Program.cs` (NEW — replaces auto-generated entry point so we can run our pre-XAML single-instance code)
- Modify: `windows/src/VeloxClip.App/VeloxClip.App.csproj` (disable auto-generated Main, point to our `Program.Main`)
- Modify: `windows/src/VeloxClip.App/App.xaml.cs` (hook activation redirection)

WinUI 3 normally auto-generates `Main` from `App.xaml`. To run single-instance logic *before* the XAML runtime initialises, we disable the auto Main with `<DISABLE_XAML_GENERATED_MAIN>true</DISABLE_XAML_GENERATED_MAIN>` and provide our own.

- [ ] **Step 1: Disable auto-generated Main**

Edit `windows/src/VeloxClip.App/VeloxClip.App.csproj`. Inside the existing `<PropertyGroup>` (the one with `<OutputType>WinExe</OutputType>`), add:

```xml
    <DISABLE_XAML_GENERATED_MAIN>true</DISABLE_XAML_GENERATED_MAIN>
```

- [ ] **Step 2: Create `windows/src/VeloxClip.App/SingleInstance/SingleInstanceController.cs`**

```csharp
using System;
using System.Threading.Tasks;
using Microsoft.Windows.AppLifecycle;

namespace VeloxClip.App.SingleInstance;

/// <summary>
/// Owns the AppInstance key for VeloxClip and decides whether the current
/// process is the primary instance or should hand off and exit.
/// </summary>
internal static class SingleInstanceController
{
    private const string InstanceKey = "VeloxClip.Singleton";

    /// <summary>
    /// Result of <see cref="ClaimOrRedirect"/>. When <see cref="IsPrimary"/>
    /// is false the caller must exit immediately.
    /// </summary>
    public readonly record struct InstanceClaim(bool IsPrimary, AppInstance Primary);

    public static async Task<InstanceClaim> ClaimOrRedirectAsync(AppActivationArguments activationArgs)
    {
        var primary = AppInstance.FindOrRegisterForKey(InstanceKey);
        if (primary.IsCurrent)
        {
            return new InstanceClaim(IsPrimary: true, Primary: primary);
        }

        // Forward this activation to the primary instance, then signal caller to exit.
        await primary.RedirectActivationToAsync(activationArgs).AsTask().ConfigureAwait(false);
        return new InstanceClaim(IsPrimary: false, Primary: primary);
    }
}
```

- [ ] **Step 3: Create `windows/src/VeloxClip.App/Program.cs`**

```csharp
using System;
using System.Threading;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using VeloxClip.App.SingleInstance;

namespace VeloxClip.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();

        var activationArgs = AppInstance.GetCurrent().GetActivatedEventArgs();

        // Block on the async claim during startup — UI hasn't started yet.
        var claim = SingleInstanceController.ClaimOrRedirectAsync(activationArgs)
            .GetAwaiter()
            .GetResult();

        if (!claim.IsPrimary)
        {
            // Activation already redirected to primary. Exit silently.
            return 0;
        }

        Application.Start(_ =>
        {
            var context = new DispatcherQueueSynchronizationContext(
                DispatcherQueue.GetForCurrentThread());
            SynchronizationContext.SetSynchronizationContext(context);
            _ = new App();
        });

        return 0;
    }
}
```

- [ ] **Step 4: Hook activation-redirect handling in `App.xaml.cs`**

Modify `windows/src/VeloxClip.App/App.xaml.cs`. Replace the constructor body and `OnLaunched` with the version below (other members unchanged):

```csharp
    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;

        // When a secondary instance redirects activation here, surface the window.
        Microsoft.Windows.AppLifecycle.AppInstance
            .GetCurrent()
            .Activated += OnActivatedFromSecondaryInstance;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _host = HostBuilderExtensions.BuildAppHost();
        _logger = _host.Services.GetRequiredService<ILogger<App>>();
        _logger.LogInformation("App starting (pid={Pid})", System.Environment.ProcessId);

        _mainWindow = new MainWindow();
        _mainWindow.Activate();
    }

    private void OnActivatedFromSecondaryInstance(
        object? sender,
        Microsoft.Windows.AppLifecycle.AppActivationArguments e)
    {
        if (_mainWindow is null)
        {
            return;
        }

        // Marshal to UI thread, show + bring to front.
        _mainWindow.DispatcherQueue.TryEnqueue(() =>
        {
            _logger?.LogInformation("Secondary instance activation redirected; surfacing window");
            _mainWindow.Activate();
            if (_mainWindow.AppWindow is { } appWindow)
            {
                appWindow.Show();
                appWindow.MoveInZOrderAtTop();
            }
        });
    }
```

- [ ] **Step 5: Verify Core tests still pass**

```bash
cd windows && dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: `Passed: 8`.

- [ ] **Step 6: Commit**

```bash
git add windows/src/VeloxClip.App
git commit -m "feat(windows/app): single-instance via AppInstance with activation redirect"
```

---

## Task 9: Tray icon + Show / Settings (disabled) / Quit menu

**Files:**
- Create: `windows/src/VeloxClip.App/Tray/TrayIconHost.xaml`
- Create: `windows/src/VeloxClip.App/Tray/TrayIconHost.xaml.cs`
- Modify: `windows/src/VeloxClip.App/App.xaml.cs` (own the tray host lifecycle)
- Modify: `windows/src/VeloxClip.App/VeloxClip.App.csproj` (add H.NotifyIcon.WinUI ref)

`H.NotifyIcon.WinUI` is declarative — we host the `TaskbarIcon` inside a XAML UserControl (`TrayIconHost`) that the App constructs once at startup. The icon resource path uses the runtime asset directory, not the MSIX manifest.

- [ ] **Step 1: Add `H.NotifyIcon.WinUI` to `windows/src/VeloxClip.App/VeloxClip.App.csproj`**

Insert into the `PackageReference` `<ItemGroup>`:

```xml
    <PackageReference Include="H.NotifyIcon.WinUI" />
```

- [ ] **Step 2: Reserve `Assets\app.ico` as build content**

Add this `<ItemGroup>` to `windows/src/VeloxClip.App/VeloxClip.App.csproj` (top-level, sibling of existing groups):

```xml
  <ItemGroup>
    <Content Include="Assets\app.ico">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </Content>
  </ItemGroup>
```

The actual `app.ico` file ships in Task 11; this entry is harmless until then because `Content Include` only fails on missing files at publish time, not build time.

- [ ] **Step 3: Create `windows/src/VeloxClip.App/Tray/TrayIconHost.xaml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<UserControl
    x:Class="VeloxClip.App.Tray.TrayIconHost"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:tb="using:H.NotifyIcon">
    <tb:TaskbarIcon
        x:Name="Tray"
        ToolTipText="VeloxClip"
        IconSource="ms-appx:///Assets/app.ico"
        NoLeftClickDelay="True"
        LeftClickCommand="{x:Bind ShowCommand, Mode=OneTime}">
        <tb:TaskbarIcon.ContextFlyout>
            <MenuFlyout>
                <MenuFlyoutItem Text="Show" Click="OnShowClicked" />
                <MenuFlyoutItem Text="Settings" IsEnabled="False" />
                <MenuFlyoutSeparator />
                <MenuFlyoutItem Text="Quit" Click="OnQuitClicked" />
            </MenuFlyout>
        </tb:TaskbarIcon.ContextFlyout>
    </tb:TaskbarIcon>
</UserControl>
```

- [ ] **Step 4: Create `windows/src/VeloxClip.App/Tray/TrayIconHost.xaml.cs`**

```csharp
using System;
using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace VeloxClip.App.Tray;

public sealed partial class TrayIconHost : UserControl
{
    /// <summary>Invoked when the user picks "Show" or left-clicks the tray.</summary>
    public event EventHandler? ShowRequested;

    /// <summary>Invoked when the user picks "Quit".</summary>
    public event EventHandler? QuitRequested;

    public IRelayCommand ShowCommand { get; }

    public TrayIconHost()
    {
        ShowCommand = new RelayCommand(() => ShowRequested?.Invoke(this, EventArgs.Empty));
        InitializeComponent();
    }

    private void OnShowClicked(object sender, RoutedEventArgs e)
        => ShowRequested?.Invoke(this, EventArgs.Empty);

    private void OnQuitClicked(object sender, RoutedEventArgs e)
        => QuitRequested?.Invoke(this, EventArgs.Empty);

    /// <summary>
    /// Forces the underlying NotifyIcon to release its Shell tray slot
    /// before the process exits. Called from App.Shutdown.
    /// </summary>
    public void Dispose() => Tray.Dispose();
}
```

- [ ] **Step 5: Modify `App.xaml.cs` to own the tray host**

In `windows/src/VeloxClip.App/App.xaml.cs`:

- Add `using VeloxClip.App.Tray;` at the top.
- Add a private field `private TrayIconHost? _tray;` next to `_mainWindow`.
- Inside `OnLaunched`, **after** `_mainWindow.Activate();`, append:

```csharp
        _tray = new TrayIconHost();
        _tray.ShowRequested += (_, _) =>
        {
            _mainWindow.DispatcherQueue.TryEnqueue(() =>
            {
                _mainWindow.Activate();
                if (_mainWindow.AppWindow is { } appWindow)
                {
                    appWindow.Show();
                    appWindow.MoveInZOrderAtTop();
                }
            });
        };
        _tray.QuitRequested += (_, _) => Shutdown();
```

- Modify the existing `Shutdown` method to dispose the tray before exiting:

```csharp
    internal void Shutdown()
    {
        _logger?.LogInformation("App stopping");
        _tray?.Dispose();
        Log.CloseAndFlush();
        _host?.Dispose();
        Exit();
    }
```

- [ ] **Step 6: Verify Core tests still pass**

```bash
cd windows && dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: `Passed: 8`.

- [ ] **Step 7: Commit**

```bash
git add windows/src/VeloxClip.App
git commit -m "feat(windows/app): tray icon with Show / Settings / Quit menu"
```

---

## Task 10: Main window close-to-hide

**Files:**
- Modify: `windows/src/VeloxClip.App/MainWindow.xaml.cs`

Pressing the X on the main window must *hide* it (tray + process stay alive), matching macOS dock behavior. Quitting happens only from the tray menu.

- [ ] **Step 1: Replace `windows/src/VeloxClip.App/MainWindow.xaml.cs`**

```csharp
using Microsoft.UI.Xaml;

namespace VeloxClip.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "VeloxClip";

        // Intercept the close button: hide instead of destroying the window.
        if (AppWindow is { } appWindow)
        {
            appWindow.Closing += OnAppWindowClosing;
        }
    }

    private void OnAppWindowClosing(
        Microsoft.UI.Windowing.AppWindow sender,
        Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        args.Cancel = true;
        sender.Hide();
    }
}
```

- [ ] **Step 2: Verify Core tests still pass**

```bash
cd windows && dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: `Passed: 8`.

- [ ] **Step 3: Commit**

```bash
git add windows/src/VeloxClip.App/MainWindow.xaml.cs
git commit -m "feat(windows/app): hide main window on close, exit only via tray Quit"
```

---

## Task 11: Icon assets (app.ico + MSIX PNGs)

**Files:**
- Create: `windows/build/icons/app.ico`
- Create: `windows/src/VeloxClip.App/Assets/app.ico` (copy of the above)
- Create: `windows/src/VeloxClip.App/Assets/StoreLogo.png`
- Create: `windows/src/VeloxClip.App/Assets/Square150x150Logo.png`
- Create: `windows/src/VeloxClip.App/Assets/Square44x44Logo.png`
- Create: `windows/src/VeloxClip.App/Assets/Wide310x150Logo.png`
- Create: `windows/src/VeloxClip.App/Assets/SplashScreen.png`

Reuse the existing macOS app icon. The Mac source is at `VeloxClip/Resources/AppIcon.icns`. We derive a multi-resolution `.ico` and the MSIX PNG set from it. This task runs on macOS — `sips` + `iconutil` produce the PNGs; `convert` (ImageMagick) or `png2ico` produces the ICO.

- [ ] **Step 1: Locate the source PNGs**

```bash
cd "/Users/daichangyu/code/VeloxClip/.claude/worktrees/hardcore-nash-ed3715"
ls VeloxClip/Resources/AppIcon.icns
iconutil -c iconset VeloxClip/Resources/AppIcon.icns -o /tmp/veloxclip.iconset
ls /tmp/veloxclip.iconset
```

Expected: a directory containing `icon_16x16.png`, `icon_32x32.png`, `icon_128x128.png`, `icon_256x256.png`, `icon_512x512.png` (and `@2x` variants).

- [ ] **Step 2: Verify ImageMagick is available, install if needed**

```bash
which magick || which convert
```

If neither is present:

```bash
brew install imagemagick
```

- [ ] **Step 3: Build the multi-resolution ICO**

```bash
mkdir -p windows/build/icons windows/src/VeloxClip.App/Assets
magick \
  /tmp/veloxclip.iconset/icon_16x16.png \
  /tmp/veloxclip.iconset/icon_32x32.png \
  /tmp/veloxclip.iconset/icon_128x128.png \
  /tmp/veloxclip.iconset/icon_256x256.png \
  windows/build/icons/app.ico
cp windows/build/icons/app.ico windows/src/VeloxClip.App/Assets/app.ico
```

If `magick` not found, fall back to `convert <inputs...> windows/build/icons/app.ico`.

Expected: `windows/build/icons/app.ico` is a non-empty binary file (`file windows/build/icons/app.ico` reports `MS Windows icon resource`).

- [ ] **Step 4: Generate MSIX asset PNGs**

```bash
SRC=/tmp/veloxclip.iconset/icon_512x512.png
ASSETS=windows/src/VeloxClip.App/Assets
magick "$SRC" -resize 50x50    "$ASSETS/StoreLogo.png"
magick "$SRC" -resize 150x150  "$ASSETS/Square150x150Logo.png"
magick "$SRC" -resize 44x44    "$ASSETS/Square44x44Logo.png"
# Wide tile: pad icon onto a 310x150 transparent canvas
magick "$SRC" -resize 150x150 -background none -gravity center -extent 310x150 \
  "$ASSETS/Wide310x150Logo.png"
# Splash: 620x300 transparent canvas with icon centred
magick "$SRC" -resize 300x300 -background none -gravity center -extent 620x300 \
  "$ASSETS/SplashScreen.png"
ls -la "$ASSETS"
```

Expected: five PNG files at the listed sizes.

- [ ] **Step 5: Remove the placeholder `.gitkeep`**

```bash
rm -f windows/src/VeloxClip.App/Assets/.gitkeep
```

- [ ] **Step 6: Verify Core tests still pass (no logic changed but we sanity-check the project still resolves)**

```bash
cd windows && dotnet restore VeloxClip.Windows.sln && dotnet test tests/VeloxClip.Core.Tests --nologo
```

Expected: `Passed: 8`.

- [ ] **Step 7: Commit**

```bash
git add windows/build/icons windows/src/VeloxClip.App/Assets
git commit -m "build(windows): generate app.ico + MSIX tile assets from macOS icon"
```

---

## Task 12: Local packaging script `windows/build/package.ps1`

**Files:**
- Create: `windows/build/package.ps1`

A reproducible local equivalent of the CI workflow. Used by contributors and by the workflow itself as the single source of build commands.

- [ ] **Step 1: Create `windows/build/package.ps1`**

```powershell
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
```

- [ ] **Step 2: Add an ignore entry for the `dist/` output**

Edit `.gitignore` and append in the Windows section already created in Task 1:

```gitignore
windows/dist/
```

- [ ] **Step 3: No local verification on macOS — script targets Windows**

This script will be exercised end-to-end in Task 13 via CI. On macOS we only verify it parses by checking the shebang/header is consistent. Skip and proceed.

- [ ] **Step 4: Commit**

```bash
git add windows/build/package.ps1 .gitignore
git commit -m "build(windows): add package.ps1 local one-shot build/test/publish script"
```

---

## Task 13: GitHub Actions workflow + tag-conditional release upload

**Files:**
- Create: `.github/workflows/build-windows.yml`
- Modify: `README.md` — add a one-line pointer to `windows/README.md`
- Modify: `CHANGELOG.md` — record P0 completion

End-to-end source of truth: this workflow exercises the entire scaffold on a Windows runner and is the gate that flips P0 from "implementation done" to "verified done".

- [ ] **Step 1: Create `.github/workflows/build-windows.yml`**

```yaml
name: build-windows

on:
  push:
    branches: [main]
    tags: ['v*.*.*']
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: write   # needed to upload release assets on tag

jobs:
  build:
    runs-on: windows-2022
    timeout-minutes: 30
    defaults:
      run:
        working-directory: windows
        shell: pwsh

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup .NET 8
        uses: actions/setup-dotnet@v4
        with:
          global-json-file: windows/global.json

      - name: Cache NuGet
        uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: nuget-${{ runner.os }}-${{ hashFiles('windows/**/*.csproj', 'windows/Directory.Packages.props', 'windows/global.json') }}
          restore-keys: nuget-${{ runner.os }}-

      - name: Resolve version
        id: ver
        run: |
          $ref = "${{ github.ref }}"
          if ($ref -like 'refs/tags/v*') {
              $v = $ref -replace '^refs/tags/v',''
          } else {
              $v = '0.1.0-ci.' + "${{ github.run_number }}"
          }
          echo "version=$v" >> $env:GITHUB_OUTPUT
          echo "Resolved version: $v"

      - name: Restore
        run: dotnet restore VeloxClip.Windows.sln

      - name: Build
        run: dotnet build VeloxClip.Windows.sln -c Release --no-restore --nologo

      - name: Test
        run: dotnet test tests/VeloxClip.Core.Tests -c Release --no-build --nologo

      - name: Package (MSIX + portable)
        run: pwsh build/package.ps1 -Configuration Release -Version "${{ steps.ver.outputs.version }}"

      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: veloxclip-windows-${{ steps.ver.outputs.version }}
          path: windows/dist/*
          if-no-files-found: error

      - name: Attach to GitHub Release (tag only)
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: |
            windows/dist/VeloxClip-${{ steps.ver.outputs.version }}-x64.msix
            windows/dist/VeloxClip-${{ steps.ver.outputs.version }}-x64-portable.zip
          fail_on_unmatched_files: true
```

- [ ] **Step 2: Update root `README.md`**

Add the following line directly after the existing project intro paragraph (locate the line that ends with the macOS description, append a new blockquote on the next line):

```markdown

> **Windows port:** under active development — see [`windows/README.md`](windows/README.md) and the design at [`docs/superpowers/specs/2026-05-08-windows-port-p0-scaffold-design.md`](docs/superpowers/specs/2026-05-08-windows-port-p0-scaffold-design.md).
```

- [ ] **Step 3: Update `CHANGELOG.md`**

Insert under the most recent "Unreleased" section (or create one at the top if absent):

```markdown
### Added
- **Windows port — P0 scaffold**: `windows/` project skeleton (Core / Platform / App), WinUI 3 placeholder window, system tray, single-instance via AppInstance, Serilog file logging, `%LOCALAPPDATA%\VeloxClip\` scaffold, and GitHub Actions workflow producing unsigned MSIX + portable zip on tags.
```

- [ ] **Step 4: Push and verify CI**

```bash
git add .github/workflows/build-windows.yml README.md CHANGELOG.md
git commit -m "ci(windows): add build-windows workflow + README/CHANGELOG entries"
git push -u origin HEAD
```

Then watch the workflow:

```bash
gh run watch
```

Expected outcome:
- `Restore`, `Build`, `Test` steps green
- `Package` step green; `windows/dist/VeloxClip-0.1.0-ci.<run>-x64.msix` and `...portable.zip` both produced
- `Upload build artifacts` attaches both files to the run

If `Build` fails with `XamlCompiler error WMC1108` or similar, the most common cause is the Windows App SDK runtime missing — `setup-dotnet` does not pre-install it, but the build itself pulls the `Microsoft.WindowsAppSDK` NuGet which contains the build tools. Re-run the workflow; transient feed issues clear themselves.

- [ ] **Step 5: Local end-to-end smoke test on a Windows machine**

> This is the only step in the entire plan that requires a Windows host (or VM). Without it, P0's DoD items "F5 launches window + tray", "close hides", "second instance surfaces first", and "Quit exits" are unverified. If no Windows host is available now, mark this step pending and revisit before declaring P0 done — do not commit a "complete" claim until it passes.

On a Windows 11 22H2 machine with .NET 8 SDK:

```pwsh
git clone <repo> ; cd <repo>/windows
dotnet run --project src/VeloxClip.App -c Debug
```

Verify in order:
1. Main window appears titled "VeloxClip" with "coming soon" text
2. Tray icon appears (system tray, bottom-right); tooltip "VeloxClip"
3. Click X on main window → window hides, tray icon remains, process still running (check Task Manager: `VeloxClip.exe` present)
4. Tray left-click or right-click → **Show** → window reappears and activates
5. Tray right-click → **Settings** is greyed out
6. Open a second terminal, `dotnet run --project src/VeloxClip.App -c Debug` again → second process exits within 1–2 seconds, first window comes to front
7. Check `%LOCALAPPDATA%\VeloxClip\logs\veloxclip-YYYYMMDD.log` contains `App starting` and (after Quit) `App stopping`
8. Tray right-click → **Quit** → window closes, tray icon disappears, process exits cleanly

If any check fails, file the failure against the corresponding task (e.g. Step 6 failing → Task 8 single-instance logic).

- [ ] **Step 6: Commit any fixes from smoke test, push, verify CI green**

Iterate until the workflow run from Step 4 is green **and** all eight smoke-test checks in Step 5 pass.

- [ ] **Step 7: Tag-driven release dry run (optional but recommended)**

```bash
git tag v0.1.0-windows-p0
git push origin v0.1.0-windows-p0
gh run watch
gh release view v0.1.0-windows-p0
```

Expected: Release page lists `VeloxClip-0.1.0-windows-p0-x64.msix` and `...portable.zip` as downloadable assets.

If a real release tag is not appropriate yet, skip this step; CI artifacts on the run still prove the packaging path.

---

## P0 Definition of Done — final checklist (from the spec)

Tick these when reporting P0 complete. Each maps back to a task above.

- [ ] Solution compiles `0 warning 0 error` (Tasks 2–10, verified by Task 13 CI)
- [ ] `dotnet test tests/VeloxClip.Core.Tests` passes (Tasks 2–4, 8 tests)
- [ ] F5 launches main window + tray icon (Task 13 Step 5.1–5.2)
- [ ] Second instance surfaces first instance and exits (Task 13 Step 5.6)
- [ ] Close hides; Quit exits (Task 13 Step 5.3, 5.8)
- [ ] `%LOCALAPPDATA%\VeloxClip\logs\veloxclip-YYYYMMDD.log` records lifecycle (Task 13 Step 5.7)
- [ ] CI green on push/PR; tag pushes MSIX + portable zip to Release (Task 13 Step 4 / Step 7)
- [ ] `windows/README.md` documents env, build, run, test, package, CI (Task 1 Step 7)
