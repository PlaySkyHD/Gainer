using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Caching.Memory;

namespace Gainer.Api.Connectors;

/// <summary>What an authorization code grants once it is redeemed.</summary>
public sealed record ConnectorAuthorizationGrant(
    Guid UserId,
    string ClientId,
    string ClientName,
    string RedirectUri,
    string CodeChallenge);

/// <summary>
/// One-time authorization codes with a short lifetime. They live in memory: the API runs as one
/// instance, and a restart only means approving again.
/// </summary>
public sealed class ConnectorAuthorizationCodes(IMemoryCache cache)
{
    /// <summary>How long a code may be redeemed.</summary>
    public static readonly TimeSpan Lifetime = TimeSpan.FromSeconds(60);

    private readonly Lock gate = new();

    public string Issue(ConnectorAuthorizationGrant grant)
    {
        string code = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        cache.Set(Key(code), grant, Lifetime);
        return code;
    }

    /// <summary>Returns the grant and removes it, so a second redemption fails.</summary>
    public ConnectorAuthorizationGrant? Redeem(string? code)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            return null;
        }

        string key = Key(code);
        lock (gate)
        {
            if (!cache.TryGetValue(key, out ConnectorAuthorizationGrant? grant))
            {
                return null;
            }

            cache.Remove(key);
            return grant;
        }
    }

    private static string Key(string code) =>
        "connector-code:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(code)));
}
