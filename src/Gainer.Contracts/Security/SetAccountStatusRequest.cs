namespace Gainer.Contracts.Security;

/// <summary>Activates or deactivates an Identity account.</summary>
public sealed record SetAccountStatusRequest(bool IsActive);
