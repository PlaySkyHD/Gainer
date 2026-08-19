using System.ComponentModel.DataAnnotations;

namespace Gainer.Contracts.Security;

/// <summary>Requests a manually shareable invitation for an email address.</summary>
public sealed record CreateInvitationRequest(
    [Required, EmailAddress, StringLength(254)] string Email);
