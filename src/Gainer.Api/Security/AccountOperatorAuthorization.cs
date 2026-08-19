namespace Gainer.Api.Security;

/// <summary>Stable authorization boundary for identity-only account operations.</summary>
public static class AccountOperatorAuthorization
{
    /// <summary>The policy required by account-operator endpoints.</summary>
    public const string PolicyName = "AccountOperator";

    /// <summary>The dedicated Identity role accepted by the policy.</summary>
    public const string RoleName = "AccountOperator";
}
