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

# 2. dbus + avahi for mDNS (netmuxd also does its own mDNS; toggle with ENABLE_AVAHI).
if [ "${ENABLE_AVAHI:-true}" = "true" ] && command -v avahi-daemon >/dev/null 2>&1; then
  mkdir -p /run/dbus && rm -f /run/dbus/pid
  dbus-daemon --system --fork || log "dbus-daemon failed (continuing)"
  avahi-daemon --no-chroot -D || log "avahi-daemon failed (continuing)"
fi

# 3. netmuxd — discovers the device over WiFi (mDNS) and serves the usbmuxd socket.
log "Starting netmuxd"
netmuxd &
sleep "${NETMUXD_WAIT:-5}"

# 4. AltServer in daemon mode (foreground, PID 1) — handles refresh requests.
log "Starting AltServer (daemon) using anisette ${ALTSERVER_ANISETTE_SERVER}"
exec AltServer
