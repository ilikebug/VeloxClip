using FluentAssertions;
using Xunit;

namespace VeloxClip.Core.Tests;

public class SanityTests
{
    [Fact]
    public void Toolchain_IsAlive()
    {
        // Proves: csproj resolves, xUnit discovers, FluentAssertions linked,
        // CPM pins resolved, project reference to Core works.
        (1 + 1).Should().Be(2);
    }
}
