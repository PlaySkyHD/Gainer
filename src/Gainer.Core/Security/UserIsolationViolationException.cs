namespace Gainer.Core.Security;

/// <summary>Indicates an attempted write outside the authenticated user's ownership boundary.</summary>
public sealed class UserIsolationViolationException : InvalidOperationException
{
    /// <summary>Initializes a user-isolation violation without including resource contents.</summary>
    public UserIsolationViolationException()
        : base("The requested data operation violates the user isolation boundary.")
    {
    }
}
