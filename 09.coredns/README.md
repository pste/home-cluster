# CoreDNS

Custom configuration for the CoreDNS instance deployed by Talos in `kube-system`.

## What changed

The base Corefile was retrieved with:

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

A block per domain is added before the default `.` block.
The `template` plugin resolves any hostname under that domain to Traefik's ClusterIP (`${TRAEFIK_IP}`), without needing a DNS entry per app.

Domains currently configured:
- `${LOCAL_DOMAIN}` — private/internal domain, set in `.env`
- `${DOMAIN}` — public domain on Cloudflare, resolved internally via split DNS (see below)

## Apply

```bash
source .env
kustomize build ./coredns | envsubst | kubectl apply -f -
```

CoreDNS has the `reload` plugin enabled — it picks up ConfigMap changes automatically within 30 seconds, no restart needed.

## Verify

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox -- nslookup qualcosa.$LOCAL_DOMAIN 10.96.0.10
```

## Tailscale split DNS

For each domain, configure a restricted nameserver in the Tailscale admin console:

**Admin Console → DNS → Add nameserver**
- Nameserver IP: `10.96.0.10` (CoreDNS ClusterIP)
- Restrict to domain: `$LOCAL_DOMAIN` (repeat for each domain)

The client routes DNS queries for that domain through CoreDNS, which returns Traefik's ClusterIP, reachable via the Tailscale subnet router.

### Verify from a Tailscale client

```bash
nslookup anything.$LOCAL_DOMAIN
# expected: Address: $TRAEFIK_IP
```

The SERVFAIL on the AAAA record is expected — only A records are configured in the template.

## Alternative: Cloudflare public DNS

Instead of split DNS, you can add a DNS record directly on Cloudflare:
- Type: **A**
- Name: `*` (wildcard) or a specific subdomain
- IP: `$TRAEFIK_IP`
- Proxy: **off** (DNS only)

This is simpler but exposes the internal ClusterIP on public DNS. Since the IP is not routable from outside the Tailscale network, it is not a security risk — but it is an information leak.
