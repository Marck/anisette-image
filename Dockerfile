# AltServer-Linux + netmuxd, for headless WiFi refresh of sideloaded iOS apps.
#
# Runs in a Kubernetes hostNetwork pod (mDNS device discovery needs the node's LAN).
# anisette is provided by a separate sidecar container, reached on 127.0.0.1:6969.
#
# Base: trixie (GLIBC 2.41). netmuxd's release binary needs GLIBC >= 2.38, so
# bookworm (2.36) fails at runtime with "GLIBC_2.38 not found".
FROM debian:trixie-slim

# buildx sets TARGETARCH per platform (amd64 / arm64).
ARG TARGETARCH
# Pinned upstream versions — Renovate keeps these in lockstep via the grouped
# "altserver stack" custom managers (see renovate.json); each bump is reviewed + the
# image smoke-tested in CI before release.
# renovate: datasource=github-releases depName=NyaMisty/AltServer-Linux
ARG ALTSERVER_VERSION=0.0.5
# renovate: datasource=github-releases depName=jkcoxson/netmuxd
ARG NETMUXD_VERSION=0.3.2
# renovate: datasource=github-tags depName=altstoreio/AltStore versioning=loose
ARG ALTSTORE_VERSION=1.6.3

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

# Bake AltStore Classic (arch-independent IPA) so install-altstore works offline and the
# whole client+server stack is versioned as one image. The CDN path uses underscores for
# dots (1.6.3 -> 1_6_3). A runtime ALTSTORE_IPA_URL still overrides this if set.
RUN set -eux; \
    mkdir -p /var/lib/altserver; \
    ver="$(echo "${ALTSTORE_VERSION}" | tr '.' '_')"; \
    curl -fsSL -o /var/lib/altserver/AltStore.ipa \
      "https://cdn.altstore.io/file/altstore/apps/altstore/${ver}.ipa"

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
