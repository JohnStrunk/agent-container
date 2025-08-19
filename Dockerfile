FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN rm -f /etc/apt/apt.conf.d/docker-clean
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    docker-cli \
    git \
    gosu \
    nodejs \
    npm \
    python3 \
    python3-pip

# Allow higher UID/GID range for useradd
RUN sed -i 's/^UID_MIN.*/UID_MIN 1000/' /etc/login.defs && \
    sed -i 's/^UID_MAX.*/UID_MAX 200000/' /etc/login.defs

# Install uv and uvx from the official Astral image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN curl -fsSLo /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64 && \
    install /tmp/hadolint /usr/local/bin && \
    rm -f /tmp/hadolint

# Install Python-based tools
# hadolint ignore=DL3013
RUN pip install --no-cache-dir --break-system-packages \
    pipenv \
    poetry \
    pre-commit

# Install coding agents
# hadolint ignore=DL3016
RUN npm install -g @anthropic-ai/claude-code && \
    npm install -g @google/gemini-cli

COPY entrypoint.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
