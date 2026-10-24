using System.Text.Json;

namespace Gainer.Core.Sync;

/// <summary>Current snapshot of one resource in an account export.</summary>
public sealed record AccountExportResource(
    string ResourceType,
    Guid ResourceId,
    long Version,
    JsonElement Snapshot);

/// <summary>All existing resources of the current user as of one server revision.</summary>
public sealed record AccountDataExport(
    long AsOfRevision,
    IReadOnlyList<AccountExportResource> Resources);

/// <summary>Builds the data export of the authenticated user from the sync change feed.</summary>
public interface IAccountDataExport
{
    Task<AccountDataExport> ExportAsync(CancellationToken cancellationToken = default);
}
