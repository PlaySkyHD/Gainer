using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.WebUtilities;

namespace Gainer.Api.Connectors;

/// <summary>Proof Key for Code Exchange with the S256 method (RFC 7636).</summary>
public static partial class Pkce
{
    /// <summary>True for a well-formed S256 challenge: 43 base64url characters.</summary>
    public static bool IsValidChallenge(string? challenge) =>
        challenge is not null && ChallengePattern().IsMatch(challenge);

    /// <summary>True when the verifier is well-formed and hashes to the challenge.</summary>
    public static bool Verify(string? verifier, string challenge)
    {
        if (verifier is null || !VerifierPattern().IsMatch(verifier))
        {
            return false;
        }

        string computed = WebEncoders.Base64UrlEncode(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        return CryptographicOperations.FixedTimeEquals(
            Encoding.ASCII.GetBytes(computed),
            Encoding.ASCII.GetBytes(challenge));
    }

    [GeneratedRegex("^[A-Za-z0-9_-]{43}$")]
    private static partial Regex ChallengePattern();

    [GeneratedRegex("^[A-Za-z0-9._~-]{43,128}$")]
    private static partial Regex VerifierPattern();
}
