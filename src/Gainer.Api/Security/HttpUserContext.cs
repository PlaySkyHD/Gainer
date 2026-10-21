using System.Security.Claims;
using Gainer.Core.Security;
using Gainer.Infrastructure.Integrations;

namespace Gainer.Api.Security;

/// <summary>
/// The authenticated request user. Without one, the user a trusted server component bound to this
/// scope (<see cref="BackgroundUserScope" />), otherwise anonymous.
/// </summary>
internal sealed class HttpUserContext(IHttpContextAccessor httpContextAccessor, BackgroundUserScope backgroundUser) : IUserContext
{
    public Guid? UserId
    {
        get
        {
            string? identifier = httpContextAccessor.HttpContext?.User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (identifier is not null)
            {
                return Guid.TryParse(identifier, out Guid userId) && userId != Guid.Empty ? userId : null;
            }
            return backgroundUser.UserId;
        }
    }
}
