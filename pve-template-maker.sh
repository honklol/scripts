#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.3.2"          # Script version
TEMP_DL="/tmp/pve-dl"    # Where images are fetched before import
LOG_FILE="/var/log/pve-template-maker.log"
COLOR=1

# -------- Dependency Check --------
check_deps() {
    local deps=(pvesm qm pvesh jq curl awk grep tput)
    for d in "${deps[@]}"; do
        command -v "$d" &>/dev/null || { echo "Missing required command: $d" 1>&2; exit 3; }
    done
}

# -------- Color/TTY Check --------
init_colors() {
  if ! tput colors &>/dev/null || [[ "$(tput colors)" -lt 8 ]]; then
      COLOR=0
  fi
}
color() {
  if (( COLOR )); then echo -ne "$1"; fi
}
C_CYAN='\e[1;36m'; C_GREEN='\e[1;32m'; C_YELLOW='\e[1;33m'; C_RED='\e[1;31m'; C_RESET='\e[0m'

# -------- Trap/Cleanup/Error --------
cleanup() {
  local ec=$?
  color "${C_RESET}"; tput cnorm 2>/dev/null || true
  [[ -d "${TEMP_DL}" ]] && rm -rf "${TEMP_DL}"
  echo -e "\n$(date '+%F %T') • Cleanup complete (exit ${ec})" >>"${LOG_FILE}"
}
trap cleanup EXIT INT TERM

error() {
  color "${C_RED}"
  echo -e "\nERROR: $*" | tee -a "${LOG_FILE}" >&2
  color "${C_RESET}" ; tput cnorm 2>/dev/null || true
  exit 1
}

stage()   { color "${C_CYAN}"; echo -e "\n==> $*${C_RESET}"; redraw_progress_if_needed; }
notice()  { color "${C_GREEN}"; echo -e "✔ $*${C_RESET}"; redraw_progress_if_needed; }

# -------- Progress Bar (APT-style) --------
PROGRESS_SHOWN=0
PROGRESS_CUR=0
PROGRESS_TOTAL=1
PROGRESS_TXT=""

show_progress() {
    PROGRESS_CUR=$1; PROGRESS_TOTAL=$2; PROGRESS_TXT="$3"; PROGRESS_SHOWN=1
    _draw_progress_bar
}
_draw_progress_bar() {
    # Get terminal width and height
    local bar_w pct fill term_cols term_rows
    term_cols=$(tput cols 2>/dev/null || echo 80)
    term_rows=$(tput lines 2>/dev/null || echo 24)
    bar_w=$((term_cols-30)); ((bar_w<10)) && bar_w=10
    pct=0; if (( PROGRESS_TOTAL != 0 )); then pct=$(( PROGRESS_CUR * 100 / PROGRESS_TOTAL )); fi
    fill=0; if (( PROGRESS_TOTAL != 0 )); then fill=$(( pct * bar_w / 100 )); fi

    # Move cursor to bottom, at last row, clear that line
    tput civis
    tput sc
    tput cup $((term_rows-1)) 0
    printf "%s[" "$( ((COLOR)) && echo -e $C_YELLOW )"
    printf '%0.s#' $(seq 1 $fill)
    printf '%0.s ' $(seq 1 $((bar_w-fill)))
    printf "] %3s%%  %-20.20s%s\r" "${pct}" "${PROGRESS_TXT}" "$C_RESET"
    tput rc
}
hide_progress() {
    if ((PROGRESS_SHOWN)); then
      local term_rows; term_rows=$(tput lines 2>/dev/null || echo 24)
      tput cup $((term_rows-1)) 0
      tput el
      tput cnorm
      PROGRESS_SHOWN=0
    fi
}
redraw_progress_if_needed() { ((PROGRESS_SHOWN)) && _draw_progress_bar; }

# -------- OS Data --------
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
declare -a OS_ORDER=(
  "Ubuntu 22.04 LTS Server"
  "openSUSE Leap 15.6"
  "Debian 12 (Bookworm)"
  "Fedora Server 40"
  "Arch Linux"
  "AlmaLinux 9"
  "Ubuntu 20.04 LTS Server"
  "Alpine Linux 3.21"
  "Rocky Linux 9"
  "openSUSE Tumbleweed"
  "Gentoo"
  "Ubuntu 24.04 LTS Server"
)

# -------- Hardware Detect --------
HOST_CORES=$(grep -c ^processor /proc/cpuinfo)
HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
DEFAULT_CORES=$(( HOST_CORES > 8 ? 4 : 2 ))
DEFAULT_RAM=$(( HOST_MEM > 16384 ? 4096 : 2048 ))

# -------- Storage Selection --------
list_storages() {
  pvesm status --enabled | awk 'NR>1{printf "%d) %-15s (%s)\n", NR-1,$1,$2}'
}
select_storage() {
  color "${C_CYAN}"
  echo -e "\nSelect target storage:${C_RESET}"
  list_storages

  local sel
  safe_read "Enter number: " sel
  [[ ! "$sel" =~ ^[0-9]+$ || $sel -lt 1 ]] && error "Invalid storage selection."
  STORAGE=$(pvesm status --enabled | awk "NR==$((sel+1)){print \$1}")
  [[ -z "${STORAGE}" ]] && error "Invalid selection."
}
storage_supports_qcow2() {
  local st=$1 fmt
  fmt=$(pvesm status --storage "${st}" | awk 'NR==2{print $2}')
  case ${fmt} in dir|nfs|zfs|zfspool|cephfs) echo "qcow2";;
    lvm*|iscsi*) echo "raw";; *) echo "qcow2";; esac
}

