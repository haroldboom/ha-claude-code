ARG BUILD_FROM=python:3.13-slim-bookworm
FROM ${BUILD_FROM}

ARG HA_MCP_VERSION=8.7.0
ARG TTYD_VERSION=1.7.7
ARG CLAUDE_CHANNEL=stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git jq less nginx-light procps ripgrep sudo tini tmux \
    && rm -rf /var/lib/apt/lists/*

RUN case "$(dpkg --print-architecture)" in \
        amd64) t=x86_64 ;; arm64) t=aarch64 ;; *) echo "unsupported arch" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${t}" \
    && chmod 0755 /usr/local/bin/ttyd

# ha-mcp lives in a root-owned venv so the claude user can't modify it.
RUN python -m venv /opt/ha-mcp \
    && /opt/ha-mcp/bin/pip install --no-cache-dir "ha-mcp==${HA_MCP_VERSION}"

# Native Claude Code binary, copied out of root's home so every user can run it.
# Updates ship as add-on releases (DISABLE_AUTOUPDATER in claude-session).
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CHANNEL}" \
    && install -m 0755 "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude \
    && rm -rf /root/.local /root/.claude /root/.claude.json /root/.cache

# claude: runs the terminal and Claude Code. mcp: runs ha-mcp and is the only
# user that can read the HA token. claude reaches ha-mcp only through sudo.
RUN groupadd -g 1000 claude && useradd -u 1000 -g claude -d /config/home -s /bin/bash -M claude \
    && groupadd -r mcp && useradd -r -g mcp -d /data/ha-mcp -s /usr/sbin/nologin -M mcp

COPY rootfs /
RUN chmod 0755 /usr/local/bin/start.sh /usr/local/bin/ha-mcp-stdio /usr/local/bin/claude-session \
    && chmod 0440 /etc/sudoers.d/ha-mcp \
    && visudo -cf /etc/sudoers.d/ha-mcp

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/start.sh"]
