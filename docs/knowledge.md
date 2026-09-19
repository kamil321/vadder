# Vadder — Knowledge

Collected decisions and constraints for the Valheim mod-sync tool. Keep this file updated
when something changes.

## Goal

A tool that keeps clients' Valheim mods in sync with the server's mod setup. The client only
needs a single `vadder.bat`; everything else is pulled from the server.

## Hard constraints

- The client must be a **one-click** flow: only `vadder.bat` is installed on the client.
- Client scripts may only use things available on a **raw Windows 11** install:
  `curl.exe`, `tar.exe` (libarchive), `certutil.exe`, `reg.exe`, `xcopy/robocopy`, `mklink /H`,
  `findstr`, `fc`, plus `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "..."` one-liners.
- PowerShell one-liners are used ONLY where raw batch parsing is brittle. Inline `-Command`
  is not a `.ps1` script file, so the default execution policy does not block it; the
  `-ExecutionPolicy Bypass` flag makes it robust regardless.
- User-home access must be **username-agnostic**: always `%APPDATA%`, `%LOCALAPPDATA%`,
  `%USERPROFILE%`, never a hardcoded user name.
- Server endpoints are deliberately **dumb**: `text/plain` hashes + binary zips. No JSON, no
  complex client parsing.
- Everything must validate before acting and fail with a clear message instead of trying too hard.

## Profiles on server and client

- Only the `valheim_vadder_sync` profile is used — on server (build source) and clients
  (install target). Other r2modman profiles (`valheim`, `Default`, `valheim_server`, ...) are
  **completely irrelevant** and must never be touched by any vadder script.
- The `BepInEx\config` folder IS part of the zip: new clients must receive the server defaults.
- A client's already-personalized config must survive re-sync: the client **backs up** its
  local `BepInEx\config`, wipes the profile, extracts the fresh profile, then **restores** its
  backup on top. Local config always wins.
- Extraction strategy: replace the whole profile directory (guarantees the client matches the
  server exactly, removes deleted mods), with the config backup/restore around it.

## Server-safety marker: `VADDER_WRITABLE`

Running the *client* scripts on the *server* machine must not destroy the server's
authoritative profile.

- The `VADDER_WRITABLE` file (empty, zip root, visible name) is injected into `mods.zip` by
  the packer. It is **excluded from the packer's source scan** and is **never present** in the
  server's on-disk `valheim_vadder_sync` directory.
- Therefore: a profile directory that contains `VADDER_WRITABLE` was produced by a vadder sync
  (i.e. it is a real client profile).
- Client `update-mods.bat` decision table (on the *local* `valheim_vadder_sync`):

  | Local sync dir | Server reachable | Action |
  |---|---|---|
  | does not exist | n/a | fresh client → target = sync (network errors surface in the fetch step) |
  | exists, marked | n/a | normal client → target = sync |
  | exists, unmarked | yes | likely running ON the server → target = `valheim_vadder_test` (self-test profile) |
  | exists, unmarked | no | **fail & refuse** — profile was not created by vadder and server is off |

- The scripts zip does NOT carry the marker (scripts are inert and identical everywhere).
- Safety net: the packer logs a loud warning if `VADDER_WRITABLE` is ever found inside the
  server's own source profile (e.g. someone copied a client profile back onto the server).

## Zip contents / excludes (mods)

