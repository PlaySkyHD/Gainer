using Gainer.Core.Security;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

internal abstract class UserScopedRepository<TEntity>(AppDbContext context) : IUserScopedRepository
    where TEntity : class, IUserOwnedEntity
{
    protected IQueryable<TEntity> OwnedEntities => context.Set<TEntity>();

    protected DbSet<TEntity> TrackedEntities => context.Set<TEntity>();
}
