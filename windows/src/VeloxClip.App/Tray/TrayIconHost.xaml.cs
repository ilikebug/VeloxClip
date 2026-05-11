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
