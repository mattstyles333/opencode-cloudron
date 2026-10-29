#!/bin/bash
# Runs the image the way Cloudron does (read-only root, writable /app/data, /tmp and /run) with and
# without the Cloudron login, and checks the server, auth handling, health check, restarts, backups
# and the CLI wrapper. With a second image, also checks upgrading from it keeps data.
#
# Usage: test/smoke.sh <image> [previous image]

set -eu -o pipefail

image="${1:?usage: test/smoke.sh <image> [previous image]}"
previous_image="${2:-}"
network="opencode-smoke-$$"
curl_image="curlimages/curl:8.16.0"
failures=0

cleanup() {
    docker rm -f oc-sso oc-nosso oc-upgrade >/dev/null 2>&1 || true
    docker volume rm -f oc-sso-data oc-nosso-data oc-upgrade-data >/dev/null 2>&1 || true
    docker network rm "${network}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name}: expected ${expected}, got ${actual}"
        failures=$((failures + 1))
    fi
}

run_app() {
    local name="$1" port="$2" app_image="$3"
    shift 3
    docker run -d --name "${name}" --network "${network}" --read-only \
        --tmpfs /tmp:exec,mode=1777 --tmpfs /run:exec \
        -v "${name}-data:/app/data" -p "127.0.0.1:${port}:8000" "$@" "${app_image}" >/dev/null
}

wait_healthy() {
    local name="$1" port="$2"
    for _ in $(seq 1 60); do
        if curl -sf "http://127.0.0.1:${port}/healthcheck" >/dev/null; then return 0; fi
        sleep 1
    done
    echo "FAIL ${name} did not become healthy"
    docker logs "${name}"
    exit 1
}

status() {
    curl -s -o /dev/null -w '%{http_code}' "$@"
}

# From another container on the same network, i.e. not through the Cloudron proxy
status_from_peer() {
    docker run --rm --network "${network}" "${curl_image}" -s -o /dev/null -w '%{http_code}' "$@"
}

in_app() {
    local name="$1"
    shift
    docker exec -u cloudron "${name}" bash -c "source /app/code/opencode-env.sh && $*"
}

session_titles() {
    local port="$1" password="$2"
    curl -s -u "opencode:${password}" "http://127.0.0.1:${port}/api/session?limit=50" | jq -r '[.data[].title] | sort | join(",")'
}

create_session() {
    local port="$1" password="$2" title="$3"
    curl -sf -u "opencode:${password}" -X POST -H 'content-type: application/json' \
        -d "{\"title\":\"${title}\"}" "http://127.0.0.1:${port}/api/session" >/dev/null
}

# What Cloudron's backup and restore do for the SQLite file listed in the manifest
backup_and_restore_db() {
    local name="$1" app_image="$2"
    local db=/app/data/opencode.db
    docker run --rm -v "${name}-data:/app/data" --read-only --tmpfs /tmp --tmpfs /run "${app_image}" \
        sqlite3 -cmd ".timeout 120000" "${db}" "VACUUM INTO '/app/data/backup.db'"
    docker stop "${name}" >/dev/null
    docker run --rm -v "${name}-data:/app/data" --read-only --tmpfs /tmp --tmpfs /run "${app_image}" \
        bash -c "rm -f ${db} ${db}-journal ${db}-wal ${db}-shm && mv /app/data/backup.db ${db}"
    docker start "${name}" >/dev/null
}

docker network create "${network}" >/dev/null
docker pull -q "${curl_image}" >/dev/null

