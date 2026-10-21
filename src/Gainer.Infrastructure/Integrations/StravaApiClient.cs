using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Gainer.Core.Integrations;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace Gainer.Infrastructure.Integrations;

public sealed class StravaOptions
{
    public const string SectionName = "Strava";

    public string ClientId { get; set; } = string.Empty;
    public string ClientSecret { get; set; } = string.Empty;
    public string? ClientSecretFile { get; set; }

    /// <summary>Public URL of the callback endpoint; its host must be the Authorization Callback Domain of the Strava app.</summary>
    public string? CallbackUrl { get; set; }

    /// <summary>Where the callback sends the browser sheet back to the app.</summary>
    public string AppRedirectUri { get; set; } = "gainer://strava";
    public string OAuthBaseUrl { get; set; } = "https://www.strava.com/";

    /// <summary>Strava moves the API to https://api-v3.strava.com/ from January 2027.</summary>
    public string ApiBaseUrl { get; set; } = "https://www.strava.com/api/v3/";
    public int TimeoutSeconds { get; set; } = 30;
    public int WorkerIntervalSeconds { get; set; } = 60;

    /// <summary>A record must be unchanged this long before it is sent, so edits right after finishing are included.</summary>
    public int SettleSeconds { get; set; } = 120;

    /// <summary>Client id and secret are present; without them the feature is off.</summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(ClientId) && !string.IsNullOrWhiteSpace(ResolveClientSecret());

    public string ResolveClientSecret()
    {
        if (!string.IsNullOrWhiteSpace(ClientSecret)) return ClientSecret.Trim();
        if (string.IsNullOrWhiteSpace(ClientSecretFile) || !File.Exists(ClientSecretFile)) return string.Empty;
        return File.ReadAllText(ClientSecretFile).Trim();
    }
}

public enum StravaFailure
{
    /// <summary>Token invalid, revoked or missing permission.</summary>
    Unauthorized,
    RateLimited,

    /// <summary>Network, timeout or 5xx; worth retrying.</summary>
    Transient,

    /// <summary>Strava refused the request itself (4xx); retrying will not help.</summary>
    Rejected,
}

public sealed class StravaApiException(StravaFailure failure, string message, int? statusCode = null, Exception? innerException = null)
    : Exception(message, innerException)
{
    public StravaFailure Failure { get; } = failure;
    public int? StatusCode { get; } = statusCode;
}

public sealed record StravaTokens(
    string AccessToken,
    string RefreshToken,
    DateTime ExpiresAtUtc,
    long? AthleteId,
    string? AthleteName);

/// <summary>State of an upload. <see cref="DuplicateOfActivityId" /> is set when Strava already has the activity.</summary>
public sealed record StravaUploadState(long UploadId, long? ActivityId, string? Error, long? DuplicateOfActivityId)
{
    public bool IsProcessing => ActivityId is null && Error is null;
}

public interface IStravaApiClient
{
    Task<StravaTokens> ExchangeCodeAsync(string code, CancellationToken cancellationToken = default);

    Task<StravaTokens> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default);

    Task DeauthorizeAsync(string accessToken, CancellationToken cancellationToken = default);

    Task<StravaUploadState> UploadAsync(string accessToken, StravaUpload upload, CancellationToken cancellationToken = default);

    Task<StravaUploadState> GetUploadAsync(string accessToken, long uploadId, CancellationToken cancellationToken = default);

    Task SetSportTypeAsync(string accessToken, long activityId, string sportType, CancellationToken cancellationToken = default);
}

