#!/bin/bash
if [ -z $1 ]; then
echo "Error: No storage medium provided."
exit 1
elif [ -z $2 ]; then
echo "Error: No VM ID provided."
exit 1
else
curl -LO https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2
qm create $2 --memory 2048 --name centos-7-cloudinit --net0 virtio,bridge=vmbr1
qm importdisk $2 CentOS-7-x86_64-GenericCloud.qcow2 $1
qm set $2 --scsihw virtio-scsi-pci --scsi0 $1:$2/vm-$2-disk-0.qcow2
qm set $2 --ide2 local:cloudinit
qm set $2 --boot c --bootdisk scsi0
qm set $2 --serial0 socket --vga serial0
qm template $2
rm CentOS-7-x86_64-GenericCloud.qcow2
exit 0
fi
