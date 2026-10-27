using System.Data.Common;
using System.Security.Cryptography;
using System.Text;
using Gainer.Core.Access;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

/// <summary>
/// Refreshes that race a parallel refresh of the same session. The parallel refresh runs and commits between the last
/// read and the first write of the racing one, the window in which a version conflict hits the slower request.
/// </summary>
[TestClass]
public sealed class DeviceSessionRaceTests
{
    private static readonly DateTimeOffset Start = new(2026, 8, 18, 12, 0, 0, TimeSpan.Zero);
    private static PostgreSqlTestFixture? fixture;
    private readonly MutableTimeProvider timeProvider = new(Start);
    private string connectionString = string.Empty;
    private Guid userId;

    private static PostgreSqlTestFixture Fixture =>
        fixture ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    [ClassInitialize]
    public static async Task StartPostgreSqlAsync(TestContext context)
    {
        _ = context;
        fixture = new PostgreSqlTestFixture();
        await fixture.StartAsync();
    }

    [ClassCleanup]
    public static async Task StopPostgreSqlAsync()
    {
        if (fixture is not null)
        {
            await fixture.DisposeAsync();
        }
    }

    [TestInitialize]
    public async Task CreateDatabaseAsync()
    {
        connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        userId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString);
        await context.Database.MigrateAsync(TestContext.CancellationToken);
        context.Users.Add(new AppUser
        {
            Id = userId,
            UserName = "athlete@example.test",
            NormalizedUserName = "ATHLETE@EXAMPLE.TEST",
            Email = "athlete@example.test",
            NormalizedEmail = "ATHLETE@EXAMPLE.TEST",
            EmailConfirmed = true,
            IsActive = true,
            SecurityStamp = Guid.NewGuid().ToString("N"),
            ConcurrencyStamp = Guid.NewGuid().ToString("N"),
        });
        await context.SaveChangesAsync(TestContext.CancellationToken);
    }

    [TestMethod]
    [DataRow(true, DisplayName = "discarded token")]
    [DataRow(false, DisplayName = "previous token after the grace period")]
    public async Task ReusedTokenRevokesTheSessionWhileTheDeviceRotates(bool discardedToken)
    {
        string first = await SignInAsync();
        string lost = await RefreshedAsync(first);
        string reused;
        string device;
        if (discardedToken)
        {
            device = await RefreshedAsync(first);
            reused = lost;
        }
        else
        {
            device = lost;
            reused = first;
            timeProvider.Advance(TimeSpan.FromHours(7));
        }

        string? rotated = null;
        DeviceSessionRefreshResult attacker = await RefreshAsync(reused, async () => rotated = await RefreshedAsync(device));

        Assert.AreEqual(DeviceSessionRefreshStatus.ReuseDetected, attacker.Status);
        Assert.IsNotNull(rotated);
        Assert.IsTrue(await IsRevokedAsync(), "The parallel rotation must not cancel the revocation.");
        Assert.AreEqual(DeviceSessionRefreshStatus.Invalid, (await RefreshAsync(rotated)).Status);
    }

    [TestMethod]
    [DataRow(true, DisplayName = "attacker reads first, device saves first")]
    [DataRow(false, DisplayName = "device reads first, attacker saves first")]
    public async Task ParallelGraceRetriesOfDeviceAndAttackerKeepTheWinnerAndALaterRetryStillRevokes(bool attackerReadsFirst)
    {
        string stolen = await SignInAsync();
        _ = await RefreshedAsync(stolen);
        timeProvider.Advance(TimeSpan.FromSeconds(20));

        // Both sides retry with the previous token; the server cannot tell them apart. The slower one loses the race
        // and leaves the session unchanged, so the winner's token stays current and works like a single grace retry.
        string? inner = null;
        DeviceSessionRefreshResult outer = await RefreshAsync(stolen, async () => inner = await RefreshedAsync(stolen));

        Assert.AreEqual(DeviceSessionRefreshStatus.Invalid, outer.Status);
        Assert.IsNotNull(inner);
        Assert.IsTrue(await IsCurrentAsync(inner), "The winning grace retry holds the current token.");
        Assert.IsFalse(await IsRevokedAsync());

        // The loser retries again in sequence, which discards the winner's token: its return reveals the second copy.
        string retried = await RefreshedAsync(stolen);
        string discardedHolder = attackerReadsFirst ? "device" : "attacker";
        Assert.AreEqual(
            DeviceSessionRefreshStatus.ReuseDetected,
            (await RefreshAsync(inner)).Status,
            $"The {discardedHolder}'s discarded token must revoke the session.");
        Assert.IsTrue(await IsRevokedAsync());
        Assert.AreEqual(DeviceSessionRefreshStatus.Invalid, (await RefreshAsync(retried)).Status);
    }

    [TestMethod]
    public async Task AbandonedRefreshThatLosesTheRaceKeepsTheTokenOfTheResentRefresh()
    {
        string first = await SignInAsync();
        string current = await RefreshedAsync(first);
        timeProvider.Advance(TimeSpan.FromMinutes(15));

        // The client gives up on the slow refresh and resends the same token; the resent one commits first.
        string? resent = null;
        DeviceSessionRefreshResult abandoned = await RefreshAsync(current, async () => resent = await RefreshedAsync(current));

        Assert.AreEqual(DeviceSessionRefreshStatus.Invalid, abandoned.Status);
        Assert.IsNotNull(resent);
        Assert.IsTrue(await IsCurrentAsync(resent), "The abandoned refresh must not discard the token the client keeps.");
        Assert.AreEqual(0, await CountDiscardedTokensAsync());
        Assert.AreEqual(DeviceSessionRefreshStatus.Refreshed, (await RefreshAsync(resent)).Status);
    }

    [TestMethod]
    [DataRow(true, DisplayName = "retry reads first, rotation saves first")]
    [DataRow(false, DisplayName = "rotation reads first, retry saves first")]
    public async Task RotationRacingAGraceRetryNeitherAcceptsAStaleTokenNorHidesReuse(bool retryReadsFirst)
    {
        string stolen = await SignInAsync();
        string device = await RefreshedAsync(stolen);
        timeProvider.Advance(TimeSpan.FromSeconds(20));

        if (retryReadsFirst)
        {
            // The device rotates between the attacker's read and save, so the attacker's token is no longer the previous.
            string? rotated = null;
            DeviceSessionRefreshResult attacker = await RefreshAsync(stolen, async () => rotated = await RefreshedAsync(device));

            Assert.AreEqual(DeviceSessionRefreshStatus.Invalid, attacker.Status);
            Assert.IsNotNull(rotated);
            Assert.IsTrue(await IsCurrentAsync(rotated), "The device's current token must not be discarded.");
            Assert.AreEqual(DeviceSessionRefreshStatus.Invalid, (await RefreshAsync(stolen)).Status);
            Assert.AreEqual(DeviceSessionRefreshStatus.Refreshed, (await RefreshAsync(rotated)).Status);
            return;
        }

        // The attacker's retry discards the device's token between the device's read and save.
        string? attackerToken = null;
        DeviceSessionRefreshResult deviceResult = await RefreshAsync(device, async () => attackerToken = await RefreshedAsync(stolen));

        Assert.AreEqual(DeviceSessionRefreshStatus.ReuseDetected, deviceResult.Status);
        Assert.IsNotNull(attackerToken);
        Assert.IsTrue(await IsRevokedAsync(), "The device's discarded token must revoke the session.");
        Assert.AreEqual(DeviceSessionRefreshStatus.Invalid, (await RefreshAsync(attackerToken)).Status);
    }

    [TestMethod]
    public async Task ParallelGraceRetriesWithTheSameTokenKeepTheWinnersToken()
    {
        string first = await SignInAsync();
        _ = await RefreshedAsync(first);
        timeProvider.Advance(TimeSpan.FromSeconds(20));

        // Both retries discard the same lost token, so the slower one hits the key of the discarded tokens or the
        // version. It is answered as invalid without an exception and without touching the winner's token.
        string? winner = null;
        DeviceSessionRefreshResult loser = await RefreshAsync(first, async () => winner = await RefreshedAsync(first));

        Assert.AreEqual(DeviceSessionRefreshStatus.Invalid, loser.Status);
        Assert.IsNotNull(winner);
        Assert.AreEqual(1, await CountDiscardedTokensAsync());
        Assert.IsTrue(await IsCurrentAsync(winner));
        Assert.AreEqual(DeviceSessionRefreshStatus.Refreshed, (await RefreshAsync(winner)).Status);
    }

    private async Task<string> SignInAsync()
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        IssuedDeviceSession session = await CreateService(context).CreateAsync(userId, "Test-iPhone", TestContext.CancellationToken);
        return session.RefreshToken;
    }

    private async Task<string> RefreshedAsync(string refreshToken)
    {
        DeviceSessionRefreshResult result = await RefreshAsync(refreshToken);
        Assert.AreEqual(DeviceSessionRefreshStatus.Refreshed, result.Status);
        return result.Session?.RefreshToken ?? throw new InvalidOperationException("The refresh issued no token.");
    }

    /// <summary>Refreshes; <paramref name="beforeFirstWrite"/> runs once after the last read, before the first write.</summary>
    private async Task<DeviceSessionRefreshResult> RefreshAsync(string refreshToken, Func<Task>? beforeFirstWrite = null)
    {
        IInterceptor[] interceptors = beforeFirstWrite is null ? [] : [new BeforeFirstWriteInterceptor(beforeFirstWrite)];
        await using AppDbContext context = PostgreSqlTestFixture.CreateContextWithInterceptors(connectionString, userId, interceptors);
        return await CreateService(context).RefreshAsync(refreshToken, TestContext.CancellationToken);
    }

    private DeviceSessionService CreateService(AppDbContext context) =>
        new(context, Options.Create(new DeviceSessionOptions()), timeProvider);

    private async Task<bool> IsRevokedAsync()
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        return await context.DeviceSessions.AnyAsync(
            item => item.UserId == userId && item.RevokedAt != null,
            TestContext.CancellationToken);
    }

    private async Task<bool> IsCurrentAsync(string refreshToken)
    {
        byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(refreshToken));
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        return await context.DeviceSessions.AnyAsync(
            item => item.UserId == userId && item.RevokedAt == null && item.RefreshTokenHash == hash,
            TestContext.CancellationToken);
    }

    private async Task<int> CountDiscardedTokensAsync()
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        return await context.DeviceSessionDiscardedTokens.CountAsync(TestContext.CancellationToken);
    }

    /// <summary>Runs an action once, right before the first command of the context that is not a query.</summary>
    private sealed class BeforeFirstWriteInterceptor(Func<Task> action) : DbCommandInterceptor
    {
        private bool fired;

        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(
            DbCommand command,
            CommandEventData eventData,
            InterceptionResult<DbDataReader> result,
            CancellationToken cancellationToken = default)
        {
            await FireBeforeWriteAsync(command);
            return result;
        }

        public override async ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(
            DbCommand command,
            CommandEventData eventData,
            InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            await FireBeforeWriteAsync(command);
            return result;
        }

        private async Task FireBeforeWriteAsync(DbCommand command)
        {
            if (fired || command.CommandText.TrimStart().StartsWith("SELECT", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            fired = true;
            await action();
        }
    }

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset currentUtc = utcNow;

        public override DateTimeOffset GetUtcNow() => currentUtc;

        public void Advance(TimeSpan duration)
        {
            currentUtc += duration;
        }
    }

    public TestContext TestContext { get; set; } = null!;
}
