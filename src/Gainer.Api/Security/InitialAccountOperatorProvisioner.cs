using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Api.Security;

/// <summary>Result of the explicit initial account-operator provisioning step.</summary>
public enum InitialAccountOperatorProvisioningResult
{
    /// <summary>The first operator account was created.</summary>
    Created,

    /// <summary>An operator was already provisioned and no data changed.</summary>
    AlreadyProvisioned,
}

/// <summary>Creates the first operator account from an external secret.</summary>
public interface IInitialAccountOperatorProvisioner
{
    /// <summary>Provisions the account once or reports that it already exists.</summary>
    Task<InitialAccountOperatorProvisioningResult> ProvisionAsync(
        CancellationToken cancellationToken = default);
}

/// <summary>Configuration and command constants for initial operator provisioning.</summary>
public static class InitialAccountOperatorProvisioning
{
    /// <summary>Explicit process argument that runs provisioning instead of the API.</summary>
    public const string CommandArgument = "--provision-account-operator";

    /// <summary>Configuration key containing the path to the external JSON secret.</summary>
    public const string SecretPathConfigurationKey = "Provisioning:AccountOperatorSecretPath";

    /// <summary>Returns whether the process was explicitly started in provisioning mode.</summary>
    public static bool IsRequested(IEnumerable<string> arguments) =>
        arguments.Contains(CommandArgument, StringComparer.Ordinal);
}

/// <summary>Identity-only implementation of the initial provisioning boundary.</summary>
public sealed class InitialAccountOperatorProvisioner(
    UserManager<AppUser> userManager,
    RoleManager<IdentityRole<Guid>> roleManager,
    IConfiguration configuration) : IInitialAccountOperatorProvisioner
{
    private const long MaximumSecretFileBytes = 16 * 1024;

    /// <inheritdoc />
    public async Task<InitialAccountOperatorProvisioningResult> ProvisionAsync(
        CancellationToken cancellationToken = default)
    {
        if (await HasOperatorAsync())
        {
            return InitialAccountOperatorProvisioningResult.AlreadyProvisioned;
        }

        if (await userManager.Users.AnyAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "Initial account-operator provisioning requires an empty identity store.");
        }

        ProvisioningSecret secret = await ReadSecretAsync(cancellationToken);
        await EnsureRoleAsync();

        var user = new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = secret.Email,
            Email = secret.Email,
            EmailConfirmed = true,
            IsActive = true,
        };
        IdentityResult creation = await userManager.CreateAsync(user, secret.Password);
        EnsureSucceeded(creation, "The initial account-operator account could not be created.");

        IdentityResult roleAssignment = await userManager.AddToRoleAsync(
            user,
            AccountOperatorAuthorization.RoleName);
        if (!roleAssignment.Succeeded)
        {
            await userManager.DeleteAsync(user);
            EnsureSucceeded(roleAssignment, "The account-operator role could not be assigned.");
        }

        return InitialAccountOperatorProvisioningResult.Created;
    }

    private async Task<bool> HasOperatorAsync()
    {
        if (!await roleManager.RoleExistsAsync(AccountOperatorAuthorization.RoleName))
        {
            return false;
        }

        IList<AppUser> operators = await userManager.GetUsersInRoleAsync(
            AccountOperatorAuthorization.RoleName);
        return operators.Count > 0;
    }

    private async Task EnsureRoleAsync()
    {
        if (await roleManager.RoleExistsAsync(AccountOperatorAuthorization.RoleName))
        {
            return;
        }

        IdentityResult result = await roleManager.CreateAsync(
            new IdentityRole<Guid>(AccountOperatorAuthorization.RoleName));
        EnsureSucceeded(result, "The account-operator role could not be created.");
    }

    private async Task<ProvisioningSecret> ReadSecretAsync(CancellationToken cancellationToken)
    {
        string? configuredPath = configuration[
            InitialAccountOperatorProvisioning.SecretPathConfigurationKey];
        if (string.IsNullOrWhiteSpace(configuredPath))
        {
            throw new InvalidOperationException(
                "An external account-operator provisioning secret path is required.");
        }

        string path = Path.GetFullPath(configuredPath);
        await using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 4096,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        if (stream.Length == 0 || stream.Length > MaximumSecretFileBytes)
        {
            throw new InvalidOperationException("The account-operator provisioning secret is invalid.");
        }

        try
        {
            ProvisioningSecret? secret = await JsonSerializer.DeserializeAsync<ProvisioningSecret>(
                stream,
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true,
                    UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow,
                },
                cancellationToken);
            if (secret is null
                || !new EmailAddressAttribute().IsValid(secret.Email)
                || string.IsNullOrWhiteSpace(secret.Password))
            {
                throw new InvalidOperationException("The account-operator provisioning secret is invalid.");
            }

            return secret with { Email = secret.Email.Trim() };
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException(
                "The account-operator provisioning secret is invalid.",
                exception);
        }
    }

    private static void EnsureSucceeded(IdentityResult result, string message)
    {
        if (!result.Succeeded)
        {
            throw new InvalidOperationException(message);
        }
    }

    private sealed record ProvisioningSecret(string Email, string Password);
}
