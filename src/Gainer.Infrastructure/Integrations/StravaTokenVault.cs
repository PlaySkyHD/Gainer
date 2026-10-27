using System.Security.Cryptography;
using Gainer.Core.Integrations;
using Microsoft.AspNetCore.DataProtection;

namespace Gainer.Infrastructure.Integrations;

/// <summary>Encrypts Strava tokens at rest and refreshes the access token shortly before it expires.</summary>
public sealed class StravaTokenVault(IDataProtectionProvider dataProtection, IStravaApiClient strava, TimeProvider timeProvider)
{
    private static readonly TimeSpan RefreshMargin = TimeSpan.FromMinutes(5);
    private readonly IDataProtector protector = dataProtection.CreateProtector("Gainer.Strava.Tokens.v1");

    public void Store(StravaConnection connection, StravaTokens tokens)
    {
        connection.ProtectedAccessToken = protector.Protect(tokens.AccessToken);
        connection.ProtectedRefreshToken = protector.Protect(tokens.RefreshToken);
        connection.AccessTokenExpiresAtUtc = tokens.ExpiresAtUtc;
    }

    /// <summary>A valid access token; the caller saves the connection when the tokens changed.</summary>
    /// <exception cref="StravaApiException">With <see cref="StravaFailure.Unauthorized" /> when the tokens no longer work.</exception>
    public async Task<string> AccessTokenAsync(StravaConnection connection, CancellationToken cancellationToken)
    {
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        if (connection.AccessTokenExpiresAtUtc - RefreshMargin > utcNow)
        {
            return Unprotect(connection.ProtectedAccessToken);
        }
        StravaTokens tokens = await strava.RefreshAsync(Unprotect(connection.ProtectedRefreshToken), cancellationToken);
        Store(connection, tokens);
        connection.UpdatedAtUtc = utcNow;
        return tokens.AccessToken;
    }

    private string Unprotect(string value)
    {
        try
        {
            return protector.Unprotect(value);
        }
        catch (CryptographicException exception)
        {
            // Lost data-protection keys make the tokens unusable; the user has to connect again.
            throw new StravaApiException(StravaFailure.Unauthorized, "The stored Strava tokens cannot be read.", innerException: exception);
        }
    }
}
