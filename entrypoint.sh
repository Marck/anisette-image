#!/usr/bin/env bash
# Boot order (mirrors the documented bare-metal WiFi-refresh setup):
#   pairing record -> avahi/dbus (mDNS) -> netmuxd (network device) -> AltServer daemon.
# AltServer runs with NO Apple-ID args: ongoing refresh is driven by the AltStore app
# on the device, which supplies credentials per request. Credentials are only needed for
# the one-time install (see README).
set -euo pipefail

LOCKDOWN_DIR="${LOCKDOWN_DIR:-/var/lib/lockdown}"
PAIRING_RECORD_DIR="${PAIRING_RECORD_DIR:-/secrets/lockdown}"

log() { echo "[entrypoint] $*"; }

# 1. Stage the read-only pairing record(s) into the writable lockdown dir.
mkdir -p "${LOCKDOWN_DIR}"
if compgen -G "${PAIRING_RECORD_DIR}/*.plist" >/dev/null; then
  log "Installing pairing record(s) from ${PAIRING_RECORD_DIR}"
  cp -f "${PAIRING_RECORD_DIR}"/*.plist "${LOCKDOWN_DIR}/"
  chmod 0600 "${LOCKDOWN_DIR}"/*.plist || true
else
  log "WARNING: no *.plist pairing record in ${PAIRING_RECORD_DIR}."
  log "WiFi refresh needs a pairing record generated off-cluster once (see README)."
fi

# 1b. Optionally pre-stage the AltStore IPA so `install-altstore` can use it without a
#     kubectl cp. Only downloads when ALTSTORE_IPA_URL is set; safe to leave unset.
ALTSTORE_IPA_PATH="${ALTSTORE_IPA_PATH:-/var/lib/altserver/AltStore.ipa}"
if [ -n "${ALTSTORE_IPA_URL:-}" ] && [ ! -f "${ALTSTORE_IPA_PATH}" ]; then
  mkdir -p "$(dirname "${ALTSTORE_IPA_PATH}")"
  log "Pre-staging AltStore IPA from ${ALTSTORE_IPA_URL}"
  curl -fsSL -o "${ALTSTORE_IPA_PATH}" "${ALTSTORE_IPA_URL}" \
    || log "IPA download failed (continuing; install-altstore can still fetch on demand)"
fi
export ALTSTORE_IPA_PATH

# 2. dbus + avahi for mDNS — AltServer advertises _altserver._tcp via libdns_sd
#    (avahi-compat), so avahi must be up. Toggle with ENABLE_AVAHI.
if [ "${ENABLE_AVAHI:-true}" = "true" ] && command -v avahi-daemon >/dev/null 2>&1; then
  dbus-uuidgen --ensure || true                 # avahi/dbus need a machine-id
  mkdir -p /run/dbus && rm -f /run/dbus/pid
  dbus-daemon --system --fork || log "dbus-daemon failed (continuing)"
  for _ in $(seq 1 10); do                       # wait for the system bus socket
    [ -S /run/dbus/system_bus_socket ] && break; sleep 0.3
  done
  avahi-daemon --no-chroot --no-rlimits -D || log "avahi-daemon failed (continuing)"
fi

# 3. netmuxd — discovers the device over WiFi (mDNS) and serves the usbmuxd socket.
log "Starting netmuxd"
netmuxd &
sleep "${NETMUXD_WAIT:-5}"

# 4. AltServer in daemon mode (foreground, PID 1) — handles refresh requests.
log "Starting AltServer (daemon) using anisette ${ALTSERVER_ANISETTE_SERVER}"
exec AltServer
