namespace Gainer.Contracts.Security;

/// <summary>Identity-only account metadata visible to an account operator.</summary>
public sealed record AccountSummaryResponse(Guid AccountId, string Email, bool IsActive);
