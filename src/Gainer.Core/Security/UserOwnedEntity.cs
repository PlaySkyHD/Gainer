namespace Gainer.Core.Security;

/// <summary>Provides server-controlled ownership for user data.</summary>
public abstract class UserOwnedEntity : IUserOwnedEntity
{
    /// <inheritdoc />
    public Guid UserId { get; private set; }
}
