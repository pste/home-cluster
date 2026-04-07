# Tailscale

This allows me to create a mesh VPN (based on WireGuard) that allows me to reach my cluster from the outside (i.e. my mobile phone).

Tailscale is deployed as a **subnet router**: it advertises the cluster CIDRs to the Tailnet, so any Tailscale device can reach Pods and Services by their internal IPs.

## Setup

### Step 1: generate an Auth Key

Login on the Tailscale admin console and generate an Auth Key.
`https://login.tailscale.com/admin/settings/keys`

**Ephemeral vs normal key:**
- *Ephemeral*: the device is automatically removed from the Tailnet when the pod dies. Use this if you don't want stale devices accumulating in the admin console.
- *Normal* (reusable): the device persists. Combined with `TS_KUBE_SECRET`, the pod will reuse the same WireGuard identity across restarts without re-authenticating.

### Step 2: create the auth secret

The auth key must be created manually (not tracked in git):

```bash
kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY=tskey-auth-XXXXXXXXX \
  --namespace tailscale
```

### Step 3: apply all resources via kustomize

```bash
kubectl apply -k ./tailscale
```

This applies in order: Namespace, RBAC (ServiceAccount + Role + RoleBinding), Deployment.

### Step 4: approve the advertised routes

After the pod starts, the subnet routes are in **pending** state until approved manually.
Go to the Tailscale admin console → Machines → find your node → Edit route settings → enable the advertised routes.

### Step 5: verify

```bash
# Check the pod is running
kubectl get pods -n tailscale

# Check Tailscale picked up the routes (look for the "tailscale-state" secret created by the pod)
kubectl get secret tailscale-state -n tailscale

# From any device on your Tailnet, try to reach a cluster service by its ClusterIP
```

## Notes

### CIDRs
The default Talos CIDRs are advertised:
- `10.244.0.0/16` — Pod CIDR
- `10.96.0.0/12` — Service CIDR

If you customized them during Talos setup, verify with:
```bash
kubectl cluster-info dump | grep -E "cluster-cidr|service-cluster-ip-range"
```
Then update `TS_ROUTES` in `03_deployment.yaml` accordingly.

### State persistence
`TS_KUBE_SECRET` makes the pod save its WireGuard keys and node identity into the `tailscale-state` Secret.
This means the cluster will always appear as the **same device** in the Tailscale admin console, even after pod restarts.

### DNS
`TS_ACCEPT_DNS=false` prevents Tailscale from overriding the cluster DNS (CoreDNS), which would break internal service resolution.
