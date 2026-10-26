using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Classifies database errors. Only a unique violation on a constraint that stands for a competing stored state of the
/// same user (a "one per user" index) is a conflict. Handlers look their own identifiers up under the user filter
/// before inserting, so a primary key violation means the identifier belongs to another user; that and every other
/// database error is left to <see cref="SyncMutationProcessor"/>, which reports it as a permanent payload error.
/// </summary>
internal static class PersistenceErrors
{
    public static PostgresException? FindPostgres(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            if (current is PostgresException postgres) return postgres;
        }
        return null;
    }

    /// <summary>True when <paramref name="exception"/> is a unique violation of a key of <typeparamref name="TEntity"/>.</summary>
    public static bool IsKeyViolation<TEntity>(this DbContext context, Exception exception)
        where TEntity : class =>
        UniqueConstraintName(exception) is { } name &&
        EntityType<TEntity>(context).GetKeys().Any(key => string.Equals(key.GetName(), name, StringComparison.Ordinal));

    /// <summary>True when <paramref name="exception"/> is a violation of the unique index of <typeparamref name="TEntity"/> on exactly these properties.</summary>
    public static bool IsUniqueIndexViolation<TEntity>(
        this DbContext context,
        Exception exception,
        params string[] propertyNames)
        where TEntity : class =>
        UniqueConstraintName(exception) is { } name &&
        EntityType<TEntity>(context).GetIndexes().Any(index =>
            index.IsUnique &&
            index.Properties.Select(property => property.Name).SequenceEqual(propertyNames, StringComparer.Ordinal) &&
            string.Equals(index.GetDatabaseName(), name, StringComparison.Ordinal));

    private static string? UniqueConstraintName(Exception exception) =>
        FindPostgres(exception) is { SqlState: PostgresErrorCodes.UniqueViolation } postgres ? postgres.ConstraintName : null;

    private static IEntityType EntityType<TEntity>(DbContext context) where TEntity : class =>
        context.Model.FindEntityType(typeof(TEntity))
            ?? throw new InvalidOperationException($"{typeof(TEntity).Name} is not part of the model.");
}
