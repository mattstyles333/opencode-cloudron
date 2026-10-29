#!/usr/bin/env node
// Bumps the package to the latest OpenCode release on npm: Dockerfile, manifest and CHANGELOG.
// Prints the new package version, or nothing when already up to date.
//
// Usage: node scripts/update-opencode.mjs [opencode version]

import fs from "node:fs"
import path from "node:path"

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..")
const file = (name) => path.join(root, name)

const parse = (version) => version.split("-")[0].split(".").map(Number)
const newer = (a, b) => {
  const [x, y] = [parse(a), parse(b)]
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i]
  return false
}

let latest = process.argv[2]
if (!latest) {
  const response = await fetch("https://registry.npmjs.org/@opencode/cli/latest")
  if (!response.ok) throw new Error(`npm registry returned ${response.status}`)
  latest = (await response.json()).version
}

const dockerfile = fs.readFileSync(file("Dockerfile"), "utf8")
const current = dockerfile.match(/^ARG OPENCODE_VERSION=(.+)$/m)?.[1]
if (!current) throw new Error("Dockerfile has no ARG OPENCODE_VERSION")
if (!newer(latest, current)) process.exit(0)

const manifest = JSON.parse(fs.readFileSync(file("CloudronManifest.json"), "utf8"))
const [major, minor, patch] = parse(manifest.version)
const [currentMajor, currentMinor] = parse(current)
const [latestMajor, latestMinor] = parse(latest)
const version = latestMajor !== currentMajor || latestMinor !== currentMinor
  ? `${major}.${minor + 1}.0`
  : `${major}.${minor}.${patch + 1}`

fs.writeFileSync(file("Dockerfile"), dockerfile.replace(/^ARG OPENCODE_VERSION=.+$/m, `ARG OPENCODE_VERSION=${latest}`))

manifest.version = version
manifest.upstreamVersion = latest
fs.writeFileSync(file("CloudronManifest.json"), JSON.stringify(manifest, null, 2) + "\n")

const changelog = fs.readFileSync(file("CHANGELOG"), "utf8")
const entry = `[${version}]\n* Update OpenCode to ${latest}\n* [Release notes](https://github.com/anomalyco/opencode/releases)\n\n`
fs.writeFileSync(file("CHANGELOG"), entry + changelog)

console.log(version)
