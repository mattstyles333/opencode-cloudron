## About

[OpenCode](https://opencode.ai) is an open source AI coding agent. This package runs the OpenCode
server with its web UI, so you can plan, write and run code from any browser, with sessions,
projects and credentials stored on your Cloudron.

## Features

* Full OpenCode web UI: sessions, diffs, file browser and a built-in terminal
* Works with Anthropic, OpenAI, Google, OpenRouter, local models and many other providers
* MCP servers, custom agents, commands, skills and plugins
* Cloudron login in front of the app (optional), with automatic sign-in to OpenCode
* Projects live in `/app/data/workspace` and are included in Cloudron backups
* Ships with git, GitHub CLI, Node.js, Python with uv, ripgrep and fd

## Security

OpenCode can run any command with the permissions of the app. Treat access to this app like shell
access to its container, and only grant it to people you trust.
