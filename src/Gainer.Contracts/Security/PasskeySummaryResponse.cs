namespace Gainer.Contracts.Security;

/// <summary>A passkey registered for the signed-in account; the id is the Base64Url credential id.</summary>
public sealed record PasskeySummaryResponse(string Id, string Name, DateTimeOffset CreatedAt);
