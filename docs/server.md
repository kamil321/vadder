# Vadder — Server runbook

Node.js + Express (TypeScript) HTTP server that serves the two zips (mods + client scripts)
and reports their SHA-256 hashes, on port **2460**.

## Quick start (dev / on the server host)

```powershell
cd server
pnpm install
pnpm dev          # tsx watch, rebuilds on edits
```

Production-ish run:

```powershell
pnpm build        # tsc → dist/
node dist/index.js
```

The build sources are picked up from env defaults (see `docs/knowledge.md`), so on the actual
server host the mods zip simply reflects the current `valheim_vadder_sync` profile.

## Endpoints

| Method | Path | Response |
|---|---|---|
| GET | `/api/mods/hash` | `text/plain` hex SHA-256 of `mods.zip` (404 if not built yet) |
| GET | `/api/mods/zip` | downloads `mods.zip`, `Cache-Control: no-store` |
| GET | `/api/scripts/hash` | `text/plain` hex SHA-256 of `scripts.zip` |
| GET | `/api/scripts/zip` | downloads `scripts.zip` |
| GET | `/api/health` | JSON status (which artifacts are built) |
| GET | `/` | plain-text index of endpoints |

## Behavior

- **Automatic rebuild:** a file change inside either source tree schedules a rebuild; the zip
  is regenerated once nothing has changed for `VADDER_DEBOUNCE_MS` (default 30 000 ms). Only the
  affected zip is rebuilt. Written as `*.zip.tmp` then atomically renamed over the final zip.
- **Startup:** both artifacts (re)built on boot so endpoints are never stale.
- **Excludes (mods):** `*.log`, `BepInEx\cache`, and the source-marker `VADDER_WRITABLE`.
- **Marker:** an empty `VADDER_WRITABLE` file is injected at the zip root (server-safety
  handshake; see `docs/knowledge.md`). 

## Deployment checklist (ds.hiijac.com)

- [ ] Port `2460/tcp` open in the server-host Windows Firewall (and router/cloud if applicable).
- [ ] Server reachable at `http://ds.hiijac.com:2460/api/health` from a client machine.
- [ ] Run it as a persistent/detached process (`node dist/index.js`), e.g. via Task Scheduler
      "at logon" or a process manager, so the debounce keeps rebuilding while nobody watches
      the console.
- [ ] Make sure the `VADDER_MODS_DIR` default resolves on that host (login user's `%APPDATA%`,
      or set the env var explicitly).

## Data directory

`server/data/` holds `mods.zip`, `scripts.zip` (+ `.tmp` during builds). It is gitignored.