# Test

## Build the test app

The Ingress host uses `${DOMAIN}`, substituted at apply time from `.env`:
```
set -a; source ../.env; set +a
envsubst < ./1_test_http.yaml | kubectl apply -f -
```

Feel free to ignore this warning:
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nginx" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "nginx" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "nginx" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "nginx" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")

## Test the route through Traefik (no DNS needed)

The Service is a ClusterIP, so the only LAN entry point is Traefik's MetalLB external IP (`$TRAEFIK_EXT_IP`).  
Traefik routes by hostname, so pass the `Host` header explicitly:  
`curl -H "Host: web-test.$DOMAIN" http://$TRAEFIK_EXT_IP`

Without the header Traefik answers `404 page not found`: no Ingress matches the bare IP.

## Test the DNS route

The wildcard `*.${DOMAIN}` already resolves to Traefik (Pi-hole for the LAN, CoreDNS for Pods, Tailscale split DNS), so no `hosts` rule is needed:  
`curl http://web-test.$DOMAIN`

## Cleanup

`kubectl delete namespace web-test`
