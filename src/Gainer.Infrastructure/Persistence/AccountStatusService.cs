using Gainer.Core.Access;
using Microsoft.AspNetCore.Identity;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Identity-only account status management.</summary>
public sealed class AccountStatusService(UserManager<AppUser> userManager) : IAccountStatusService
{
    /// <inheritdoc />
    public async Task<bool> SetActiveAsync(Guid accountId, bool isActive)
    {
        AppUser? user = await userManager.FindByIdAsync(accountId.ToString());
        if (user is null)
        {
            return false;
        }

        user.IsActive = isActive;
        IdentityResult result = await userManager.UpdateSecurityStampAsync(user);
        if (!result.Succeeded)
        {
            throw new InvalidOperationException("The account status could not be updated.");
        }

        return true;
    }
}
