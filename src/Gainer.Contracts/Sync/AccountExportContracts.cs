using System.Text.Json;

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

public sealed record AccountExportResponse(
    string Format,
    int SchemaVersion,
    int SyncProtocolVersion,
    DateTimeOffset ExportedAtUtc,
    long AsOfRevision,
    IReadOnlyList<AccountExportResourceResponse> Resources);
