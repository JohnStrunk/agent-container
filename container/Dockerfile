# Stage 1: Download and extract Go
FROM debian:13-slim@sha256:26f98ccd92fd0a44d6928ce8ff8f4921b4d2f535bfa07555ee5d18f61429cf0c AS golang-installer
ARG GOLANG_VERSION=1.25.0
# hadolint ignore=DL3008,SC2086
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    ARCH="$(dpkg --print-architecture)" && \
    curl -fsSLo /tmp/go.tar.gz https://go.dev/dl/go${GOLANG_VERSION}.linux-${ARCH}.tar.gz && \
    tar -C /tmp -xzf /tmp/go.tar.gz

# Stage 2: Final image
FROM debian:13-slim@sha256:26f98ccd92fd0a44d6928ce8ff8f4921b4d2f535bfa07555ee5d18f61429cf0c

# PYTHON_TOOLS documented here for reference
ENV PYTHON_TOOLS=dvc[all],pipenv,poetry,pre-commit
ENV DEBIAN_FRONTEND=noninteractive

# Allow higher UID/GID range for useradd (stable configuration)
RUN sed -i 's/^UID_MIN.*/UID_MIN 1000/' /etc/login.defs && \
    sed -i 's/^UID_MAX.*/UID_MAX 200000/' /etc/login.defs

# Install base system packages (debian-native tools)
RUN rm -f /etc/apt/apt.conf.d/docker-clean

# Copy package lists for installation
COPY ../common/packages/apt-packages.txt /tmp/apt-packages.txt
COPY ../common/packages/npm-packages.txt /tmp/npm-packages.txt
COPY ../common/packages/python-packages.txt /tmp/python-packages.txt
COPY ../common/packages/versions.txt /tmp/versions.txt

# hadolint ignore=DL3008
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    grep -v '^#' /tmp/apt-packages.txt | grep -v '^$' | xargs apt-get install -y --no-install-recommends

# Install uv and uvx from the official Astral image
COPY --from=ghcr.io/astral-sh/uv:latest@sha256:72ab0aeb448090480ccabb99fb5f52b0dc3c71923bffb5e2e26517a1c27b7fec /uv /uvx /bin/

# Install golang from builder stage
COPY --from=golang-installer /tmp/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Install hadolint
ARG HADOLINT_VERSION=2.12.0
# Note: Version sourced from versions.txt, but ARG defaults kept for compatibility
# hadolint ignore=SC2086
RUN ARCH="$(uname -m)" && \
    case "$ARCH" in \
        aarch64) HADOLINT_ARCH="arm64" ;; \
        x86_64) HADOLINT_ARCH="x86_64" ;; \
        *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac && \
    curl -fsSLo /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-${HADOLINT_ARCH} && \
    install /tmp/hadolint /usr/local/bin && \
    rm -f /tmp/hadolint

# Install Python tools globally during build to avoid runtime delay
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3013,DL3042
RUN --mount=type=cache,target=/root/.cache/pip \
    grep -v '^#' /tmp/python-packages.txt | grep -v '^$' | xargs pip install --break-system-packages

# Install coding agents with npm cache mount
# hadolint ignore=DL3016
RUN --mount=type=cache,target=/root/.npm \
    xargs npm install -g --cache /root/.npm < /tmp/npm-packages.txt

# Copy and run common tool installation script
COPY ../common/scripts/install-tools.sh /tmp/install-tools.sh
RUN chmod +x /tmp/install-tools.sh && \
    /tmp/install-tools.sh && \
    rm /tmp/install-tools.sh


# Create environment marker file to identify container environment
RUN echo "agent-container" > /etc/agent-environment && \
    chmod 644 /etc/agent-environment

COPY container/entrypoint.sh /entrypoint.sh
RUN chmod a+rx /entrypoint.sh
COPY container/entrypoint_user.sh /entrypoint_user.sh
RUN chmod a+rx /entrypoint_user.sh
ENTRYPOINT ["/entrypoint.sh"]
