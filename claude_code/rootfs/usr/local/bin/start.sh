#!/bin/bash
# Runs as root under tini. Picks the HA credential for the configured mode,
# hands it to the mcp user only, then drops to claude for the terminal.
set -euo pipefail

OPTIONS=/data/options.json
log() { echo "[claude_code] $*"; }
die() { log "ERROR: $*"; exit 1; }
opt() { jq -r --arg k "$1" '.[$k] // ""' "$OPTIONS"; }

# The options file holds the tokens. Only root may read it, and only root and
# mcp may enter /data (mcp keeps its state in /data/ha-mcp).
chown root:mcp /data
chmod 0710 /data
chmod 0600 "$OPTIONS"

MODE=$(opt mode)
HA_URL=$(opt ha_url)
HA_URL=${HA_URL%/}

# Wait for Core: the add-on can start before HA is answering.
ha_status() {  # $1=method $2=path $3=token [$4=body]
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X "$1" \
        -H "Authorization: Bearer $3" -H 'Content-Type: application/json' \
        ${4:+--data "$4"} "$URL$2" || echo 000
}
wait_for_ha() {
    local code
    for _ in $(seq 1 60); do
        code=$(ha_status GET /api/ "$TOKEN")
        case "$code" in
            200) return 0 ;;
            401|403) die "Home Assistant rejected the $MODE token (HTTP $code)." ;;
        esac
        sleep 5
    done
    die "Home Assistant at $URL did not answer after 5 minutes (last HTTP $code)."
}

case "$MODE" in
    read_only)
        TOKEN=$(opt read_only_token)
        URL=$HA_URL
        READ_ONLY=true
        [ -n "$TOKEN" ] || die "mode is read_only but read_only_token is empty."
        wait_for_ha
        # Members of system-read-only can't render templates; anyone who can is
        # allowed to control entities, so refuse to run read-only with them.
        code=$(ha_status POST /api/template "$TOKEN" '{"template":"ok"}')
        if [ "$code" = 200 ]; then
            die "read_only_token belongs to a user who can control entities. Use a user in the system-read-only group (see DOCS)."
        fi
        log "read_only: token is a read-only HA user (template render refused with HTTP $code)."
        ;;
    read_write)
        TOKEN=$(opt read_write_token)
        URL=$HA_URL
        if [ -z "$TOKEN" ]; then
            TOKEN=${SUPERVISOR_TOKEN:-}
            URL=http://supervisor/core
            [ -n "$TOKEN" ] || die "no read_write_token and no Supervisor token available."
            log "read_write: using the add-on's Supervisor token."
        fi
        READ_ONLY=false
        wait_for_ha
        ;;
    *) die "unknown mode '$MODE'." ;;
esac

# Env for ha-mcp, readable by mcp only. The settings sidecar is off so nothing
# inside the container offers a way to change READ_ONLY_MODE at runtime.
install -d -o mcp -g mcp -m 0700 /run/ha-mcp /data/ha-mcp
umask 0277
cat > /run/ha-mcp/env <<ENV
HOME=/data/ha-mcp
HA_MCP_CONFIG_DIR=/data/ha-mcp
HOMEASSISTANT_URL=$URL
HOMEASSISTANT_TOKEN=$TOKEN
READ_ONLY_MODE=$READ_ONLY
HA_MCP_DISABLE_SETTINGS_UI=1
ENV
umask 0022
chown mcp:mcp /run/ha-mcp/env
unset TOKEN SUPERVISOR_TOKEN

# Claude's persistent home and workspace live in the add-on config folder.
install -d -o claude -g claude -m 0700 /config/home
install -d -o claude -g claude -m 0755 /config/workspace

nginx
log "mode=$MODE; terminal ready."

CLAUDE_ENV=(HOME=/config/home USER=claude LOGNAME=claude SHELL=/bin/bash
    TERM=xterm-256color LANG=C.UTF-8
    PATH=/usr/local/bin:/usr/bin:/bin
    CLAUDE_HA_MODE="$MODE")
KEY=$(opt anthropic_api_key)
[ -n "$KEY" ] && CLAUDE_ENV+=(ANTHROPIC_API_KEY="$KEY")
unset KEY

cd /config/workspace
exec env -i "${CLAUDE_ENV[@]}" \
    setpriv --reuid=claude --regid=claude --init-groups \
    ttyd -W -i lo -p 7682 -t titleFixed="Claude Code ($MODE)" \
    tmux new-session -A -s claude /usr/local/bin/claude-session
