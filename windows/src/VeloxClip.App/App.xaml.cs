using System;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.UI.Xaml;
using Serilog;
using VeloxClip.App.Hosting;
using VeloxClip.App.Tray;

namespace VeloxClip.App;

public partial class App : Application
{
    private IHost? _host;
    private ILogger<App>? _logger;
    private Window? _mainWindow;
    private TrayIconHost? _tray;

    /// <summary>The DI container, available after <see cref="OnLaunched"/>.</summary>
    internal static IServiceProvider Services =>
        ((App)Current)._host?.Services
        ?? throw new InvalidOperationException("Host not built yet.");

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
        // Start synchronously so future IHostedService workers (P1+ clipboard
        // monitor, hotkey listener, etc.) actually run.
        _host.Start();
        _logger = _host.Services.GetRequiredService<ILogger<App>>();
        _logger.LogInformation("App starting (pid={Pid})", System.Environment.ProcessId);

        _mainWindow = new MainWindow();
        _mainWindow.Activate();

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

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        _logger?.LogError(e.Exception, "Unhandled exception in UI thread");
        // Allow default WinUI handling to continue; we just record it.
    }

    /// <summary>Invoked by the tray "Quit" command. Flushes logs then exits.</summary>
    internal void Shutdown()
    {
        _logger?.LogInformation("App stopping");
        _tray?.Dispose();
        _host?.StopAsync(TimeSpan.FromSeconds(5)).GetAwaiter().GetResult();
        Log.CloseAndFlush();
        _host?.Dispose();
        Exit();
    }
}
