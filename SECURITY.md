# Security

## Reporting a vulnerability

Report vulnerabilities in this package privately through
[GitHub's security advisories](https://github.com/mattstyles333/opencode-cloudron/security/advisories/new).
Please don't open a public issue. Expect a first reply within a few days.

Vulnerabilities in OpenCode itself belong upstream at
[anomalyco/opencode](https://github.com/anomalyco/opencode/security). Cloudron platform issues go to
[Cloudron](https://www.cloudron.io/contact.html).

## What this package protects

* With the Cloudron login on, only Cloudron users and groups you allow reach OpenCode. The package
  adds OpenCode's server credentials only to requests that come through the Cloudron reverse proxy.
  Other containers on the Cloudron network still need the OpenCode password.
* Without the Cloudron login, OpenCode's own password protects everything except the web UI shell
  and `/healthcheck`, which only reports up or down.
* The server, its tools and the terminal run as the unprivileged `cloudron` user in a read-only
  container. Only `/app/data`, `/tmp` and `/run` are writable.

## What it can't protect

OpenCode is an agent that runs commands. Anyone who can use it can do anything the app can:

* read and change everything in `/app/data`, including provider API keys and SSH keys
* reach any network address the server can, including other apps on the Cloudron network
* spend money with your connected model providers

Text the agent reads (web pages, issues, files from other people) can try to steer it. Keep
OpenCode's permission prompts on for risky tools, review what it runs, and only grant access to
people you'd trust with a shell.
