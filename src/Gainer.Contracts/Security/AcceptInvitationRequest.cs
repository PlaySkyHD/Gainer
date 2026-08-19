using System.ComponentModel.DataAnnotations;

namespace Gainer.Contracts.Security;

/// <summary>Activates the account bound to a valid single-use invitation.</summary>
public sealed record AcceptInvitationRequest(
    [Required, StringLength(256, MinimumLength = 1)] string Token,
    [Required, StringLength(256)] string Password);
