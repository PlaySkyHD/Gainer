using System.Security.Cryptography;
using System.Text;
using Gainer.Core.Access;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Stable invitation timing and token settings.</summary>
public static class AccountInvitationOptions
{
    /// <summary>Lifetime of a newly issued invitation.</summary>
    public static readonly TimeSpan Lifetime = TimeSpan.FromDays(3);

    internal const int TokenBytes = 32;
}

internal sealed class AccountInvitationService(
    AppDbContext database,
    UserManager<AppUser> userManager,
    TimeProvider timeProvider) : IAccountInvitationService
{
    public async Task<IssuedAccountInvitation> IssueAsync(
        string email,
        CancellationToken cancellationToken = default)
    {
        string normalizedEmail = email.Trim();
        await using IDbContextTransaction transaction = await database.Database.BeginTransactionAsync(
            cancellationToken);
        AppUser? user = await userManager.FindByEmailAsync(normalizedEmail);
        if (user is not null && (user.EmailConfirmed || await userManager.HasPasswordAsync(user)))
        {
            throw new AccountInvitationCannotBeIssuedException();
        }

        if (user is null)
        {
            user = new AppUser
            {
                Id = Guid.NewGuid(),
                UserName = normalizedEmail,
                Email = normalizedEmail,
                EmailConfirmed = false,
                IsActive = false,
            };
            IdentityResult created = await userManager.CreateAsync(user);
            if (!created.Succeeded)
            {
                throw new AccountInvitationCannotBeIssuedException();
            }
        }

        string token = CreateToken();
        byte[] tokenHash = HashToken(token);
        DateTimeOffset now = timeProvider.GetUtcNow();
        DateTimeOffset expiresAt = now + AccountInvitationOptions.Lifetime;
        AccountInvitation? invitation = await database.AccountInvitations
            .SingleOrDefaultAsync(item => item.UserId == user.Id, cancellationToken);
        if (invitation is null)
        {
            invitation = new AccountInvitation
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                Version = 1,
            };
            database.AccountInvitations.Add(invitation);
        }
        else
        {
            invitation.Version++;
        }

        invitation.TokenHash = tokenHash;
        invitation.CreatedAt = now;
        invitation.ExpiresAt = expiresAt;
        invitation.UsedAt = null;
        await database.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new IssuedAccountInvitation(token, expiresAt);
    }

    public async Task<AccountInvitationAcceptanceResult> AcceptAsync(
        string token,
        string password,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return AccountInvitationAcceptanceResult.InvalidInvitation;
        }

        byte[] tokenHash = HashToken(token.Trim());
        await using IDbContextTransaction transaction = await database.Database.BeginTransactionAsync(
            cancellationToken);
        AccountInvitation? invitation = await database.AccountInvitations
            .SingleOrDefaultAsync(item => item.TokenHash == tokenHash, cancellationToken);
        DateTimeOffset now = timeProvider.GetUtcNow();
        if (invitation is null || invitation.UsedAt is not null || invitation.ExpiresAt <= now)
        {
            return AccountInvitationAcceptanceResult.InvalidInvitation;
        }

        invitation.UsedAt = now;
        invitation.Version++;
        try
        {
            await database.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            await transaction.RollbackAsync(cancellationToken);
            return AccountInvitationAcceptanceResult.InvalidInvitation;
        }

        AppUser? user = await userManager.FindByIdAsync(invitation.UserId.ToString());
        if (user is null || user.EmailConfirmed || await userManager.HasPasswordAsync(user))
        {
            await transaction.RollbackAsync(cancellationToken);
            return AccountInvitationAcceptanceResult.InvalidInvitation;
        }

        IdentityResult passwordResult = await userManager.AddPasswordAsync(user, password);
        if (!passwordResult.Succeeded)
        {
            await transaction.RollbackAsync(cancellationToken);
            return AccountInvitationAcceptanceResult.InvalidPassword;
        }

        user.EmailConfirmed = true;
        user.IsActive = true;
        IdentityResult activationResult = await userManager.UpdateAsync(user);
        if (!activationResult.Succeeded)
        {
            await transaction.RollbackAsync(cancellationToken);
            return AccountInvitationAcceptanceResult.InvalidInvitation;
        }

        await transaction.CommitAsync(cancellationToken);
        return AccountInvitationAcceptanceResult.Accepted;
    }

    private static string CreateToken() =>
        Microsoft.AspNetCore.WebUtilities.WebEncoders.Base64UrlEncode(
            RandomNumberGenerator.GetBytes(AccountInvitationOptions.TokenBytes));

    private static byte[] HashToken(string token) => SHA256.HashData(Encoding.UTF8.GetBytes(token));
}
