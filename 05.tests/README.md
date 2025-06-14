# Test

## Build the test app
`kubectl apply -f ./1_test_http.yaml`

Feel free to ignore this warning:
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nginx" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "nginx" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "nginx" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "nginx" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")

## Test the pod reachability
Check the web service can be reached:  
`curl 192.168.x.bbb`

## Testing a (local) DNS route
Add `hosts` rule:
`192.168.x.bbb   web-test.homelab.net`
then
`curl web-test.homelab.net`