using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class ModelSnapshotTests
{
    [TestMethod]
    public void ModelSnapshotMatchesTheCurrentModel()
    {
        // The design-time factory needs no database: HasPendingModelChanges only compares the model with the snapshot.
        using AppDbContext context = new AppDbContextFactory().CreateDbContext([]);

        Assert.IsFalse(
            context.Database.HasPendingModelChanges(),
            "The EF model differs from AppDbContextModelSnapshot. Add a migration with 'dotnet ef migrations add'.");
    }
}
