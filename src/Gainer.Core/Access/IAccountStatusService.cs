namespace Gainer.Core.Access;

/// <summary>Changes Identity account availability without accessing user fitness data.</summary>
public interface IAccountStatusService
{
    /// <summary>Sets an account's active state and revokes its existing sessions.</summary>
    Task<bool> SetActiveAsync(Guid accountId, bool isActive);
}

/// <summary>Identity-only account metadata used by the operator boundary.</summary>
public sealed record AccountIdentitySummary(Guid AccountId, string Email, bool IsActive);

/// <summary>Lists account metadata without exposing any fitness repositories.</summary>
public interface IAccountDirectoryService
{
    /// <summary>Returns the small private-beta account directory.</summary>
    Task<IReadOnlyList<AccountIdentitySummary>> ListAsync(CancellationToken cancellationToken = default);
}
