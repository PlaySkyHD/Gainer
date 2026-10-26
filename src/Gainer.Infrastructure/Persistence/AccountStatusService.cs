using Gainer.Core.Access;
using Microsoft.AspNetCore.Identity;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Identity-only account status management.</summary>
public sealed class AccountStatusService(
    UserManager<AppUser> userManager,
    IDeviceSessionService deviceSessions) : IAccountStatusService
{
    /// <inheritdoc />
    public async Task<bool> SetActiveAsync(Guid accountId, bool isActive, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
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

        if (!isActive)
        {
            // Not cancellable: the account is already deactivated, its sessions must not outlive that.
            await deviceSessions.RevokeAllAsync(accountId, CancellationToken.None);
        }

        return true;
    }
}
