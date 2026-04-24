# Storage

## SMB shares (with CSI driver)

CSI driver for SMB shares, pinned at `v1.13.0`. The manifests have been downloaded from the official install script and saved locally:

```bash
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/v1.13.0/deploy/install-driver.sh | bash -s v1.13.0 --
```

The script applies in order: RBAC, CSIDriver, controller, node (Windows node excluded).  
The StorageClass is from:

```bash
kubectl create -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/deploy/example/storageclass-smb.yaml
```

### Step 1a: create the SMB credentials secret

The secret must be created manually (not tracked in git):

```bash
kubectl create secret generic smbcreds \
  --from-literal=username=<your-username> \
  --from-literal=password=<your-password> \
  --namespace default \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 1b: create the NAS credentials secrets (read-only and read-write)

Two separate secrets must be created manually (not tracked in git), one per access level:

```bash
# Read-only user
kubectl create secret generic nascreds-ro \
  --from-literal=username=<nas-ro-username> \
  --from-literal=password=<nas-ro-password> \
  --namespace default \
  --dry-run=client -o yaml | kubectl apply -f -

# Read-write user
kubectl create secret generic nascreds-rw \
  --from-literal=username=<nas-rw-username> \
  --from-literal=password=<nas-rw-password> \
  --namespace default \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 2: update the StorageClass

Edit `05_storageclass-smb.yaml` and set the actual SMB share path:

```yaml
parameters:
  source: "//192.168.178.x/sharename"   # replace with your NAS/server address
```

`07_storageclass-nas-rw.yaml` uses `envsubst` for the NAS address — no manual edit needed (see Step 3).

> **Note:** read-only NAS shares (`nas-ro`) require **static provisioning** (PV + PVC).
> Dynamic provisioning does not work with RO shares because the SMB CSI driver needs
> to create a subdirectory inside the share at provision time, which requires write access.
> See `sample-pod-mount.yaml` for the static provisioning pattern.

### Step 3: apply all resources via kustomize

`07_storageclass-nas-rw.yaml` uses environment variables substituted at apply time via `envsubst`. Export the variables before applying:

```bash
set -a; source ../.env; set +a
kustomize build ./storage | envsubst | kubectl apply -f -
```

### Step 4: verify

```bash
kubectl -n kube-system get pod -o wide -l app=csi-smb-controller
kubectl -n kube-system get pod -o wide -l app=csi-smb-node
kubectl get storageclass smb nas-rw
```

### Step 5: Notes

Our PV are in 'Retain' mode: if PVC is deleted, the PV remains to be bound again or to be manually deleted.  
If you need to bound again a PV, maybe after deleting it s PVC, you need to manually patch if this way:  
```bash
kubectl patch pv pv-nas-ro --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
```
This command will release the claimRef and allows a rebind. 

---

## Local Disk (Talos UserVolume)

Local NVMe volumes are managed at the Talos level — not via kubectl.

Add the following to `controlplane.yaml` to provision a volume:

```yaml
---
apiVersion: v1alpha1
kind: UserVolumeConfig
name: hdd-data-1
provisioning:
  diskSelector:
    match: disk.transport == 'nvme'
  minSize: 20GB
  maxSize: 50GB
```

Then apply:

```bash
talosctl apply-config --file controlplane.yaml
```

Check the mount point:

```bash
talosctl get mountstatus
```

Use the volume in a Pod:

```yaml
volumes:
  - name: hdd-data-1
    hostPath:
      path: /var/mnt/hdd-data-1
```

List available disks:

```bash
talosctl get disks -n $TALOSIP -e $TALOSIP
```

Wipe a disk if needed:

```bash
talosctl wipe disk nvme0n1 --drop-partition
```
