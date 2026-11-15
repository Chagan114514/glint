# Glint 1.1.1 — Update Checker

Glint 1.1.1 adds an update checker, with controls in Settings.

## What's new

- **Launch update check** — Glint remembers the installed version and asks the update server whether a newer version exists. If one exists, it offers a link to GitHub; you can update later or skip that version.
- **Settings controls** — Settings → Software Update now has an automatic-check switch and a manual **Check for Updates** button.
- **Patch-aware prompts** — a server response with `patch_url` / `files` is presented as an incremental update that only needs the changed files. A `major` / `full` response opens the complete installer.
- **Resilient check** — if the primary update server is unreachable, Glint falls back to the public GitHub release page. Automatic checks stay silent on total failure; manual checks show the error.
- **Privacy** — the check sends only the app version, platform and build number. Screenshots, recordings, OCR and annotations never leave the Mac. Auto-check can be disabled.

The app version is **1.1.1** (build 4). Update protocol: [`UPDATE_API.md`](UPDATE_API.md).

## Install

Download `Glint-1.1.1.dmg`, drag Glint into Applications, and allow Screen & System Audio Recording on first use. macOS 14+ (Apple Silicon). Microphone capture needs macOS 15+.
