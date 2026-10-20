namespace Gainer.Contracts.Security;

/// <summary>
/// A bearer access token and the rotating refresh token of a device session. The refresh token
/// replaces any earlier one and is shown only in this response.
/// </summary>
public sealed record TokenResponse(
    string AccessToken,
    int ExpiresIn,
    string RefreshToken,
    DateTimeOffset RefreshTokenExpiresAt);
