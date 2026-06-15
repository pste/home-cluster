# Pi-hole

Network-wide ad blocking DNS server, exposed on the LAN through a MetalLB `LoadBalancer` IP.

## What is deployed

- Namespace `pihole`
- Secret with the web UI password (value from `PIHOLE_WEBPASSWORD` in `.env`)
- Deployment running `pihole/pihole` (v6, configured via `FTLCONF_*` env vars), with a dnsmasq wildcard resolving `*.${DOMAIN}` to Traefik for LAN clients
- Service of type `LoadBalancer` with a fixed IP (`${PIHOLE_IP}`) for DNS on port 53 (TCP+UDP)
- Ingress `pihole.${DOMAIN}` for the admin web UI through Traefik

## Required env

Add to `.env`:

```bash
# Fixed LAN IP for the Pi-hole DNS service — must be inside the MetalLB pool (METALLB_IP_RANGE)
PIHOLE_IP=192.168.x.x
# Admin web UI password
PIHOLE_WEBPASSWORD=your-password
# Traefik's MetalLB external IP (LAN-routable) — the wildcard below points LAN
# clients here. NOT the ClusterIP used by CoreDNS (TRAEFIK_IP): the LAN cannot
# reach the cluster Service CIDR.
TRAEFIK_EXT_IP=192.168.x.x
```

## Apply

```bash
# set -a exports everything sourced — required, envsubst only sees exported vars
set -a; source ../.env; set +a
kubectl kustomize ./pihole | envsubst | kubectl apply -f -
```

The Secret gets its value from `PIHOLE_WEBPASSWORD` — make sure it is set in `.env` before applying, or the password will be empty. After changing the password, restart the Pod to pick it up:

```bash
kubectl rollout restart deployment/pihole -n pihole
```

## Use it — FRITZ!Box setup

Point the FRITZ!Box **upstream** resolver at Pi-hole — this is the scheme that actually works on this router (config only on the router, nothing changes in the cluster):

1. **Internet → Account Information → DNS Server → "Use other DNSv4 servers"**: preferred `$PIHOLE_IP`, alternative empty (or a public DNS as fallback, see note)
2. No DHCP lease renewal needed — clients already use the router (`192.168.x.1`) as DNS, and it now forwards to Pi-hole.

> **Why not the "Local DNS server" field?** On this FRITZ!Box, `Home Network → Network → Network Settings → Local DNS server = $PIHOLE_IP` does **not** redirect client queries to Pi-hole: the router keeps advertising **itself** as the clients' DNS via DHCP, so traffic still goes `client → router → upstream`. Setting that field while leaving the upstream on the ISP makes the dashboard stay empty even though the internet works. The upstream setting above is what counts.
>
> Trade-off of this scheme: all queries reach Pi-hole **from the router**, so the dashboard shows a single client (the router IP), not per-device stats. If the alternative DNS is set to a public server, some queries may hit it and skip blocking when Pi-hole is slow/down.

**IPv6:** disabled on this router (`Internet → Account Information → IPv6 → IPv6 support off`). The Pi-hole Service is IPv4-only (`ipFamilyPolicy: SingleStack`), so if IPv6 is re-enabled the AAAA queries would bypass Pi-hole unless a DNSv6 upstream is also pointed at it.

Add `$DOMAIN` to the exceptions in **Home Network → Network → Network Settings → "DNS Rebind Protection"**: the FRITZ!Box blocks DNS answers pointing to private IPs (like the `*.$DOMAIN` wildcard → Traefik). Required because Pi-hole resolves `*.$DOMAIN` to Traefik's private IP.

FTL's per-client rate limit is disabled in the Deployment (`FTLCONF_dns_rateLimit_count=0`): the whole LAN arrives from the router's single IP, which would otherwise trip the limit.

The Service uses `externalTrafficPolicy: Local` so Pi-hole logs the **real source IP** instead of the cluster pod-network IP (`10.244.0.1`). With the upstream scheme above that real IP is the router (`192.168.x.1`); it would become the actual device IP only if clients ever query Pi-hole directly. Safe with MetalLB L2, which advertises the Service IP only from a node running the Pod.

Admin UI: `https://pihole.$DOMAIN/admin/` (resolved by CoreDNS split DNS → Traefik, certificate issued by cert-manager via the `letsencrypt` ClusterIssuer).

## Local resolution of ${DOMAIN}

The Deployment sets a dnsmasq wildcard (`FTLCONF_misc_dnsmasq_lines = address=/${DOMAIN}/${TRAEFIK_EXT_IP}`): any name under `${DOMAIN}` resolves to Traefik's IP for LAN clients — same logic as the CoreDNS template used by Tailscale clients. New apps only need an Ingress, no DNS entry.

> **`TRAEFIK_EXT_IP` vs `TRAEFIK_IP`** — they are different on purpose. LAN clients can only reach Traefik through its **MetalLB external IP** (`TRAEFIK_EXT_IP`, e.g. `192.168.x.220`); the cluster ClusterIP (`TRAEFIK_IP`, e.g. `10.100.x.x`) used by the CoreDNS template is reachable only from inside the cluster and from Tailscale clients (which route the Service CIDR). Pointing the LAN wildcard at the ClusterIP makes `*.${DOMAIN}` resolve to an address the LAN cannot reach.

