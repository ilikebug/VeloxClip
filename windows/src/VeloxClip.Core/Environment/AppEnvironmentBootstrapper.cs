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
