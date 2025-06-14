# Setup MetalLB

References:  
- https://blog.dalydays.com/post/kubernetes-homelab-series-part-3-loadbalancer-with-metallb/

# Step 1: install MetalLB
`kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml`

# Step 2: reserve some IPs
I've kept the range 192.168.x.bbb - 192.168.x.ccc on my FritxBox off my DHCP.

# Step 3: associate your IPs into the cluster
Note: choose an IP range OUTSIDE your DHCP configuration.
`kubectl apply -f ./2_ipaddresspool.yaml`

# Step 4: advertise your IPs
`kubectl apply -f ./3_advertise.yaml`

# Check Proxy

(strictArp has to be verified if needed...not present in my new setup)
We're using ARP to announce so, to enable strict ARP mode, we edit kube-system/kube-proxy daemonset and add:
`spec: container: commands: --ipvs-strict-arp`

In some system (not mine) this can be done editing this configMap:
`kubectl edit configmap -n kube-system kube-proxy`
```
(..)
  strictARP: true
```