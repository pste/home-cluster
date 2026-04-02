# Ingress Controller

## Install Traefik ingress controller
`https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-crd/`

We have two options to setup Traefik: with Helm or "manually": I chose the second way for my home-lab.

### Step 1: install CRDs (must be done before kustomize, they are cluster-scoped)

```bash
# Install Traefik Resource Definitions:
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml

# Install RBAC for Traefik:
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml
```

### Step 2: apply all resources via kustomize

```bash
kubectl apply -k ./traefik
```

This applies in order: Namespace, RBAC (ServiceAccount + ClusterRole + ClusterRoleBinding), Deployment, Service (LoadBalancer → MetalLB assigns an IP), IngressClass.

### Step 3: verify

```bash
# Check the pod is running
kubectl get pods -n ingress-traefik

# Check MetalLB assigned an IP to the service
kubectl get svc -n ingress-traefik

# Check the IngressClass is registered
kubectl get ingressclass
```

### Optional: access the dashboard

The dashboard port (8080) is not exposed by the Service. To access it locally:
```bash
kubectl port-forward -n ingress-traefik deployment/traefik 8080:8080
```
Then open `http://localhost:8080/dashboard/`
Note: you also need to uncomment `--api.dashboard=true` and `--api.insecure=true` in `traefik/03_deployment.yaml`.

## DEPRECATED 20251223 (March 2026 nginx-ingress-controller will be dismissed)
## Ingress NGINX

This is the community mantained NGINX ingress-controller (*not* the NGINX one called nginx-ingress-controller)
https://github.com/kubernetes/ingress-nginx

## Install

This will install the whole thing
`kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/cloud/deploy.yaml`

## Cleanup from ingress-nginx
Delete all resources inside the namespace  
`kubectl delete all --all -n ingress-nginx`  

Delete the namespace itself  
`kubectl delete namespace ingress-nginx`  

Check and delete ingressClass  
`kubectl delete ingressClass nginx`  
You can fetch all ingressClass using  
`kubectl get ingressClass -A`  

Check and delete validating webhook  
`kubectl delete ValidatingWebhookConfiguration ingress-nginx-admission`  
You can fetch all the validating webhooks using  
`kubectl get ValidatingWebhookConfiguration`  
