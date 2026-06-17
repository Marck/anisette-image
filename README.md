# altserver-wifi

A small container image bundling [AltServer-Linux](https://github.com/NyaMisty/AltServer-Linux)
and [netmuxd](https://github.com/jkcoxson/netmuxd) for **headless, USB-free WiFi refresh**
of sideloaded iOS apps (AltStore Classic). Built for `linux/amd64` + `linux/arm64` and
published to `ghcr.io/marck/altserver-wifi` (private).

Designed to run in a Kubernetes **hostNetwork** pod (deployed by the `altserver` Helm
chart in [helm-charts](https://github.com/Marck/helm-charts)), with
[anisette](https://github.com/Dadoum/anisette-v3-server) as a **sidecar** reached on
`127.0.0.1:6969`.

## Why hostNetwork / why this is USB-free

- AltStore Classic re-signs apps with a free Apple developer certificate (the same
  mechanism as Sideloadly). Signatures expire after **7 days** (free accounts: max
  **3 apps**), so apps must be periodically re-signed — that's what this does.
- The device is reached over WiFi via **mDNS** (`_apple-mobdev2._tcp`). Kubernetes pod
  overlays don't pass multicast, so the pod must share the node's network namespace
  (`hostNetwork: true`) and sit on the **same LAN/VLAN** as the iPhone.
- No USB on the cluster: after a **one-time pairing done off-cluster**, netmuxd connects
  to the device over WiFi using the pairing record. The phone is never plugged into the
  cluster.

## How refresh works (no stored credentials)

`entrypoint.sh` stages the pairing record, starts avahi/dbus (mDNS) and `netmuxd`, then
runs **`AltServer` in daemon mode (no arguments)**. The AltStore app on the device drives
refresh and supplies Apple-ID credentials per request — so the **running container stores
no Apple-ID password**. Credentials are only needed for the one-time install (below).

## One-time setup

The operator-facing setup — generating the device pairing record, sealing the secrets,
and the one-time AltStore install — lives with the deployment, in the
[`altserver` Helm chart README](https://github.com/Marck/helm-charts/tree/main/helm-charts/altserver#setup).

## Environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `ALTSERVER_ANISETTE_SERVER` | `http://127.0.0.1:6969` | anisette server URL (the sidecar) |
| `PAIRING_RECORD_DIR` | `/secrets/lockdown` | read-only mount of the pairing record secret |
| `LOCKDOWN_DIR` | `/var/lib/lockdown` | writable dir the record is copied into |
| `ENABLE_AVAHI` | `true` | start avahi/dbus for mDNS |
| `NETMUXD_WAIT` | `5` | seconds to let netmuxd discover the device before AltServer starts |

## Build / versioning

Pinned upstream versions are build args in the `Dockerfile`
(`ALTSERVER_VERSION`, `NETMUXD_VERSION`). The image version is the `VERSION` file; CI
(`.github/workflows/build.yml`) reads it, builds both arches by digest, merges the
manifest, and tags `=VERSION` / `latest` / `sha-<short>`. Bump `VERSION` to publish.

## Notes / caveats

- Runs as **root**: usbmuxd/netmuxd/avahi need to bind the mux socket and do mDNS.
- The exact muxd/avahi configuration can vary by environment; final validation requires a
  real paired device on the LAN.
