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
