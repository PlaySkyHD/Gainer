using System.Text.Json;
using Gainer.Contracts.Coach;

namespace Gainer.Contracts.Sync;

public static class AccountExportFormat
{
    public const string Name = "gainer-account-export";
    public const int SchemaVersion = 1;
}

public sealed record AccountExportResourceResponse(
    string ResourceType,
    Guid ResourceId,
    long Version,
    JsonElement Snapshot);

/// <summary>
/// The account export file. <see cref="CoachMemories" /> was added later without a new schema version:
/// readers of schema version 1 that do not know the field can ignore it.
/// </summary>
public sealed record AccountExportResponse(
    string Format,
    int SchemaVersion,
    int SyncProtocolVersion,
    DateTimeOffset ExportedAtUtc,
    long AsOfRevision,
    IReadOnlyList<AccountExportResourceResponse> Resources,
    IReadOnlyList<CoachMemoryResponse>? CoachMemories = null);
