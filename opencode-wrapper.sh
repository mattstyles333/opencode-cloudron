#!/bin/bash

# Runs the CLI as the app user with the app's environment, so `opencode` in the Cloudron web
# terminal connects to the running server instead of starting a separate one as root.

source /app/code/opencode-env.sh

if [[ "${PWD}" != /app/data/* ]]; then
    cd "${OPENCODE_WORKSPACE}"
fi

if [[ "$(id -u)" == "0" ]]; then
    exec /usr/local/bin/gosu cloudron:cloudron /app/code/bin/opencode "$@"
fi

exec /app/code/bin/opencode "$@"
