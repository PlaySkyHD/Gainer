using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class PersistenceModelTests
{
    private static readonly string[] ExpectedSchemaNames = ["identity", "tracking", "training", "sync", "ai", "integrations"];

    [TestMethod]
    public void IdentityModelUsesDedicatedPostgresSchemaAndGuidKeys()
    {
        using var context = CreateContext(Guid.NewGuid());
        IEntityType user = context.Model.FindEntityType(typeof(AppUser))
            ?? throw new InvalidOperationException("The identity user is not mapped.");

        Assert.AreEqual(DatabaseSchemas.Identity, user.GetSchema());
        Assert.AreEqual("users", user.GetTableName());
        Assert.AreEqual("uuid", user.FindProperty(nameof(AppUser.Id))?.GetColumnType());
        Assert.AreSequenceEqual(
            ExpectedSchemaNames, DatabaseSchemas.All.ToArray(), SequenceOrder.InAnyOrder);
    }

    [TestMethod]
    public void PersistenceConventionsMapOwnershipVersionsAndCalendarTypes()
    {
        using var context = CreateContext(Guid.NewGuid());
        IEntityType probe = context.Model.FindEntityType(typeof(PersistenceConventionProbe))
            ?? throw new InvalidOperationException("The convention probe is not mapped.");

        AssertProperty(probe, nameof(PersistenceConventionProbe.Id), "uuid", isNullable: false);
        AssertProperty(probe, nameof(PersistenceConventionProbe.UserId), "uuid", isNullable: false);
        AssertProperty(probe, nameof(PersistenceConventionProbe.Version), "bigint", isNullable: false);
        Assert.IsTrue(probe.FindProperty(nameof(PersistenceConventionProbe.Version))?.IsConcurrencyToken);
        AssertProperty(
            probe,
            nameof(PersistenceConventionProbe.OccurredAtUtc),
            "timestamp with time zone",
            isNullable: false);
        AssertProperty(probe, nameof(PersistenceConventionProbe.LocalDate), "date", isNullable: false);
    }

    [TestMethod]
    public void PersistenceRejectsNonUtcTimestampsBeforeDatabaseAccess()
    {
        HostApplicationBuilder builder = Host.CreateApplicationBuilder();
        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:gainer-db"] =
                "Host=localhost;Database=gainer_model_tests;Username=test;Password=test",
        });
        builder.Services.AddScoped<IUserContext>(_ => new StubUserContext(Guid.NewGuid()));
        builder.AddGainerPersistence();
        using IHost host = builder.Build();
        using IServiceScope scope = host.Services.CreateScope();
        AppDbContext context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        context.Users.Add(new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = "utc-check",
            LockoutEnd = new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.FromHours(2)),
        });

        InvalidOperationException exception = Assert.Throws<InvalidOperationException>(() =>
        {
            context.SaveChanges();
        });

        Assert.Contains(nameof(AppUser.LockoutEnd), exception.Message);
    }

    [TestMethod]
    public void UserOwnedQueriesAreFilteredByTheCurrentUser()
    {
        Guid firstUserId = Guid.NewGuid();
        Guid secondUserId = Guid.NewGuid();
        using var firstContext = CreateContext(firstUserId);
        using var secondContext = CreateContext(secondUserId);

        string firstQuery = firstContext.Set<PersistenceConventionProbe>().ToQueryString();
        string secondQuery = secondContext.Set<PersistenceConventionProbe>().ToQueryString();

        Assert.Contains(firstUserId.ToString(), firstQuery);
        Assert.Contains(secondUserId.ToString(), secondQuery);
        Assert.Contains("WHERE", firstQuery);
        Assert.Contains(nameof(IUserOwnedEntity.UserId), firstQuery);
    }

    [TestMethod]
    public void OwnershipInterceptorAssignsNewEntitiesToTheCurrentUser()
    {
        Guid currentUserId = Guid.NewGuid();
        using var context = CreateContext(currentUserId);
        var entity = new PersistenceConventionProbe { Id = Guid.NewGuid() };
        context.Add(entity);
        var interceptor = new UserOwnershipInterceptor(new StubUserContext(currentUserId));

        interceptor.ApplyOwnership(context);

        Assert.AreEqual(currentUserId, entity.UserId);
    }

    [TestMethod]
    public void OwnershipInterceptorRejectsForeignAndAnonymousWrites()
    {
        Guid currentUserId = Guid.NewGuid();
        using var foreignContext = CreateContext(currentUserId);
        var foreignEntity = new PersistenceConventionProbe { Id = Guid.NewGuid() };
        foreignContext.Add(foreignEntity);
        foreignContext.Entry(foreignEntity).Property(entity => entity.UserId).CurrentValue = Guid.NewGuid();
        var authenticatedInterceptor = new UserOwnershipInterceptor(new StubUserContext(currentUserId));

        Assert.Throws<UserIsolationViolationException>(() =>
            authenticatedInterceptor.ApplyOwnership(foreignContext));

        using var anonymousContext = CreateContext(userId: null);
        anonymousContext.Add(new PersistenceConventionProbe { Id = Guid.NewGuid() });
        var anonymousInterceptor = new UserOwnershipInterceptor(new StubUserContext(UserId: null));
        Assert.Throws<UserIsolationViolationException>(() =>
            anonymousInterceptor.ApplyOwnership(anonymousContext));
    }

    private static ConventionTestDbContext CreateContext(Guid? userId)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql("Host=localhost;Database=gainer_model_tests;Username=test;Password=test")
            .Options;
        return new ConventionTestDbContext(options, new StubUserContext(userId));
    }

    private static void AssertProperty(
        IEntityType entityType,
        string propertyName,
        string columnType,
        bool isNullable)
    {
        IProperty property = entityType.FindProperty(propertyName)
            ?? throw new InvalidOperationException($"Property '{propertyName}' is not mapped.");
        Assert.AreEqual(columnType, property.GetColumnType());
        Assert.AreEqual(isNullable, property.IsNullable);
    }

    private sealed class ConventionTestDbContext(
        DbContextOptions<AppDbContext> options,
        IUserContext userContext) : AppDbContext(options, userContext)
    {
        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<PersistenceConventionProbe>()
                .ToTable("convention_probes", DatabaseSchemas.Tracking);
            base.OnModelCreating(modelBuilder);
        }
    }

    private sealed class PersistenceConventionProbe : UserOwnedEntity
    {
        public Guid Id { get; init; }
        public long Version { get; init; }
        public DateTime OccurredAtUtc { get; init; }
        public DateOnly LocalDate { get; init; }
    }

    private sealed record StubUserContext(Guid? UserId) : IUserContext;
}
