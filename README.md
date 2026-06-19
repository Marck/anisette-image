# anisette-image

Mirror-build of [**dadoum/anisette-v3-server**](https://github.com/Dadoum/anisette-v3-server)
to **`ghcr.io/marck/anisette-v3-server`** — a fresh, reproducible, multi-arch image consumed by the
[`anisette` Helm chart](https://github.com/Marck/helm-charts/tree/main/helm-charts/anisette) for
[SideStore](https://sidestore.io).

## Why this exists

Upstream only ever publishes a single **`latest`** Docker tag, and that image is **~a year stale**.
It predates a series of fixes that the SideStore login path needs — most importantly the pre-created
provisioning folder from [upstream PR #47](https://github.com/Dadoum/anisette-v3-server/pull/47).
Running the stale `latest` produces `generic libc/file manipulation error (-45054)` at provisioning,
because the Apple ADI lib does a *non-recursive* `mkdir(<runtimeDir>/anisette-v3/provisioning/<uuid>)`
whose parent doesn't exist.

Rather than guess which upstream commit fixes things, this repo **builds upstream's own Dockerfile at
a pinned commit** and publishes the result to our registry. Updates are deliberate: Renovate raises a
PR to bump the pin, and CI refuses to publish an image that's missing the provisioning folder.

## How it works

- **No vendored Dockerfile.** The build context is upstream's repo at the pinned commit
  (`buildx` git context), so we always build their exact, current Dockerfile —
  see [`.github/workflows/build.yml`](.github/workflows/build.yml).
- **Pinned upstream commit.** `UPSTREAM_REF` in the workflow `env:` is a 40-char commit SHA.
- **Renovate** ([`renovate.json`](renovate.json)) tracks `Dadoum/anisette-v3-server`’s `main` via the
  `git-refs` datasource and opens a PR to bump `UPSTREAM_REF` when upstream moves. Never auto-merged —
  an upstream bump can change provisioning behaviour and is only fully verifiable with a real device.
- **Smoke gate.** Before publishing, CI builds the image and asserts the server binary, the non-root
  `Alcoholic` user, and the **`/opt/anisette-v3/provisioning`** folder (PR #47) all exist. A pin that
  predates PR #47 fails the build.
- **Multi-arch.** `linux/amd64` + `linux/arm64`, built per-platform then merged into one manifest.

## Tags

| Tag | Meaning |
|-----|---------|
| `latest` | Newest build from the default branch |
| `upstream-<short-sha>` | The pinned upstream commit this image was built from |

## Updating the upstream pin

1. Let Renovate open the bump PR (or edit `UPSTREAM_REF` by hand to a newer commit SHA from
   `Dadoum/anisette-v3-server@main`).
2. CI builds + smoke-tests it. Merge to `main` → the image publishes to GHCR.
3. The Helm chart pulls `:latest` (Renovate there pins it by digest), so ArgoCD rolls it out.
4. **Verify on a device** — sign in via SideStore — since provisioning can't be checked in CI.

## One-time setup

After the **first** successful publish, make the GHCR package **public** so the cluster can pull it
without an imagePullSecret (the `anisette` chart is intentionally secret-free):

> GitHub → your profile → **Packages** → `anisette-v3-server` → **Package settings** →
> **Change visibility** → **Public**.

## Local build (podman)

```bash
# Build upstream's Dockerfile at the pinned commit, exactly like CI:
REF=$(grep -oE 'UPSTREAM_REF: *"[a-f0-9]{40}"' .github/workflows/build.yml | grep -oE '[a-f0-9]{40}')
podman build -t anisette-v3-server:local "https://github.com/Dadoum/anisette-v3-server.git#${REF}"

# Confirm the -45054 fix (PR #47) is present:
podman run --rm --entrypoint sh anisette-v3-server:local -c \
  'test -d /opt/anisette-v3/provisioning && echo "provisioning folder OK"'
```

## History

This repo previously built `altserver-wifi` (AltServer-Linux + netmuxd). That approach is a dead end on
iOS 17+ (Apple moved on-device services behind RemoteXPC), so it was replaced by SideStore + a
self-hosted anisette server. The build pipeline was repurposed here.
