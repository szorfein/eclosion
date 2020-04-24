#!/usr/bin/env sh

set -o errexit -o nounset

ROOT_CONF=/etc/eclosion/eclosion.conf
TMP_CONF=/tmp/eclosion.conf

# user variables
OLD_ZPOOL=
OLD_CUSTOM_CMDLINE=
OLD_CUSTOM_ECLOSION_ARGS=

die() { echo "$1"; exit 1; }

add_conf() { echo "$1" >> $TMP_CONF; }

display_disk() {
  lsblk -po NAME,MODEL,SIZE
}

search_uuid() {
  BY_UUID=$(find -L /dev/disk/by-uuid -samefile "$1")
  [ -z "$BY_UUID" ] && {
    echo "No UUID found for $1" 
    return 1
  }
  [ -n "$BY_UUID" ] && return 0
}

search_disk() {
  while :; do
    echo
    echo "Which disk is your $1 ? (Full path, e.g: /dev/sda1)"
    printf "> "; read -r
    [ -b "$REPLY" ] && {
      search_uuid "$REPLY"
      res=$?
      [ $res -eq 0 ] && break
    }
  done
}

rem_old_entry() {
  [ -f "$2" ] || {
    echo "File $2 no found"
    return
  }
  old="$(grep "$1" "$2")"
  [ -z "$old" ] && return
  echo "clean $2 with $1"
  sed -i "/$1 / d" "$2" 1>/dev/null # Add a space to remove multiple occurence of boot
  echo $?
}

need_root() {
  [ "$(id -u)" -ne 0 ] && die "I need root privilege to $1"
  return 0
}

write_fstab() {
  _DEV=$1
  _PATH=$2
  _FS=$3
  _ARGS=$4
  _DUMP=0
  _FSCK=2

  need_root "change the fstab"
  echo "$_DEV $_PATH $_FS $_ARGS $_DUMP $_FSCK" >> /etc/fstab
}

write_cryptboot() {
  _NAME=cryptboot
  _PASS=none
  _OPTS=luks

  need_root "change the crypttab"
  echo "$_NAME $CRYPTBOOT $_PASS $_OPTS" >> /etc/crypttab
}