Notes:
- No NXDOMAIN: non-existent names under `${DOMAIN}` also resolve to Traefik (you get its 404).
- To point a specific name elsewhere, add a more specific line (they stack with `;` separators), e.g. `address=/nas.${DOMAIN}/<NAS_IP>` — more specific wins.
- Prefer keeping DNS config in the Deployment (versioned). Local DNS Records added from the UI now persist (data is on the local Talos disk), but they live outside Git.

## Ad/malware blocklists — `pihole-adfilter.sh`

`pihole-adfilter.sh` is **only a bootstrap script** to run on first install (or after wiping the data volume): it builds `gravity.db` and the group structure. Storage is now persistent (local Talos disk), so the DB survives Pod restarts and no longer needs rebuilding each time. Day-to-day changes (toggling ads, per-client rules) are done from the Pi-hole UI, not this script.

How filtering works here (important — Pi-hole's group model trips people up): a blocklist only blocks a client if the list is in a **group the client belongs to**. Unassigned clients fall back to the **Default group (id 0)** — the only way to filter *everyone*. So the script builds:

- group `ads` and group `malware`, each populated with its lists;
- group `pihole`, a **parking spot** for the original/migrated Pi-hole lists (e.g. StevenBlack, which is mixed ads+malware) — kept in the DB but **out of the Default**, so they don't block anyone until you move them;
- the **Default group** is filled with only the categories passed to `setup` (default `malware`) — that is the network-wide filter.

Lists stay `enabled=1`; what makes a category global is being **in the Default group**, not the enabled flag. To enable ads for everyone from the UI, assign the ads adlists to the Default group; for per-client rules, assign that client to the `ads`/`malware` group.

It operates directly on the SQLite DB (`/etc/pihole/gravity.db`) and calls `pihole -g`, so it must run **inside the Pod**, not on the host. It is idempotent (`INSERT OR IGNORE`), safe to re-run.

```bash
# 1. Copy the script into the running Pod
POD=$(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}')
kubectl cp ./pihole-adfilter.sh pihole/$POD:/tmp/pihole-adfilter.sh

# 2. Get a shell inside the Pod (it already runs as root)
kubectl exec -it -n pihole $POD -- bash

# 3. Inside the Pod: make it executable and run the bootstrap
chmod +x /tmp/pihole-adfilter.sh
/tmp/pihole-adfilter.sh setup            # global filter = malware (default)
# /tmp/pihole-adfilter.sh setup malware ads   # to also block ads network-wide
```

Other commands (inside the Pod):

```bash
/tmp/pihole-adfilter.sh status       # show what filters the network + group state
```

> No `sudo` is needed inside the Pod — the container already runs as root, so the script's `require_root` check passes. To change which blocklists are used, edit the `ADS_LISTS` / `MALWARE_LISTS` arrays at the top of the script and re-run `setup`.

## Verify

```bash
# DNS resolution through Pi-hole
nslookup google.com $PIHOLE_IP

# A known ad domain should be blocked (returns 0.0.0.0)
nslookup doubleclick.net $PIHOLE_IP

# Wildcard: any name under DOMAIN must resolve to Traefik's IP
nslookup whatever.$DOMAIN $PIHOLE_IP
```

## Notes

- Storage is persistent on a `hostPath` subdirectory of the `hdd-data-1` UserVolume (`/var/mnt/hdd-data-1/pihole-data`): blocklists and settings survive Pod restarts. The local disk is used on purpose — SQLite (`gravity.db`) does not play well with the SMB/network storage classes. The kubelet creates the hostPath dir as `root:root 0755`, and FTL by default drops to uid/gid 1000, which cannot create `gravity.db` there. Rather than a chown initContainer, FTL is told to **run as root** via `PIHOLE_UID=0` / `PIHOLE_GID=0`, so it writes `/etc/pihole` directly with no extra step. This is acceptable because the namespace is already `privileged` and the container starts as root anyway. (Avoid a separate fix-up image like `busybox`: with `strategy: Recreate` the old Pod is killed before the new one starts, so during a rollout Pi-hole — the LAN/node DNS — is down and the node cannot resolve the registry to pull anything new → `Init:ImagePullBackOff` deadlock.)
- A `startupProbe` (tcpSocket on port 53, ~300s headroom) gates liveness/readiness during boot. On a fresh volume the first gravity build waits up to 120s for DNS and only then binds port 53 — longer than the liveness budget — so without the startupProbe the container is killed mid-bootstrap (exit 137) in a ~2-minute restart loop and never finishes building `gravity.db`.
- Don't point CoreDNS or the cluster nodes at Pi-hole: cluster DNS stays on CoreDNS (`kube-system`), Pi-hole only serves LAN clients.
- The namespace declares the `privileged` Pod Security profile: Pi-hole's container starts as root (s6 init, port 53) and cannot satisfy `restricted`, and the persistent `hostPath` volume is forbidden by both `baseline` and `restricted`. The container itself requests no extra capabilities/privileged mode — only the hostPath forces this profile (same as the jellyfin and tailscale namespaces). Without it, Talos' default warn/audit=restricted produces a PodSecurity violation at apply time.
