#!/usr/bin/env bash
# One-shot AltStore (or any IPA) install helper — run interactively via:
#   kubectl -n altserver exec -it <pod> -c altserver -- install-altstore <apple-id> [ipa-path-or-url]
#
# Why this can't be fully automated: Apple 2FA prompts for a one-time code (sent to
# the device, ~30s TTL) during auth, so the install is inherently interactive. This
# helper just removes the boilerplate: it derives the UDID from the pairing record file
# (idevice_id -l is empty with netmuxd), uses the pre-staged IPA by default, reads the
# password without echoing it, and points AltServer at the anisette sidecar.
set -euo pipefail

APPLE_ID="${1:-}"
IPA_ARG="${2:-${ALTSTORE_IPA_PATH:-/var/lib/altserver/AltStore.ipa}}"

if [ -z "$APPLE_ID" ]; then
  echo "usage: install-altstore <apple-id> [ipa-path-or-url]" >&2
  echo "  IPA defaults to the pre-staged \$ALTSTORE_IPA_PATH ($IPA_ARG)" >&2
  exit 2
fi

# Resolve the IPA — download if a URL was given.
if [[ "$IPA_ARG" =~ ^https?:// ]]; then
  IPA=/tmp/install-altstore.ipa
  echo "Downloading IPA from ${IPA_ARG} ..."
  curl -fsSL -o "$IPA" "$IPA_ARG"
else
  IPA="$IPA_ARG"
fi
if [ ! -f "$IPA" ]; then
  echo "ERROR: IPA not found at '$IPA'." >&2
  echo "  Pre-stage one via ALTSTORE_IPA_URL, pass a path/URL as arg 2, or kubectl cp it in." >&2
  exit 1
fi

# Derive the UDID from the pairing record filename. netmuxd does NOT implement the usbmux
# "subscribe" call, so `idevice_id -l` is empty even when the device is registered — don't
# rely on it. The pairing record (which netmuxd needs anyway) is named <UDID>.plist.
# Override with the UDID env var if needed.
LOCKDOWN_DIR="${LOCKDOWN_DIR:-/var/lib/lockdown}"
UDID="${UDID:-$(ls "${LOCKDOWN_DIR}"/*.plist 2>/dev/null | head -n1 | xargs -r basename 2>/dev/null | sed 's/\.plist$//')}"
if [ -z "$UDID" ]; then
  echo "ERROR: no pairing record in ${LOCKDOWN_DIR} and no UDID env set." >&2
  echo "  Seal the device pairing record into altserver-pairing-record first (see README)." >&2
  exit 1
fi
echo "Target device: $UDID  (from pairing record; verify it's in netmuxd's 'Adding device' log)"
echo "IPA:           $IPA"

# Read the password without echoing or putting it in the exec command line / shell history.
read -r -s -p "Apple ID password for ${APPLE_ID}: " APPLE_PW; echo
if [ -z "$APPLE_PW" ]; then echo "ERROR: empty password." >&2; exit 1; fi

echo "Installing — if 2FA is enabled, enter the 6-digit code when prompted..."
exec env ALTSERVER_ANISETTE_SERVER="${ALTSERVER_ANISETTE_SERVER:-http://127.0.0.1:6969}" \
  AltServer -u "$UDID" -a "$APPLE_ID" -p "$APPLE_PW" "$IPA"
