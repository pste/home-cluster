# CoreDNS

Custom configuration for the CoreDNS instance deployed by Talos in `kube-system`.

## What changed

The base Corefile was retrieved with:

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

A `your.domain` block was added before the default `.` block.
It uses the `template` plugin to resolve any `*.your.domain` hostname to Traefik's ClusterIP (`10.100.197.118`), so all Ingress resources using that domain are reachable without per-host DNS entries.

## Apply

```bash
kubectl apply -k ./coredns
```

CoreDNS has the `reload` plugin enabled — it picks up ConfigMap changes automatically within 30 seconds, no restart needed.

## Verify

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox -- nslookup qualcosa.your.domain 10.96.0.10
```

## Tailscale split DNS

To make `*.your.domain` resolvable from any Tailscale client, configure a restricted nameserver in the Tailscale admin console:

**Admin Console → DNS → Add nameserver**
- Nameserver IP: `10.96.0.10` (CoreDNS ClusterIP)
- Restrict to domain: `your.domain`

The client routes traffic for `your.domain` through CoreDNS, which returns Traefik's ClusterIP, which is reachable via the Tailscale subnet router.

### Verify from a Tailscale client

```bash
nslookup qualcosa.your.domain
# expected: Address: 10.100.197.118
```

The SERVFAIL on the AAAA record is expected — only A records are configured in the template.
