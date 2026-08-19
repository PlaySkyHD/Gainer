# Gainer VPS runbook

This runbook deploys the private, invitation-only MVP at `https://gainer.markfort.xyz` to one Linux VPS. Aspire is the application/publish model; Docker Compose supervises production. The existing host Caddy service remains the only public TLS endpoint.

## Network topology

```text
Internet :80/:443
       -> host Caddy (TLS and certificates)
       -> 127.0.0.1:8081
       -> Gainer edge container :80
       -> API and PostgreSQL on the private Compose network
```

Do not publish container port 443 and do not add a UFW rule for 8081. The existing `game.markfort.xyz` Caddy site remains unchanged.

## Host preparation

1. Verify that the `A`/`AAAA` record for `gainer.markfort.xyz` resolves to the VPS.
2. Use an unprivileged deployment user with key-based SSH. Disable SSH password authentication and root login after initial setup; restrict port 22 to trusted administration addresses where practical.
3. Keep Docker Engine, the Compose plugin, Caddy, and OS security updates installed. UFW permits public TCP 80/443 and the restricted SSH rule only.
4. Create a private Azure Blob container. Disable anonymous access and issue a container-scoped SAS with only the Restic permissions required for listing, reading, creating, writing, and pruning blobs. Record and rotate its expiry.
5. Create `/etc/gainer/secrets` owned by root with mode `0700`. Keep the secret files root-owned with mode `0444`: the root-only parent directory prevents host users from traversing to them, while Docker's non-root application UID can read the individual bind-mounted secret. Never put their values in the repository, image, Compose output, logs, or shell history.
6. Copy `deploy/.env.example` to `/etc/gainer/deployment.env`, make it root-readable, and set the Azure account/repository and immutable image tags. Keep `GAINER_PUBLIC_ORIGIN=https://gainer.markfort.xyz`, `GAINER_SITE_ADDRESS=:80`, and `GAINER_EDGE_PORT=8081`.

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

- Alert on `/health/ready`, restart loops, disk capacity, certificate renewal, backup age, and restore failures. PostgreSQL or schema failure makes readiness fail; OpenAI failure degrades only Coach.
- Keep structured logs at `Information`. Never enable request-body logging. Configure OTLP only to an internal endpoint.
- Before deployment, record current API, migrator, and edge image digests. On a failed health check, restore all three previous immutable references in `/etc/gainer/deployment.env` and run `docker compose up -d --wait` again.
- Follow expand/contract migrations: deploy additive schema before new code and remove old columns only after every rollback candidate no longer uses them.
- Never run `docker compose down -v` in production. Rollbacks change image references, not volumes.
