---
sidebar_label: Docker
---

# Chivalry: Medieval Warfare Docker Container

This Docker container runs a Chivalry: Medieval Warfare dedicated server. It is built on the SteamCMD image and runs the native Linux server, `Binaries/Linux/UDKGameServer-Linux`, from Steam app 220070 (the dedicated server tool, anonymous login).

## Quick Start

```yaml
services:
  chivalry:
    image: lancommander/chivalry:latest
    container_name: chivalry

    ports:
      - 7777:7777/udp
      - 27015:27015/udp

    volumes:
      - "/data/Servers/Chivalry - Medieval Warfare/Team Objective:/config"

    environment:
      CMW_SERVER_NAME: "My Chivalry Server"
      CMW_ADMIN_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

## How It Starts

1. `PostInitialization/20-InstallGame.ps1` replaces the SteamCMD image's install hook. It runs `app_update 220070` (Linux depot) into `Server/`, retries up to `STEAM_INSTALL_ATTEMPTS` times, then chowns `Server/` to the server user and remounts the overlay so the new files show up in `Merged/`. With `STEAM_APP_UPDATE=false` it does nothing.
2. `PostInitialization/30-ConfigureChivalry.ps1` writes the `CMW_*` settings into `Merged/UDKGame/Config/PCServer-UDKGame.ini` (see [Server Configuration](#server-configuration)). It also writes `Binaries/Linux/steam_appid.txt` (`CMW_STEAM_APPID`, the game's app id 219640). The depot doesn't include that file, and without it the server never opens the query port.
3. `START_EXE` (`/usr/local/bin/cmw-server`) links the server's user data directory to `Merged/`, then runs:

   ```
   UDKGameServer-Linux <map>?steamsockets?Port=<CMW_PORT>?QueryPort=<CMW_QUERY_PORT>[?<CMW_URL_OPTIONS>] -seekfreeloadingserver [CMW_EXTRA_ARGS] [START_ARGS]
   ```

   from `Binaries/Linux`, with `Binaries/Linux/lib` and the install root (for `steamclient.so`) on `LD_LIBRARY_PATH`.

The first start downloads about 1.2 GB. Loading the first map then takes about a minute.

The server writes no log file and prints almost nothing to the console. `docker logs` ends with the `Starting: UDKGameServer-Linux ...` line and a few `[S_API FAIL] SteamAPI_Init() failed` lines. Those are normal: they come from the Steam *client* API, which a dedicated server doesn't use. To check that the server is up, send a Steam `A2S_INFO` query to the query port. It returns the server name, map and player count.

## Configuration Options

### Ports

- **7777/udp**: game traffic (`CMW_PORT`)
- **27015/udp**: Steam server queries (`CMW_QUERY_PORT`). It is only opened with `CMW_STEAM_SOCKETS=true`.

Clients can join from the server browser or with the console command `open <ip>:7777`.

### Environment Variables

See the [README](../README.md#environment-variables) for the full table.

### Maps

The map prefix selects the game mode:

| Prefix | Mode |
|--------|------|
| `AOCTO-` | Team Objective |
| `AOCTD-` | Team Deathmatch |
| `AOCLTS-` | Last Team Standing |
| `AOCFFA-` | Free for All |
| `AOCKOTH-` | King of the Hill |
| `AOCDuel-` | Duel |
| `AOCCTF-` | Capture the Flag |

Team Objective maps: `AOCTO-Hillside_P`, `AOCTO-Stoneshill_P`, `AOCTO-Battlegrounds_v3_P`, `AOCTO-Darkforest_p`, `AOCTO-Citadel_p`, `AOCTO-Coldfront_p`, `AOCTO-Outpost_p`, `AOCTO-Belmez-CM_p`, `AOCTO-CastleAssault-CM_P`, `AOCTO-Cove-CM_p`, `AOCTO-DrunkenBazaar-CM_p`, `AOCTO-Hideout-CM_p`, `AOCTO-Irilla-CM_P`, `AOCTO-KingsGarden-CM_p`, `AOCTO-Shore-CM_p`.

To list every map, run `find /config/Merged/UDKGame/CookedPCServer -iname 'AOC*_p.udk'` in the container. Map names are not case-sensitive.

### Server Configuration

The Linux server reads its config from `~/.local/share/TornBanner/Chivalry/UDKGame/Config/` instead of the install directory. `cmw-server` replaces that directory with a link to `Merged/`, so the server uses `Merged/UDKGame/Config/PCServer-UDKGame.ini`. The first time the hook or the server writes that file, the edited copy goes into `Overlay/UDKGame/Config/`. It persists from then on, and SteamCMD updates to `Server/` don't overwrite it.

The hook only changes these keys:

| Key | Section | Variable |
|-----|---------|----------|
| `ServerName`, `MessageOfTheDay` | `[Engine.GameReplicationInfo]` | `CMW_SERVER_NAME`, `CMW_MOTD` |
| `MaxPlayers` | `[Engine.GameInfo]` | `CMW_MAX_PLAYERS` |
| `GamePassword`, `AdminPassword` | `[Engine.AccessControl]` | `CMW_GAME_PASSWORD`, `CMW_ADMIN_PASSWORD` (always written, so an empty variable clears the password) |
| `Maplist` (all entries), `MapListIndex` | `[AOC.AOCGame]` | `CMW_MAPS` (only when set) |

Edit anything else (votes, team damage, class limits, `bAutoBalance`, ...) in `Overlay/UDKGame/Config/PCServer-UDKGame.ini` while the server is stopped. The server rewrites the file while it runs, so edits made while it is running can be lost.

### Hooks

| Hook | When |
|------|------|
| `PreSteamInstallGame` / `PostSteamInstallGame` | Around the SteamCMD install, before the chown and overlay remount |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **No output in `docker logs` after `Starting: UDKGameServer-Linux ...`**: this is normal. See [How It Starts](#how-it-starts).
- **Not in the Steam server browser / nothing on the query port**: `CMW_STEAM_SOCKETS` must be `true` (without `?steamsockets` the server opens only the game port), and `Merged/Binaries/Linux/steam_appid.txt` must contain `219640`. The hook writes it on every start. The query port opens about 20 seconds after `Starting: ...`.
- **`Removed map(s) not found in UDKGame/CookedPCServer from CMW_MAPS`**: a map name in `CMW_MAPS` is misspelled or not installed. It's left out of the rotation, because the server stops when the rotation reaches a missing map.
- **Settings in `PCServer-UDKGame.ini` are ignored**: make sure you edit `Overlay/UDKGame/Config/PCServer-UDKGame.ini`, not the copy in `Server/`, and that no `CMW_*` variable sets the same key.
- **`Binaries/Linux/UDKGameServer-Linux not found`**: the SteamCMD install failed. Check the SteamCMD output earlier in the log, or set `STEAM_VALIDATE=true` for one start.
