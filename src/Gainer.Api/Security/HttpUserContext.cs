using System.Security.Claims;
using Gainer.Core.Security;

namespace Gainer.Api.Security;

internal sealed class HttpUserContext(IHttpContextAccessor httpContextAccessor) : IUserContext
{
    public Guid? UserId
    {
        get
        {
            string? identifier = httpContextAccessor.HttpContext?.User.FindFirstValue(ClaimTypes.NameIdentifier);
            return Guid.TryParse(identifier, out Guid userId) && userId != Guid.Empty ? userId : null;
        }
    }
}
