namespace Gainer.Core.Security;

/// <summary>Marks an entity whose data belongs to exactly one application user.</summary>
public interface IUserOwnedEntity
{
    /// <summary>Gets the immutable owner assigned by the server.</summary>
    Guid UserId { get; }
}
