using Microsoft.AspNetCore.Identity;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Represents an invited application identity.</summary>
public sealed class AppUser : IdentityUser<Guid>
{
    /// <summary>Whether the account may create authenticated sessions.</summary>
    public bool IsActive { get; set; } = true;
}
