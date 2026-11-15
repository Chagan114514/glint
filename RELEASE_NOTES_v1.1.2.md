# Glint 1.1.2 — Update Endpoint

Glint 1.1.2 points the update checker at the production endpoint and makes the check resilient to transport and certificate issues.

## What's new

- **Production endpoint** — checks `https://101.37.126.79/api/glint/updates` with a GET request.
- **TLS fallback** — the server certificate is currently valid for `chagandev.space`, not the bare IP. Glint tries HTTPS first, then the same endpoint over HTTP so version checks still work; if the cert is fixed, HTTPS is used automatically.
- **GitHub fallback** — if both endpoint transports fail, Glint follows the public GitHub release page and prompts for the latest release.

- **Launch update check** — Glint remembers the installed version and asks the update server whether a newer version exists. If one exists, it offers a link to GitHub; you can update later or skip that version.
- **Settings controls** — Settings → Software Update now has an automatic-check switch and a manual **Check for Updates** button.
- **Patch-aware prompts** — a server response with `patch_url` / `files` is presented as an incremental update that only needs the changed files. A `major` / `full` response opens the complete installer.
- **Resilient check** — if the primary update server is unreachable, Glint falls back to the public GitHub release page. Automatic checks stay silent on total failure; manual checks show the error.
- **Privacy** — the check sends only the app version, platform and build number. Screenshots, recordings, OCR and annotations never leave the Mac. Auto-check can be disabled.

The app version is **1.1.2** (build 5). Update protocol: [`UPDATE_API.md`](UPDATE_API.md).

## Install

Download `Glint-1.1.2.dmg`, drag Glint into Applications, and allow Screen & System Audio Recording on first use. macOS 14+ (Apple Silicon). Microphone capture needs macOS 15+.
