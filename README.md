# Chivalry: Medieval Warfare Server (Docker)

This repository provides a Dockerized **Chivalry: Medieval Warfare** dedicated server. It runs the native Linux server (`Binaries/Linux/UDKGameServer-Linux`) from the official dedicated server tool (Steam app 220070, anonymous).
The image builds on [`lancommander/steamcmd`](https://github.com/LANCommander/LANCommander.Servers.SteamCMD). It supports file overlaying using OverlayFS.

---

## Features

- Installs and updates the server (Steam app 220070, Linux depot, about 1.2 GB) with SteamCMD, anonymously
- Common server settings (name, passwords, player limit, map rotation) are environment variables
- The server's config (`PCServer-UDKGame.ini`) is kept in `Overlay/`, so your own edits persist across restarts and updates
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  chivalry:
    image: lancommander/chivalrymedievalwarfare:latest
    container_name: chivalry

    ports:
      - "7777:7777/udp"
      - "27015:27015/udp"

    volumes:
      - ./config:/config

    environment:
      CMW_SERVER_NAME: "My Chivalry Server"
      CMW_MAP: "AOCTO-Hillside_P"
      CMW_MAPS: "AOCTO-Hillside_P,AOCTO-Stoneshill_P,AOCTO-Darkforest_p,AOCTO-Citadel_p"
      CMW_MAX_PLAYERS: "32"
      CMW_ADMIN_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

---

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # Game files from SteamCMD (Binaries/, Engine/, UDKGame/)
    ├── Overlay/           # Your files, layered on top of Server/
    │   └── UDKGame/
    │       └── Config/
    │           └── PCServer-UDKGame.ini   # Server config, written by the image and by the server
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [SteamCMD image's variables](https://github.com/LANCommander/LANCommander.Servers.SteamCMD).

| Variable | Description | Default |
|----------|-------------|---------|
| `CMW_MAP` | Starting map. Empty uses the first map of `CMW_MAPS`. | `AOCTO-Hillside_P` |
| `CMW_MAPS` | Map rotation, separated by commas or spaces. Replaces the `Maplist` in `PCServer-UDKGame.ini`. Maps that aren't installed are dropped. Empty keeps the existing rotation. | |
| `CMW_PORT` | Game port (`?Port=`) | `7777` |
| `CMW_QUERY_PORT` | Steam query port (`?QueryPort=`) | `27015` |
| `CMW_STEAM_SOCKETS` | Add `?steamsockets` to the URL (the official launch option). Without it, the query port isn't opened and the server isn't listed in the Steam server browser. | `true` |
| `CMW_STEAM_APPID` | Game app id written to `Binaries/Linux/steam_appid.txt`. The server opens the query port only when that file exists. | `219640` |
| `CMW_SERVER_NAME` | `ServerName` | `Chivalry: Medieval Warfare Server` |
| `CMW_MOTD` | `MessageOfTheDay`. Empty leaves the ini value alone. | |
| `CMW_MAX_PLAYERS` | `MaxPlayers` | `32` |
| `CMW_GAME_PASSWORD` | Join password. Empty means no password. | |
| `CMW_ADMIN_PASSWORD` | Admin password (`AdminPassword`). Empty disables admin login. | |
| `CMW_URL_OPTIONS` | Extra URL options appended to the map URL (`Key=Value?Key=Value`) | |
| `CMW_EXTRA_ARGS` | Extra command-line arguments, split on whitespace | |
| `STEAM_APP_ID` | Dedicated server app | `220070` |
| `STEAM_APP_UPDATE` | Install/update the server on start | `true` |
| `STEAM_VALIDATE` | Validate the install on every start | `false` |
| `STEAM_USERNAME` / `STEAM_PASSWORD` | SteamCMD login | `anonymous` / |
| `STEAM_BRANCH` / `STEAM_BRANCH_PASSWORD` | SteamCMD beta branch | |
| `STEAM_INSTALL_ATTEMPTS` | SteamCMD retries | `3` |
| `START_EXE` | Launcher | `/usr/local/bin/cmw-server` |
| `START_ARGS` | Extra arguments, appended after `CMW_EXTRA_ARGS` | |

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/steamcmd:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/steamcmd:local -t lancommander/chivalrymedievalwarfare:local .
```

---

## License

Chivalry: Medieval Warfare and SteamCMD are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
