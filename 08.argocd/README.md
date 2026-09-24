# ArgoCD

CICD through ArgoCD

## Description

This setup installs ArgoCD using the official manifest pinned at `stable` and saved into `02_argocd.yaml`.

### Install: apply all resources via kustomize

The ArgoCD manifest contains large CRDs that exceed the annotation size limit of `kubectl apply`. Use server-side apply.  
The ingress uses `${DOMAIN}` and the notifications secret `${NTFY_URL}` — substitute them via `envsubst` (explicit list, see [Notifications](#notifications)) before applying:

```bash
set -a; source ../.env; set +a
kubectl kustomize ./argocd | envsubst '${DOMAIN} ${NTFY_URL}' | kubectl apply --server-side -f -
```

On subsequent updates, add `--force-conflicts` to handle field manager conflicts:

```bash
set -a; source ../.env; set +a
kubectl kustomize ./argocd | envsubst '${DOMAIN} ${NTFY_URL}' | kubectl apply --server-side --force-conflicts -f -
```

## Accessing the UI

### Ingress (production approach)

ArgoCD is exposed via Traefik ingress at `https://argocd.$DOMAIN`.  
TLS is managed by cert-manager (see the dedicated setup).

Since TLS termination is handled by Traefik, the server runs in insecure mode (plain HTTP internally). This is configured declaratively via a Kustomize patch on `argocd-cmd-params-cm` (`server.insecure: "true"`), so no manual intervention is needed.

### Alternative: port-forward

Useful for quick access without the ingress stack:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open https://localhost:8080.

### Alternative: NodePort

If you prefer direct node access without an ingress controller:

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
```

The default approach is **ClusterIP** — the NodePort patch is temporary and not committed.

## Login

Username: `admin`  
Password:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

## Notifications

The notifications controller shipped with the upstream manifest is configured
to push to **ntfy** (same topic used by [13.monitoring](../13.monitoring/README.md)):

- `04_patch_notifications-cm.yaml` — `ntfy` webhook service, templates, triggers
  and a **global subscription**, so every Application is covered without
  per-app annotations. Triggers:
  - `on-sync-failed` — sync operation ended in `Error`/`Failed` (message
    includes the sync error)
  - `on-health-degraded` — app health is `Degraded` (e.g. pods crashing)
  - `on-sync-status-unknown` — sync status `Unknown` (repo unreachable,
    manifest generation error)
- `05_patch_notifications-secret.yaml` — the ntfy topic URL (`NTFY_URL` from `.env`)

The ConfigMap contains `$ntfy-url`, an ArgoCD reference to a secret key, **not**
a shell variable. Since notifications were added, apply with an explicit list
of variables for envsubst:

```bash
set -a; source ../.env; set +a
kubectl kustomize ./argocd | envsubst '${DOMAIN} ${NTFY_URL}' | kubectl apply --server-side --force-conflicts -f -
```

Quick check of the controller:

```bash
kubectl -n argocd logs deploy/argocd-notifications-controller --tail=50
```

## CI/CD Flow

The full delivery pipeline works as follows:

```
git tag v1.x.x  (app repo)
    └─→ GitHub Actions
            ├─→ build + push → DockerHub
            └─→ commit kustomization.yaml → k8s repo (newTag updated)
                    └─→ ArgoCD detects commit
                            └─→ kustomize build → kubectl apply
                                    └─→ cluster updated
```

Each app repo (UI, API) has a GitHub Actions workflow that:
1. Builds the Docker image and pushes it to DockerHub
2. Clones the k8s repo and runs `kustomize edit set image <image>:<tag>`
3. Commits and pushes `kustomization.yaml` back to the k8s repo

ArgoCD polls the k8s repo and syncs automatically when a new commit is detected.


## ArgoCD Application

Each application is registered in ArgoCD via an `Application` resource stored in the app's k8s repo. It is **not** managed by ArgoCD itself — it must be applied manually once to bootstrap:

```bash
kubectl apply -f argocd.yaml
```

The `Application` resource is excluded from `kustomization.yaml` intentionally to avoid a self-referential loop where ArgoCD would manage its own registration.

## Secrets

Secrets are encrypted with SOPS (age) and **excluded from ArgoCD sync**. They are stored in a dedicated subfolder and applied manually:

```
k8s/
├── kustomization.yaml   ← managed by ArgoCD
├── secrets/
│   └── kustomization.yaml   ← applied manually
│   └── secrets.yaml
│   └── secrets-pg.yaml
│   └── secrets-smb.yaml
```

Apply secrets manually:

```bash
kubectl apply -k k8s/secrets/
```

This avoids the need for a custom ArgoCD image with KSOPS support, keeping the setup simple.
