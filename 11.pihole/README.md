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
- Don't add Local DNS Records from the UI: with `emptyDir` storage they vanish on Pod restart. Keep DNS config in the Deployment.

## Ad/malware blocklists — `pihole-adfilter.sh`

`pihole-adfilter.sh` is a **bootstrap script to run after a reinstall or Pod restart**: storage is an `emptyDir`, so `gravity.db` (groups, adlists, associations) is wiped on every restart and must be rebuilt. It keeps two separate groups — `ads` and `malware` — so ads can be toggled off while malware/phishing filtering always stays on.

It operates directly on the SQLite DB (`/etc/pihole/gravity.db`) and calls `pihole -g`, so it must run **inside the Pod**, not on the host. It is idempotent (`INSERT OR IGNORE`), safe to re-run.

```bash
# 1. Copy the script into the running Pod
POD=$(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}')
kubectl cp ./pihole-adfilter.sh pihole/$POD:/tmp/pihole-adfilter.sh

# 2. Get a shell inside the Pod (it already runs as root)
kubectl exec -it -n pihole $POD -- bash

# 3. Inside the Pod: make it executable and run the setup
chmod +x /tmp/pihole-adfilter.sh
/tmp/pihole-adfilter.sh setup        # creates groups, adds lists, runs pihole -g
```

Other commands (inside the Pod):

```bash
/tmp/pihole-adfilter.sh ads off      # disable ads only (malware stays on)
/tmp/pihole-adfilter.sh ads on       # re-enable ads
/tmp/pihole-adfilter.sh status       # show group state and list count per category
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

- Storage is an `emptyDir`: blocklists and settings are lost on Pod restart (gravity re-downloads the lists at startup). Switch to a PVC for persistence — avoid the SMB storage classes, SQLite does not play well with network shares.
- Don't point CoreDNS or the cluster nodes at Pi-hole: cluster DNS stays on CoreDNS (`kube-system`), Pi-hole only serves LAN clients.
- The namespace declares the `baseline` Pod Security profile: Pi-hole's container starts as root (s6 init, port 53) and cannot satisfy `restricted`. Without these labels, Talos' default warn/audit=restricted produces a PodSecurity warning at apply time.
