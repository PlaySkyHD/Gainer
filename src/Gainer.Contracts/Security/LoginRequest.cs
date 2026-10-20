using System.ComponentModel.DataAnnotations;

namespace Gainer.Contracts.Security;

/// <summary>Credentials for an existing, privately provisioned account and the signing-in device.</summary>
public sealed record LoginRequest(
    [Required, EmailAddress, StringLength(254)] string Email,
    [Required, StringLength(256)] string Password,
    [StringLength(100)] string? DeviceName = null);
