# Jellyfin

Self-hosted media server, exposed on HTTPS through Traefik at `jellyfin.${DOMAIN}`.

## What is deployed

- Namespace `jellyfin` (PodSecurity `privileged` — required because the config
  volume is a `hostPath`, forbidden under `baseline`/`restricted`)
- Static `PersistentVolume` + `PersistentVolumeClaim` mounting the NAS video
  share **read-only** (`//${NAS_IP}/${NAS_SHARE_VIDEO}`), reusing the
  `nascreds-ro` secret from the storage setup
- Deployment running `jellyfin/jellyfin`:
  - `/config` → subdirectory `/var/mnt/hdd-data-1/jellyfin-config` on the shared
    local Talos disk (persistent, SQLite-safe)
  - `/cache` → `emptyDir` (transient transcode scratch)
  - `/media/video` → NAS share (read-only)
- `ClusterIP` Service on port 8096
- Ingress `jellyfin.${DOMAIN}` through Traefik, TLS via cert-manager `letsencrypt`

## Required env

Add to `.env` (most are shared with the storage/networking setup):

```bash
DOMAIN=example.com          # already set — Ingress host jellyfin.${DOMAIN}
NAS_IP=192.168.x.x          # already set — NAS address
NAS_SHARE_VIDEO=video       # NAS share holding the media library (read-only)
```

## Prerequisites

1. **NAS read-only credentials** — the `nascreds-ro` secret must already exist in
   the `default` namespace (created during [04.storage](../04.storage/README.md), Step 1b).

2. **Local disk for the config** — the Deployment mounts the config as a
   subdirectory (`/var/mnt/hdd-data-1/jellyfin-config`) of the existing
   `hdd-data-1` Talos UserVolume. No per-app Talos provisioning is needed:
   `hostPath: DirectoryOrCreate` creates the subdirectory on first start, since
   `/var/mnt/hdd-data-1` is already a writable mount (see
   [04.storage](../04.storage/README.md), "Local Disk").

## Apply

```bash
# set -a exports everything sourced — required, envsubst only sees exported vars
set -a; source ../.env; set +a
kubectl kustomize ./jellyfin | envsubst | kubectl apply -f -
```

## First-time setup

Open `https://jellyfin.${DOMAIN}` and run the setup wizard. Add a library
pointing at `/media/video` (the read-only NAS mount). Jellyfin only reads from
it, so it cannot move/delete/rename files — expected and intentional.

Optionally, under **Dashboard → Networking → Known proxies**, you can add
Traefik's pod network so Jellyfin logs the real client IP instead of the proxy.

## Notes

- **Read-only media:** the share is mounted `ro`, so metadata Jellyfin would
  normally write next to media files (`.nfo`, downloaded artwork) is kept inside
  Jellyfin's own config/metadata store instead — fine for playback.
- **Transcoding:** software only (no GPU passthrough configured). No CPU limit is
  set on the container so transcodes don't stutter; a 2Gi memory limit caps
  runaway use. For heavy use consider provisioning hardware acceleration.
- **DNS:** `jellyfin.${DOMAIN}` resolves to Traefik via CoreDNS split DNS
  (Tailscale clients) and the Pi-hole dnsmasq wildcard (LAN clients) — no extra
  DNS record needed, just the Ingress.
- **Why `privileged` namespace:** only the `hostPath` config volume forces it;
  the container requests no extra capabilities and does not run privileged.

## Verify

```bash
kubectl -n jellyfin get pod,svc,ingress
kubectl -n jellyfin get pvc pvc-jellyfin-media        # expect Bound
kubectl -n jellyfin logs deploy/jellyfin | tail -n 20
```
