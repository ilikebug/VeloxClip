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
