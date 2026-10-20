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
        return tokens;
    }

    public static void UseAccessToken(this HttpClient client, string? accessToken)
    {
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

    public TestSession Clone() => new() { AccessToken = AccessToken };

    public void Apply(HttpRequestMessage request)
    {
        if (AccessToken is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", AccessToken);
        }
    }

    public static async Task<TestSession> SignInAsync(HttpClient client, string email, string password)
    {
        TokenResponse tokens = await BearerTestClient.LoginAsync(client, email, password);
        return new TestSession { AccessToken = tokens.AccessToken };
    }
}
