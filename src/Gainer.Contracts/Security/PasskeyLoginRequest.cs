using System.ComponentModel.DataAnnotations;

namespace Gainer.Contracts.Security;

/// <summary>A passkey assertion that signs the device in.</summary>
public sealed record PasskeyLoginRequest(
    [Required, StringLength(16_384, MinimumLength = 1)] string CredentialJson,
    [Required, StringLength(8_192, MinimumLength = 1)] string State,
    [StringLength(100)] string? DeviceName = null);
