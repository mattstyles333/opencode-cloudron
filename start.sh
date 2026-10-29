#!/bin/bash

set -eu -o pipefail

if [[ ! -f /app/data/env.sh ]]; then
    echo "==> Creating /app/data/env.sh"
    cp /app/code/env.sh.template /app/data/env.sh
fi

# env.sh is user content, so source it before enabling strict mode for the rest of the script
set +u
source /app/code/opencode-env.sh
set -u

echo "==> Preparing directories"
mkdir -p "${HOME}/.local/bin" "${XDG_CONFIG_HOME}/opencode" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}/opencode" \
    "${OPENCODE_WORKSPACE}" "${XDG_CACHE_HOME}" /run/nginx

if [[ ! -f "${HOME}/.bashrc" ]]; then
    cat > "${HOME}/.bashrc" <<'EOF'
# Interactive shell settings for the OpenCode web terminal. Environment lives in /app/data/env.sh.
[[ $- != *i* ]] && return
PS1='\u@opencode:\w\$ '
alias ll='ls -lah'
EOF
fi

# Backups of SQLite files listed in the manifest fail if the file is missing
touch "${OPENCODE_DB}"

# opencode reads hostname, port and password from its service config when started with --service.
# Other keys (env, cors) that the user set with `opencode service set` are kept.
service_config="${XDG_CONFIG_HOME}/opencode/service.json"
[[ -s "${service_config}" ]] || echo '{}' > "${service_config}"
password=$(jq -r '.password // empty' "${service_config}")
if [[ -z "${password}" ]]; then
    echo "==> Generating server password"
    password=$(pwgen -1s 40)
fi
jq --arg password "${password}" --argjson port "${OPENCODE_PORT}" \
    '.hostname = "127.0.0.1" | .port = $port | .password = $password' \
    "${service_config}" > "${service_config}.tmp"
mv "${service_config}.tmp" "${service_config}"
chmod 600 "${service_config}"

# The registration of the previous run points at a process that no longer exists
rm -f "${XDG_STATE_HOME}/opencode/service.json"

# Requests arriving from the default gateway come from the Cloudron reverse proxy, which has already
# enforced the login wall when SSO is on. Those get the server credentials added. Everything else,
# including other containers on the Cloudron network, must present the server password itself.
gateway_hex=$(awk '$2 == "00000000" { print $3; exit }' /proc/net/route)
platform_ips="127.0.0.1"
if [[ -n "${gateway_hex}" ]]; then
    platform_ips+=" $(printf '%d.%d.%d.%d' "0x${gateway_hex:6:2}" "0x${gateway_hex:4:2}" "0x${gateway_hex:2:2}" "0x${gateway_hex:0:2}")"
fi
platform_ips+=" ${OPENCODE_TRUSTED_PROXY_IPS:-}"

basic_auth="Basic $(printf 'opencode:%s' "${password}" | base64 -w0)"
geo_entries=""
for ip in ${platform_ips}; do
    geo_entries+="        ${ip} 1;\n"
done

if [[ -n "${CLOUDRON_PROXY_AUTH:-}" ]]; then
    echo "==> Cloudron login is enabled. Browser sessions are signed in to OpenCode automatically"
    platform_authorization="${basic_auth}"
else
    echo "==> Cloudron login is disabled. OpenCode asks for its server password"
    platform_authorization='$http_authorization'
fi

sed -e "s|##PLATFORM_IPS##|${geo_entries}|" \
    -e "s|##PLATFORM_AUTHORIZATION##|${platform_authorization}|" \
    -e "s|##OPENCODE_PORT##|${OPENCODE_PORT}|g" \
    /app/code/nginx.conf.template > /run/nginx/nginx.conf

echo "==> Fixing ownership"
chown cloudron:cloudron /app/data
find /app/data -xdev \! -user cloudron -exec chown -h cloudron:cloudron {} +
chown -R cloudron:cloudron /run/opencode /run/nginx

echo "==> Starting OpenCode ${OPENCODE_VERSION}"
exec /usr/bin/supervisord --configuration /app/code/supervisord.conf --nodaemon -i OpenCode
