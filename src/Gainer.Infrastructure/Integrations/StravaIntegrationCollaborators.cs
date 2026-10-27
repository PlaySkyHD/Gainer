namespace Gainer.Infrastructure.Integrations;

/// <summary>The Strava-specific collaborators of <see cref="StravaIntegrationService"/>, registered together in DI.</summary>
public sealed record StravaIntegrationCollaborators(
    IStravaApiClient Client,
    StravaTokenVault Tokens,
    StravaExportSignal Signal,
    StravaAuthorizationState AuthorizationState);
