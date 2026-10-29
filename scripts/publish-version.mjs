#!/usr/bin/env node
// Adds the version in CloudronManifest.json to CloudronVersions.json, the catalog Cloudron reads
// community app installs and updates from. Does what `cloudron versions add --image` does, so CI
// can publish without the Cloudron CLI.
//
// Usage: node scripts/publish-version.mjs <docker image> [--state published|testing]

import fs from "node:fs"
import path from "node:path"

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..")
const args = process.argv.slice(2)
const image = args.find((arg) => !arg.startsWith("--"))
const stateIndex = args.indexOf("--state")
const state = stateIndex === -1 ? "published" : args[stateIndex + 1]

if (!image) throw new Error("Usage: publish-version.mjs <docker image> [--state published|testing]")
if (!["published", "testing"].includes(state)) throw new Error(`Unknown state ${state}`)

const read = (file) => fs.readFileSync(path.join(root, file), "utf8")
const fileRef = (value) => (typeof value === "string" && value.startsWith("file://") ? value.slice(7) : null)

function changelogSection(text, version) {
  const lines = text.split("\n")
  const start = lines.findIndex((line) => line.trim() === `[${version}]`)
  if (start === -1) throw new Error(`CHANGELOG has no [${version}] section`)
  const end = lines.findIndex((line, index) => index > start && /^\[.+\]\s*$/.test(line.trim()))
  return lines.slice(start + 1, end === -1 ? undefined : end).join("\n").trim()
}

const manifest = JSON.parse(read("CloudronManifest.json"))
const version = manifest.version

for (const key of ["description", "postInstallMessage"]) {
  const file = fileRef(manifest[key])
  if (file) manifest[key] = read(file).trim()
}
const changelogFile = fileRef(manifest.changelog)
if (changelogFile) manifest.changelog = changelogSection(read(changelogFile), version)

// The catalog points at iconUrl; a local file reference means nothing to a remote Cloudron
delete manifest.icon
manifest.dockerImage = image

const required = ["id", "title", "description", "tagline", "website", "tags", "changelog", "mediaLinks",
  "healthCheckPath", "iconUrl", "packagerName", "packagerUrl"]
const missing = required.filter((key) => manifest[key] === undefined || (Array.isArray(manifest[key]) && !manifest[key].length))
if (missing.length) throw new Error(`Manifest is missing ${missing.join(", ")}`)

const versionsPath = path.join(root, "CloudronVersions.json")
const catalog = fs.existsSync(versionsPath) ? JSON.parse(fs.readFileSync(versionsPath, "utf8")) : { stable: true, versions: {} }
if (catalog.versions[version]) throw new Error(`Version ${version} is already in CloudronVersions.json. Bump the manifest version.`)

const now = new Date().toUTCString()
catalog.versions[version] = { manifest, creationDate: now, ts: now, publishState: state }
fs.writeFileSync(versionsPath, JSON.stringify(catalog, null, 2) + "\n")
console.log(`Added ${version} (${image}) to CloudronVersions.json as ${state}`)
