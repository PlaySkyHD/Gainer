using System.Formats.Cbor;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.WebUtilities;

namespace Gainer.IntegrationTests;

/// <summary>
/// A platform authenticator in software: answers WebAuthn options the way iOS does for an app
/// with an associated domain (origin = relying party, "none" attestation, ES256).
/// </summary>
internal sealed class SoftwarePasskeyAuthenticator : IDisposable
{
    private readonly ECDsa key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private readonly byte[] credentialId = RandomNumberGenerator.GetBytes(16);
    private byte[] userHandle = [];

    public string Origin { get; set; } = "https://gainer.markfort.xyz";

    public string CredentialId => WebEncoders.Base64UrlEncode(credentialId);

    public string Register(string creationOptionsJson)
    {
        JsonNode options = JsonNode.Parse(creationOptionsJson)!;
        string rpId = options["rp"]!["id"]!.GetValue<string>();
        userHandle = WebEncoders.Base64UrlDecode(options["user"]!["id"]!.GetValue<string>());
        byte[] clientData = ClientData("webauthn.create", options["challenge"]!.GetValue<string>());

        ECParameters parameters = key.ExportParameters(includePrivateParameters: false);
        var coseKey = new CborWriter(CborConformanceMode.Ctap2Canonical);
        coseKey.WriteStartMap(5);
        coseKey.WriteInt32(1);
        coseKey.WriteInt32(2);
        coseKey.WriteInt32(3);
        coseKey.WriteInt32(-7);
        coseKey.WriteInt32(-1);
        coseKey.WriteInt32(1);
        coseKey.WriteInt32(-2);
        coseKey.WriteByteString(parameters.Q.X!);
        coseKey.WriteInt32(-3);
        coseKey.WriteByteString(parameters.Q.Y!);
        coseKey.WriteEndMap();

        byte[] authenticatorData =
        [
            .. AuthenticatorDataPrefix(rpId, attestedCredential: true),
            .. new byte[16],
            (byte)(credentialId.Length >> 8),
            (byte)credentialId.Length,
            .. credentialId,
            .. coseKey.Encode(),
        ];
        var attestation = new CborWriter(CborConformanceMode.Ctap2Canonical);
        attestation.WriteStartMap(3);
        attestation.WriteTextString("fmt");
        attestation.WriteTextString("none");
        attestation.WriteTextString("attStmt");
        attestation.WriteStartMap(0);
        attestation.WriteEndMap();
        attestation.WriteTextString("authData");
        attestation.WriteByteString(authenticatorData);
        attestation.WriteEndMap();

        return Credential(new JsonObject
        {
            ["clientDataJSON"] = WebEncoders.Base64UrlEncode(clientData),
            ["attestationObject"] = WebEncoders.Base64UrlEncode(attestation.Encode()),
            ["transports"] = new JsonArray("internal", "hybrid"),
        });
    }

    public string SignIn(string requestOptionsJson)
    {
        JsonNode options = JsonNode.Parse(requestOptionsJson)!;
        string rpId = options["rpId"]!.GetValue<string>();
        byte[] clientData = ClientData("webauthn.get", options["challenge"]!.GetValue<string>());
        byte[] authenticatorData = AuthenticatorDataPrefix(rpId, attestedCredential: false);
        byte[] signature = key.SignData(
            [.. authenticatorData, .. SHA256.HashData(clientData)],
            HashAlgorithmName.SHA256,
            DSASignatureFormat.Rfc3279DerSequence);

        return Credential(new JsonObject
        {
            ["clientDataJSON"] = WebEncoders.Base64UrlEncode(clientData),
            ["authenticatorData"] = WebEncoders.Base64UrlEncode(authenticatorData),
            ["signature"] = WebEncoders.Base64UrlEncode(signature),
            ["userHandle"] = WebEncoders.Base64UrlEncode(userHandle),
        });
    }

    public void Dispose() => key.Dispose();

    // User present, user verified (Face ID), backup eligible and backed up (iCloud Keychain).
    private static byte[] AuthenticatorDataPrefix(string rpId, bool attestedCredential) =>
    [
        .. SHA256.HashData(Encoding.UTF8.GetBytes(rpId)),
        (byte)(0x01 | 0x04 | 0x08 | 0x10 | (attestedCredential ? 0x40 : 0)),
        0, 0, 0, 0,
    ];

    private byte[] ClientData(string type, string challenge) =>
        JsonSerializer.SerializeToUtf8Bytes(new JsonObject
        {
            ["type"] = type,
            ["challenge"] = challenge,
            ["origin"] = Origin,
            ["crossOrigin"] = false,
        });

    private string Credential(JsonObject response) => new JsonObject
    {
        ["id"] = CredentialId,
        ["rawId"] = CredentialId,
        ["type"] = "public-key",
        ["authenticatorAttachment"] = "platform",
        ["response"] = response,
        ["clientExtensionResults"] = new JsonObject(),
    }.ToJsonString();
}
