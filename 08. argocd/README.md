# ArgoCD

CICD through ArgoCD

## Description

This setup installs ArgoCD using the official manifest pinned at `stable` and saved into `02_argocd.yaml`.

### Install: apply all resources via kustomize

```bash
kubectl apply -k ./argocd
```

## Accessing the UI

### Ingress (production approach)

ArgoCD is exposed via Traefik ingress at `https://argocd.saba.net`.  
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
