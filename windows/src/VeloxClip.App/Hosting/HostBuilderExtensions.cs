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
