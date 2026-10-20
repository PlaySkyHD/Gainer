using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Caching.Memory;

namespace Gainer.Api.Security;

/// <summary>
/// Hands the passkey handler's ceremony state to the client encrypted, bound to the account and
/// ceremony type, valid for five minutes and accepted only once.
/// </summary>
public sealed class PasskeyCeremonyProtector(IDataProtectionProvider dataProtection, IMemoryCache usedStates)
{
    /// <summary>How long a ceremony may take from options to response.</summary>
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(5);

    /// <summary>Encrypts the state of a registration or sign-in ceremony.</summary>
    public string Protect(PasskeyCeremony ceremony, Guid? userId, string state)
    {
        string payload = JsonSerializer.Serialize(new CeremonyPayload(userId, state));
        return Protector(ceremony).Protect(payload, Lifetime);
    }

    /// <summary>Returns the state if the token is authentic, unexpired, unused, and for this account.</summary>
    public bool TryConsume(PasskeyCeremony ceremony, Guid? userId, string token, out string state)
    {
        state = string.Empty;
        CeremonyPayload? payload;
        try
        {
            payload = JsonSerializer.Deserialize<CeremonyPayload>(Protector(ceremony).Unprotect(token));
        }
        catch (Exception exception) when (exception is CryptographicException or JsonException or FormatException)
        {
            return false;
        }

        if (payload is null || payload.UserId != userId)
        {
            return false;
        }

        string key = "passkey-ceremony:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
        lock (usedStates)
        {
            if (usedStates.TryGetValue(key, out _))
            {
                return false;
            }

            usedStates.Set(key, true, Lifetime);
        }

        state = payload.State;
        return true;
    }

    private ITimeLimitedDataProtector Protector(PasskeyCeremony ceremony) =>
        dataProtection.CreateProtector("Gainer.Passkeys", ceremony.ToString()).ToTimeLimitedDataProtector();

    private sealed record CeremonyPayload(Guid? UserId, string State);
}

/// <summary>The two WebAuthn ceremonies.</summary>
public enum PasskeyCeremony
{
    /// <summary>Creating a passkey for a signed-in account.</summary>
    Registration,

    /// <summary>Signing in with an existing passkey.</summary>
    SignIn,
}
