namespace Gainer.Infrastructure.Persistence;

/// <summary>Defines the PostgreSQL schemas owned by the modular monolith.</summary>
public static class DatabaseSchemas
{
    public const string Identity = "identity";
    public const string Tracking = "tracking";
    public const string Training = "training";
    public const string Sync = "sync";
    public const string Ai = "ai";
    public const string Integrations = "integrations";

    /// <summary>Returns every application-owned schema.</summary>
    public static IReadOnlyList<string> All { get; } =
        [Identity, Tracking, Training, Sync, Ai, Integrations];
}
