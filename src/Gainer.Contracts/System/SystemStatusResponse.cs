namespace Gainer.Contracts.System;

/// <summary>Describes the active API contract without exposing runtime internals.</summary>
/// <param name="Status">The API status.</param>
/// <param name="ApiVersion">The active HTTP contract version.</param>
public sealed record SystemStatusResponse(string Status, string ApiVersion);
