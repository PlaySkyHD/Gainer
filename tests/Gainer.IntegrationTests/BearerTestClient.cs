using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Gainer.Contracts.Security;

namespace Gainer.IntegrationTests;

/// <summary>Signs test clients in through the public token endpoints.</summary>
internal static class BearerTestClient
{
    public static async Task<TokenResponse> LoginAsync(
        HttpClient client,
        string email,
        string password,
        string? deviceName = null)
    {
        using HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(email, password, deviceName));
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        return await response.Content.ReadFromJsonAsync<TokenResponse>()
            ?? throw new InvalidOperationException("The login response was empty.");
    }

    /// <summary>Signs in and sends the access token on every later request of this client.</summary>
    public static async Task<TokenResponse> AuthenticateAsync(
        this HttpClient client,
        string email,
        string password)
    {
        TokenResponse tokens = await LoginAsync(client, email, password);
        client.UseAccessToken(tokens.AccessToken);
        // Sync requests of protocol 4 and newer must name the account, as the app does.
        client.DefaultRequestHeaders.Add(
            AccountHeaderName,
            (await ResolveAccountIdAsync(client, tokens.AccessToken)).ToString("D"));
        return tokens;
    }

    public const string AccountHeaderName = "X-Gainer-Account-Id";

    public static async Task<Guid> ResolveAccountIdAsync(HttpClient client, string accessToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/session");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using HttpResponseMessage response = await client.SendAsync(request);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        SessionResponse session = await response.Content.ReadFromJsonAsync<SessionResponse>()
            ?? throw new InvalidOperationException("The session response was empty.");
        return session.UserId;
    }

    public static void UseAccessToken(this HttpClient client, string? accessToken)
    {
        // The account header names the account of the previous token; a new token or a logout drops it.
        client.DefaultRequestHeaders.Remove(AccountHeaderName);
        client.DefaultRequestHeaders.Authorization = accessToken is null
            ? null
            : new AuthenticationHeaderValue("Bearer", accessToken);
    }

    public static Task<HttpResponseMessage> RefreshAsync(HttpClient client, string refreshToken) =>
        client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshTokenRequest(refreshToken));
}

/// <summary>The access token of one signed-in test account, applied per request.</summary>
internal sealed class TestSession
{
    public string? AccessToken { get; set; }

    /// <summary>The account of a session created by <see cref="SignInAsync"/>.</summary>
    public Guid? AccountId { get; private set; }

    public TestSession Clone() => new() { AccessToken = AccessToken, AccountId = AccountId };

    /// <summary>The same sign-in as a client that never sends the account header.</summary>
    public TestSession WithoutAccountHeader() => new() { AccessToken = AccessToken };

    /// <summary>
    /// Applies the access token and, like the app, the account header that sync requests of
    /// protocol 4 and newer must carry. A header already set on the request is kept.
    /// </summary>
    public void Apply(HttpRequestMessage request, bool includeAccountHeader = true)
    {
        if (AccessToken is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", AccessToken);
        }

        if (includeAccountHeader && AccountId is Guid accountId
            && !request.Headers.Contains(BearerTestClient.AccountHeaderName))
        {
            request.Headers.Add(BearerTestClient.AccountHeaderName, accountId.ToString("D"));
        }
    }

    public static async Task<TestSession> SignInAsync(HttpClient client, string email, string password)
    {
        TokenResponse tokens = await BearerTestClient.LoginAsync(client, email, password);
        return new TestSession
        {
            AccessToken = tokens.AccessToken,
            AccountId = await BearerTestClient.ResolveAccountIdAsync(client, tokens.AccessToken),
        };
    }
}
