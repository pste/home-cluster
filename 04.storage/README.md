# Storage

## Local Disk(s)

List my disks:  
`talosctl get disks -n $TALOSIP -e $TALOSIP`  

Wipe my HDD (nvme0n1):  
`talosctl wipe disk nvme0n1 --drop-partition`

Edit the controlplane (add the end), to add a Volume:  
```
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

Create the Volume:  
`talosctl apply-config --file controlplane.yaml`

Check the mount point:  
`talosctl get mountstatus`

Use the volume in a Pod:  
```
  volumes:
    - name: hdd-data-1
      hostPath:
        path: /var/mnt/hdd-data-1
```

## SMB shares (with CSI driver)

Install:  
`curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/v1.13.0/deploy/install-driver.sh | bash -s v1.13.0 --`

Storage class:  
`kubectl create -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/deploy/example/storageclass-smb.yaml`

Check status:  
`kubectl -n kube-system get pod -o wide --watch -l app=csi-smb-controller`
`kubectl -n kube-system get pod -o wide --watch -l app=csi-smb-node`

Now in your App you can create a Secret for credentials, a PV and a PVC to use the volume.