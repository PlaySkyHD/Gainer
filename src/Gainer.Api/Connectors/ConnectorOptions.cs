namespace Gainer.Api.Connectors;

/// <summary>Settings for connected assistants, bound from <c>Security:Connectors</c>.</summary>
public sealed class ConnectorOptions
{
    /// <summary>Configuration section.</summary>
    public const string SectionName = "Security:Connectors";

    private static readonly string[] DefaultRedirectHosts = ["chatgpt.com", "chat.openai.com", "claude.ai", "claude.com"];

    /// <summary>
    /// Hosts an authorization code may be sent to. Empty uses the defaults, so a configured list
    /// replaces them instead of adding to them.
    /// </summary>
    public string[] AllowedRedirectHosts { get; set; } = [];

    /// <summary>The effective host list.</summary>
    public IReadOnlyList<string> RedirectHosts =>
        AllowedRedirectHosts.Length == 0 ? DefaultRedirectHosts : AllowedRedirectHosts;
}
