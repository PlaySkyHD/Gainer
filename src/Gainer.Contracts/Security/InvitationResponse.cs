namespace Gainer.Contracts.Security;

/// <summary>A newly generated manual activation link that is returned only once.</summary>
public sealed record InvitationResponse(string ActivationPath, DateTimeOffset ExpiresAt);
