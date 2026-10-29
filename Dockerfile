FROM cloudron/node-base:24-20261021@sha256:7435d8aca138ce01cfca4cd7ec05683223b8f5d7198c9abdaaefa1b6ba14b4c6

RUN mkdir -p /app/code/bin
WORKDIR /app/code

# gosu and ssh take the home directory from passwd, not $HOME
RUN usermod -d /app/data/home cloudron

# Tools the agent and the web terminal commonly reach for. git, build-essential, jq, sqlite3,
# python3 and nginx/supervisor already come with the base image.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ripgrep fd-find tmux tree python3-pip python3-venv && \
    ln -s /usr/bin/fdfind /usr/local/bin/fd && \
    rm -rf /var/cache/apt /var/lib/apt/lists

ARG GH_VERSION=2.103.3
RUN cd /tmp && \
    curl -fsSLO https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz && \
    curl -fsSL https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt | grep "gh_${GH_VERSION}_linux_amd64.tar.gz" | sha256sum -c - && \
    tar -xzf gh_${GH_VERSION}_linux_amd64.tar.gz && \
    install -m 0755 gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/gh && \
    rm -rf /tmp/gh_*

ARG UV_VERSION=0.13.6
RUN cd /tmp && \
    curl -fsSLO https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz && \
    curl -fsSL https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz.sha256 | sha256sum -c - && \
    tar -xzf uv-x86_64-unknown-linux-gnu.tar.gz && \
    install -m 0755 uv-x86_64-unknown-linux-gnu/uv uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/ && \
    rm -rf /tmp/uv-*

# The baseline build runs on CPUs without AVX2, which some VPS hosts still expose.
# npm pack verifies the tarball against the registry's integrity hash.
ARG OPENCODE_VERSION=2.2.1
ENV OPENCODE_VERSION=${OPENCODE_VERSION}
RUN cd /tmp && \
    npm pack --silent @opencode/cli-linux-x64-baseline@${OPENCODE_VERSION} && \
    tar -xzf opencode-cli-linux-x64-baseline-${OPENCODE_VERSION}.tgz && \
    install -m 0755 package/bin/opencode /app/code/bin/opencode && \
    rm -rf /tmp/package /tmp/*.tgz /root/.npm

COPY opencode-env.sh opencode-wrapper.sh start.sh nginx.conf.template supervisord.conf env.sh.template /app/code/
RUN echo ok > /app/code/healthcheck.txt && \
    ln -s /app/code/opencode-wrapper.sh /usr/local/bin/opencode && \
    HOME=/tmp/build-home /app/code/bin/opencode --version && rm -rf /tmp/build-home

EXPOSE 8000

CMD [ "/app/code/start.sh" ]
