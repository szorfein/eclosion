#!/usr/bin/env bash

set -ue

CONF=~/eclosion.conf

DISKS=""
BOOT_DISKS=""

# Erase previous content
:>$CONF

die() { echo "$1"; exit 1; }

# keep this function to format disk in another program !
detect_disk() {
  lsblk -Sf -o NAME,SIZE,MODEL,TRAN | grep ^s
}

add_conf() { echo $1 >> $CONF; }

detect_zpool() {
  ZPOOL_NAME=$(zpool status | grep -i pool | awk '{print $2}')
  [ -z $ZPOOL_NAME ] && { 
    echo "Fail to detect your pool name... enter your pool name."
    read -r ZPOOL_NAME
  }
  echo -n $ZPOOL_NAME
  add_conf ZPOOL_NAME=$ZPOOL_NAME
  echo
}

# use eselect kernel list to detect your kernel version
detect_kernel() {
  KERNEL_LIST=$(eselect kernel list | grep "*" | awk '{print $2}' | sed s/linux-//)
  [ -z $KERNEL_LIST ] && die "eselect kernel list is void..."
  [ ! -d /usr/src/linux-$KERNEL_LIST ] && die "path /usr/src/linux-$KERNEL_LIST no found"
  add_conf KERNEL=$KERNEL_LIST
  echo $KERNEL_LIST
  unset KERNEL_LIST
}

mount_boot() {
  if ! grep $1 /proc/mounts >/dev/null ; then
    mount $1 || die "unable to mount $1..."
  fi
}

mount_boot /boot # cryptboot
mount_boot /boot/efi # efi

# find uuid: ls -l /dev/disk/by-uuid/ | grep sdc1 | awk '{print $9}'
# sudo lsblk -f | grep sdc1 | awk '{print $3}'
detect_partition() {
  BOOT_PARTITION=$(grep /boot/efi /proc/mounts | awk '{print $1}')
  BOOT_DISK=$(echo $BOOT_PARTITION | tr -d "[0-9]+")
  BOOT_PARTITION_NUMBER=$(echo $BOOT_PARTITION | grep -o "[0-9]")
  add_conf BOOT_DISK=$BOOT_DISK
  add_conf BOOT_PARTITION_NUMBER=$BOOT_PARTITION_NUMBER
  echo $BOOT_PARTITION
  unset BOOT_PARTITION BOOT_DISK BOOT_PARTITION_NUMBER
}

detect_init() {
  if [ -f /lib/systemd/systemd ] ; then
    INIT=/lib/systemd/systemd
  elif [ -f /usr/lib/systemd/systemd ] ; then
    INIT=/usr/lib/systemd/systemd
  elif [ -f /sbin/init ] ; then
    INIT=/sbin/init
  fi
  [ -z $INIT ] && die "init is no found."
  add_conf INIT=$INIT
  echo "$INIT"
  unset INIT
}

echo -ne "Check your zpool name...\t"
detect_zpool

echo -ne "Check your kernel...\t\t"
detect_kernel

echo -ne "Detect partitions...\t\t"
detect_partition

echo -ne "Detect init...\t\t\t"
detect_init

echo -e "\nREAD content of the file $CONF..."
cat <$CONF
