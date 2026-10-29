#!/usr/bin/env node
// Bumps OpenCode, the Cloudron base image, GitHub CLI and uv to their latest releases, then bumps
// the package version and adds a CHANGELOG section. Prints the new package version, or nothing
// when everything is current.
//
// Usage: node scripts/update-deps.mjs

import fs from "node:fs"
import path from "node:path"

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..")
const file = (name) => path.join(root, name)

const semver = (version) => version.replace(/^v/, "").split("-")[0].split(".").map(Number)
const newer = (a, b) => {
  const [x, y] = [semver(a), semver(b)]
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i]
  return false
}

async function json(url) {
  const headers = { "user-agent": "opencode-cloudron-updater" }
  if (url.startsWith("https://api.github.com/") && process.env.GITHUB_TOKEN) headers.authorization = `Bearer ${process.env.GITHUB_TOKEN}`
  const response = await fetch(url, { headers })
  if (!response.ok) throw new Error(`${url} returned ${response.status}`)
  return response.json()
}

const githubRelease = async (repo) => (await json(`https://api.github.com/repos/${repo}/releases/latest`)).tag_name.replace(/^v/, "")

let dockerfile = fs.readFileSync(file("Dockerfile"), "utf8")
const arg = (name) => dockerfile.match(new RegExp(`^ARG ${name}=(.+)$`, "m"))?.[1]
const setArg = (name, value) => {
  dockerfile = dockerfile.replace(new RegExp(`^ARG ${name}=.+$`, "m"), `ARG ${name}=${value}`)
}

const changes = []
let opencodeMinorChange = false

const opencode = { current: arg("OPENCODE_VERSION"), latest: (await json("https://registry.npmjs.org/@opencode/cli/latest")).version }
if (newer(opencode.latest, opencode.current)) {
  setArg("OPENCODE_VERSION", opencode.latest)
  const [a, b] = [semver(opencode.current), semver(opencode.latest)]
  opencodeMinorChange = a[0] !== b[0] || a[1] !== b[1]
  changes.push(`Update OpenCode to ${opencode.latest} ([release notes](https://github.com/anomalyco/opencode/releases))`)
}

for (const [name, repo, label] of [["GH_VERSION", "cli/cli", "GitHub CLI"], ["UV_VERSION", "astral-sh/uv", "uv"]]) {
  const current = arg(name)
  const latest = await githubRelease(repo)
  if (newer(latest, current)) {
    setArg(name, latest)
    changes.push(`Update ${label} to ${latest}`)
  }
}

// Base image tags are <node major>-<date>; stay on the current Node major
const from = dockerfile.match(/^FROM cloudron\/node-base:(\d+)-(\d{8})@(sha256:[a-f0-9]+)$/m)
if (!from) throw new Error("Dockerfile FROM is not cloudron/node-base:<major>-<date>@<digest>")
const [, nodeMajor, baseDate] = from
const tags = (await json(`https://hub.docker.com/v2/repositories/cloudron/node-base/tags?page_size=100&name=${nodeMajor}-`)).results
  .filter((tag) => new RegExp(`^${nodeMajor}-\\d{8}$`).test(tag.name) && tag.digest)
  .sort((a, b) => a.name.localeCompare(b.name))
const base = tags.at(-1)
if (base && base.name > `${nodeMajor}-${baseDate}`) {
  dockerfile = dockerfile.replace(from[0], `FROM cloudron/node-base:${base.name}@${base.digest}`)
  changes.push(`Update base image to cloudron/node-base:${base.name}`)
}

if (!changes.length) process.exit(0)

const manifest = JSON.parse(fs.readFileSync(file("CloudronManifest.json"), "utf8"))
const [major, minor, patch] = semver(manifest.version)
const version = opencodeMinorChange ? `${major}.${minor + 1}.0` : `${major}.${minor}.${patch + 1}`
manifest.version = version
manifest.upstreamVersion = arg("OPENCODE_VERSION")

fs.writeFileSync(file("Dockerfile"), dockerfile)
fs.writeFileSync(file("CloudronManifest.json"), JSON.stringify(manifest, null, 2) + "\n")
const changelog = fs.readFileSync(file("CHANGELOG"), "utf8")
fs.writeFileSync(file("CHANGELOG"), `[${version}]\n${changes.map((change) => `* ${change}`).join("\n")}\n\n${changelog}`)

console.log(version)
