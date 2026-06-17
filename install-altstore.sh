#!/usr/bin/env bash
# One-shot AltStore (or any IPA) install helper — run interactively via:
#   kubectl -n altserver exec -it <pod> -c altserver -- install-altstore <apple-id> [ipa-path-or-url]
#
# Why this can't be fully automated: Apple 2FA prompts for a one-time code (sent to
# the device, ~30s TTL) during auth, so the install is inherently interactive. This
# helper just removes the boilerplate: it auto-detects the UDID via netmuxd, uses the
# pre-staged IPA by default, reads the password without echoing it, and points AltServer
# at the anisette sidecar.
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

# The device must already be visible through netmuxd (WiFi sync on, same LAN).
UDID="$(idevice_id -l 2>/dev/null | head -n1 || true)"
if [ -z "$UDID" ]; then
  echo "ERROR: no device visible to netmuxd (idevice_id -l is empty)." >&2
  echo "  Enable 'Show this iPhone when on Wi-Fi', put the phone on the same LAN, and retry." >&2
  exit 1
fi
echo "Target device: $UDID"
echo "IPA:           $IPA"

# Read the password without echoing or putting it in the exec command line / shell history.
read -r -s -p "Apple ID password for ${APPLE_ID}: " APPLE_PW; echo
if [ -z "$APPLE_PW" ]; then echo "ERROR: empty password." >&2; exit 1; fi

echo "Installing — if 2FA is enabled, enter the 6-digit code when prompted..."
exec env ALTSERVER_ANISETTE_SERVER="${ALTSERVER_ANISETTE_SERVER:-http://127.0.0.1:6969}" \
  AltServer -u "$UDID" -a "$APPLE_ID" -p "$APPLE_PW" "$IPA"
