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