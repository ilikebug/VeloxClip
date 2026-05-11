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
