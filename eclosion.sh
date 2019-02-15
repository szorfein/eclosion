#!/bin/sh

########################################################
# Program Vars

ECLODIR=$(pwd)
ECLODIR_STATIC=$ECLODIR/static
WORKDIR=/tmp/eclosion
ROOT=/mnt/root
LOG=/tmp/eclosion.log
LUKS=false
QUIET=true

########################################################
# Cmdline options

usage() {
  echo "-k, --kernel    Kernel version to use [Required]"
  echo "-l, --luks    Add cryptsetup to the image"
  echo "-h, --help    Print this fabulous help"
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

if [ ! -d /lib/modules/$KERNEL ] ; then
  echo "Kernel version $KERNEL no found"
  exit 1
fi

########################################################
# Install $WORKDIR

[[ -d $WORKDIR ]] && rm -rf $WORKDIR/*

[[ ! -d $WORKDIR ]] && mkdir $WORKDIR
[[ ! -d $ECLODIR_STATIC ]] && mkdir -p $ECLODIR_STATIC
echo >$LOG && echo "[+] Build saved to $LOG"

cd $WORKDIR

########################################################
# Base

mkdir -p bin dev etc lib64 mnt/root proc root sbin sys run usr/lib64

# If use lib64
if [[ -s /lib ]] ; then
  [[ ! -s lib ]] && ln -s lib64 lib
  [[ ! -s usr/lib ]] && cd usr; ln -s lib64 lib; cd ..
else
  mkdir lib
  mkdir usr/lib
fi

# Device nodes
cp -a /dev/{null,console,tty,tty0,tty1,zero} dev/

########################################################
# ZFS

bins="blkid zfs zpool mount.zfs zdb fsck.zfs"
modules="zlib_deflate spl zavl znvpair zcommon zunicode icp zfs"

########################################################
# Functions

doBin() {
  local lib bin link
  bin=$(which $1 2>/dev/null)
  [[ $? -ne 0 ]] && bin=$1
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
}

doMod() {
  local m mod=$1 modules lib_dir=/lib/modules/$KERNEL

  for mod; do
    modules="$(sed -nre "s/(${mod}(|[_-]).*$)/\1/p" ${lib_dir}/modules.dep)"
    if [ -n "${modules}" ]; then
      for m in ${modules}; do
        m="${m%:}"
        echo "[+] Copying module $m ..." >>$LOG
        mkdir -p .${lib_dir}/${m%/*} && cp -ar ${lib_dir}/${m} .${lib_dir}/${m}
      done
    else
      echo "[-] ${mod} kernel module not found"
    fi
  done
}

########################################################
# Install hooks

. $ECLODIR/hooks/busybox
. $ECLODIR/hooks/udev

DEVTMPFS=$(grep devtmpfs /proc/filesystems)
if [ -z "$DEVTMPFS" ] ; then
  . $ECLODIR/hooks/mdev
fi

########################################################
# Install cryptsetup

#modules+=" vfat nls_cp437 nls_iso8859-1 ext4"

########################################################
# libgcc_s.so.1 required by zfs

search_lib=$(find /usr/lib* -type f -name libgcc_s.so.1)
if [[ -n $search_lib ]] ; then
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

cp -a /lib/modules/$KERNEL/modules.dep ./lib/modules/$KERNEL/

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

########################################################
# Build the init

cat > init << EOF
#!/bin/sh

# TODO: Later from /proc/cmdline
INIT=/lib/systemd/systemd
ROOT=$ROOT
MODULES="$modules"
UDEVD=$UDEVD
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

rescueShell() {
  echo "\$1. Dropping you to a shell."
  /bin/sh -l
}

# Disable kernel log
echo 0 > /proc/sys/kernel/printk
clear

#######################################################
# Modules

# Load modules
if [ -n "\$MODULES" ]; then
  for m in \$MODULES ; do
    modprobe -q \$m
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
# Kernel args

for x in \$(cat /proc/cmdline) ; do
  case \$x in
    root=ZFS=*)
      BOOT=\$x
    ;;
  esac
done

# Seach a line like root=ZFS=zfsforninja/ROOT/gentoo
if [ -z \$BOOT ] ; then
  rescueShell "No pool defined has kernel cmdline"
else
  # if root=ZFS=zfsforninja/ROOT/gentoo, become
  #         zfsforninja/ROOT/gentoo
  BOOTFS=\${BOOT##*=}
  RPOOL=\${BOOTFS%%/*}
fi

#######################################################
# Import POOL and dataset

. /lib/eclosion/init-top/zfs
. /lib/eclosion/init-bottom/zfs

#######################################################
# Cleanup and switch

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

# Create the initramfs
if [ $QUIET == true ] ; then
  find . -print0 | cpio --null -ov --format=newc 2>>$LOG | gzip -9 > ../eclosion-initramfs.img
  echo -e "\nImage size $(tail -n 1 $LOG)"
else
  find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../eclosion-initramfs.img
fi

cd ..
echo "[+] initramfs created at $(pwd)/eclosion-initramfs.img"

exit 0
