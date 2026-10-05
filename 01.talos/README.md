# TalosOS

Built the image for bare metal via `image-factory`:  
https://www.talos.dev/v1.10/learn-more/image-factory/

## ISO preparation

I choose this options:  
```
bare-metal
amd64
no secure boot
no system extensions
customization:
  talos.halt_if_installed=0
```

The halt_if_installed flag was set to `false` because I needed to wipe and reinstall the whole system ans Talos has a protection to avoid reinstalling over a previous install.

## Flashing Tips

I've used `BalenaEtcher.io` but also `Rufus` or `Ventoy` are valid options.

# Mono Node setup

## Network preparation

To run Talos you have to ensure that the node will receive always the same IP.  
To do so please assign a static IP to the node. We will refer to this IP as the env variable $TALOSIP from now.

## Install

After the boot from USB, the dashboard shows the `System: Ready` label. Now we can enter from a remote console to install everything.  
I'm running all of these commands from a `./talosctl` folder.

0. Generate config files from the node
`talosctl gen config k8ste https://$TALOSIP:6443`

1. We need to identify the disk that will be (fully!) used for our OS:  
`talosctl -n $TALOSIP get disks --insecure`
In my case I edited the `controlplane.yaml` to write my USB disk to the `disk` section:  
```
  install:
    disk:
      /dev/sda
```

2. This is a mono-node cluster, so edit controlplane.yaml to allow pods on the ControlPlane:  
`allowSchedulingOnControlPlanes: true`

3. 
EVERY node must be advertised (also control-plane) to the Balancer
```
machine:
  # Comment out this section for single-node clusters
  # nodeLabels:
  #   node.kubernetes.io/exclude-from-external-load-balancers: ""
```

4. 
With this config you can apply the config file: 
`talosctl apply-config -n $TALOSIP --insecure --file ./controlplane.yaml`  

The server reboots automatically after the apply command.  
The dashboard reports: 
`Stage: running`
`Ready: false`

## Bootstrap

This step is needed to finalize the setup: it copies the certificates on the node and creates the etcd.
`talosctl bootstrap -n $TALOSIP -e $TALOSIP --talosconfig ./talosconfig`  

The dashboard says (after a while):  
`Stage: running`
`Ready: true`

## kubectl

Generate the kubeconfig file:  
`talosctl -e $TALOSIP -n $TALOSIP kubeconfig ./kubeconfig`  

Update talos config file pointing to my default endpoint. This allows you to avoid the `-e` parameter to every command:  
`talosctl config endpoint $TALOSIP`  
Same for default node:  
`talosctl config node $TALOSIP`

# Node up and running

Now the node is ready.  

It is useful to add some env to your `.bashrc` file:  
export TALOSIP="192.168.x.y"
export TALOSCONFIG=~/.talosctl/talosconfig
export KUBECONFIG=~/.talosctl/kubeconfig

## Open Dashboard

`talosctl dashboard -n $TALOSIP -e $TALOSIP`

## Apply changes to installed Talos

If you need to modify further your cluster config, just edit the `talosconfig.yaml` and:
`talosctl apply-config -n $TALOSIP -e $TALOSIP`

# Upgrade to a new Server version
Check actual version:  
`talosctl version`  
Check latest remote version:  
`curl -s https://api.github.com/repos/siderolabs/talos/releases/latest | grep -m1 tag_name`  
Warning: avoid to jump minor versions setup (i.e. from 1.12 to 1.14). Always step into every version
Check latest remote minor version (i.e. for 1.13):  
`curl -s "https://api.github.com/repos/siderolabs/talos/releases?per_page=100" | grep tag_name | grep v1.13`  

Note: it is NOT necessary to scale down every non-system Pod. 
The upgrade puts the node in drain state; the drain sends a sigterm to the pods and they're terminated.  
Just check if exists some PodDisruptionBudget (kubectl get pdb -A): if it exists means that a Pod has "minAvailable: 1" and will not be killed.  

Launch the upgrade:  
`talosctl upgrade --nodes $TALOSIP -e $TALOSIP --image ghcr.io/siderolabs/installer:v1.12.0`  

During the reboot phase you can chech the status with:  
`talosctl dashboard`

## Upgrade to latest Server build version
If not using the ImageBuilder (as I am doing), you can launch:  
`talosctl upgrade --image ghcr.io/siderolabs/installer:v1.13.11` 

To check if using the ImageBuilder launch:  
`talosctl get machineconfig -o yaml | grep 'image:' | grep installer`
If the installer is `ghcr.io/siderolabs/installer:v1.10.3` you're using the base image; otherwise you'll find something like `factory.talos.dev/installer/<SCHEMATIC_ID>:v1.13.2`.

## Client upgrade
```bash
# Remove the old binary (if required by permissions)
sudo rm /usr/local/bin/talosctl

# Download and install the latest client
curl -sL https://talos.dev/install | sh
```

## Client certificate expired
Check if expired:
```bash
talosctl config info
# (or)
cat talosconfig | grep crt | awk '{print $2}' | base64 -d | openssl x509 -noout -dates
```

Copy the `controlplane.yaml` file in a **new** folder, then `cd` into it to:
```bash
talosctl gen secrets --from-controlplane-config controlplane.yaml -o secrets.yaml
```

Now grep the clustername from my config:
```bash
grep clusterName controlplane.yaml 
```
and use the name (in my case `k8ste`) to generate a new config (BEWARE: this rewrite your files in this folder):
```bash
talosctl gen config --with-secrets secrets.yaml k8ste https://$TALOSIP:6443 --force
```

Finally configure the node:
```bash
talosctl --talosconfig talosconfig config endpoint $TALOSIP
talosctl --talosconfig talosconfig config node $TALOSIP
```

Now everything should work:
```bash
talosctl -n $TALOSIP version
```

### kubectl expired
Verify kubectl expiration date:  
```bash
kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -dates
```

If expired, generatea new one config:
```bash
talosctl -n $TALOSIP kubeconfig --force
```