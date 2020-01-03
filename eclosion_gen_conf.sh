#!/usr/bin/env bash

set -ue

CONF=~/eclosion.conf
ROOT_CONF=/etc/eclosion/eclosion.conf
OLD_ZPOOL=""
OLD_CUSTOM_CMDLINE=""
OLD_CUSTOM_ECLOSION_ARGS=""

# retrieve old content
if [ -f $ROOT_CONF ] ; then
  if grep ZPOOL $ROOT_CONF >/dev/null ; then
    OLD_ZPOOL="$(grep ZPOOL $ROOT_CONF)"
  fi
  if grep CUSTOM_CMDLINE $ROOT_CONF >/dev/null ; then
    OLD_CUSTOM_CMDLINE="$(grep CUSTOM_CMDLINE $ROOT_CONF)"
  fi
  if grep CUSTOM_ECLOSION_ARGS $ROOT_CONF >/dev/null ; then
    OLD_CUSTOM_ECLOSION_ARGS="$(grep CUSTOM_ECLOSION_ARGS $ROOT_CONF)"
  fi
fi

# Erase previous content
:>$CONF

die() { echo "$1"; exit 1; }

# keep this function to format disk in another program !
detect_disk() {
  lsblk -Sf -o NAME,SIZE,MODEL,TRAN | grep ^s
}

add_conf() { echo $1 >> $CONF; }

detect_zpool() {
  if [ -z $OLD_ZPOOL ] ; then
    ZPOOL_NAME=$(zpool status | grep -i pool | awk '{print $2}')
    [ -z $ZPOOL_NAME ] && { 
      echo "Fail to detect your pool name... enter your pool name."
      read -r ZPOOL_NAME
    }
    ZPOOL="$ZPOOL_NAME/ROOT/gentoo"
  else
    ZPOOL="${OLD_ZPOOL#*=}"
  fi
  echo $ZPOOL
  add_conf "# your main zfs pool here"
  add_conf ZPOOL=$ZPOOL
  unset ZPOOL_NAME
}

# use eselect kernel list to detect your kernel version
detect_kernel() {
  KERNEL_LIST=$(eselect kernel list | grep "*" | awk '{print $2}' | sed s/linux-//)
  [ -z $KERNEL_LIST ] && die "eselect kernel list is void..."
  [ ! -d /usr/src/linux-$KERNEL_LIST ] && die "path /usr/src/linux-$KERNEL_LIST no found"
  add_conf "# last kernel found with eselect kernel list"
  add_conf KERNEL=$KERNEL_LIST
  echo $KERNEL_LIST
}

checkRoot() {
  [ "$(id -u)" -ne 0 ] &&
    die "I need better permission to mount your boot partition"
}

# used by efibootmgr
# find uuid: ls -l /dev/disk/by-uuid/ | grep sdc1 | awk '{print $9}'
# lsblk -f | grep sdc1 | awk '{print $3}'
detect_partition() {
  BOOT_PARTITION=/dev/$(lsblk -f | grep vfat | grep -o "s[a-z0-9]*")
  BOOT_DISK=$(echo $BOOT_PARTITION | tr -d "[0-9]+")
  BOOT_PARTITION_NUMBER=$(echo $BOOT_PARTITION | grep -o "[0-9]")
  add_conf "# Disk fat32 $BOOT_PARTITION used by efibootmgr"
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
  add_conf "# init detected"
  add_conf INIT=$INIT
  echo "$INIT"
}

detect_cmdline() {
  add_conf "# your custom kernel command line"
  if [ -z "$OLD_CUSTOM_CMDLINE" ] ; then
    CUSTOM_CMDLINE=""
    add_conf CUSTOM_CMDLINE="$CUSTOM_CMDLINE"
  else
    CUSTOM_CMDLINE="${OLD_CUSTOM_CMDLINE#*=}"
    add_conf CUSTOM_CMDLINE="$CUSTOM_CMDLINE"
  fi
  CMDLINE="init=$INIT root=ZFS=$ZPOOL $(echo $CUSTOM_CMDLINE | tr -d "'\"")"
  echo "$CMDLINE"
  add_conf CMDLINE="$CMDLINE"
  unset CMDLINE INIT ZPOOL
}

eclosion_args() {
  add_conf "# your custom flags to pass to eclosion"
  if [ -z "$OLD_CUSTOM_ECLOSION_ARGS" ] ; then
    CUSTOM_ECLOSION_ARGS=""
    add_conf CUSTOM_ECLOSION_ARGS="$CUSTOM_ECLOSION_ARGS"
  else
    CUSTOM_ECLOSION_ARGS="${OLD_CUSTOM_ECLOSION_ARGS#*=}"
    add_conf CUSTOM_ECLOSION_ARGS="$CUSTOM_ECLOSION_ARGS"
  fi
  ECLOSION_ARGS="--kernel $KERNEL_LIST $(echo $CUSTOM_ECLOSION_ARGS | tr -d "'\"")"
  echo "$ECLOSION_ARGS"
  add_conf ECLOSION_ARGS="$ECLOSION_ARGS"
  unset ECLOSION_ARGS KERNEL_LIST
}

echo -ne "Check your zpool name...\t"
detect_zpool

echo -ne "Check your kernel...\t\t"
detect_kernel

echo -ne "Detect partitions...\t\t"
detect_partition

echo -ne "Detect init...\t\t\t"
detect_init

echo -ne "Check the cmdline...\t\t"
detect_cmdline

echo -ne "Check eclosion args...\t\t"
eclosion_args

echo -e "\nREAD content of the file $CONF..."
cat <$CONF
echo

if [ -f $ROOT_CONF ] ; then
  if diff $ROOT_CONF $CONF >/dev/null ; then
    echo "no change"
    exit 0
  else
    diff $ROOT_CONF $CONF
    read -p "apply change ?"
    if [[ $REPLY =~ ^y|^Y ]] ; then
      echo "Copying the new file..."
    else
      echo "do nothing..."
      exit 0
    fi
  fi
else
  echo "New config file, copying..."
fi

if [ $(id -u) -ne 0 ] ; then
  die "I need root privilege to copy the new file at $ROOT_CONF, use sudo next time"
else
  cp $CONF $ROOT_CONF
  chmod 644 $ROOT_CONF
fi

exit 0
