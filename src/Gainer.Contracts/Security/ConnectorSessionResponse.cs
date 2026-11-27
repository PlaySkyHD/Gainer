namespace Gainer.Contracts.Security;

/// <summary>An external assistant connected to the account, e.g. ChatGPT.</summary>
/// <param name="Id">Identifier used to revoke the connection.</param>
/// <param name="Name">Name the assistant registered with.</param>
/// <param name="CreatedAt">When the owner approved the connection.</param>
/// <param name="LastUsedAt">When the assistant last renewed its access.</param>
public sealed record ConnectorSessionResponse(Guid Id, string Name, DateTimeOffset CreatedAt, DateTimeOffset LastUsedAt);
