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

## Use it

The FRITZ!Box acts as DNS intermediary: clients keep using the router, which forwards to Pi-hole with a public fallback (redundancy if the Pod is down — accepted trade-off: some queries may hit the fallback and skip blocking, and Pi-hole sees all queries as coming from the router, so no per-client stats).

FRITZ!Box configuration:

1. **Internet → Account Information → DNS Server → "Use other DNSv4 servers"**
   - Preferred: `$PIHOLE_IP`
   - Alternative: `1.1.1.1`
2. **Home Network → Network → Network Settings → "DNS Rebind Protection"**: add `$DOMAIN` to the exceptions — the FRITZ!Box blocks DNS answers pointing to private IPs (like the `*.$DOMAIN` wildcard → Traefik) unless the domain is whitelisted here.

No DHCP lease renewal needed: clients already point at the router. Because the whole LAN reaches Pi-hole from the router's single IP, FTL's per-client rate limit is disabled in the Deployment (`FTLCONF_dns_rateLimit_count=0`).

Admin UI: `https://pihole.$DOMAIN/admin/` (resolved by CoreDNS split DNS → Traefik, certificate issued by cert-manager via the `letsencrypt` ClusterIssuer).

## Local resolution of ${DOMAIN}

The Deployment sets a dnsmasq wildcard (`FTLCONF_misc_dnsmasq_lines = address=/${DOMAIN}/${TRAEFIK_IP}`): any name under `${DOMAIN}` resolves to Traefik's IP for LAN clients — same logic as the CoreDNS template used by Tailscale clients. New apps only need an Ingress, no DNS entry.

Notes:
- No NXDOMAIN: non-existent names under `${DOMAIN}` also resolve to Traefik (you get its 404).
- To point a specific name elsewhere, add a more specific line (they stack with `;` separators), e.g. `address=/nas.${DOMAIN}/<NAS_IP>` — more specific wins.
- Don't add Local DNS Records from the UI: with `emptyDir` storage they vanish on Pod restart. Keep DNS config in the Deployment.

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
