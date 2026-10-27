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

    /// <summary>Grace-period retries allowed per rotation; one more revokes the session.</summary>
    internal const int MaximumGraceRetries = 10;

    /// <summary>Discarded tokens stored per session; a retry that would store one more revokes the session.</summary>
    internal const int MaximumStoredDiscardedTokens = 50;

    /// <summary>A session expires after this long without a refresh.</summary>
    public TimeSpan IdleLifetime { get; set; } = TimeSpan.FromDays(60);

    /// <summary>Optional upper bound from sign-in; unlimited when unset.</summary>
    public TimeSpan? AbsoluteLifetime { get; set; }

    /// <summary>
    /// How long the token replaced by the last rotation is still accepted, for responses lost in transit.
    /// Mobile clients may be backgrounded or offline for hours before they retry; older tokens never get a grace.
    /// </summary>
    public TimeSpan ReuseGracePeriod { get; set; } = TimeSpan.FromHours(6);
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
        DeviceSession? session = await FindSessionAsync(presentedHash, cancellationToken);
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
        if (!presentedCurrent && !await TryDiscardForRetryAsync(session, presentedHash, now, cancellationToken))
        {
            // An old or discarded token came back, or retries piled up: either copy may be stolen.
            session.RevokedAt = now;
            session.Version++;
            await SaveIgnoringConcurrencyAsync(cancellationToken);
            return new DeviceSessionRefreshResult(DeviceSessionRefreshStatus.ReuseDetected);
        }

        // Within the grace period the previous token stays the reference, so a client whose
        // response was lost can retry until the grace period ends or a retry limit is hit.
        // Each retry has discarded the last issued token and remembered it: the real device never
        // presents a discarded token again, so if one shows up, someone else used the previous
        // token and the session is revoked. Once the issued successor is used, the previous
        // token no longer qualifies.
        string token = CreateToken();
        if (presentedCurrent)
        {
            session.PreviousRefreshTokenHash = session.RefreshTokenHash;
            session.RotatedAt = now;
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

    public async Task<DateTimeOffset?> GetSignedInAtAsync(
        Guid sessionId,
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        DateTimeOffset now = timeProvider.GetUtcNow();
        return await database.DeviceSessions
            .Where(item => item.Id == sessionId
                && item.UserId == userId
                && item.RevokedAt == null
                && item.ExpiresAt > now)
            .Select(item => (DateTimeOffset?)item.CreatedAt)
            .SingleOrDefaultAsync(cancellationToken);
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

    /// <summary>
    /// Finds the session by its current or previous token. Only when neither matches, which a normal refresh never hits,
    /// a second query looks for a session that discarded the token.
    /// </summary>
    private async Task<DeviceSession?> FindSessionAsync(byte[] presentedHash, CancellationToken cancellationToken)
    {
        DeviceSession? session = await database.DeviceSessions
            .Include(item => item.User)
            .SingleOrDefaultAsync(
                item => item.RefreshTokenHash == presentedHash || item.PreviousRefreshTokenHash == presentedHash,
                cancellationToken);
        return session ?? await database.DeviceSessions
            .Include(item => item.User)
            .SingleOrDefaultAsync(
                item => item.DiscardedTokens.Any(discarded => discarded.TokenHash == presentedHash),
                cancellationToken);
    }

    private bool IsWithinGracePeriod(DeviceSession session, byte[] presentedHash, DateTimeOffset now) =>
        session.PreviousRefreshTokenHash is byte[] previous
        && CryptographicOperations.FixedTimeEquals(previous, presentedHash)
        && session.RotatedAt is DateTimeOffset rotatedAt
        && now - rotatedAt <= settings.ReuseGracePeriod;

    /// <summary>
    /// Accepts a grace-period retry by remembering the last issued token as discarded. Returns false, so the caller
    /// revokes the session, when the token is no grace retry or a limit is reached: at most
    /// <see cref="DeviceSessionOptions.MaximumGraceRetries"/> retries per rotation and
    /// <see cref="DeviceSessionOptions.MaximumStoredDiscardedTokens"/> stored tokens per session.
    /// </summary>
    private async Task<bool> TryDiscardForRetryAsync(
        DeviceSession session,
        byte[] presentedHash,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (!IsWithinGracePeriod(session, presentedHash, now))
        {
            return false;
        }

        await database.Entry(session).Collection(item => item.DiscardedTokens).LoadAsync(cancellationToken);

        // Discarded tokens stay revocation triggers through later rotations and retries; dropping them earlier would
        // let an attacker hide the device's token by rotating and retrying again. Only a token older than the idle
        // lifetime goes: the device holding it has not refreshed since it was discarded, so its session would have
        // expired anyway.
        session.DiscardedTokens.RemoveAll(item => now - item.DiscardedAt >= settings.IdleLifetime);
        DateTimeOffset rotatedAt = session.RotatedAt.GetValueOrDefault();
        if (session.DiscardedTokens.Count(item => item.DiscardedAt >= rotatedAt) >= DeviceSessionOptions.MaximumGraceRetries
            || session.DiscardedTokens.Count >= DeviceSessionOptions.MaximumStoredDiscardedTokens)
        {
            return false;
        }

        session.DiscardedTokens.Add(new DeviceSessionDiscardedToken
        {
            SessionId = session.Id,
            TokenHash = session.RefreshTokenHash,
            DiscardedAt = now,
        });
        return true;
    }

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
        catch (DbUpdateException exception) when (database.IsKeyViolation<DeviceSessionDiscardedToken>(exception))
        {
            // A parallel retry already discarded the same token.
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
