#!/usr/bin/env bash
set -Eeuo pipefail

release_id="${1:?release id is required}"
registry_namespace="${2:?registry namespace is required}"
deployment_mode="${3:-pull}"
image_tag="${4:-sha-${release_id}}"
release_root="/srv/gainer/releases/${release_id}"
compose_file="${release_root}/deploy/compose.yaml"
environment_file="/etc/gainer/deployment.env"
current_link="/srv/gainer/current"
previous_release="$(readlink -f "${current_link}" 2>/dev/null || true)"
environment_backup="${environment_file}.before-${release_id}"

test -f "${compose_file}"
test -f "${environment_file}"
cp --preserve=mode,ownership,timestamps "${environment_file}" "${environment_backup}"

set_environment_value() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "${environment_file}"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${environment_file}"
    else
        printf '%s=%s\n' "${key}" "${value}" >> "${environment_file}"
    fi
}

rollback() {
    local exit_code=$?
    cp --preserve=mode,ownership,timestamps "${environment_backup}" "${environment_file}"
    if [[ -n "${previous_release}" && -f "${previous_release}/deploy/compose.yaml" ]]; then
        docker compose --project-name gainer --env-file "${environment_file}" \
            --file "${previous_release}/deploy/compose.yaml" up -d --wait
        ln -sfn "${previous_release}" "${current_link}"
    fi
    exit "${exit_code}"
}
trap rollback ERR

set_environment_value GAINER_API_IMAGE "${registry_namespace}/gainer-api:${image_tag}"
set_environment_value GAINER_MIGRATOR_IMAGE "${registry_namespace}/gainer-migrator:${image_tag}"
set_environment_value GAINER_EDGE_IMAGE "${registry_namespace}/gainer-edge:${image_tag}"
set_environment_value GAINER_BACKUP_IMAGE "${registry_namespace}/gainer-backup:${image_tag}"

docker compose --project-name gainer --env-file "${environment_file}" --file "${compose_file}" config --quiet
if [[ "${deployment_mode}" == "pull" ]]; then
    docker compose --project-name gainer --env-file "${environment_file}" --file "${compose_file}" pull api migrator edge
elif [[ "${deployment_mode}" != "local" ]]; then
    echo "Deployment mode must be 'pull' or 'local'." >&2
    false
fi
docker compose --project-name gainer --env-file "${environment_file}" --file "${compose_file}" up -d --wait

curl --fail --silent --show-error --retry 5 --retry-delay 2 \
    --header 'Host: gainer.markfort.xyz' http://127.0.0.1:8081/health/ready >/dev/null
ln -sfn "${release_root}" "${current_link}"
trap - ERR
rm -f "${environment_backup}"

echo "Deployment ${release_id} completed successfully."
