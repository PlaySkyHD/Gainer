using System.Security.Cryptography;
using Gainer.Core.Access;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Lifetime settings of mobile device sessions, bound from <c>Security:DeviceSessions</c>.</summary>
public sealed class DeviceSessionOptions
{
    /// <summary>Configuration section of these settings.</summary>
    public const string SectionName = "Security:DeviceSessions";

    internal const int TokenBytes = 32;

    internal const int MaximumDeviceNameLength = 100;

    /// <summary>A session expires after this long without a refresh.</summary>
    public TimeSpan IdleLifetime { get; set; } = TimeSpan.FromDays(60);

    /// <summary>Optional upper bound from sign-in; unlimited when unset.</summary>
    public TimeSpan? AbsoluteLifetime { get; set; }

    /// <summary>How long the token replaced by the last rotation is still accepted, for responses lost in transit.</summary>
    public TimeSpan ReuseGracePeriod { get; set; } = TimeSpan.FromMinutes(1);
}

internal sealed class DeviceSessionService(
    AppDbContext database,
    IOptions<DeviceSessionOptions> options,
    TimeProvider timeProvider) : IDeviceSessionService
{
    private readonly DeviceSessionOptions settings = options.Value;

    public async Task<IssuedDeviceSession> CreateAsync(
        Guid userId,
        string deviceName,
        CancellationToken cancellationToken = default)
    {
        DateTimeOffset now = timeProvider.GetUtcNow();
        await database.DeviceSessions
            .Where(item => item.UserId == userId && (item.RevokedAt != null || item.ExpiresAt <= now))
            .ExecuteDeleteAsync(cancellationToken);

        string token = CreateToken();
        var session = new DeviceSession
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DeviceName = NormalizeDeviceName(deviceName),
            RefreshTokenHash = HashToken(token),
            CreatedAt = now,
            LastUsedAt = now,
            Version = 1,
        };
        session.ExpiresAt = NextExpiry(session, now);
        database.DeviceSessions.Add(session);
        await database.SaveChangesAsync(cancellationToken);
        return new IssuedDeviceSession(session.Id, userId, token, session.ExpiresAt);
    }

    public async Task<DeviceSessionRefreshResult> RefreshAsync(
        string refreshToken,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(refreshToken))
        {
            return new DeviceSessionRefreshResult(DeviceSessionRefreshStatus.Invalid);
        }

        byte[] presentedHash = HashToken(refreshToken.Trim());
        DeviceSession? session = await database.DeviceSessions
            .Include(item => item.User)
            .SingleOrDefaultAsync(
                item => item.RefreshTokenHash == presentedHash
                    || item.PreviousRefreshTokenHash == presentedHash
                    || item.DiscardedRefreshTokenHash == presentedHash,
                cancellationToken);
        DateTimeOffset now = timeProvider.GetUtcNow();
        if (session is null
            || session.RevokedAt is not null
            || session.ExpiresAt <= now
            || !session.User.IsActive
            || !session.User.EmailConfirmed)
        {
            return new DeviceSessionRefreshResult(DeviceSessionRefreshStatus.Invalid);
        }

        bool presentedCurrent = CryptographicOperations.FixedTimeEquals(session.RefreshTokenHash, presentedHash);
        if (!presentedCurrent && !IsGraceRetry(session, presentedHash, now))
        {
            // An old or discarded token came back: either copy may be stolen.
            session.RevokedAt = now;
            session.Version++;
            await SaveIgnoringConcurrencyAsync(cancellationToken);
            return new DeviceSessionRefreshResult(DeviceSessionRefreshStatus.ReuseDetected);
        }

        // Within the grace period the previous token stays the reference, so a client whose
        // response was lost can retry once. The token from the lost response is remembered: if it
        // shows up later, someone else used the previous token and the session is revoked.
        string token = CreateToken();
        if (presentedCurrent)
        {
            session.PreviousRefreshTokenHash = session.RefreshTokenHash;
            session.RotatedAt = now;
            session.DiscardedAt = null;
        }
        else
        {
            session.DiscardedRefreshTokenHash = session.RefreshTokenHash;
            session.DiscardedAt = now;
        }

        session.RefreshTokenHash = HashToken(token);
        session.LastUsedAt = now;
        session.ExpiresAt = NextExpiry(session, now);
        session.Version++;
        if (!await SaveIgnoringConcurrencyAsync(cancellationToken))
        {
            return new DeviceSessionRefreshResult(DeviceSessionRefreshStatus.Invalid);
        }

        return new DeviceSessionRefreshResult(
            DeviceSessionRefreshStatus.Refreshed,
            new IssuedDeviceSession(session.Id, session.UserId, token, session.ExpiresAt));
    }

    public Task<bool> IsActiveAsync(
        Guid sessionId,
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        DateTimeOffset now = timeProvider.GetUtcNow();
        return database.DeviceSessions.AnyAsync(
            item => item.Id == sessionId
                && item.UserId == userId
                && item.RevokedAt == null
                && item.ExpiresAt > now
                && item.User.IsActive,
            cancellationToken);
    }

    public async Task RevokeAsync(
        Guid sessionId,
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        DateTimeOffset now = timeProvider.GetUtcNow();
        await database.DeviceSessions
            .Where(item => item.Id == sessionId && item.UserId == userId && item.RevokedAt == null)
            .ExecuteUpdateAsync(
                update => update
                    .SetProperty(item => item.RevokedAt, now)
                    .SetProperty(item => item.Version, item => item.Version + 1),
                cancellationToken);
    }

    public async Task RevokeAllAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        DateTimeOffset now = timeProvider.GetUtcNow();
        await database.DeviceSessions
            .Where(item => item.UserId == userId && item.RevokedAt == null)
            .ExecuteUpdateAsync(
                update => update
                    .SetProperty(item => item.RevokedAt, now)
                    .SetProperty(item => item.Version, item => item.Version + 1),
                cancellationToken);
    }

    private bool IsGraceRetry(DeviceSession session, byte[] presentedHash, DateTimeOffset now) =>
        session.PreviousRefreshTokenHash is byte[] previous
        && CryptographicOperations.FixedTimeEquals(previous, presentedHash)
        && session.RotatedAt is DateTimeOffset rotatedAt
        && now - rotatedAt <= settings.ReuseGracePeriod
        && session.DiscardedAt is null;

    private DateTimeOffset NextExpiry(DeviceSession session, DateTimeOffset now)
    {
        DateTimeOffset idleExpiry = now + settings.IdleLifetime;
        return settings.AbsoluteLifetime is TimeSpan absolute && session.CreatedAt + absolute < idleExpiry
            ? session.CreatedAt + absolute
            : idleExpiry;
    }

    private async Task<bool> SaveIgnoringConcurrencyAsync(CancellationToken cancellationToken)
    {
        try
        {
            await database.SaveChangesAsync(cancellationToken);
            return true;
        }
        catch (DbUpdateConcurrencyException)
        {
            return false;
        }
    }

    private static string NormalizeDeviceName(string deviceName)
    {
        string trimmed = deviceName.Trim();
        if (trimmed.Length == 0)
        {
            return "Gainer";
        }

        return trimmed.Length <= DeviceSessionOptions.MaximumDeviceNameLength
            ? trimmed
            : trimmed[..DeviceSessionOptions.MaximumDeviceNameLength];
    }

    private static string CreateToken() =>
        Microsoft.AspNetCore.WebUtilities.WebEncoders.Base64UrlEncode(
            RandomNumberGenerator.GetBytes(DeviceSessionOptions.TokenBytes));

    private static byte[] HashToken(string token) => SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token));
}
