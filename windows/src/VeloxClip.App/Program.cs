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
