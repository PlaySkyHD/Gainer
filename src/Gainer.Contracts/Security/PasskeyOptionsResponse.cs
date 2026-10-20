namespace Gainer.Contracts.Security;

/// <summary>
/// WebAuthn options for a passkey ceremony and the opaque, single-use state that must be sent
/// back with the authenticator's response within five minutes.
/// </summary>
public sealed record PasskeyOptionsResponse(string OptionsJson, string State);
