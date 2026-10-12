# studio box: one per project (docs/superpowers/specs/2026-10-12-project-box-design.md).
# Node, bun, opencode, goose and Chromium are mounted read-only from the host, not installed here.
FROM ubuntu:26.04
ARG UID=1000
ARG GID=1000
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates python3 ripgrep iptables socat procps \
      libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 \
      libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
      libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 fonts-liberation fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /box/home && chown "$UID:$GID" /box/home
