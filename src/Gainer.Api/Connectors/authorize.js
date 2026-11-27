// Freigabeseite für verbundene KI-Assistenten: Passkey-Anmeldung im Browser, danach Rücksprung
// mit Autorisierungscode. Kein Cookie, kein Inline-Skript (CSP script-src 'self').
(() => {
  'use strict';

  const page = document.body.dataset;
  const button = document.getElementById('approve');
  const status = document.getElementById('status');

  const toBuffer = (value) => {
    let base64 = value.replace(/-/g, '+').replace(/_/g, '/');
    while (base64.length % 4) base64 += '=';
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes.buffer;
  };

  const toBase64Url = (buffer) => {
    let binary = '';
    for (const byte of new Uint8Array(buffer)) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };

  // Ältere Browser kennen parseRequestOptionsFromJSON und toJSON noch nicht.
  const requestOptions = (json) => {
    if (window.PublicKeyCredential && typeof PublicKeyCredential.parseRequestOptionsFromJSON === 'function') {
      return PublicKeyCredential.parseRequestOptionsFromJSON(json);
    }
    const options = { ...json, challenge: toBuffer(json.challenge) };
    if (Array.isArray(json.allowCredentials)) {
      options.allowCredentials = json.allowCredentials.map((item) => ({ ...item, id: toBuffer(item.id) }));
    }
    return options;
  };

  const credentialJson = (credential) => {
    if (typeof credential.toJSON === 'function') return credential.toJSON();
    const response = credential.response;
    return {
      id: credential.id,
      rawId: toBase64Url(credential.rawId),
      type: credential.type,
      authenticatorAttachment: credential.authenticatorAttachment || undefined,
      clientExtensionResults: credential.getClientExtensionResults(),
      response: {
        clientDataJSON: toBase64Url(response.clientDataJSON),
        authenticatorData: toBase64Url(response.authenticatorData),
        signature: toBase64Url(response.signature),
        userHandle: response.userHandle ? toBase64Url(response.userHandle) : null,
      },
    };
  };

  const post = (url, payload) => fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  const fail = (message) => {
    status.textContent = message;
    button.disabled = false;
  };

  button.addEventListener('click', async () => {
    button.disabled = true;
    status.textContent = '';
    try {
      const optionsResponse = await post(page.optionsUrl, {});
      if (!optionsResponse.ok) {
        fail('Die Anmeldung konnte nicht gestartet werden. Bitte versuche es erneut.');
        return;
      }
      const options = await optionsResponse.json();
      const credential = await navigator.credentials.get({
        publicKey: requestOptions(JSON.parse(options.optionsJson)),
      });
      const approval = await post(page.approveUrl, {
        request: page.request,
        state: options.state,
        credentialJson: JSON.stringify(credentialJson(credential)),
      });
      if (!approval.ok) {
        fail(approval.status === 400
          ? 'Die Anfrage ist abgelaufen. Starte die Verbindung im Assistenten neu.'
          : 'Der Passkey wurde nicht akzeptiert.');
        return;
      }
      const result = await approval.json();
      window.location.assign(result.redirectUri);
    } catch (error) {
      fail(error && error.name === 'NotAllowedError'
        ? 'Anmeldung abgebrochen.'
        : 'Die Anmeldung ist fehlgeschlagen. Bitte versuche es erneut.');
    }
  });
})();
