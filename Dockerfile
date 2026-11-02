# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/steamcmd:local
ARG BASE_IMAGE=lancommander/steamcmd:latest
FROM ${BASE_IMAGE}

# ----------------------------
# Server settings
#   - STEAM_*: Chivalry: Medieval Warfare Dedicated Server (app 220070, Linux depot, anonymous)
#   - CMW_*: written to UDKGame/Config/PCServer-UDKGame.ini by 30-ConfigureChivalry.ps1, or put on
#     the command line by cmw-server
# ----------------------------
ENV STEAM_APP_ID="220070" \
    STEAM_VALIDATE="false" \
    STEAM_INSTALL_ATTEMPTS="3" \
    CMW_MAP="AOCTO-Hillside_P" \
    CMW_MAPS="" \
    CMW_PORT="7777" \
    CMW_QUERY_PORT="27015" \
    CMW_STEAM_SOCKETS="true" \
    CMW_STEAM_APPID="219640" \
    CMW_SERVER_NAME="Chivalry: Medieval Warfare Server" \
    CMW_MOTD="" \
    CMW_MAX_PLAYERS="32" \
    CMW_GAME_PASSWORD="" \
    CMW_ADMIN_PASSWORD="" \
    CMW_URL_OPTIONS="" \
    CMW_EXTRA_ARGS="" \
    START_EXE="/usr/local/bin/cmw-server" \
    START_ARGS=""

USER root

COPY Scripts/cmw-server /usr/local/bin/cmw-server
RUN chmod +x /usr/local/bin/cmw-server

COPY Hooks/ "${BASE_HOOKS}/"

# 7777/udp: game. 27015/udp: Steam server queries (only with CMW_STEAM_SOCKETS=true).
EXPOSE 7777/udp 27015/udp

USER lancommander

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
