FROM debian:13-slim@sha256:66b37a5078a77098bfc80175fb5eb881a3196809242fd295b25502854e12cbec

ARG GOLANG_VERSION=1.25.0
ARG HADOLINT_VERSION=2.12.0
ENV PYTHON_TOOLS=dvc[all],pipenv,poetry,pre-commit

ENV DEBIAN_FRONTEND=noninteractive
RUN rm -f /etc/apt/apt.conf.d/docker-clean
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    bc \
    ca-certificates \
    curl \
    docker-cli \
    dnsutils \
    findutils \
    g++ \
    gh \
    git \
    gosu \
    jq \
    less \
    lsof \
    make \
    man-db \
    nodejs \
    npm \
    procps \
    psmisc \
    python3 \
    python3-pip \
    ripgrep \
    rsync \
    shellcheck \
    socat \
    tcl \
    tk \
    unzip \
    vim \
    yq

# Allow higher UID/GID range for useradd
RUN sed -i 's/^UID_MIN.*/UID_MIN 1000/' /etc/login.defs && \
    sed -i 's/^UID_MAX.*/UID_MAX 200000/' /etc/login.defs

# Install uv and uvx from the official Astral image
COPY --from=ghcr.io/astral-sh/uv:latest@sha256:4b96ee9429583983fd172c33a02ecac5242d63fb46bc27804748e38c1cc9ad0d /uv /uvx /bin/

# Install Python tools globally during build to avoid runtime delay
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3013
RUN echo "Installing Python tools globally..." && \
    for tool in $(echo "$PYTHON_TOOLS" | tr ',' ' '); do \
        echo "Installing $tool..." && \
        pip install --no-cache-dir --break-system-packages "$tool"; \
    done && \
    echo "Python tools installation complete"

# Install hadolint
RUN curl -fsSLo /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64 && \
    install /tmp/hadolint /usr/local/bin && \
    rm -f /tmp/hadolint

# Install golang
RUN curl -fsSLo /tmp/go.tar.gz https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm -f /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# Install coding agents
# hadolint ignore=DL3016
RUN npm install -g \
    @anthropic-ai/claude-code@latest \
    @google/gemini-cli@latest \
    @github/copilot@latest

COPY entrypoint.sh /entrypoint.sh
RUN chmod a+rx /entrypoint.sh
COPY entrypoint_user.sh /entrypoint_user.sh
RUN chmod a+rx /entrypoint_user.sh
ENTRYPOINT ["/entrypoint.sh"]
