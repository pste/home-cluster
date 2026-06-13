# Jellyfin

Self-hosted media server, exposed on HTTPS through Traefik at `jellyfin.${DOMAIN}`.

## What is deployed

- Namespace `jellyfin` (PodSecurity `privileged` — required because the config
  volume is a `hostPath`, forbidden under `baseline`/`restricted`)
- Static `PersistentVolume` + `PersistentVolumeClaim` mounting the NAS video
  share **read-only** (`//${NAS_IP}/${NAS_SHARE_VIDEO}`), reusing the
  `nascreds-ro` secret from the storage setup
- Deployment running `jellyfin/jellyfin`:
  - `/config` → local Talos UserVolume `/var/mnt/jellyfin-config` (persistent, SQLite-safe)
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

2. **Local Talos UserVolume for the config** — the Deployment mounts
   `/var/mnt/jellyfin-config` from the node. Provision it at the Talos level
   (it is **not** a kubectl resource) by adding to `controlplane.yaml`:

   ```yaml
   ---
   apiVersion: v1alpha1
   kind: UserVolumeConfig
   name: jellyfin-config
   provisioning:
     diskSelector:
       match: disk.transport == 'nvme'
     minSize: 10GB
     maxSize: 30GB
   ```

   then apply and verify the mount:

   ```bash
   talosctl apply-config --file controlplane.yaml
   talosctl get mountstatus       # expect /var/mnt/jellyfin-config
   ```

   > **This step is mandatory, not optional.** Talos' root filesystem is
   > read-only, so without the UserVolume mounted at `/var/mnt/jellyfin-config`
   > the Pod stays in `ContainerCreating` with
   > `mkdir /var/mnt/jellyfin-config: read-only file system` —
   > `hostPath: DirectoryOrCreate` cannot create a directory on the immutable
   > root. The path becomes writable only once Talos mounts the volume there.

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
