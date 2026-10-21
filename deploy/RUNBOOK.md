# Gainer VPS runbook

This runbook deploys the private, invitation-only MVP at `https://gainer.markfort.xyz` to one Linux VPS. Aspire is the application/publish model; Docker Compose supervises production. The existing host Caddy service remains the only public TLS endpoint.

## Network topology

```text
Internet :80/:443
       -> host Caddy (TLS and certificates)
       -> 127.0.0.1:8081
       -> Gainer edge container :80 (API reverse proxy only)
       -> API and PostgreSQL on the private Compose network
```

Do not publish container port 443 and do not add a UFW rule for 8081. The existing `game.markfort.xyz` Caddy site remains unchanged.

## Host preparation

1. Verify that the `A`/`AAAA` record for `gainer.markfort.xyz` resolves to the VPS.
2. Use an unprivileged deployment user with key-based SSH. Disable SSH password authentication and root login after initial setup; restrict port 22 to trusted administration addresses where practical.
3. Keep Docker Engine, the Compose plugin, Caddy, and OS security updates installed. UFW permits public TCP 80/443 and the restricted SSH rule only.
4. Create a private Azure Blob container. Disable anonymous access and issue a container-scoped SAS with only the Restic permissions required for listing, reading, creating, writing, and pruning blobs. Record and rotate its expiry.
5. Create `/etc/gainer/secrets` owned by root with mode `0700`. Keep the secret files root-owned with mode `0444`: the root-only parent directory prevents host users from traversing to them, while Docker's non-root application UID can read the individual bind-mounted secret. Never put their values in the repository, image, Compose output, logs, or shell history.
6. Copy `deploy/.env.example` to `/etc/gainer/deployment.env`, make it root-readable, and set the Azure account/repository and immutable image tags. Keep `GAINER_SITE_ADDRESS=:80` and `GAINER_EDGE_PORT=8081`.
7. Set `OPENFOODFACTS_CONTACT_EMAIL` to a monitored technical address. Keep the default HTTPS base URL unless a deliberate compatible mirror is used. The shipped limits (12 barcode and 8 search requests/minute), 8-second timeout and 1 MB response cap stay below the provider budgets; reduce them if the provider requests it.

The account operator file has this shape and is consumed only by the explicit one-time provision command:

```json
{"email":"operator@example.invalid","password":"replace-with-a-long-unique-password"}
```

## Existing host Caddy

Add this separate site block to `/etc/caddy/Caddyfile`; do not replace or edit the other application's block:

```caddyfile
gainer.markfort.xyz {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8081
}
```

Do not configure `trusted_proxies` on host Caddy. It must replace any client-supplied `X-Forwarded-For` with the real client address; the Gainer edge trusts host Caddy and passes that address on, and the API uses it for per-client rate limits on sign-in, token refresh and `/health/ready`.

Back up the current file, validate the candidate, and reload only a valid configuration:

```sh
cp --preserve=all /etc/caddy/Caddyfile /etc/caddy/Caddyfile.before-gainer
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

If validation fails, restore the backup and do not reload. Host Caddy automatically obtains and renews the certificate. Its state belongs to the host service and is intentionally not mounted into or backed up by the Gainer stack.

## Publish and deploy

```sh
aspire publish --project src/Gainer.AppHost/Gainer.AppHost.csproj --output-path artifacts/aspire --non-interactive
docker compose --env-file /etc/gainer/deployment.env -f deploy/compose.yaml config --quiet
docker compose --env-file /etc/gainer/deployment.env -f deploy/compose.yaml pull
docker compose --env-file /etc/gainer/deployment.env -f deploy/compose.yaml up -d --wait
```

The one-shot migrator must finish successfully before the API starts. Never bypass it: the API stays unready until the schema problem is understood.

### GitHub Actions deployment

The manually dispatched `Deploy production` workflow builds immutable API, migrator, edge and backup images in GHCR and rolls the selected commit out through `/srv/gainer/releases/<commit>`. Configure these repository or `production` environment secrets before its first run:

- `VPS_HOST`: the VPS hostname or address.
- `VPS_USER`: an unprivileged deployment user with permission to run the scoped Docker deployment commands.
- `VPS_SSH_KEY`: a dedicated Ed25519 private key used only by this workflow.
- `VPS_KNOWN_HOSTS`: the verified OpenSSH host-key line for the VPS; never obtain it with `StrictHostKeyChecking=no` inside the workflow.

Install the matching public key on the VPS only after verifying its fingerprint. Prefer a dedicated deployment account and a narrowly scoped sudoers rule over unrestricted root SSH. The workflow uses GitHub's short-lived token to authenticate the server to GHCR during the rollout; no long-lived registry password is required. Production values such as `OPENFOODFACTS_CONTACT_EMAIL` remain in `/etc/gainer/deployment.env` and are never copied into GitHub Actions.

Before reloading host Caddy, smoke-test the loopback edge while preserving the public Host header:

```sh
curl --fail --silent -H 'Host: gainer.markfort.xyz' http://127.0.0.1:8081/health/live
curl --fail --silent -H 'Host: gainer.markfort.xyz' http://127.0.0.1:8081/health/ready
```

After the Caddy reload, test the public path:

```sh
curl --fail --silent https://gainer.markfort.xyz/health/live
curl --fail --silent https://gainer.markfort.xyz/health/ready
curl --head --silent http://gainer.markfort.xyz
ss -lntup
```

HTTP must redirect to HTTPS, the certificate must match `gainer.markfort.xyz`, and 8081 must appear only on `127.0.0.1`. Confirm from another host that 8081, PostgreSQL, OTLP, and Aspire are not reachable.

After the first successful external TLS test, enable this response header in the `gainer.markfort.xyz` host-Caddy block, validate and reload Caddy, and repeat the tests:

```caddyfile
Strict-Transport-Security "max-age=31536000; includeSubDomains"
```

Do not use `preload` until every subdomain is permanently HTTPS-only.

Provision the initial operator once with the API image's `--provision-account-operator` command and the same database and secret mounts. Delete or rotate the provisioning file after success. Invite colleagues through the operator endpoints; this role never grants access to fitness data.

## Backup and isolated restore

`RESTIC_REPOSITORY` uses `azure:<container>:/<path>`. Restic encrypts data client-side with `restic_password`; Azure encryption at rest is an additional layer. The backup job publishes no port.

Run the operations profile from a root-owned systemd timer:

```sh
docker compose --env-file /etc/gainer/deployment.env -f deploy/compose.yaml --profile operations run --rm backup
```

Quarterly, restore into a separately named empty database, never over production:

```sh
docker compose --env-file /etc/gainer/deployment.env -f deploy/compose.yaml --profile operations run --rm --entrypoint /usr/local/bin/restore.sh -e PGDATABASE=gainer_restore backup
```

Record identity/body/training/sync counts and the latest migration printed by the restore script. Recover Data Protection keys only after verifying the isolated database. Host-Caddy certificates are reissuable and are not part of this application backup.

## Local Azure Blob drill

The development AppHost models `backup-storage` with Azurite and persists it in `gainer-azurite-data`. Production uses Restic's native `azure:` backend with the container-scoped SAS. The backup image also contains rclone solely because Restic's native Azure backend cannot consume Azurite's HTTP path-style endpoint.

For the local drill use `RESTIC_REPOSITORY=rclone::azureblob:<container>/<path>`, `RCLONE_AZUREBLOB_USE_EMULATOR=true`, the standard Azurite account/key, and `RCLONE_AZUREBLOB_ENDPOINT=http://<azurite-host>:<port>/devstoreaccount1`. Run `backup.sh`, restore into a separate database with `restore.sh`, and finish with `restic check`. Never use emulator credentials or its HTTP endpoint in production.

## Monitoring, incidents, and rollback

- Strava export: create an API application at https://www.strava.com/settings/api with the Authorization Callback Domain set to the public API host. Put `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` and `STRAVA_CALLBACK_URL` (`https://<host>/api/v1/integrations/strava/callback`) into `/etc/gainer/deployment.env`. Leaving id or secret empty keeps Strava off and the app says so. Tokens are encrypted with the data-protection keys, so losing the key volume asks every user to connect Strava again. The export worker runs inside the API; a Strava outage only delays exports.
- Alert on `/health/ready`, restart loops, disk capacity, certificate renewal, backup age, and restore failures. PostgreSQL or schema failure makes readiness fail. Invalid OpenAI, meal-estimation or image-limit configuration makes readiness fail; a transient OpenAI outage degrades Coach and online meal estimation while manual nutrition tracking and reusable meals remain available.
- `/health/ready` also validates the Open Food Facts URL, required contact identity and bounded request settings. It intentionally does not issue a product request, so a transient provider outage degrades lookup/search while manual and offline diary entry remain available.
- Keep structured logs at `Information`. Never enable request-body logging. Configure OTLP only to an internal endpoint.
- Do not add outbound URL paths or query strings to logging or tracing: they may contain food search text or a barcode. The application exports only the provider authority for outbound HTTP spans.
- Before deployment, record current API, migrator, and edge image digests. On a failed health check, restore all three previous immutable references in `/etc/gainer/deployment.env` and run `docker compose up -d --wait` again.
- Follow expand/contract migrations: deploy additive schema before new code and remove old columns only after every rollback candidate no longer uses them.
- Never run `docker compose down -v` in production. Rollbacks change image references, not volumes.
