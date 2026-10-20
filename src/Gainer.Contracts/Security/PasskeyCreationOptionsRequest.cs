using System.ComponentModel.DataAnnotations;

namespace Gainer.Contracts.Security;

/// <summary>Confirms the account owner before a new passkey is created; not needed right after sign-in.</summary>
public sealed record PasskeyCreationOptionsRequest(
    [StringLength(256)] string? Password = null);
