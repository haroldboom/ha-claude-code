# Claude Code for Home Assistant

A Home Assistant add-on that runs [Claude Code](https://claude.com/claude-code)
in a sidebar terminal, with the community
[ha-mcp](https://github.com/homeassistant-ai/ha-mcp) server built in and a
**read-only / read-write** switch.

Read-only is enforced by a read-only Home Assistant user and by ha-mcp's own
read-only mode. Claude's processes never hold the token, so the switch holds
even if Claude tries to work around it. Details:
[claude_code/DOCS.md](claude_code/DOCS.md).

## Install

1. Settings → Add-ons → Add-on store → ⋮ → Repositories → add
   `https://github.com/haroldboom/ha-claude-code`.
2. Install **Claude Code**, follow the Documentation tab to create the read-only
   user, paste its token, and start the add-on.

Supports `amd64` and `aarch64`.

## Development

```sh
docker build -t claude-code-addon:dev claude_code
tests/smoke.sh claude-code-addon:dev
```

Not affiliated with Anthropic or the ha-mcp project.
