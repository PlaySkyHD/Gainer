namespace Gainer.Core.Mutations;

/// <summary>Provides the complete typed state emitted for an upsert change.</summary>
public interface IResourceSnapshot
{
    ResourceKey Resource { get; }
    long Version { get; }
}

/// <summary>Collects all changes that must be committed with one mutation.</summary>
public interface IChangeCollector
{
    IReadOnlyList<CapturedChange> Changes { get; }
    void CaptureUpsert(IResourceSnapshot snapshot);
    void CaptureDeletion(ResourceKey resource, long version);
}

/// <summary>Represents a typed resource change pending transactional persistence.</summary>
public abstract record CapturedChange(ResourceKey Resource, long Version);

/// <summary>Represents a complete resource snapshot.</summary>
public sealed record UpsertedResourceChange(IResourceSnapshot Snapshot)
    : CapturedChange(Snapshot.Resource, Snapshot.Version);

/// <summary>Represents a resource tombstone.</summary>
public sealed record DeletedResourceChange(ResourceKey Resource, long Version)
    : CapturedChange(Resource, Version);

/// <summary>Collects a mutation's changes while preventing ambiguous duplicates.</summary>
public sealed class ChangeCollector : IChangeCollector
{
    private readonly List<CapturedChange> changes = [];

    public IReadOnlyList<CapturedChange> Changes => changes.AsReadOnly();

    public void CaptureUpsert(IResourceSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        Add(new UpsertedResourceChange(snapshot));
    }

    public void CaptureDeletion(ResourceKey resource, long version)
    {
        ArgumentNullException.ThrowIfNull(resource);
        Add(new DeletedResourceChange(resource, version));
    }

    private void Add(CapturedChange change)
    {
        if (change.Version <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(change), "A captured version must be positive.");
        }

        if (changes.Any(existing => existing.Resource == change.Resource))
        {
            throw new InvalidOperationException("A mutation can capture each resource only once.");
        }

        changes.Add(change);
    }
}