echo "== Cloudron login enabled"
run_app oc-sso 18001 "${image}" -e CLOUDRON_PROXY_AUTH=1
wait_healthy oc-sso 18001
password=$(docker exec oc-sso opencode service get password)
check "web UI" 200 "$(status http://127.0.0.1:18001/)"
check "API signed in through the proxy" 200 "$(status http://127.0.0.1:18001/api/info)"
check "API from a peer without password" 401 "$(status_from_peer http://oc-sso:8000/api/info)"
check "API from a peer with password" 200 "$(status_from_peer -u "opencode:${password}" http://oc-sso:8000/api/info)"
check "healthcheck body" "ok" "$(curl -s http://127.0.0.1:18001/healthcheck)"
check "internal healthcheck route is hidden" 404 "$(status http://127.0.0.1:18001/_healthcheck_upstream)"
check "server runs as cloudron" "cloudron" "$(docker exec oc-sso bash -c 'for p in /proc/[0-9]*; do [[ "$(cat $p/comm 2>/dev/null)" == opencode ]] && stat -c %U $p; done' | sort -u)"
check "data owned by cloudron" "cloudron" "$(docker exec oc-sso stat -c %U /app/data/home /app/data/workspace /app/data/opencode.db | sort -u)"
check "CLI as root reaches the server" 0 "$(docker exec oc-sso opencode api get /api/info >/dev/null 2>&1; echo $?)"
check "tools on PATH" 0 "$(in_app oc-sso 'git --version && gh --version && uv --version && rg --version && fd --version && node --version' >/dev/null 2>&1; echo $?)"
check "server logs reach the app log" 0 "$(docker logs oc-sso 2>&1 | grep -q 'role=server'; echo $?)"
check "log directory kept out of backups" "/run/opencode/log" "$(docker exec oc-sso readlink /app/data/home/.local/share/opencode/log)"
check "npm cache kept out of backups" "/run/opencode/cache/npm" "$(in_app oc-sso 'npm config get cache')"

docker exec oc-sso supervisorctl -c /app/code/supervisord.conf stop opencode >/dev/null
check "healthcheck fails while the server is down" 500 "$(status http://127.0.0.1:18001/healthcheck)"
docker exec oc-sso supervisorctl -c /app/code/supervisord.conf start opencode >/dev/null
wait_healthy oc-sso 18001

create_session 18001 "${password}" before-restart
docker restart oc-sso >/dev/null
wait_healthy oc-sso 18001
check "password kept across restarts" "${password}" "$(docker exec oc-sso opencode service get password)"
check "sessions kept across restarts" "before-restart" "$(session_titles 18001 "${password}")"

create_session 18001 "${password}" before-backup
backup_and_restore_db oc-sso "${image}"
wait_healthy oc-sso 18001
check "sessions survive a database backup and restore" "before-backup,before-restart" "$(session_titles 18001 "${password}")"

echo "== Cloudron login disabled"
run_app oc-nosso 18002 "${image}"
wait_healthy oc-nosso 18002
password=$(docker exec oc-nosso opencode service get password)
check "web UI" 200 "$(status http://127.0.0.1:18002/)"
check "API without password" 401 "$(status http://127.0.0.1:18002/api/info)"
check "API with password" 200 "$(status -u "opencode:${password}" http://127.0.0.1:18002/api/info)"
check "API with wrong password" 401 "$(status -u opencode:wrong http://127.0.0.1:18002/api/info)"
check "healthcheck body" "ok" "$(curl -s http://127.0.0.1:18002/healthcheck)"

if [[ -n "${previous_image}" ]]; then
    echo "== Upgrade from ${previous_image}"
    docker pull -q "${previous_image}" >/dev/null
    run_app oc-upgrade 18003 "${previous_image}" -e CLOUDRON_PROXY_AUTH=1
    wait_healthy oc-upgrade 18003
    password=$(docker exec oc-upgrade opencode service get password)
    create_session 18003 "${password}" from-previous-version
    docker rm -f oc-upgrade >/dev/null
    run_app oc-upgrade 18003 "${image}" -e CLOUDRON_PROXY_AUTH=1
    wait_healthy oc-upgrade 18003
    check "password kept across the upgrade" "${password}" "$(docker exec oc-upgrade opencode service get password)"
    check "sessions kept across the upgrade" "from-previous-version" "$(session_titles 18003 "${password}")"
    check "API after the upgrade" 200 "$(status http://127.0.0.1:18003/api/info)"
fi

if [[ "${failures}" -gt 0 ]]; then
    echo "${failures} check(s) failed"
    docker logs oc-sso 2>&1 | tail -50
    exit 1
fi
echo "All checks passed"
