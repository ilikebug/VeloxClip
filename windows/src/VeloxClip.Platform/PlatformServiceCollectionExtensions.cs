using Microsoft.Extensions.DependencyInjection;

namespace VeloxClip.Platform;

/// <summary>
/// Entry point for registering Windows-specific service implementations
/// with the App-layer DI container.
///
/// P0: intentionally empty. P1+ will populate this with clipboard monitor,
/// global hotkey, paste-back, screenshot capture, and friends.
/// </summary>
public static class PlatformServiceCollectionExtensions
{
    public static IServiceCollection AddVeloxClipPlatform(this IServiceCollection services)
    {
        System.ArgumentNullException.ThrowIfNull(services);
        // No registrations yet.
        return services;
    }
}
