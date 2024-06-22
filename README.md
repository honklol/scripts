# Cloudinit templates for Proxmox

## Ubuntu Server 20.04 (focal)
- Usage: ``curl https://honklol.github.io/scripts/cloudinit/ubuntu-20.04.sh | bash -s -- <storage> <vm id> <net bridge>``
- Example: ```curl https://honklol.github.io/scripts/cloudinit/ubuntu-20.04.sh | bash -s -- local-lvm 10000 vmbr0```
