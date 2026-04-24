# cert-manager

Deploys [cert-manager](https://cert-manager.io) with two `ClusterIssuer` resources for Let's Encrypt (staging and production) using the **Cloudflare DNS challenge**.

This approach works for private/internal domains and clusters not exposed to the internet — cert-manager only needs outbound access to the Cloudflare API to complete the DNS-01 challenge.

## Setup

### Step 1: create a Cloudflare API token

In the Cloudflare dashboard: **My Profile → API Tokens → Create Token**

Use the "Edit zone DNS" template with these settings:
- **Permissions:** Zone / DNS / Edit
- **Zone Resources:** Include / Specific zone / `$DOMAIN`

### Step 2: install cert-manager

```bash
kubectl apply -k ./install
```

Wait for all pods to be running before proceeding — the CRDs must be established before the ClusterIssuer can be created:

```bash
kubectl rollout status deployment/cert-manager -n cert-manager
kubectl rollout status deployment/cert-manager-webhook -n cert-manager
```

### Step 3: apply config (Secret + ClusterIssuer)

The ClusterIssuer uses `${LETSENCRYPT_EMAIL}` — substitute it via `envsubst` before applying:

```bash
source .env
kustomize build ./config | envsubst | kubectl apply -f -
```

### Step 4: store the Cloudflare token as a Secret

```bash
source .env
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=$CFTOK \
  --namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
```

### Step 5: verify

```bash
# Check all cert-manager pods are running
kubectl get pods -n cert-manager

# Check ClusterIssuers are ready
kubectl get clusterissuer
```

## Usage

To issue a certificate for an Ingress, add these annotations and a `tls` block:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt
spec:
  tls:
    - hosts:
        - myapp.$DOMAIN
      secretName: myapp-tls
  rules:
    - host: myapp.$DOMAIN
      ...
```

## How Let's Encrypt registration works

No manual registration is required. cert-manager automatically registers an ACME account with Let's Encrypt the first time it contacts their servers, using the email provided in the ClusterIssuer. That email is only used for certificate expiry notifications.

## Notes

- `install/00_cert-manager.yaml` is the official upstream manifest pinned to v1.16.2
- `install/01_patch_dns.yaml` patches the cert-manager deployment to use public nameservers (Cloudflare + Google) for DNS-01 propagation checks. This is required because CoreDNS has custom zones (e.g. `$DOMAIN`) that return SERVFAIL for SOA queries, which would block cert-manager's propagation verification.
- The Cloudflare API token is stored as a Secret and referenced by the ClusterIssuer — never commit the real token
- The `install/` kustomization must be applied with `--server-side --force-conflicts` after the first install to avoid field manager conflicts on subsequent updates:
  ```bash
  kubectl apply --server-side --force-conflicts -k ./install
  ```
