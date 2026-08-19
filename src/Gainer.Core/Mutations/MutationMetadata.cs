namespace Gainer.Core.Mutations;

/// <summary>Identifies a client mutation without accepting a client-selected user.</summary>
public sealed record MutationMetadata
{
    private MutationMetadata(Guid mutationId, Guid clientId, long clientSequence)
    {
        MutationId = mutationId;
        ClientId = clientId;
        ClientSequence = clientSequence;
    }

    public Guid MutationId { get; }
    public Guid ClientId { get; }
    public long ClientSequence { get; }

    /// <summary>Creates validated mutation metadata.</summary>
    public static MutationMetadata Create(Guid mutationId, Guid clientId, long clientSequence)
    {
        if (mutationId == Guid.Empty || clientId == Guid.Empty)
        {
            throw new ArgumentException("Mutation and client identifiers cannot be empty.");
        }

        return clientSequence > 0
            ? new MutationMetadata(mutationId, clientId, clientSequence)
            : throw new ArgumentOutOfRangeException(nameof(clientSequence));
    }
}
