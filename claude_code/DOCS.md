# Claude Code

Claude Code in a terminal in the Home Assistant sidebar, with the community
[ha-mcp](https://github.com/homeassistant-ai/ha-mcp) server already connected.
One option switches between read-only and read/write access to Home Assistant.

## Setup

1. **Create a read-only HA user** (needed for `read_only` mode, which is the default).
   Home Assistant has a `system-read-only` group, but the UI can't assign it:
   1. Settings → People → Users → add a user (for example `claude`), not an administrator.
   2. Stop Core (`ha core stop` from the SSH add-on).
   3. In `/config/.storage/auth`, find that user and set `"group_ids": ["system-read-only"]`.
   4. Start Core (`ha core start`), log in as that user, and create a long-lived
      access token on its profile page.
2. Paste the token into **read_only_token** and start the add-on.
3. Open **Claude Code** in the sidebar and log in. You have three ways to log in
   (see [Claude login](#claude-login)). Logging in from the terminal is the default.
4. Run `/mcp` in Claude Code: `home-assistant` should show as connected.

## Options

| Option | Meaning |
|---|---|
| `mode` | `read_only` (default) or `read_write`. Restart the add-on after changing it. |
| `read_only_token` | Token of the read-only HA user. Required for `read_only`. |
| `read_write_token` | Optional token for `read_write`. Empty means the add-on's own admin access. |
| `ha_url` | Where to reach HA with the tokens above. The default works inside HA OS. |
| `claude_oauth_token` | Optional. Pro/Max subscription token from `claude setup-token`. |
| `anthropic_api_key` | Optional. API key, billed to the API account. Ignored if `claude_oauth_token` is set. |

## Claude login

Claude Pro and Max subscriptions include Claude Code, and usage counts against
the same limits as claude.ai. There are three ways to log in:

- **Log in from the terminal** (default, nothing to set). Choose the Claude account
  option, open the link it prints on any device, approve, and paste the code back.
  The login is stored in the add-on config folder, survives restarts and updates,
  and refreshes itself.
- **`claude_oauth_token`**: run `claude setup-token` on any computer where you use
  Claude Code. It prints a subscription token that lasts about a year. Paste it into
  this option and restart; the terminal then skips the login screen. When it
  expires, generate a new one.
- **`anthropic_api_key`**: pay-per-use API billing instead of a subscription.

If both a token and a key are set, the add-on uses the subscription token, so a
leftover key never moves billing off the subscription. Claude can see its own login
credential (it needs it to run). It still never sees the Home Assistant token.

## How read-only is enforced

Read-only mode has two locks, and neither depends on Claude following instructions:

1. **The HA user.** HA itself refuses entity control, config edits and template
   rendering for `system-read-only` users. The add-on checks this at startup: if the
   read-only token can render a template, the user isn't in that group and the add-on
   **refuses to start**.
2. **ha-mcp's read-only mode** (`READ_ONLY_MODE`). ha-mcp hides its write tools and
   blocks write actions in mixed tools at call time. This covers what the HA user
   alone doesn't: HA's read-only group only checks entity *control*, so service calls
   with no entity target (`notify.*`, `script.<name>`, `shell_command.*`,
   `rest_command.*`) are still allowed for that user. With ha-mcp's
   `ha_call_service` hidden, Claude has no tool to make them.

For those locks to hold, Claude must not be able to get a token or change the
mode, so the container is split between two users:

- **`claude`** runs the terminal and Claude Code. Its environment holds no HA
  token. It can't read `/data` (the add-on options, including the tokens), the
  ha-mcp settings, or the Supervisor token.
- **`mcp`** runs ha-mcp and is the only user that can read the token. Claude Code
  starts ha-mcp through one sudo rule that allows that exact command, with no
  arguments and a reset environment, so it can't pass a different mode or token.
  ha-mcp's settings web UI is turned off, so nothing in the container can switch
  read-only off while it runs.
- The terminal only accepts connections from HA ingress, so other add-ons can't
  open it.

The CI smoke test (`tests/smoke.sh`) checks each of these against a mock HA on
every push.

In `read_write` mode Claude still can't read the token. It can do whatever that
token's user can do through ha-mcp.

## Files

- `/addon_configs/<id>_claude_code/workspace`: Claude's working directory.
- `/addon_configs/<id>_claude_code/home`: Claude's home (login, settings, history).

Claude can't reach your HA configuration directory directly. It works through
ha-mcp's tools.

## Updates

Claude Code's auto-updater is off inside the add-on. New Claude Code and ha-mcp
versions arrive as add-on releases.
