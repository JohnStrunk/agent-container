# Stage 1: Download and extract Go
FROM debian:13-slim@sha256:e711a7b30ec1261130d0a121050b4ed81d7fb28aeabcf4ea0c7876d4e9f5aca2 AS golang-installer
ARG GOLANG_VERSION=1.25.0
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -fsSLo /tmp/go.tar.gz https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz && \
    tar -C /tmp -xzf /tmp/go.tar.gz

# Stage 2: Final image
FROM debian:13-slim@sha256:e711a7b30ec1261130d0a121050b4ed81d7fb28aeabcf4ea0c7876d4e9f5aca2

# PYTHON_TOOLS documented here for reference
ENV PYTHON_TOOLS=dvc[all],pipenv,poetry,pre-commit
ENV DEBIAN_FRONTEND=noninteractive

# Allow higher UID/GID range for useradd (stable configuration)
RUN sed -i 's/^UID_MIN.*/UID_MIN 1000/' /etc/login.defs && \
    sed -i 's/^UID_MAX.*/UID_MAX 200000/' /etc/login.defs

# Install base system packages (debian-native tools)
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
    gnupg \
    gosu \
    jq \
    less \
    lsb-release \
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

# Install HashiCorp repository and terraform (separate layer for better caching)
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    curl -fsSL https://apt.releases.hashicorp.com/gpg > /etc/apt/trusted.gpg.d/hashicorp.asc && \
    echo "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends terraform

# Install uv and uvx from the official Astral image
COPY --from=ghcr.io/astral-sh/uv:latest@sha256:5cb6b54d2bc3fe2eb9a8483db958a0b9eebf9edff68adedb369df8e7b98711a2 /uv /uvx /bin/

# Install golang from builder stage
COPY --from=golang-installer /tmp/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Install hadolint
ARG HADOLINT_VERSION=2.12.0
RUN curl -fsSLo /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64 && \
    install /tmp/hadolint /usr/local/bin && \
    rm -f /tmp/hadolint

# Install Python tools globally during build to avoid runtime delay
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3013,DL3042
RUN --mount=type=cache,target=/root/.cache/pip \
    echo "Installing Python tools globally..." && \
    for tool in $(echo "$PYTHON_TOOLS" | tr ',' ' '); do \
    echo "Installing $tool..." && \
    pip install --cache-dir=/root/.cache/pip --break-system-packages "$tool"; \
    done && \
    echo "Python tools installation complete"

# Install coding agents with npm cache mount
# hadolint ignore=DL3016
RUN --mount=type=cache,target=/root/.npm \
    npm install -g --cache /root/.npm \
    @anthropic-ai/claude-code@latest \
    @google/gemini-cli@latest

# Copy default configuration files to /etc/skel/
# These will be copied to user home by entrypoint.sh
COPY --chown=0:0 --chmod=u=rw,u+X,go=r,go+X files/homedir/ /etc/skel/

COPY entrypoint.sh /entrypoint.sh
RUN chmod a+rx /entrypoint.sh
COPY entrypoint_user.sh /entrypoint_user.sh
RUN chmod a+rx /entrypoint_user.sh
ENTRYPOINT ["/entrypoint.sh"]
