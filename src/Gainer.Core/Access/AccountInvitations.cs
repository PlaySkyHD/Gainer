namespace Gainer.Core.Access;

/// <summary>Result returned when an operator creates a manually shareable invitation.</summary>
public sealed record IssuedAccountInvitation(string Token, DateTimeOffset ExpiresAt);

/// <summary>Possible outcomes of an invitation acceptance attempt.</summary>
public enum AccountInvitationAcceptanceResult
{
    /// <summary>The invited account was activated.</summary>
    Accepted,

    /// <summary>The token is unknown, expired, or already used.</summary>
    InvalidInvitation,

    /// <summary>The selected password does not meet the account requirements.</summary>
    InvalidPassword,
}

/// <summary>Creates and consumes account invitations without exposing persistence details.</summary>
public interface IAccountInvitationService
{
    /// <summary>Creates or replaces the pending invitation for an inactive email address.</summary>
    Task<IssuedAccountInvitation> IssueAsync(string email, CancellationToken cancellationToken = default);

    /// <summary>Atomically consumes a token and activates its account.</summary>
    Task<AccountInvitationAcceptanceResult> AcceptAsync(
        string token,
        string password,
        CancellationToken cancellationToken = default);
}

/// <summary>Raised when an invitation cannot be issued for the requested identity.</summary>
public sealed class AccountInvitationCannotBeIssuedException : InvalidOperationException
{
    /// <summary>Creates the intentionally non-specific failure.</summary>
    public AccountInvitationCannotBeIssuedException()
        : base("The account invitation cannot be issued.")
    {
    }
}