/// <summary>The few Strava endpoints Gainer needs: OAuth, uploads and the activity type.</summary>
public sealed partial class StravaApiClient(
    HttpClient httpClient,
    IOptions<StravaOptions> options,
    ILogger<StravaApiClient>? logger = null) : IStravaApiClient
{
    private const int MaximumLoggedErrorLength = 500;
    private readonly StravaOptions settings = options.Value;
    private readonly ILogger log = logger ?? NullLogger<StravaApiClient>.Instance;

    public Task<StravaTokens> ExchangeCodeAsync(string code, CancellationToken cancellationToken = default) =>
        TokenAsync(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
        }, cancellationToken);

    public Task<StravaTokens> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default) =>
        TokenAsync(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken,
        }, cancellationToken);

    public async Task DeauthorizeAsync(string accessToken, CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, OAuthUri("oauth/deauthorize"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using HttpResponseMessage response = await SendAsync(request, cancellationToken);
        await EnsureSuccessAsync(response);
    }

    public async Task<StravaUploadState> UploadAsync(string accessToken, StravaUpload upload, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(upload);
        using var content = new MultipartFormDataContent();
        var file = new ByteArrayContent(upload.TcxFile);
        file.Headers.ContentType = new MediaTypeHeaderValue("application/vnd.garmin.tcx+xml");
        content.Add(file, "file", upload.ExternalId + ".tcx");
        content.Add(new StringContent("tcx"), "data_type");
        content.Add(new StringContent(upload.ExternalId), "external_id");
        content.Add(new StringContent(upload.Name), "name");
        if (upload.Description is { } description) content.Add(new StringContent(description), "description");
        if (upload.Trainer) content.Add(new StringContent("1"), "trainer");
        using var request = new HttpRequestMessage(HttpMethod.Post, ApiUri("uploads")) { Content = content };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using HttpResponseMessage response = await SendAsync(request, cancellationToken);
        if (response.StatusCode == HttpStatusCode.BadRequest &&
            await TryReadUploadAsync(response, cancellationToken) is { } rejected)
        {
            return rejected;
        }
        await EnsureSuccessAsync(response);
        return await TryReadUploadAsync(response, cancellationToken)
            ?? throw new StravaApiException(StravaFailure.Transient, "Strava returned an unreadable upload.");
    }

    public async Task<StravaUploadState> GetUploadAsync(string accessToken, long uploadId, CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, ApiUri($"uploads/{uploadId}"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using HttpResponseMessage response = await SendAsync(request, cancellationToken);
        await EnsureSuccessAsync(response);
        return await TryReadUploadAsync(response, cancellationToken)
            ?? throw new StravaApiException(StravaFailure.Transient, "Strava returned an unreadable upload.");
    }

    public async Task SetSportTypeAsync(string accessToken, long activityId, string sportType, CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Put, ApiUri($"activities/{activityId}"))
        {
            Content = JsonContent.Create(new { sport_type = sportType }),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using HttpResponseMessage response = await SendAsync(request, cancellationToken);
        await EnsureSuccessAsync(response);
    }

    /// <summary>Reads the activity id from texts like „x.tcx duplicate of activity 123“.</summary>
    public static long? ParseDuplicateActivityId(string? error)
    {
        if (error is null) return null;
        Match match = DuplicatePattern().Match(error);
        return match.Success && long.TryParse(match.Groups[1].ValueSpan, out long id) ? id : null;
    }

    private async Task<StravaTokens> TokenAsync(Dictionary<string, string> form, CancellationToken cancellationToken)
    {
        form["client_id"] = settings.ClientId;
        form["client_secret"] = settings.ResolveClientSecret();
        using var request = new HttpRequestMessage(HttpMethod.Post, OAuthUri("oauth/token"))
        {
            Content = new FormUrlEncodedContent(form),
        };
        using HttpResponseMessage response = await SendAsync(request, cancellationToken);
        // Strava answers a revoked or unknown refresh token with 400.
        if (response.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized)
        {
            throw new StravaApiException(StravaFailure.Unauthorized, "Strava rejected the authorization.", (int)response.StatusCode);
        }
        await EnsureSuccessAsync(response);
        TokenResponse token = await response.Content.ReadFromJsonAsync<TokenResponse>(cancellationToken)
            ?? throw new StravaApiException(StravaFailure.Transient, "Strava returned an empty token response.");
        if (string.IsNullOrEmpty(token.AccessToken) || string.IsNullOrEmpty(token.RefreshToken))
        {
            throw new StravaApiException(StravaFailure.Transient, "Strava returned an incomplete token response.");
        }
        string? name = token.Athlete is { } athlete
            ? string.Join(' ', new[] { athlete.FirstName, athlete.LastName }.Where(part => !string.IsNullOrWhiteSpace(part))).Trim()
            : null;
        return new StravaTokens(
            token.AccessToken,
            token.RefreshToken,
            DateTimeOffset.FromUnixTimeSeconds(token.ExpiresAt).UtcDateTime,
            token.Athlete?.Id,
            string.IsNullOrEmpty(name) ? null : name);
    }

    private async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(settings.TimeoutSeconds));
        try
        {
            HttpResponseMessage response = await httpClient.SendAsync(request, timeout.Token);
            // The body is read after the timeout scope; buffer it now.
            await response.Content.LoadIntoBufferAsync(timeout.Token);
            return response;
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new StravaApiException(StravaFailure.Transient, "Strava timed out.", innerException: exception);
        }
        catch (HttpRequestException exception)
        {
            throw new StravaApiException(StravaFailure.Transient, "Strava is unavailable.", innerException: exception);
        }
    }

    private async Task EnsureSuccessAsync(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode) return;
        int status = (int)response.StatusCode;
        StravaFailure failure = response.StatusCode switch
        {
            HttpStatusCode.Unauthorized => StravaFailure.Unauthorized,
            HttpStatusCode.TooManyRequests => StravaFailure.RateLimited,
            _ when status >= 500 || response.StatusCode == HttpStatusCode.RequestTimeout => StravaFailure.Transient,
            _ => StravaFailure.Rejected,
        };
        // Strava explains refusals in a small JSON body without tokens; it is the only clue for 403s.
        string body = await response.Content.ReadAsStringAsync();
        string excerpt = body.Length <= MaximumLoggedErrorLength ? body : body[..MaximumLoggedErrorLength];
        log.LogWarning(
            "Strava answered {Status} for {Method} {Path}: {Body}",
            status,
            response.RequestMessage?.Method.Method,
            response.RequestMessage?.RequestUri?.AbsolutePath,
            excerpt);
        throw new StravaApiException(failure, $"Strava answered {status}.", status);
    }

    private static async Task<StravaUploadState?> TryReadUploadAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            UploadResponse? upload = await response.Content.ReadFromJsonAsync<UploadResponse>(cancellationToken);
            if (upload is null || upload.Id == 0) return null;
            string? error = string.IsNullOrWhiteSpace(upload.Error) ? null : upload.Error;
            return new StravaUploadState(upload.Id, upload.ActivityId, error, ParseDuplicateActivityId(error));
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private Uri OAuthUri(string path) => new(new Uri(settings.OAuthBaseUrl), path);

    private Uri ApiUri(string path) => new(new Uri(settings.ApiBaseUrl), path);

    [GeneratedRegex(@"duplicate of\D*(\d+)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex DuplicatePattern();

    private sealed record TokenResponse(
        [property: JsonPropertyName("access_token")] string AccessToken,
        [property: JsonPropertyName("refresh_token")] string RefreshToken,
        [property: JsonPropertyName("expires_at")] long ExpiresAt,
        [property: JsonPropertyName("athlete")] AthleteResponse? Athlete);

    private sealed record AthleteResponse(
        [property: JsonPropertyName("id")] long Id,
        [property: JsonPropertyName("firstname")] string? FirstName,
        [property: JsonPropertyName("lastname")] string? LastName);

    private sealed record UploadResponse(
        [property: JsonPropertyName("id")] long Id,
        [property: JsonPropertyName("error")] string? Error,
        [property: JsonPropertyName("activity_id")] long? ActivityId);
}
