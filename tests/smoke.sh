#!/bin/bash
# Smoke test for the add-on image against a mock Home Assistant.
# Usage: tests/smoke.sh <image>   (needs docker)
set -uo pipefail
IMAGE=${1:?usage: smoke.sh <image>}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
NET=cc-smoke-$$
FAILS=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }

cleanup() {
    docker rm -f "$NET-ha" "$NET-ro" "$NET-rw" "$NET-bad" >/dev/null 2>&1
    docker network rm "$NET" >/dev/null 2>&1
    rm -rf "$WORK"
}
trap cleanup EXIT

docker network create "$NET" >/dev/null
docker run -d --name "$NET-ha" --network "$NET" --network-alias mockha \
    -v "$HERE/mock_ha.py:/mock_ha.py:ro" python:3.13-slim-bookworm python /mock_ha.py >/dev/null

start_addon() {  # $1=name $2=options-json
    mkdir -p "$WORK/$1/data" "$WORK/$1/config"
    echo "$2" > "$WORK/$1/data/options.json"
    docker run -d --name "$NET-$1" --network "$NET" -e SUPERVISOR_TOKEN=supervisor-secret \
        -v "$WORK/$1/data:/data" -v "$WORK/$1/config:/config" "$IMAGE" >/dev/null
    for _ in $(seq 1 30); do
        docker logs "$NET-$1" 2>&1 | grep -q "terminal ready" && return 0
        [ "$(docker inspect -f '{{.State.Running}}' "$NET-$1")" = false ] && return 1
        sleep 1
    done
    return 1
}
tools() {  # $1=name -> "name ro|rw" lines, via the same sudo path Claude Code uses
    docker cp "$HERE/mcp_tools.py" "$NET-$1:/tmp/mcp_tools.py"
    timeout 120 docker exec -u claude ${MCP_CALL:+-e MCP_CALL="$MCP_CALL"} "$NET-$1" \
        python3 /tmp/mcp_tools.py sudo -n -u mcp /usr/local/bin/ha-mcp-stdio 2>/dev/null
}
as_claude() { docker exec -u claude "$NET-ro" bash -c "$1" </dev/null >/dev/null 2>&1; }

# --- read_only ---------------------------------------------------------------
if start_addon ro '{"mode":"read_only","read_only_token":"ro-token","ha_url":"http://mockha:8123","claude_oauth_token":"oat-fake","anthropic_api_key":"key-fake"}'; then
    pass "read_only starts with a read-only user's token"
else
    fail "read_only did not start"; docker logs "$NET-ro" 2>&1 | tail -20
fi

for f in /data/options.json /run/ha-mcp/env /proc/1/environ; do
    as_claude "cat $f" && fail "claude can read $f" || pass "claude cannot read $f"
done
if docker exec -u claude "$NET-ro" bash -c \
    'grep -rsl -e ro-token -e supervisor-secret / --exclude-dir=proc --exclude-dir=sys' | grep -q .; then
    fail "a token is in a file claude can read"
else
    pass "no token in any file claude can read"
fi
as_claude "sudo -n true" && fail "claude can sudo to root" || pass "claude cannot sudo to root"
as_claude "sudo -n -u mcp /usr/local/bin/ha-mcp-stdio --help" \
    && fail "sudo accepts extra arguments" || pass "sudo rejects extra arguments"
as_claude "sudo -n -u mcp READ_ONLY_MODE=false /usr/local/bin/ha-mcp-stdio" \
    && fail "sudo accepts env overrides" || pass "sudo rejects env overrides"

# Claude login: the subscription token reaches Claude and beats the API key.
CENV=$(docker exec -u claude "$NET-ro" bash -c 'tr "\0" "\n" < /proc/$(pgrep -u claude -o ttyd)/environ')
echo "$CENV" | grep -qx CLAUDE_CODE_OAUTH_TOKEN=oat-fake && pass "subscription token passed to Claude" \
    || fail "subscription token not passed to Claude"
echo "$CENV" | grep -q '^ANTHROPIC_API_KEY=' && fail "API key passed alongside the subscription token" \
    || pass "API key dropped when a subscription token is set"
docker exec -u claude "$NET-ro" jq -e '.hasCompletedOnboarding == true' /config/home/.claude.json >/dev/null \
    && pass "first-run login screen skipped with a token" || fail "onboarding not marked complete"

RO=$(tools ro)
[ -n "$RO" ] && pass "MCP handshake over sudo works ($(echo "$RO" | wc -l) tools)" || fail "no tools listed"
echo "$RO" | grep -q '^ha_call_service ' && fail "ha_call_service listed in read_only" \
    || pass "ha_call_service hidden in read_only"
OUT=$(MCP_CALL='{"name":"ha_manage_updates","arguments":{"action":"install","entity_id":"update.x"}}' tools ro)
echo "$OUT" | grep -q READ_ONLY_MODE && pass "mixed tool write blocked at call time" \
    || fail "mixed tool write not blocked"

code=$(docker run --rm --network "$NET" curlimages/curl:8.10.1 -s -o /dev/null -w '%{http_code}' "http://$NET-ro:7681/")
[ "$code" = 403 ] && pass "terminal refused to non-ingress clients" || fail "terminal answered $code to a non-ingress client"

# --- read_only with a token that can control things: must refuse ------------
if start_addon bad '{"mode":"read_only","read_only_token":"rw-token","ha_url":"http://mockha:8123"}'; then
    fail "read_only started with a token that can control entities"
else
    pass "read_only refuses a token that can control entities"
fi

# --- read_write --------------------------------------------------------------
if start_addon rw '{"mode":"read_write","read_write_token":"rw-token","ha_url":"http://mockha:8123"}'; then
    RW=$(tools rw)
    echo "$RW" | grep -q '^ha_call_service ' && pass "ha_call_service listed in read_write" \
        || fail "ha_call_service missing in read_write"
    [ "$(echo "$RW" | wc -l)" -gt "$(echo "$RO" | wc -l)" ] && pass "read_write lists more tools than read_only" \
        || fail "read_write does not list more tools"
else
    fail "read_write did not start"
fi

echo
[ "$FAILS" = 0 ] && echo "all checks passed" || echo "$FAILS check(s) failed"
exit "$FAILS"
