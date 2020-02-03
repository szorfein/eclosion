#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

########################################################
# Program Vars

if [ -d /lib/eclosion ] ; then
  ECLODIR=/lib/eclosion
else
  ECLODIR=$(pwd)
fi

ECLODIR_STATIC=$ECLODIR/static
WORKDIR=/tmp/eclosion
ROOT=/mnt/root
LOG=$ECLODIR/build-img.log
QUIET=true
CUSTOM=false
BANNER=""

die() { echo "[-] $1"; exit 1; }

########################################################
# Cmdline options

usage() {
  echo "-k, --kernel    Kernel version to use [Required]"
  echo "-l, --luks    Add cryptsetup to the image"
  echo "-g, --gpg    Add gpg-2 to the image with gpg-agent"
  echo "-u, --usb    Add support to load usb key"
  echo "-h, --help    Print this fabulous help"
  echo "-K, --keymap    Add other keymap than en to the initram"
  echo "-e, --external-key    Full path of the key file to add directly to the initram"
  echo "-c, --custom    Copy the custom script to the image located at /etc/eclosion/custom"
  echo "-b, --banner-ascii    Full path of a ascii banner, a simple .txt file"
  exit 0
}

if [ "$#" -eq 0 ] ; then
  echo "$0: Argument required"
  echo "Try $0 --help for more information."
  exit 1
fi

while [ "$#" -gt 0 ] ; do
  case "$1" in
    -k | --kernel)
      KERNEL=$2
      shift
      shift
      ;;
    -l | --luks)
      LUKS=true
      shift
      ;;
    -g | --gpg)
      GPG=true
      shift
      ;;
    -u | --usb)
      USB=true
      shift
      ;;
    -K | --keymap)
      KEYMAP=$2
      shift
      shift
      ;;
    -e | --external-key)
      EXT_KEY=$2
      shift
      shift
      ;;
    -c | --custom)
      CUSTOM=true
      [ -f /etc/eclosion/custom ] ||
          die "custom script no found at /etc/eclosion/custom"
      shift
      ;;
    -b | --banner-ascii)
      BANNER=$2
      shift
      shift
      ;;
    -h | --help)
      usage
      shift
      ;;
    *)
      echo "$0: Invalid option '$1'"
      echo "Try '$0 --help' for more information."
      exit 1
      ;;
  esac
done

[ -d /lib/modules/$KERNEL ] || die "Kernel version $KERNEL no found"

########################################################
# Check root

[ $(id -u) -ne 0 ] && die "Run this program as a root pls"

########################################################
# Install $WORKDIR

