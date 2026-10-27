namespace Gainer.Core.Mutations;

/// <summary>Describes every aggregate version checked by one atomic mutation.</summary>
public sealed class AtomicMutationScope
{
    private AtomicMutationScope(IReadOnlyList<ResourceVersionExpectation> resources)
    {
        Resources = resources;
    }

    /// <summary>Gets the resources that must be changed in one transaction.</summary>
    public IReadOnlyList<ResourceVersionExpectation> Resources { get; }

    /// <summary>Creates a non-empty scope without duplicate resources.</summary>
    public static AtomicMutationScope Create(params ResourceVersionExpectation[] resources)
    {
        ArgumentNullException.ThrowIfNull(resources);
        if (resources.Length == 0)
        {
            throw new ArgumentException("A mutation must target at least one resource.", nameof(resources));
        }

        bool hasDuplicates = resources.Select(resource => resource.Resource).Distinct().Count() != resources.Length;
        return !hasDuplicates
            ? new AtomicMutationScope(Array.AsReadOnly(resources.ToArray()))
            : throw new ArgumentException("A mutation scope cannot repeat a resource.", nameof(resources));
    }
}

/// <summary>Pairs an aggregate with the version on which a mutation is based.</summary>
public sealed record ResourceVersionExpectation
{
    private ResourceVersionExpectation(ResourceKey resource, long baseVersion)
    {
        Resource = resource;
        BaseVersion = baseVersion;
    }

    public ResourceKey Resource { get; }
    public long BaseVersion { get; }

    /// <summary>Creates a version expectation; zero represents a resource creation.</summary>
    public static ResourceVersionExpectation Create(ResourceKey resource, long baseVersion)
    {
        ArgumentNullException.ThrowIfNull(resource);
        return baseVersion >= 0
            ? new ResourceVersionExpectation(resource, baseVersion)
            : throw new ArgumentOutOfRangeException(nameof(baseVersion));
    }
}

/// <summary>Marks a concrete command as a typed atomic mutation.</summary>
public interface ITypedMutation
{
    MutationMetadata Metadata { get; }
    AtomicMutationScope Scope { get; }
}
