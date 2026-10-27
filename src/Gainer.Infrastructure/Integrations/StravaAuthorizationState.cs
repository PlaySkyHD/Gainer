using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Caching.Memory;

namespace Gainer.Infrastructure.Integrations;

/// <summary>Issues and consumes the signed, short-lived, single-use state parameter of the Strava OAuth round trip.</summary>
public sealed class StravaAuthorizationState(IDataProtectionProvider dataProtection, IMemoryCache usedStates)
{
    private static readonly TimeSpan StateLifetime = TimeSpan.FromMinutes(10);

    private ITimeLimitedDataProtector StateProtector =>
        dataProtection.CreateProtector("Gainer.Strava.AuthorizationState.v1").ToTimeLimitedDataProtector();

    public string Issue(Guid userId)
    {
        string payload = JsonSerializer.Serialize(new StatePayload(userId, Convert.ToHexString(RandomNumberGenerator.GetBytes(16))));
        return StateProtector.Protect(payload, StateLifetime);
    }

    public bool TryConsume(string? state, out Guid userId)
    {
        userId = Guid.Empty;
        if (string.IsNullOrEmpty(state) || state.Length > 4_000) return false;
        StatePayload? payload;
        try
        {
            payload = JsonSerializer.Deserialize<StatePayload>(StateProtector.Unprotect(state));
        }
        catch (Exception exception) when (exception is CryptographicException or JsonException or FormatException)
        {
            return false;
        }
        if (payload is null || payload.UserId == Guid.Empty) return false;

        string key = "strava-state:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(state)));
        lock (usedStates)
        {
            if (usedStates.TryGetValue(key, out _)) return false;
            usedStates.Set(key, true, StateLifetime);
        }
        userId = payload.UserId;
        return true;
    }

    private sealed record StatePayload(Guid UserId, string Nonce);
}
