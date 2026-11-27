using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;

namespace Gainer.Api.Connectors;

/// <summary>HTML of the consent page and its Content-Security-Policy.</summary>
public static class ConnectorConsentPage
{
    /// <summary>The only style the page uses; the CSP allows exactly this block by its hash.</summary>
    private const string Style =
        "body{font-family:-apple-system,system-ui,sans-serif;max-width:28rem;margin:3rem auto;padding:0 1.25rem;" +
        "line-height:1.5;color:#1c1c1e;background:#f2f2f7}" +
        "@media (prefers-color-scheme:dark){body{color:#f2f2f7;background:#000}}" +
        "h1{font-size:1.6rem;margin-bottom:.5rem}p{margin:.75rem 0}" +
        "button{width:100%;padding:.9rem;margin-top:1.25rem;font-size:1rem;font-weight:600;border:0;" +
        "border-radius:.8rem;color:#fff;background:#0a84ff}button:disabled{opacity:.5}" +
        "a{display:block;text-align:center;margin-top:1rem;color:#0a84ff}" +
        ".hint{font-size:.9rem;opacity:.75}#status{color:#ff453a;min-height:1.5rem}";

    private static readonly string StyleHash =
        Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(Style)));

    /// <summary>Policy for the page: own script, the hashed style, requests only to this origin.</summary>
    public static readonly string ContentSecurityPolicy =
        "default-src 'none'; script-src 'self'; connect-src 'self'; " +
        $"style-src 'sha256-{StyleHash}'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

    /// <summary>The consent page for a validated request.</summary>
    public static string Render(ConnectorAuthorizationRequest request, string protectedRequest, string denyUrl)
    {
        HtmlEncoder html = HtmlEncoder.Default;
        string client = html.Encode(request.ClientName);
        string host = html.Encode(new Uri(request.RedirectUri).Host);
        return $$"""
            <!DOCTYPE html>
            <html lang="de">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="referrer" content="no-referrer">
            <title>Gainer verbinden</title>
            <style>{{Style}}</style>
            </head>
            <body data-request="{{html.Encode(protectedRequest)}}"
                  data-options-url="/api/v1/auth/passkeys/request-options"
                  data-approve-url="/{{ConnectorEndpoints.OAuthRoute}}/authorize/approve">
            <h1>Gainer mit {{client}} verbinden</h1>
            <p>{{client}} möchte deine Gainer-Daten lesen: Trainings, Übungen, Körpergewicht, Ernährung und Ziele. {{client}} kann in Gainer nichts ändern.</p>
            <p class="hint">Die Daten gehen an {{host}} und werden dort verarbeitet. Du kannst die Verbindung in der Gainer-App unter Profil › Verbundene Apps jederzeit trennen.</p>
            <button id="approve" type="button">Mit Passkey anmelden und erlauben</button>
            <p id="status" role="status"></p>
            <a href="{{html.Encode(denyUrl)}}">Ablehnen</a>
            <script src="/{{ConnectorEndpoints.OAuthRoute}}/authorize.js"></script>
            </body>
            </html>
            """;
    }

    /// <summary>Error page for requests that cannot be sent back to the client safely.</summary>
    public static string RenderError(string message) => $$"""
        <!DOCTYPE html>
        <html lang="de">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Gainer verbinden</title>
        <style>{{Style}}</style>
        </head>
        <body>
        <h1>Verbindung nicht möglich</h1>
        <p>{{HtmlEncoder.Default.Encode(message)}}</p>
        </body>
        </html>
        """;
}
