using System.ComponentModel.DataAnnotations;

namespace Gainer.Contracts.Security;

/// <summary>A refresh token to exchange for a new token pair.</summary>
public sealed record RefreshTokenRequest(
    [Required, StringLength(256, MinimumLength = 1)] string RefreshToken);