- Everything under the profile is packed except:
  - `**/*.log` (covers `BepInEx\LogOutput.log`, etc.)
  - `BepInEx\cache\` (stale runtime cache)
  - `VADDER_WRITABLE` (source scan excludes it; the marker is appended separately)
- Server packs scripts as-is (all files in the repo `server/client-scripts/`).

## Rebuild trigger

- Server watches both source trees with chokidar. After a change, it waits until **no change
  occurred for 30 s**, then rebuilds only the affected zip (`<name>.zip.tmp` → atomic rename).
- Startup always (re)builds both artifacts so the endpoints never serve stale/missing files.
- Zip written into `server/data/` (gitignored). Not watched, so no rebuild loops.

## Hash protocol

- `GET /api/mods/hash`  → `200 text/plain`: hex SHA-256 of the current `mods.zip` bytes.
- `GET /api/mods/zip`   → binary download, `Cache-Control: no-store`.
- Same for `scripts`.
- "Has the hash changed?" = server-announced hash differs from the client's last stored hash
  (`%LOCALAPPDATA%\Vadder\mods.hash`). Client stores the new hash only after a verified download.
- Integrity: client downloads the zip, recomputes SHA-256 locally via
  `powershell ... (Get-FileHash -Algorithm SHA256)` and compares to the announced hash before
  extracting. Mismatch → abort with a clear message.

## Client layout (on the client machine)

```
%LOCALAPPDATA%\Vadder\
    client-scripts\   entry.bat, update-mods.bat, start-game.bat   (self-updating)
    mods.hash         last known mods.zip sha256
    scripts.hash      last known scripts.zip sha256
    cfg-backup.tmp    config backup used only during an update
    game-path.config  user-pasted game dir, revalidated every run   (optional)
```

`vadder.bat` (the only file the user double-clicks) updates `client-scripts/` and runs
`entry.bat` → `update-mods.bat` → `start-game.bat`.

## Steam / game executable resolution

- Registry: `HKCU\Software\Valve\Steam` → `SteamPath` (read via a PowerShell one-liner to avoid
  batch parsing pain with spaces + parens).
- Candidates for `valheim.exe`:
  1. `%SteamPath%\steamapps\common\Valheim\valheim.exe`
  2. every `libraryfolders.vdf` `"path"` entry + `\steamapps\common\Valheim`
  3. previously stored `%LOCALAPPDATA%\Vadder\game-path.config` (revalidated every run)
  4. user input (prompted); only persisted if `valheim.exe` actually exists there
- Game dir must be **writable** (probe file) before the two hardlinks are created:
  `winhttp.dll` and `doorstop_config.ini` from the sync profile. Not writable / different
  volume → clear failure message, never launch mod-less silently.
- Launch exactly as stock script: `cd /d "<game>"`, run
  `valheim.exe --doorstop-enable true --doorstop-target-assembly "<profile>\BepInEx\core\BepInEx.Preloader.dll"`.

## Debug/test hooks (client scripts)

- `VADDER_SERVER` env overrides the server base URL (default `http://ds.hiijac.com:2460`).
- `VADDER_GAME_DIR` env overrides game-dir resolution (still runs the writability + hardlink path).
- `VADDER_DRY_RUN=1` resolves and prints the game dir, then exits before hardlinks/launch.

## Why not Go / a compiled binary

Everything required is already native on Windows 11. A Go binary would add cross-arch builds,
distribution, and SmartScreen/mark-of-the-web friction — the opposite of "only vadder.bat".
Not simpler here.

## Windows pitfalls collected

- `mklink` is a cmd built-in (not an exe); `mklink /H` (hard link) needs NO admin, but both
  paths must live on the same volume.
- `curl` in cmd resolves to `curl.exe` from System32 on stock Win11 (always call `curl.exe`)
  and supports `-f` (fail on HTTP error), `-sS`, `-m`, `-o`.
- `tar.exe` (bsdtar/libarchive) extracts `.zip` without extra tools.
- PowerShell inline `-Command` is unaffected by script-execution policy.
- `fc /b` compares files and is a cheap "changed?" test for the stored hashes.
- `certutil -hashfile` output is awkward to parse in batch → use the PS `Get-FileHash` one-liner.

## Env vars (server)

| Var | Default |
|---|---|
| `VADDER_PORT` | `2460` |
| `VADDER_HOST` | `0.0.0.0` |
| `VADDER_MODS_DIR` | `%APPDATA%\r2modmanPlus-local\Valheim\profiles\valheim_vadder_sync` |
| `VADDER_SCRIPTS_DIR` | `<repo>/server/client-scripts` |
| `VADDER_DATA_DIR` | `<repo>/server/data` |
| `VADDER_DEBOUNCE_MS` | `30000` |