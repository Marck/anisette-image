# AltServer-Linux + netmuxd, for headless WiFi refresh of sideloaded iOS apps.
#
# Runs in a Kubernetes hostNetwork pod (mDNS device discovery needs the node's LAN).
# anisette is provided by a separate sidecar container, reached on 127.0.0.1:6969.
#
# Base: trixie (GLIBC 2.41). netmuxd's release binary needs GLIBC >= 2.38, so
# bookworm (2.36) fails at runtime with "GLIBC_2.38 not found".
FROM debian:trixie-slim

# buildx sets TARGETARCH per platform (amd64 / arm64). Pinned upstream versions.
ARG TARGETARCH
ARG ALTSERVER_VERSION=0.0.5
ARG NETMUXD_VERSION=0.3.2

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
      usbmuxd libimobiledevice-1.0-6 libimobiledevice-utils \
      avahi-daemon avahi-utils libavahi-compat-libdnssd1 dbus \
    && rm -rf /var/lib/apt/lists/*

# Fetch the AltServer (raw binary) + netmuxd (tarball) assets for this arch.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) ALT_ARCH=x86_64;  MUX_ARCH=x86_64 ;; \
      arm64) ALT_ARCH=aarch64; MUX_ARCH=aarch64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/AltServer \
      "https://github.com/NyaMisty/AltServer-Linux/releases/download/v${ALTSERVER_VERSION}/AltServer-${ALT_ARCH}"; \
    chmod +x /usr/local/bin/AltServer; \
    curl -fsSL -o /tmp/netmuxd.tar.gz \
      "https://github.com/jkcoxson/netmuxd/releases/download/v${NETMUXD_VERSION}/netmuxd-${MUX_ARCH}-unknown-linux-gnu.tar.gz"; \
    tar -xzf /tmp/netmuxd.tar.gz -C /usr/local/bin; \
    rm /tmp/netmuxd.tar.gz; \
    chmod +x /usr/local/bin/netmuxd

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY install-altstore.sh /usr/local/bin/install-altstore
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/install-altstore

# Defaults overridable from the Helm chart.
ENV ALTSERVER_ANISETTE_SERVER=http://127.0.0.1:6969 \
    PAIRING_RECORD_DIR=/secrets/lockdown \
    LOCKDOWN_DIR=/var/lib/lockdown \
    ALTSTORE_IPA_PATH=/var/lib/altserver/AltStore.ipa

# Runs as root: usbmuxd/netmuxd/avahi need to bind the mux socket and do mDNS.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
