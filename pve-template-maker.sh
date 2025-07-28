#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.3.0"          # Script version
TEMP_DL="/tmp/pve-dl"    # Where images are fetched before import
LOG_FILE="/var/log/pve-template-maker.log"

# -----------------------------  T R A P S  -----------------------------

cleanup() {
  local ec=$?
  tput sgr0  # reset colour just in case
  [[ -d "${TEMP_DL}" ]] && rm -rf "${TEMP_DL}"
  echo -e "\n$(date '+%F %T') • Cleanup complete (exit ${ec})" >>"${LOG_FILE}"
}
trap cleanup EXIT INT TERM

error() {
  echo -e "\n\e[1;31mERROR: $*\e[0m" | tee -a "${LOG_FILE}"
  exit 1
}

# ---------------------------  C O L O U R S  ---------------------------

C_CYAN='\e[1;36m'
C_GREEN='\e[1;32m'
C_YELLOW='\e[1;33m'
C_RED='\e[1;31m'
C_RESET='\e[0m'

stage()   { echo -e "${C_CYAN}\n==> $*${C_RESET}"; }
notice()  { echo -e "${C_GREEN}✔ $*${C_RESET}"; }

# -----------------------  P R O G R E S S  B A R  ----------------------

progress() {  # progress <current> <total> <text>
  local cur=$1 tot=$2 txt=$3
  local bar_w=50
  local pct=$(( cur * 100 / tot ))
  local fill=$(( pct * bar_w / 100 ))
  printf "\r${C_YELLOW}["
  printf '%0.s#' $(seq 1 $fill)
  printf '%0.s ' $(seq 1 $((bar_w-fill)))
  printf "] %3s%%  %s${C_RESET}" "${pct}" "${txt}"
}

# -----------------------------  O S  L I S T  --------------------------

declare -A OS_IMAGE=(
  ["Arch Linux"]="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
  ["Debian 12 (Bookworm)"]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  ["Alpine Linux 3.21"]="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-standard-3.21.0-x86_64.iso"
  ["Gentoo"]="https://gentoo.osuosl.org/releases/amd64/autobuilds/current-iso/gentoo-install-amd64-minimal.iso"
  ["openSUSE Tumbleweed"]="https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-JeOS.x86_64-cloud.qcow2"
  ["openSUSE Leap 15.6"]="https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-JeOS.x86_64-Cloud.qcow2"
  ["Fedora Server 40"]="https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2"
  ["Ubuntu 24.04 LTS Server"]="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  ["Ubuntu 22.04 LTS Server"]="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  ["Ubuntu 20.04 LTS Server"]="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  ["Rocky Linux 9"]="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  ["AlmaLinux 9"]="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
)

declare -A OS_NICK=(
  ["Arch Linux"]="arch"
  ["Debian 12 (Bookworm)"]="debian12"
  ["Alpine Linux 3.21"]="alpine321"
  ["Gentoo"]="gentoo"
  ["openSUSE Tumbleweed"]="tumbleweed"
  ["openSUSE Leap 15.6"]="leap156"
  ["Fedora Server 40"]="fedora40"
  ["Ubuntu 24.04 LTS Server"]="ubuntu2404"
  ["Ubuntu 22.04 LTS Server"]="ubuntu2204"
  ["Ubuntu 20.04 LTS Server"]="ubuntu2004"
  ["Rocky Linux 9"]="rocky9"
  ["AlmaLinux 9"]="almalinux9"
)

# -------------------  H A R D W A R E   D E T E C T  -------------------

HOST_CORES=$(grep -c ^processor /proc/cpuinfo)
HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')  # MB
DEFAULT_CORES=$(( HOST_CORES > 8 ? 4 : 2 ))
DEFAULT_RAM=$(( HOST_MEM > 16384 ? 4096 : 2048 ))

# ---------------------  S T O R A G E  U T I L S  ----------------------

list_storages() {
  pvesm status --enabled \
    | awk 'NR>1{printf "%d) %-15s (%s)\n", NR-1,$1,$2}'
}

select_storage() {
  echo -e "\n${C_CYAN}Select target storage:${C_RESET}"
  list_storages
  read -rp "Enter number: " sel
  STORAGE=$(pvesm status --enabled | awk "NR==$((sel+1)){print \$1}")
  [[ -z "${STORAGE}" ]] && error "Invalid selection."
}

