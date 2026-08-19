namespace Gainer.ServiceDefaults;

/// <summary>
/// Defines the health-check tags used by the Gainer probe endpoints.
/// </summary>
public static class GainerHealthCheckTags
{
    /// <summary>
    /// Marks checks that prove the process is alive.
    /// </summary>
    public const string Live = "live";

    /// <summary>
    /// Marks checks that must pass before the API can receive traffic.
    /// </summary>
    public const string Ready = "ready";
}
