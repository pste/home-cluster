# Pi-hole

Network-wide ad blocking DNS server, exposed on the LAN through a MetalLB `LoadBalancer` IP.

## What is deployed

- Namespace `pihole`
- Secret with the web UI password (placeholder, replace after apply)
- Deployment running `pihole/pihole` (v6, configured via `FTLCONF_*` env vars)
- Service of type `LoadBalancer` with a fixed IP (`${PIHOLE_IP}`) for DNS on port 53 (TCP+UDP)
- Ingress `pihole.${LOCAL_DOMAIN}` for the admin web UI through Traefik

## Required env

Add to `.env`:

```bash
# Fixed LAN IP for the Pi-hole DNS service — must be inside the MetalLB pool (METALLB_IP_RANGE)
PIHOLE_IP=192.168.x.x
```

## Apply

```bash
# set -a exports everything sourced — required, envsubst only sees exported vars
set -a; source ../.env; set +a
kubectl kustomize ./pihole | envsubst | kubectl apply -f -
```

Then set the real web password:

```bash
kubectl create secret generic pihole-webpassword \
  --from-literal=WEBPASSWORD=your-password \
  --namespace pihole --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/pihole -n pihole
```

## Use it

Point your clients (or the router's DHCP DNS option) to `$PIHOLE_IP`.

Admin UI: `http://pihole.$LOCAL_DOMAIN/admin/` (resolved by CoreDNS split DNS → Traefik).

## Verify

```bash
# DNS resolution through Pi-hole
nslookup google.com $PIHOLE_IP

# A known ad domain should be blocked (returns 0.0.0.0)
nslookup doubleclick.net $PIHOLE_IP
```

## Notes

- Storage is an `emptyDir`: blocklists and settings are lost on Pod restart (gravity re-downloads the lists at startup). Switch to a PVC for persistence — avoid the SMB storage classes, SQLite does not play well with network shares.
- Don't point CoreDNS or the cluster nodes at Pi-hole: cluster DNS stays on CoreDNS (`kube-system`), Pi-hole only serves LAN clients.
- The namespace declares the `baseline` Pod Security profile: Pi-hole's container starts as root (s6 init, port 53) and cannot satisfy `restricted`. Without these labels, Talos' default warn/audit=restricted produces a PodSecurity warning at apply time.
