#!/bin/bash
if [ -z $1 ]; then
echo "Error: No storage medium provided.
exit
else
curl -LO https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
qm create 100000 --memory 2048 --name ubuntu-20.04-cloudinit --net0 virtio,bridge=vmbr1
qm importdisk 100000 focal-server-cloudimg-amd64.img $1
qm set 100000 --scsihw virtio-scsi-pci --scsi0 $1:vm-100000-disk-0.raw
qm set 100000 --scsihw virtio-scsi-pci --scsi0 $1:vm-100000-disk-0
qm set 100000 --scsihw virtio-scsi-pci --scsi0 $1:10000/vm-100000-disk-0.raw
qm set 100000 --scsihw virtio-scsi-pci --scsi0 $1:100000/vm-100000-disk-0.raw
qm set 100000 --ide2 local:cloudinit
qm set 100000 --boot c --bootdisk scsi0
qm set 100000 --serial0 socket --vga serial0
rm focal-server-cloudimg-amd64.img
fi
