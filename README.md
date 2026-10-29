# OpenCode for Cloudron

A [Cloudron](https://cloudron.io) package for [OpenCode](https://opencode.ai), the open source AI
coding agent. It runs the OpenCode server and web UI behind your Cloudron login, with sessions,
settings, credentials and projects stored in the app's backed-up data directory.

![OpenCode web UI](screenshots/web.png)

This is a community package. It is not affiliated with Cloudron or the OpenCode team.

## Install

In the Cloudron dashboard, open **App Store → Community apps**, add this URL and install OpenCode:

```
https://github.com/mattstyles333/opencode-cloudron/blob/main/CloudronVersions.json
```

Or with the [Cloudron CLI](https://docs.cloudron.io/packaging/cli/):

```bash
cloudron install --versions-url https://raw.githubusercontent.com/mattstyles333/opencode-cloudron/main/CloudronVersions.json
```

Installed apps pick up new versions from the same URL.

## Signing in

At install time, choose how people reach OpenCode:

* **Cloudron login (recommended).** Cloudron asks users to sign in, with 2FA if enabled, and OpenCode
  opens without its own password. Only users and groups you allow can get in.
* **No Cloudron login.** OpenCode asks for its server password. Read it from the Web Terminal with
  `opencode service get password` and choose **Use password** on the connect screen. With this mode
  you can also connect a local TUI: `OPENCODE_PASSWORD=... opencode --server https://opencode.example.com`.

To change the password, run `opencode service set password "a-long-secret"` in the Web Terminal and
restart the app. Changing it signs every OpenCode session out.

OpenCode can run any command inside the app container. Only give access to people you would trust
with a shell on it.

## Using it

* **Providers.** Connect one under **Settings → Providers**, or set API keys such as
  `ANTHROPIC_API_KEY` in `/app/data/env.sh` and restart the app.
* **Projects.** Clone or create projects in `/app/data/workspace`, from the OpenCode terminal or the
  Cloudron Web Terminal, then add them in the web UI.
* **Configuration.** Global OpenCode config is `/app/data/home/.config/opencode/opencode.json`.
  OpenCode reloads it when it changes. See the [OpenCode docs](https://opencode.ai/v2/docs/config/).
* **Git and GitHub.** `git` and `gh` are installed. SSH keys go in `/app/data/home/.ssh`. Run
  `gh auth login` in the terminal to use GitHub.
* **More tools.** The image is read-only, so `apt` is unavailable, but `npm i -g`, `pip install --user`
  and `uv tool install` install into `/app/data/home/.local` and survive updates. Node.js, Python,
  uv, ripgrep, fd and build tools are preinstalled.
* **Web Terminal.** Running `opencode` in the Cloudron Web Terminal starts the TUI as the app user,
  connected to the running server.

## Data layout

| Path | Contents |
| --- | --- |
| `/app/data/workspace` | Projects. The server starts here |
| `/app/data/home` | Home directory: OpenCode config, provider credentials, git and SSH config |
| `/app/data/opencode.db` | Sessions and messages |
| `/app/data/env.sh` | Extra environment variables, sourced on start |

All of it is included in Cloudron backups. Caches live in `/run` and are rebuilt after a restart.

The default memory limit is 2 GB. Raise it in the app's **Resources** settings if you run large
builds or language servers.

## How it works

`start.sh` writes OpenCode's service config with a generated password, then supervisord runs
`opencode serve --service` on `127.0.0.1:4096` and nginx on port 8000 in front of it.

With the Cloudron login on, nginx adds the server credentials to requests from the container's
default gateway, which is where the Cloudron reverse proxy connects from after it has checked the
login. Requests from anywhere else, such as other containers on the Cloudron network, still need the
OpenCode password. With the Cloudron login off, nginx passes requests through unchanged.

`/healthcheck` answers the Cloudron health checker only.

## Development

Build and test locally:

```bash
docker build -t opencode-cloudron .
test/smoke.sh opencode-cloudron
```

To try a build on your Cloudron, use `cloudron build` and `cloudron install` from this directory.

### Releasing

The Build workflow builds the image and runs `test/smoke.sh` on every push and pull request. On
`main`, when the manifest version is not yet in `CloudronVersions.json`, it pushes the image to
`ghcr.io/mattstyles333/opencode-cloudron` and adds the version to `CloudronVersions.json`.

To release, bump `version` in `CloudronManifest.json`, add a matching section to `CHANGELOG` and
merge to `main`.

A daily workflow checks npm for new OpenCode releases and opens a pull request that bumps the
OpenCode version, the package version and the changelog.

## License

The packaging is MIT licensed. OpenCode is MIT licensed by its authors.