[ -d $WORKDIR ] && rm -rf $WORKDIR/*

[ -d $WORKDIR ] || mkdir $WORKDIR
[ -d $ECLODIR_STATIC ] || mkdir -p $ECLODIR_STATIC
echo >$LOG && echo "[+] Build saved to $LOG"

cd $WORKDIR

########################################################
# Base

mkdir -p bin dev etc lib64 mnt/root proc root sbin sys run usr/lib64

# If use lib64
if [[ -s /lib ]] ; then
  ln -s lib64 lib
  cd usr; ln -s lib64 lib; cd ..
else
  mkdir lib
  mkdir usr/lib
fi

donod() {
  pushd dev || die "donod, pushd dev"
  [ -c console ] || mknod -m 600 console c 5 1 || die "donod, console"
  [ -c null    ] || mknod -m 666 null    c 1 3 || die "donod, null"
  [ -c tty     ] || mknod -m 666 tty     c 5 0 || die "donod, tty"
  [ -c zero    ] || mknod -m 666 zero    c 1 5 || die "donod, zero"

  for i in 0 1 2; do
    [ -c tty${i} ] || mknod -m 600 tty${i} c 4 ${i} || die "donod, tty[$i]..."
  done
  popd || die "donod, popd..."
}

# Device nodes
cp -a /dev/{console,null,tty,tty[0-2],zero} dev/ || donod

########################################################
# ZFS

bins="blkid zfs zpool mount.zfs zdb fsck.zfs"
modules="zlib_deflate spl zavl znvpair zcommon zunicode icp zfs"

########################################################
# Functions

doBin() {
  local lib bin link
  if bin=$(which $1) ; then
    for lib in $(lddtree -l $bin 2>/dev/null | sort -u) ; do
      echo "[+] Copying lib $lib to .$lib ... " >>$LOG
      if [ -h $lib ] ; then
        link=$(readlink $lib)
        echo "Found a link $lib == ${lib%/*}/$link" >>$LOG
        cp -a $lib .$lib
        cp -a ${lib%/*}/$link .${lib%/*}/$link
      elif [ -x $lib ] ; then
        echo "Found binary $lib" >>$LOG
        cp -a $lib .$lib
      fi
    done
  else
    echo "no $1 found on the system, please install"
    exit 1
  fi
}

doMod() {
  local m mod=$1 modules lib_dir=/lib/modules/$KERNEL

  for mod; do
    modules="$(sed -nre "s/(${mod}(|[_-]).*$)/\1/p" ${lib_dir}/modules.dep)"
    if [ -n "${modules}" ]; then
      for m in ${modules}; do
        m="${m%:}"
        echo "[+] Copying module $m ..." >>$LOG
        mkdir -p .${lib_dir}/${m%/*}
        if [ -f ${lib_dir}/${m}.xz ] ; then
          cp -ar ${lib_dir}/${m}.xz .${lib_dir}/${m}.xz
        elif [ -f ${lib_dir}/${m}.gz ] ; then
          cp -ar ${lib_dir}/${m}.gz .${lib_dir}/${m}.gz
        elif [ -f ${lib_dir}/${m} ] ; then
          cp -ar ${lib_dir}/${m} .${lib_dir}/${m}
        else
          echo "[-] ${mod} kernel module not found" >>$LOG
        fi
      done
    else
      echo "[-] ${mod} kernel module not found" >>$LOG
    fi
  done
}

########################################################
# Install hooks

. $ECLODIR/hooks/busybox

# mdev or udev
DEVTMPFS=$(grep devtmpfs /proc/filesystems)

# mdev and udev need /etc/group
cp -a /etc/group etc/group

if [ -z "$DEVTMPFS" ] ; then
  . $ECLODIR/hooks/mdev
else
  . $ECLODIR/hooks/udev
fi

[ ! -z ${GPG:-} ] && . $ECLODIR/hooks/gpg
[ ! -z ${LUKS:-} ] && . $ECLODIR/hooks/luks
[ ! -z ${KEYMAP:-en} ] && . $ECLODIR/hooks/keymap
[ ! -z ${EXT_KEY:-} ] && . $ECLODIR/hooks/external-key
[ ! -z ${USB:-} ] && . $ECLODIR/hooks/usb

########################################################
# libgcc_s.so.1 required by zfs

gcc_version=$(gcc --version | head -n 1 | awk '{print $6}')

if search_lib=$(find /usr/lib* -type f -name libgcc_s.so.1 | grep $gcc_version) ; then
  bin+=" $search_lib"
  cp ${search_lib} usr/lib64/libgcc_s.so.1
else
  echo "[-] libgcc_s.so.1 no found on the system..."
  exit 1
fi

########################################################
# Install binary and modules

for bin in $bins ; do
  doBin $bin
done

for mod in $modules ; do
  doMod $mod
done

########################################################
# Copy the modules.dep

mkdir -p lib/modules/$KERNEL
cp -a /lib/modules/$KERNEL/modules.dep ./lib/modules/$KERNEL/modules.dep

########################################################
# Copy scripts

mkdir -p lib/eclosion/{init-top,init-bottom}
for s in $ECLODIR/scripts/init-top/* ; do
  cp $s lib/eclosion/init-top/${s##*/}
  chmod +x lib/eclosion/init-top/${s##*/}
done

for s in $ECLODIR/scripts/init-bottom/* ; do
  cp $s lib/eclosion/init-bottom/${s##*/}
  chmod +x lib/eclosion/init-bottom/${s##*/}
done

if [ $CUSTOM == true ] ; then
  cp /etc/eclosion/custom lib/eclosion/
  chmod +x lib/eclosion/custom
fi

########################################################
# Simple files

mkdir -p etc/eclosion
cp /etc/eclosion/eclosion.conf etc/eclosion/

if [ ! -z $BANNER ] ; then
  [ -f $BANNER ] || die "file $BANNER no found"
  cp $BANNER etc/eclosion/banner.logo
fi

########################################################
# Build the init

cat > init << EOF
#!/bin/sh

ROOT=$ROOT
MODULES="$modules"
UDEVD=$UDEVD
export HOME=/root
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

rescueShell() {
  echo "\$1. Dropping you to a shell."
  /bin/sh -l
}

# Disable kernel log
dmesg=

#######################################################
# if keyboard other than english

[ -f /usr/share/keymaps/keyboard.bin ] &&
  loadkmap < /usr/share/keymaps/keyboard.bin

#######################################################
# Modules

# Load modules
if [ -n "\$MODULES" ]; then
  for m in \$MODULES ; do
    modprobe \$m 2>/dev/null
  done
else
  rescueShell "No modules found"
fi

#######################################################
# Filesytem and mdev setup

mkdir -p dev/pts proc run sys \$ROOT

# mount for mdev 
# https://git.busybox.net/busybox/plain/docs/mdev.txt
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t tmpfs -o mode=755,size=1% tmpfs /run

# mount dev
if grep -q devtmpfs /proc/filesystems; then
  mount -t devtmpfs devtmpfs /dev
else
  . /lib/eclosion/init-top/mdev
fi

#######################################################
# udevd

. /lib/eclosion/init-top/udev

#######################################################
# Other hooks

[ -f /lib/eclosion/init-top/gpg ] && 
  . /lib/eclosion/init-top/gpg

#######################################################
# Kernel args

for x in \$(cat /proc/cmdline) ; do
  case \$x in
    root=ZFS=*) BOOT=\$x ;;
    init=*) INIT=\${x#*=} ;;
  esac
done

if [ -z \$BOOT ] ; then
  rescueShell "No pool defined has kernel cmdline"
else
  # change root=ZFS=zfsforninja/ROOT/gentoo, in
  # zfsforninja/ROOT/gentoo
  BOOTFS=\${BOOT##*=}
  RPOOL=\${BOOTFS%%/*}
fi

#######################################################
# source conf

[ -f /etc/eclosion/eclosion.conf ] && . /etc/eclosion/eclosion.conf

#######################################################
# Banner

[ -f /etc/eclosion/banner.logo ] && cat /etc/eclosion/banner.logo

#######################################################
# If custom hook is enable

[ -f /lib/eclosion/custom ] && . /lib/eclosion/custom

#######################################################
# Import POOL and dataset

. /lib/eclosion/init-top/zfs
. /lib/eclosion/init-bottom/zfs

#######################################################
# Cleanup and switch

[ -f /lib/eclosion/init-bottom/gpg ] && 
  . /lib/eclosion/init-bottom/gpg

. /lib/eclosion/init-bottom/udev
. /lib/eclosion/init-bottom/mdev

# cleanup
for dir in /run /sys /proc ; do
  echo "Unmouting \$dir"
  umount -l \$dir
  echo "\$?"
done

# switch
exec switch_root /mnt/root \${INIT:-/sbin/init}

# If the switch has fail
rescueShell "Yaaa, it is sucks"
EOF

chmod u+x init

INITRAMFS_NAME="initramfs-$KERNEL"

# Create the initramfs
if [ $QUIET == true ] ; then
  find . -print0 | cpio --null -ov --format=newc 2>>$LOG | gzip -9 > ../$INITRAMFS_NAME.img
  echo "[+] Build image size $(tail -n 1 $LOG)"
else
  find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../$INITRAMFS_NAME.img
fi

cd ..
echo "[+] initramfs created at $(pwd)/$INITRAMFS_NAME.img"
exit 0
