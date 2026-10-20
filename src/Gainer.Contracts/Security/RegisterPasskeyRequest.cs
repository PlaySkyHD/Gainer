using System.ComponentModel.DataAnnotations;

namespace Gainer.Contracts.Security;

/// <summary>A new passkey created by the authenticator for the signed-in account.</summary>
public sealed record RegisterPasskeyRequest(
    [Required, StringLength(16_384, MinimumLength = 1)] string CredentialJson,
    [Required, StringLength(8_192, MinimumLength = 1)] string State,
    [StringLength(100)] string? Name = null);
