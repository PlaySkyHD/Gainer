namespace Gainer.Contracts.Security;

/// <summary>Contains the request token paired with the host-only antiforgery cookie.</summary>
public sealed record AntiforgeryTokenResponse(string RequestToken, Guid? AuthenticatedUserId = null);
