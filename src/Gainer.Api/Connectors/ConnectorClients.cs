using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Options;

namespace Gainer.Api.Connectors;

/// <summary>A registered public OAuth client.</summary>
public sealed record ConnectorClient(string Name, IReadOnlyList<string> RedirectUris);

/// <summary>
/// Registers clients without storage: the client id is the protected client document itself, so the
/// authorization and token endpoints can read name and redirect URIs back from it.
/// </summary>
public sealed class ConnectorClientRegistry(IDataProtectionProvider dataProtection, IOptions<ConnectorOptions> options)
{
    /// <summary>Longest client name kept; longer names are cut.</summary>
    public const int MaximumNameLength = 60;

    /// <summary>Most redirect URIs a client may register.</summary>
    public const int MaximumRedirectUris = 5;

    private readonly IDataProtector protector = dataProtection.CreateProtector("Gainer.Connectors.Client.v1");

    /// <summary>Returns the client id for a validated client.</summary>
    public string Register(ConnectorClient client) => protector.Protect(JsonSerializer.Serialize(client));

    /// <summary>Reads a client id back; null when it was not issued by this server.</summary>
    public ConnectorClient? Find(string? clientId)
    {
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<ConnectorClient>(protector.Unprotect(clientId));
        }
        catch (CryptographicException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
    }

    /// <summary>True for absolute HTTPS URIs without user info or fragment on an allowed host.</summary>
    public bool IsAllowedRedirect(string? redirectUri) =>
        Uri.TryCreate(redirectUri, UriKind.Absolute, out Uri? uri)
        && uri.Scheme == Uri.UriSchemeHttps
        && string.IsNullOrEmpty(uri.UserInfo)
        && string.IsNullOrEmpty(uri.Fragment)
        && uri.IsDefaultPort
        && options.Value.RedirectHosts.Contains(uri.Host, StringComparer.OrdinalIgnoreCase);

    /// <summary>Normalizes a requested client name for display.</summary>
    public static string DisplayName(string? name)
    {
        string trimmed = string.IsNullOrWhiteSpace(name) ? "KI-Assistent" : name.Trim();
        return trimmed.Length <= MaximumNameLength ? trimmed : trimmed[..MaximumNameLength];
    }
}
