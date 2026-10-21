namespace Gainer.Infrastructure.Integrations;

/// <summary>
/// Sets the user of a DI scope that has no authenticated request, such as a background job or an
/// anonymous OAuth callback whose user comes from a protected state. The user context uses it only
/// when the request carries no authenticated user.
/// </summary>
public sealed class BackgroundUserScope
{
    public Guid? UserId { get; private set; }

    /// <summary>Binds the scope to one user; switching to another user in the same scope is refused.</summary>
    public void Enter(Guid userId)
    {
        if (userId == Guid.Empty) throw new ArgumentException("A user identifier is required.", nameof(userId));
        if (UserId is { } current && current != userId)
        {
            throw new InvalidOperationException("The scope is already bound to another user.");
        }
        UserId = userId;
    }
}
