# Environment shared by the server, the web terminal and `cloudron exec` sessions.
# Sourced by start.sh and opencode-wrapper.sh.

export HOME=/app/data/home
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_STATE_HOME="${HOME}/.local/state"
# Caches are rebuilt on demand, so keep them out of backups
export XDG_CACHE_HOME=/run/opencode/cache

export OPENCODE_DB=/app/data/opencode.db
export OPENCODE_DISABLE_AUTOUPDATE=1

# `npm i -g`, `pip install --user` and `uv tool install` all land in ~/.local/bin and persist
export NPM_CONFIG_PREFIX="${HOME}/.local"
export UV_TOOL_BIN_DIR="${HOME}/.local/bin"
export PATH="${HOME}/.local/bin:/app/code/bin:/usr/local/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

export SHELL=/bin/bash
export EDITOR="${EDITOR:-vi}"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

export OPENCODE_PORT=4096
export OPENCODE_WORKSPACE=/app/data/workspace

if [[ -f /app/data/env.sh ]]; then
    set -a
    source /app/data/env.sh
    set +a
fi