storage_supports_qcow2() {
  local st=$1 fmt
  fmt=$(pvesm status --storage "${st}" | awk 'NR==2{print $2}')
  case ${fmt} in
    dir|nfs|zfs|zfspool|cephfs) echo "qcow2";;
    lvm*|iscsi*)               echo "raw";;
    *)                         echo "qcow2";;
  esac
}

# ---------------------  I M A G E   F U N C T I O N S  -----------------

download_image() {
  local url=$1 dst=$2
  mkdir -p "${TEMP_DL}"
  notice "Downloading image..."
  curl -L --fail -# "${url}" -o "${dst}" \
    || error "Failed to download ${url}"
}

import_disk_and_convert() {
  local vmid=$1 img=$2 storage=$3
  local fmt imgfmt targetfmt
  imgfmt=$(qemu-img info --output=json "${img}" | jq -r '.format')
  targetfmt=$(storage_supports_qcow2 "${storage}")
  [[ "${imgfmt}" != "${targetfmt}" ]] && {
    notice "Converting ${imgfmt} → ${targetfmt} ..."
    qemu-img convert -O "${targetfmt}" "${img}" "${img}.${targetfmt}"
    img="${img}.${targetfmt}"
  }
  qm importdisk "${vmid}" "${img}" "${storage}" --format "${targetfmt}"
}

# ------------------  V M   T E M P L A T E   C R E A T E  --------------

create_template() {
  local os="$1" url="$2"
  local nick="${OS_NICK[$os]}"
  local imgfile="${TEMP_DL}/${nick}.img"
  local vmid; vmid=$(pvesh get /cluster/nextid)
  local stages=6 cur=0

  stage "Processing ${os}"
  progress $cur $stages "initialising"; sleep 0.2

  [[ ! -f "${imgfile}" ]] && download_image "${url}" "${imgfile}"
  progress $((++cur)) $stages "downloaded"

  qm create "${vmid}" \
      --name "${nick}-tpl" \
      --memory "${DEFAULT_RAM}" --cores "${DEFAULT_CORES}" \
      --cpu host --machine q35 \
      --net0 virtio,bridge=vmbr0 \
      --agent enabled=1 \
      --ostype l26 --bios ovmf --efidisk0 "${STORAGE}":1,format=raw
  progress $((++cur)) $stages "VM shell"

  import_disk_and_convert "${vmid}" "${imgfile}" "${STORAGE}"
  progress $((++cur)) $stages "disk imported"

  local diskid; diskid=$(qm config "${vmid}" | awk -F':' '/^scsi/ {print $1;exit}')
  qm set "${vmid}" --scsihw virtio-scsi-pci --"${diskid}" "${STORAGE}:vm-${vmid}-disk-0" \
       --boot order="${diskid}" --bootdisk "${diskid}"
  progress $((++cur)) $stages "disk attached"

  qm resize "${vmid}" "${diskid}" 10G --force
  qm set "${vmid}" --serial0 socket --vga serial0
  progress $((++cur)) $stages "resized & tuned"

  qm template "${vmid}"
  progress $((++cur)) $stages "TEMPLATE READY"
  echo    # newline after progress bar
  notice  "${os} template created (VMID ${vmid})."
}

# ---------------------------  M A I N   M E N U  -----------------------

main_menu() {
  echo -e "${C_CYAN}Proxmox Template Maker (v${VERSION})${C_RESET}"
  echo -e "Detected host: ${HOST_CORES} cores, ${HOST_MEM} MB RAM."
  echo    "Default template size: 10 GB"

  echo -e "\nChoose one or more OS images:"
  local i=1 choice
  declare -a choices
  for os in "${!OS_IMAGE[@]}"; do
    printf "  %2d) %s\n" "${i}" "${os}"; ((i++))
  done
  read -rp $'\nSelection (e.g. 1 3 5): ' -a choice

  for idx in "${choice[@]}"; do
    local oskey
    oskey=$(printf "%s\n" "${!OS_IMAGE[@]}" | sed -n "${idx}p")
    [[ -n "${oskey}" ]] && choices+=("${oskey}")
  done
  [[ ${#choices[@]} -eq 0 ]] && error "No valid selections."

  select_storage
  echo    # spacing

  for os in "${choices[@]}"; do
    local url imgurl
    read -rp "Custom image URL for ${os}? Leave blank for default: " imgurl
    url=${imgurl:-${OS_IMAGE[$os]}}
    create_template "${os}" "${url}"
  done

  notice "All tasks complete."
}

# -------------------------------  R U N  -------------------------------

main_menu "$@"
