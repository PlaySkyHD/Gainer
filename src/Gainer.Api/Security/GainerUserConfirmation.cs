using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;

namespace Gainer.Api.Security;

internal sealed class GainerUserConfirmation : IUserConfirmation<AppUser>
{
    public Task<bool> IsConfirmedAsync(UserManager<AppUser> manager, AppUser user) =>
        Task.FromResult(user.EmailConfirmed && user.IsActive);
}