# -------- Image Download --------
download_image() {
  local url=$1 dst=$2
  mkdir -p "${TEMP_DL}"
  notice "Downloading image..."
  show_progress 0 1 "Starting download"
  curl -L --fail --progress-bar "${url}" -o "${dst}.part" || error "Failed to download ${url}"
  mv "${dst}.part" "${dst}"
  show_progress 1 1 "Download done"
}

import_disk_and_convert() {
  local vmid=$1 img=$2 storage=$3
  local imgfmt targetfmt
  imgfmt=$(qemu-img info --output=json "${img}" | jq -r '.format') || error "Failed to get image format"
  targetfmt=$(storage_supports_qcow2 "${storage}")
  if [[ "${imgfmt}" != "${targetfmt}" ]]; then
    notice "Converting ${imgfmt} → ${targetfmt}..."
    qemu-img convert -O "${targetfmt}" "${img}" "${img}.${targetfmt}" || error "Image conversion failed"
    mv "${img}.${targetfmt}" "${img}"
  fi
  qm importdisk "${vmid}" "${img}" "${storage}" --format "${targetfmt}" || error "Import disk failed"
}

# -------- Template Creation --------
create_template() {
  local os="$1" url="$2"
  local nick="${OS_NICK[$os]}"
  local imgfile="${TEMP_DL}/${nick}.img"
  local vmid; vmid=$(pvesh get /cluster/nextid)
  local stages=6 cur=0
  stage "Processing ${os}"

  show_progress $cur $stages "initialising"; sleep 0.2
  [[ ! -f "${imgfile}" ]] && (show_progress $((++cur)) $stages "downloading"; download_image "${url}" "${imgfile}";)
  show_progress $((++cur)) $stages "downloaded"

  qm create "${vmid}" \
    --name "${nick}-tpl" \
    --memory "${DEFAULT_RAM}" --cores "${DEFAULT_CORES}" \
    --cpu host --machine q35 \
    --net0 virtio,bridge=vmbr0 \
    --agent enabled=1 \
    --ostype l26 --bios ovmf --efidisk0 "${STORAGE}":1,format=raw || error "qm create failed"
  show_progress $((++cur)) $stages "VM shell"

  import_disk_and_convert "${vmid}" "${imgfile}" "${STORAGE}"
  show_progress $((++cur)) $stages "disk imported"

  local diskid; diskid=$(qm config "${vmid}" | awk -F':' '/^scsi/ {print $1;exit}')
  [[ -z "${diskid}" ]] && error "Failed to determine disk id for VM $vmid"
  qm set "${vmid}" --scsihw virtio-scsi-pci --"${diskid}" "${STORAGE}:vm-${vmid}-disk-0" \
    --boot order="${diskid}" --bootdisk "${diskid}" || error "qm set failed"
  show_progress $((++cur)) $stages "disk attached"

  qm resize "${vmid}" "${diskid}" 10G --force || error "resize failed"
  qm set "${vmid}" --serial0 socket --vga serial0 || error "vm serial failed"
  show_progress $((++cur)) $stages "resized & tuned"

  qm template "${vmid}" || error "qm template failed"
  show_progress $((++cur)) $stages "TEMPLATE READY"
  notice  "${os} template created (VMID ${vmid})."
  hide_progress
}

# -------- Robust Safe Read --------
safe_read() {
  local prompt="$1"; shift
  if [[ -t 0 ]]; then
    read -rp "$prompt" "$@" </dev/tty
  else
    echo -n "$prompt"
    read -r "$@"
  fi
}

# -------- Main Menu --------
main_menu() {
  color "${C_CYAN}"
  echo "Proxmox Template Maker (v${VERSION})${C_RESET}"
  echo "Detected host: ${HOST_CORES} cores, ${HOST_MEM} MB RAM."
  echo "Default template size: 10 GB"

  echo -e "\nChoose one or more OS images:"
  local i=1
  for os in "${OS_ORDER[@]}"; do printf "  %2d) %s\n" "${i}" "${os}"; ((i++)); done

  local choice_input
  safe_read $'\nSelection (e.g. 1 3 5): ' choice_input
  read -ra choice <<< "$choice_input"

  declare -a choices
  for idx in "${choice[@]}"; do
    if [[ "$idx" =~ ^[0-9]+$ && "$idx" -ge 1 && "$idx" -le ${#OS_ORDER[@]} ]]; then
      local oskey="${OS_ORDER[$((idx-1))]}"
      choices+=("${oskey}")
    else
      notice "Warning: Invalid selection '$idx', skipping..."
    fi
  done
  [[ ${#choices[@]} -eq 0 ]] && error "No valid selections."

  select_storage
  echo

  for os in "${choices[@]}"; do
    local imgurl url
    safe_read "Custom image URL for ${os}? Leave blank for default: " imgurl
    url=${imgurl:-${OS_IMAGE[$os]}}
    create_template "${os}" "${url}"
    hide_progress
  done

  notice "All tasks complete."
}

# -------- Initialization and Run --------
check_deps
init_colors
main_menu "$@"