detect_new_efi_part() {
  display_disk
  search_disk ESP
  EFI=UUID=${BY_UUID##*/}
  echo "$EFI"
  rem_old_entry "\/boot\/efi" /etc/fstab
  write_fstab "$EFI" /boot/efi vfat "noauto,rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro"
}

detect_new_cryptboot_part() {
  display_disk
  search_disk CRYPTBOOT
  CRYPTBOOT=UUID=${BY_UUID##*/}
  echo "$CRYPTBOOT"
  rem_old_entry cryptboot /etc/crypttab
  write_cryptboot
  rem_old_entry "\/boot" /etc/fstab
  write_fstab /dev/mapper/cryptboot /boot ext4 "noauto,rw,relatime,nojournal_checksum,barrier,user_xattr"
}

search_root_fs() {
  echo "Exec zfs list..."
  zfs list -H -o name -d 2 | head -n 7
  echo "No old zpool found, which dataset is your ROOT fs? (e.g: poolname/ROOT/gentoo)"
  printf "> "; read -r
  OLD_ZPOOL=$REPLY
}

get_user_vars() {
  OLD_ZPOOL=$(grep ^ZPOOL $ROOT_CONF) || echo "No old zpool found"
  OLD_CUSTOM_CMDLINE="$(grep ^CUSTOM_CMDLINE $ROOT_CONF)" || echo "No old cmdline found"
  OLD_CUSTOM_ECLOSION_ARGS="$(grep ^CUSTOM_ECLOSION_ARGS $ROOT_CONF)" ||
    echo "No old eclosin args found"
}

search_zpool() {
  [ -f $ROOT_CONF ] || search_root_fs
  printf "check pool... %s" "$OLD_ZPOOL"
  if zfs get exec "${OLD_ZPOOL#*=}" >/dev/null ; then
    echo " ...[Ok]"
  else
    echo "Fail to found ${OLD_ZPOOL#*=}"
    search_root_fs
  fi
}

search_bydisk() {
  printf "Check EFI %s" "$EFI_PARTITION"
  if find -L /dev/disk -samefile "$(findfs "$EFI_PARTITION")" >/dev/null ; then
    echo " ...[Ok]"
  else
    EFI_PARTITION=
  fi
}

control_values() {
  [ -n "$OLD_ZPOOL" ] && search_zpool
  [ -n "$EFI_PARTITION" ] && search_bydisk
}

detect_init() {
  if [ -f /lib/systemd/systemd ] ; then
    INIT=/lib/systemd/systemd
  elif [ -f /usr/lib/systemd/systemd ] ; then
    INIT=/usr/lib/systemd/systemd
  elif [ -f /sbin/init ] ; then
    INIT=/sbin/init
  fi
  [ -z $INIT ] && die "Init is no found, please, post an issue on https://github.com/szorfein/eclosion/issues"
  echo "init found: $INIT"
}

# use eselect kernel list to detect your kernel version
detect_kernel() {
  KERNEL_LIST=$(eselect kernel list | grep "\*" | awk '{print $2}' | sed s/linux-//)
  [ -z "$KERNEL_LIST" ] && die "eselect kernel list is void..."
  [ ! -d /usr/src/linux-"$KERNEL_LIST" ] && die "path /usr/src/linux-$KERNEL_LIST no found"
  echo "kernel found: $KERNEL_LIST"
}

detect_efi_partition() {
  [ -f /etc/fstab ] || detect_new_efi_part
  if FSTAB=$(grep -i efi /etc/fstab | awk '{print $1}') ; then
    echo "Found your EFI partition $FSTAB in the fstab"
    EFI_PARTITION="$FSTAB"
    return 0
  elif LSBLK=$(lsblk -f | grep vfat | awk '{print $3}') ; then
    # lsblk work only if there are only one vfat device plugged, maybe disable this part...
    echo "Found your EFI partition $FSTAB with lsblk"
    EFI_PARTITION="UUID=$LSBLK"
    return 0
  else
    detect_new_efi_part
    EFI_PARTITION=$(grep -i efi /etc/fstab | awk '{print $1}')
  fi
  [ -z "$EFI_PARTITION" ] && die "Can't detect your EFI partition"
}

# From the crypttab, TODO check if you use a cryptboot first !
detect_cryptboot_partition() {
  [ -f /etc/crypttab ] || detect_new_cryptboot_part
  if CRYPTTAB=$(grep cryptboot /etc/crypttab | awk '{print $2}') ; then
    echo "Found cryptboot $CRYPTTAB in the crypttab"
    CRYPTBOOT=$CRYPTTAB
    return 0
  else
    detect_new_cryptboot_part
    CRYPTBOOT=$(grep cryptboot /etc/crypttab | awk '{print $2}')
  fi
  [ -z "$CRYPTBOOT" ] && die "cryptboot partition is no found"
}

detect_all_values() {
  detect_init
  detect_kernel
  detect_efi_partition # from the fstab
  detect_cryptboot_partition # from the crypttab
}

default_values() {
  ZPOOL="" CUSTOM_ECLOSION_ARGS=\"\" CUSTOM_CMDLINE=\"\"
  [ -n "$OLD_ZPOOL" ] && ZPOOL=${OLD_ZPOOL#*=}
  [ -n "$OLD_CUSTOM_ECLOSION_ARGS" ] && CUSTOM_ECLOSION_ARGS="${OLD_CUSTOM_ECLOSION_ARGS#*=}"
  [ -n "$OLD_CUSTOM_CMDLINE" ] && CUSTOM_CMDLINE="${OLD_CUSTOM_CMDLINE#*=}"
  return 0
}

write_user_vars() {
  add_conf "### Users variables #############"
  add_conf "# Pool name"
  add_conf ZPOOL="$ZPOOL"
  add_conf "# Args to pass to eclosion, do not set the kernel"
  add_conf CUSTOM_ECLOSION_ARGS="$CUSTOM_ECLOSION_ARGS"
  add_conf "# Custom kernel arguments"
  add_conf CUSTOM_CMDLINE="$CUSTOM_CMDLINE"
  add_conf ""
}

write_others_vars() {
  add_conf "### Automatically detected, don't edit them #############"
  add_conf "# Post an issue if something is incorrect at: https://github.com/szorfein/eclosion/issues"
  add_conf "# init detected"
  add_conf INIT="$INIT"
  add_conf "# last kernel found with eselect kernel list"
  add_conf KERNEL="$KERNEL_LIST"
  add_conf "# Your EFI partition here by LABEL, UUID, PARTUUID, etc..."
  add_conf EFI_PARTITION="$EFI_PARTITION"
  add_conf "# Your cryptboot partition here"
  add_conf CRYPTBOOT="$CRYPTBOOT"
  add_conf "# CMDLINE"
  add_conf CMDLINE=\""init=\${INIT} root=ZFS=\${ZPOOL} \${CUSTOM_CMDLINE}\""
  add_conf "# Eclosion args"
  add_conf ECLOSION_ARGS=\""--kernel \${KERNEL} \${CUSTOM_ECLOSION_ARGS}\""
}

show_diff() {
  [ -f $ROOT_CONF ] || return 0
  if diff $ROOT_CONF $TMP_CONF >/dev/null ; then
    echo "No change, bye"
    exit 0
  else
    echo "Differences between config files..."
    # hack to display diff without produce error
    for i in $(diff $ROOT_CONF $TMP_CONF); do
      echo "$i"
    done
    printf "Apply change? " ; read -r
    if echo "$REPLY" | grep -qP "^y|^Y" ; then
      echo "Copying the new file..."
      return 0
    else
      echo "Ok, i (lol) do nothing..."
      exit 0
    fi
  fi
}

copy_config_file() {
  need_root "copy the config $ROOT_CONF"
  cp $TMP_CONF $ROOT_CONF
  chmod 644 $ROOT_CONF
}

main() {
  # Erase previous content
  :>$TMP_CONF

  [ -f $ROOT_CONF ] && get_user_vars
  detect_all_values
  control_values
  default_values

  write_user_vars
  write_others_vars
  show_diff
  copy_config_file
}

main $\@
