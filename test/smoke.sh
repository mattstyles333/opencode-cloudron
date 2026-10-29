#!/bin/bash
# Runs the image the way Cloudron does (read-only root, writable /app/data, /tmp and /run) with and
# without the Cloudron login, and checks the server, auth handling, restarts and the CLI wrapper.
#
# Usage: test/smoke.sh <image>

set -eu -o pipefail

image="${1:?usage: test/smoke.sh <image>}"
network="opencode-smoke-$$"
curl_image="curlimages/curl:8.16.0"
failures=0

cleanup() {
    docker rm -f oc-sso oc-nosso >/dev/null 2>&1 || true
    docker volume rm -f oc-sso-data oc-nosso-data >/dev/null 2>&1 || true
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
    local name="$1" port="$2"
    shift 2
    docker run -d --name "${name}" --network "${network}" --read-only \
        --tmpfs /tmp:exec,mode=1777 --tmpfs /run:exec \
        -v "${name}-data:/app/data" -p "127.0.0.1:${port}:8000" "$@" "${image}" >/dev/null
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

docker network create "${network}" >/dev/null
docker pull -q "${curl_image}" >/dev/null

echo "== Cloudron login enabled"
run_app oc-sso 18001 -e CLOUDRON_PROXY_AUTH=1
wait_healthy oc-sso 18001
password=$(docker exec oc-sso opencode service get password)
check "web UI" 200 "$(status http://127.0.0.1:18001/)"
check "API signed in through the proxy" 200 "$(status http://127.0.0.1:18001/api/info)"
check "API from a peer without password" 401 "$(status_from_peer http://oc-sso:8000/api/info)"
check "API from a peer with password" 200 "$(status_from_peer -u "opencode:${password}" http://oc-sso:8000/api/info)"
check "healthcheck hidden from peers" 404 "$(status_from_peer http://oc-sso:8000/healthcheck)"
check "server runs as cloudron" "cloudron" "$(docker exec oc-sso bash -c 'for p in /proc/[0-9]*; do [[ "$(cat $p/comm 2>/dev/null)" == opencode ]] && stat -c %U $p; done' | sort -u)"
check "data owned by cloudron" "cloudron" "$(docker exec oc-sso stat -c %U /app/data/home /app/data/workspace /app/data/opencode.db | sort -u)"
check "CLI as root reaches the server" 0 "$(docker exec oc-sso opencode api get /api/info >/dev/null 2>&1; echo $?)"
check "tools on PATH" 0 "$(docker exec -u cloudron oc-sso bash -lc 'source /app/code/opencode-env.sh && git --version && gh --version && uv --version && rg --version && fd --version && node --version' >/dev/null 2>&1; echo $?)"

docker restart oc-sso >/dev/null
wait_healthy oc-sso 18001
check "password kept across restarts" "${password}" "$(docker exec oc-sso opencode service get password)"
check "API after restart" 200 "$(status http://127.0.0.1:18001/api/info)"

echo "== Cloudron login disabled"
run_app oc-nosso 18002
wait_healthy oc-nosso 18002
password=$(docker exec oc-nosso opencode service get password)
check "web UI" 200 "$(status http://127.0.0.1:18002/)"
check "API without password" 401 "$(status http://127.0.0.1:18002/api/info)"
check "API with password" 200 "$(status -u "opencode:${password}" http://127.0.0.1:18002/api/info)"
check "API with wrong password" 401 "$(status -u opencode:wrong http://127.0.0.1:18002/api/info)"

if [[ "${failures}" -gt 0 ]]; then
    echo "${failures} check(s) failed"
    docker logs oc-sso 2>&1 | tail -50
    exit 1
fi
echo "All checks passed"
