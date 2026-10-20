namespace Gainer.Contracts.Security;

/// <summary>The account of the current device session.</summary>
public sealed record SessionResponse(Guid UserId, string Email, bool IsAccountOperator);
