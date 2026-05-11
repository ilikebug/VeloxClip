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
