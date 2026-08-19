using Gainer.Core.Access;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Reads only the Identity fields needed by account operators.</summary>
public sealed class AccountDirectoryService(UserManager<AppUser> userManager) : IAccountDirectoryService
{
    /// <inheritdoc />
    public async Task<IReadOnlyList<AccountIdentitySummary>> ListAsync(
        CancellationToken cancellationToken = default) =>
        await userManager.Users
            .OrderBy(user => user.NormalizedEmail)
            .Select(user => new AccountIdentitySummary(
                user.Id,
                user.Email ?? user.UserName ?? string.Empty,
                user.IsActive))
            .ToListAsync(cancellationToken);
}
