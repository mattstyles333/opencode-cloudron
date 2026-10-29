#!/usr/bin/env node
// Manages CloudronVersions.json, the catalog Cloudron reads community app installs and updates
// from. Does what `cloudron versions add/update/revoke` do, so CI can release without the CLI.
//
// Usage:
//   node scripts/versions.mjs add <docker image> [--state testing|published]
//   node scripts/versions.mjs promote [version]     testing -> published (default: newest testing)
//   node scripts/versions.mjs revoke <version>
//   node scripts/versions.mjs notes <version>       prints the CHANGELOG section
//   node scripts/versions.mjs get <version>         prints the publish state, or nothing

import fs from "node:fs"
import path from "node:path"

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..")
const versionsPath = path.join(root, "CloudronVersions.json")
const read = (file) => fs.readFileSync(path.join(root, file), "utf8")
const fileRef = (value) => (typeof value === "string" && value.startsWith("file://") ? value.slice(7) : null)

const semver = (version) => version.split("-")[0].split(".").map(Number)
const compare = (a, b) => {
  const [x, y] = [semver(a), semver(b)]
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] - y[i]
  return 0
}

function loadCatalog() {
  return fs.existsSync(versionsPath) ? JSON.parse(fs.readFileSync(versionsPath, "utf8")) : { stable: true, versions: {} }
}

function saveCatalog(catalog) {
  fs.writeFileSync(versionsPath, JSON.stringify(catalog, null, 2) + "\n")
}

function changelogSection(version) {
  const lines = read("CHANGELOG").split("\n")
  const start = lines.findIndex((line) => line.trim() === `[${version}]`)
  if (start === -1) throw new Error(`CHANGELOG has no [${version}] section`)
  const end = lines.findIndex((line, index) => index > start && /^\[.+\]\s*$/.test(line.trim()))
  return lines.slice(start + 1, end === -1 ? undefined : end).join("\n").trim()
}

function add(image, state) {
  if (!image) throw new Error("add needs a docker image")
  if (!["published", "testing"].includes(state)) throw new Error(`Unknown state ${state}`)

  const manifest = JSON.parse(read("CloudronManifest.json"))
  const version = manifest.version

  for (const key of ["description", "postInstallMessage"]) {
    const file = fileRef(manifest[key])
    if (file) manifest[key] = read(file).trim()
  }
  if (fileRef(manifest.changelog)) manifest.changelog = changelogSection(version)

  // The catalog points at iconUrl; a local file reference means nothing to a remote Cloudron
  delete manifest.icon
  manifest.dockerImage = image

  const required = ["id", "title", "description", "tagline", "website", "tags", "changelog", "mediaLinks",
    "healthCheckPath", "iconUrl", "packagerName", "packagerUrl"]
  const missing = required.filter((key) => manifest[key] === undefined || (Array.isArray(manifest[key]) && !manifest[key].length))
  if (missing.length) throw new Error(`Manifest is missing ${missing.join(", ")}`)

  const catalog = loadCatalog()
  if (catalog.versions[version]) throw new Error(`Version ${version} is already in CloudronVersions.json. Bump the manifest version.`)
  const newest = Object.keys(catalog.versions).sort(compare).at(-1)
  if (newest && compare(version, newest) <= 0) throw new Error(`Version ${version} must be newer than ${newest}`)

  const now = new Date().toUTCString()
  catalog.versions[version] = { manifest, creationDate: now, ts: now, publishState: state }
  saveCatalog(catalog)
  console.log(`Added ${version} (${image}) as ${state}`)
}

function setState(version, from, to) {
  const catalog = loadCatalog()
  if (!version) {
    version = Object.keys(catalog.versions).filter((v) => catalog.versions[v].publishState === from).sort(compare).at(-1)
    if (!version) throw new Error(`No version is in state ${from}`)
  }
  const entry = catalog.versions[version]
  if (!entry) throw new Error(`Version ${version} is not in CloudronVersions.json`)
  if (!from.split("|").includes(entry.publishState)) throw new Error(`Version ${version} is ${entry.publishState}, expected ${from}`)
  entry.publishState = to
  entry.ts = new Date().toUTCString()
  saveCatalog(catalog)
  console.log(version)
}

const [command, ...args] = process.argv.slice(2)
const option = (name, fallback) => {
  const index = args.indexOf(name)
  return index === -1 ? fallback : args[index + 1]
}
const positional = args.filter((arg, index) => !arg.startsWith("--") && !args[index - 1]?.startsWith("--"))

switch (command) {
  case "add":
    add(positional[0], option("--state", "testing"))
    break
  case "promote":
    setState(positional[0], "testing", "published")
    break
  case "revoke":
    if (!positional[0]) throw new Error("revoke needs a version")
    setState(positional[0], "testing|published", "revoked")
    break
  case "notes":
    console.log(changelogSection(positional[0]))
    break
  case "get":
    console.log(loadCatalog().versions[positional[0]]?.publishState ?? "")
    break
  default:
    throw new Error("Usage: versions.mjs add|promote|revoke|notes|get ...")
}
