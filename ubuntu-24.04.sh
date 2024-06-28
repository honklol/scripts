#!/bin/bash
if [ -z $1 ]; then
echo "Error: No storage medium provided."
exit 1
elif [ -z $2 ]; then
echo "Error: No VM ID provided."
exit 1
elif [ -z $3 ]; then
echo "Error: No network bridge provided."
exit 1
else
curl -LO https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img 
qm create $2 --memory 2048 --name ubuntu-24.04-cloudinit --net0 virtio,bridge=$3
qm importdisk $2 noble-server-cloudimg-amd64.img $1
qm set $2 --scsihw virtio-scsi-pci --scsi0 $1:$2/vm-$2-disk-0.raw
qm set $2 --ide2 $1:cloudinit
qm set $2 --boot c --bootdisk scsi0
qm set $2 --serial0 socket --vga serial0
qm template $2
rm noble-server-cloudimg-amd64.img
exit 0
fi
