namespace Gainer.Core.Security;

/// <summary>Provides the user identity established by the trusted application boundary.</summary>
public interface IUserContext
{
    /// <summary>Gets the authenticated user identifier, or <see langword="null" /> for an anonymous request.</summary>
    Guid? UserId { get; }
}
