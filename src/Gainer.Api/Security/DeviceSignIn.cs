using Gainer.Contracts.Security;
using Gainer.Core.Access;
using Gainer.Infrastructure.Persistence;

namespace Gainer.Api.Security;

/// <summary>Turns an authenticated account into a device session and its token pair.</summary>
public sealed class DeviceSignIn(IDeviceSessionService deviceSessions, AccessTokenIssuer accessTokens)
{
    private const string DefaultDeviceName = "Gainer";

    /// <summary>Starts a new device session.</summary>
    public async Task<TokenResponse> StartAsync(AppUser user, string? deviceName, CancellationToken cancellationToken)
    {
        IssuedDeviceSession session = await deviceSessions.CreateAsync(
            user.Id,
            deviceName ?? DefaultDeviceName,
            cancellationToken);
        return await TokensAsync(user, session);
    }

    /// <summary>Issues the token pair for an existing, just rotated session.</summary>
    public async Task<TokenResponse> TokensAsync(AppUser user, IssuedDeviceSession session)
    {
        string accessToken = await accessTokens.IssueAsync(user, session.SessionId);
        return new TokenResponse(accessToken, accessTokens.LifetimeSeconds, session.RefreshToken, session.ExpiresAt);
    }
}
