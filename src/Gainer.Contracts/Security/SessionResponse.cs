namespace Gainer.Contracts.Security;

/// <summary>The authenticated user's current browser session.</summary>
public sealed record SessionResponse(Guid UserId, string Email, bool IsAccountOperator);
