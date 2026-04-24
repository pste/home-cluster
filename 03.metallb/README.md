# MetalLB

References:
- https://blog.dalydays.com/post/kubernetes-homelab-series-part-3-loadbalancer-with-metallb/

Bare-metal load balancer for Kubernetes. Assigns real IPs from the local network to `LoadBalancer` services via L2 (ARP) advertisement.

## Description

This setup installs MetalLB using the official manifest pinned at `v0.14.9` and saved into `01_metallb.yaml`.

An `IPAddressPool` defines the IP range reserved outside the router's DHCP range, and an `L2Advertisement` announces those IPs via ARP.

## Setup

### Step 1: reserve IPs on the router

On the FritzBox, exclude a range from the DHCP pool and reserve it for the cluster.  
The range is configured in `02_ipaddresspool.yaml`.

### Step 2: apply all resources via kustomize

```bash
source .env
kustomize build ./metallb | envsubst | kubectl apply -f -
```

This applies in order: MetalLB install, IPAddressPool, L2Advertisement.

### Step 3: verify

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

## Notes

### IP range
The pool uses `${METALLB_IP_RANGE}` — set the actual range in `.env` before applying.  
The range must be **outside** the DHCP range configured on the router.

### strictARP
Not required on this setup (Talos + standard kube-proxy). If needed on other systems, enable it in the kube-proxy ConfigMap:

```bash
kubectl edit configmap -n kube-system kube-proxy
```

```yaml
ipvs:
  strictARP: true
```
