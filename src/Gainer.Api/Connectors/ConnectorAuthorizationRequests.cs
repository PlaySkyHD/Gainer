using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;

namespace Gainer.Api.Connectors;

/// <summary>A validated authorization request while the owner decides on the consent page.</summary>
public sealed record ConnectorAuthorizationRequest(
    string ClientId,
    string ClientName,
    string RedirectUri,
    string? State,
    string CodeChallenge);

/// <summary>
/// Carries the request through the consent page as a protected, time-limited document, so the
/// page needs neither a cookie nor server-side state.
/// </summary>
public sealed class ConnectorAuthorizationRequests(IDataProtectionProvider dataProtection, TimeProvider timeProvider)
{
    /// <summary>How long the owner has to approve.</summary>
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);

    private readonly ITimeLimitedDataProtector protector = dataProtection
        .CreateProtector("Gainer.Connectors.AuthorizationRequest.v1")
        .ToTimeLimitedDataProtector();

    public string Protect(ConnectorAuthorizationRequest request) =>
        protector.Protect(JsonSerializer.Serialize(request), timeProvider.GetUtcNow() + Lifetime);

    /// <summary>Reads the request back; null when it is foreign, altered, or expired.</summary>
    public ConnectorAuthorizationRequest? Unprotect(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        try
        {
            string json = protector.Unprotect(value, out DateTimeOffset expiration);
            return expiration > timeProvider.GetUtcNow()
                ? JsonSerializer.Deserialize<ConnectorAuthorizationRequest>(json)
                : null;
        }
        catch (CryptographicException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
