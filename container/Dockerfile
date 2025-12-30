# Stage 1: Download and extract Go
FROM debian:13-slim@sha256:91e29de1e4e20f771e97d452c8fa6370716ca4044febbec4838366d459963801 AS golang-installer
ARG GOLANG_VERSION=1.25.0
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -fsSLo /tmp/go.tar.gz https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz && \
    tar -C /tmp -xzf /tmp/go.tar.gz

# Stage 2: Final image
FROM debian:13-slim@sha256:91e29de1e4e20f771e97d452c8fa6370716ca4044febbec4838366d459963801

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

# Install HashiCorp repository and terraform (separate layer for better caching)
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    curl -fsSL https://apt.releases.hashicorp.com/gpg > /etc/apt/trusted.gpg.d/hashicorp.asc && \
    echo "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends terraform

# Install uv and uvx from the official Astral image
COPY --from=ghcr.io/astral-sh/uv:latest@sha256:81f1a183fbdd9cec1498b066a32f0da043d4a9dda12b8372c7bfd183665e485d /uv /uvx /bin/

# Install golang from builder stage
COPY --from=golang-installer /tmp/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Install hadolint
ARG HADOLINT_VERSION=2.12.0
# Note: Version sourced from versions.txt, but ARG defaults kept for compatibility
RUN curl -fsSLo /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64 && \
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

# Copy default configuration files to /etc/skel/
# These will be copied to user home by entrypoint.sh
COPY --chown=0:0 --chmod=u=rw,u+X,go=r,go+X ../common/homedir/ /etc/skel/

COPY container/entrypoint.sh /entrypoint.sh
RUN chmod a+rx /entrypoint.sh
COPY container/entrypoint_user.sh /entrypoint_user.sh
RUN chmod a+rx /entrypoint_user.sh
ENTRYPOINT ["/entrypoint.sh"]
