# Changelog

## 0.2.0

- New `claude_oauth_token` option: paste a `claude setup-token` subscription token
  (Pro/Max) to skip the terminal login. It takes priority over `anthropic_api_key`.

## 0.1.0

- First release: Claude Code in an ingress terminal, ha-mcp 8.7.0 built in,
  `read_only` / `read_write` mode enforced through a read-only HA user plus
  ha-mcp's read-only mode, with the token kept away from Claude's processes.
