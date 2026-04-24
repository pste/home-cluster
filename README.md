# My k8s cluster

A single-node Kubernetes cluster running on bare metal at home, built on TalosOS.  
The stack covers everything from OS installation to CI/CD, with all resources managed via Kustomize.

## Stack overview

| Layer | Tool |
|---|---|
| OS & cluster | TalosOS |
| Ingress | Traefik v3 |
| Load balancer | MetalLB (L2/ARP) |
| Storage | SMB CSI driver + Talos UserVolume |
| VPN access | Tailscale (subnet router) |
| DNS | CoreDNS (custom zones) + Tailscale split DNS |
| TLS | cert-manager + Let's Encrypt (Cloudflare DNS challenge) |
| CI/CD | ArgoCD + GitHub Actions + DockerHub |

## Environment variables

Several manifests use environment variables substituted at apply time via `envsubst`.  
Copy `.env.dist` to `.env`, fill in the values, and source it before running any `kubectl` or `kustomize` command:

```bash
cp .env.dist .env
# edit .env with your values
source .env
```

Apply a module with variable substitution:

```bash
# single module
kustomize build ./09.coredns | envsubst | kubectl apply -f -

# single file
envsubst < 03.metallb/metallb/02_ipaddresspool.yaml | kubectl apply -f -
```

> `envsubst` is part of the `gettext` package: `apt install gettext` / `brew install gettext`.

## Chapters

1. **[TalosOS](01.talos/README.md)** — Provision and bootstrap the bare-metal node: image factory, disk setup, single-node config, kubeconfig generation, and upgrades.

2. **[Traefik](02.ingress-controller/README.md)** — Install the Traefik v3 ingress controller manually (without Helm): CRDs, RBAC, Deployment, LoadBalancer Service, and IngressClass.

3. **[MetalLB](03.metallb/README.md)** — Bare-metal load balancer that assigns real LAN IPs to `LoadBalancer` services via L2/ARP advertisement. Requires a reserved IP range outside the router's DHCP pool.

4. **[Storage](04.storage/README.md)** — Two storage backends: SMB CSI driver for network shares (NAS), and Talos UserVolume for local NVMe disks provisioned at the OS level.

5. **[Tests](05.tests/README.md)** — Smoke tests to verify the cluster is reachable: deploy a test nginx pod, curl it by IP, and validate DNS-based routing.

6. **[Custom Apps](06.my-app/README.md)** — Deploy a locally developed application. Uses GitHub Actions → DockerHub → ArgoCD as the build and delivery pipeline. Includes notes on DB migrations via `kubectl port-forward`.

7. **[Tailscale](07.tailscale/README.md)** — Mesh VPN (WireGuard-based) deployed as a subnet router inside the cluster. Advertises Pod and Service CIDRs to the Tailnet so any Tailscale device can reach cluster resources from outside the LAN.

8. **[ArgoCD](08.%20argocd/README.md)** — GitOps continuous delivery. Installed via official pinned manifest and exposed through Traefik with TLS. Runs in insecure mode (TLS terminated at the ingress layer).

9. **[CoreDNS](09.coredns/README.md)** — Custom DNS zones for internal domains. Resolves `*.your.domain` and `*.nestix.dev` to Traefik's ClusterIP. Combined with Tailscale split DNS for resolution from outside the cluster.

10. **[cert-manager](10.cert-manager/README.md)** — Automated TLS certificate management via Let's Encrypt and Cloudflare DNS challenge. Issues and renews certificates for all Ingress resources automatically.