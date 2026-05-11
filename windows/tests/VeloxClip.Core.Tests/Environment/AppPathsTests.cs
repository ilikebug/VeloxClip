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

        // Use Path.Combine so the assertion uses the platform separator;
        // Core targets net8.0 and tests run on macOS/Linux too.
        paths.Root.Should().Be(Path.Combine(@"C:\Base", "VeloxClip"));
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
