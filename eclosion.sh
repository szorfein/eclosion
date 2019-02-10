#!/bin/sh

WORKDIR=/tmp/eclosion
ZPOOL_NAME="zfsforninja"
ROOT=/mnt/root
ZPOOL_IMPORT_PATH="/dev/disk/by-id"

# TODO get LUKS from cmdline
LUKS="no"

[[ ! -d $WORKDIR ]] && mkdir $WORKDIR
cd $WORKDIR

# Directory structure
mkdir -p bin dev etc lib64 mnt/root proc root sbin sys
if [[ -s /lib ]] ; then
  [[ ! -s lib ]] && ln -s lib64 lib
else
  mkdir lib
fi

# Device nodes
cp -a /dev/{null,console,tty} dev/

touch etc/mdev.conf
if [[ $LUKS == "yes" ]] ; then
  mkdir -p share/gnupg
fi

# Copy binaries | static install when possible
source /etc/portage/make.conf

#######################################################
# Busybox

BUSYBOX_BIN=$WORKDIR/bin/busybox
if [ ! -x $BUSYBOX_BIN ] ; then
  echo "[+] Install busybox"
  PKG=sys-apps/busybox
  BUSYBOX_EBUILD=$(ls /usr/portage/$PKG | head -n 1)
  USE="-pam static" ebuild /usr/portage/$PKG/$BUSYBOX_EBUILD clean unpack compile
  (cp /var/tmp/portage/${PKG%/*}/${BUSYBOX_EBUILD%.*}/work/${BUSYBOX_EBUILD%.*}/busybox $BUSYBOX_BIN)
  ebuild /usr/portage/$PKG/$BUSYBOX_EBUILD clean
elif ldd $BUSYBOX_BIN >/dev/null ; then
  echo "[-] Busybox is not static"
  exit 1
else
  echo "[+] Busybox found"
fi

BUSY_BIN=$(type -p $BUSYBOX_BIN)
BUSY_APPS=/tmp/busybox-apps
$BUSY_BIN --list-full > $BUSY_APPS

mv bin/busybox . && rm -rf bin/* && rm -rf sbin/*
for bin in $(grep -e '^bin/[a-z]' $BUSY_APPS) ; do
  ln -s busybox $bin 
done
for sbin in $(grep -e '^sbin/[a-z]' $BUSY_APPS) ; do
  ln -s ../bin/busybox $sbin
done
rm bin/busybox
mv busybox bin/

#######################################################
# ZFS

# ZFS bins
bins="zfs zpool mount.zfs zdb fsck.zfs"
modules="zfs zavl zunicode icp zcommon znvpair spl"

doBin() {
  local lib bin
  bin=$(which $1)
  cp -a $bin .$bin
  for lib in $(ldd $bin | sed -nre 's,.* (/.*lib.*/.*.so.*) .*,\1,p' -e 's,.*(/lib.*/ld.*.so.*) .*,\1,p') ; do
    echo "[+] Copying lib $lib to .$lib ..."
    cp -a $lib .$lib
  done
}

doMod() {
  # TODO get kv from cmdline
  local kv=4.14.83-gentoo
  local m mod=$1 modules lib_dir=/lib/modules/${kv}

  for mod; do
    modules="$(sed -nre "s/(${mod}(|[_-]).*$)/\1/p" ${lib_dir}/modules.dep)"
    if [ -n "${modules}" ]; then
      for m in ${modules}; do
        m="${m%:}"
        echo "[+] Copying module $m ..."
        mkdir -p .${lib_dir}/${m%/*} && cp -ar ${lib_dir}/${m} .${lib_dir}/${m}
      done
    else
      echo "[-] ${mod} kernel module not found"
      exit 1
    fi
  done
}

for bin in $bins ; do
  doBin $bin
done

for mod in $modules ; do
  doMod $mod
done

# TODO: install keymap for future use of gpg 

# Handle GCC libgcc_s.so
searchLib=$(find /usr/lib* -type f | grep libgcc_s.so)
if [[ -n $searchLib ]] ; then
  for l in $searchLib ; do
    mkdir -p .${l%/*}
    cp -a ${l} .${l}
  done
else
  echo "[-] libgcc_s.so no found on the system..."
  exit 1
fi

# Create the init
cat > init << EOF
#!/bin/sh

# TODO: Later from /proc/cmdline
INIT=/lib/systemd/systemd
MODULES="$modules"
ZPOOL_NAME=$ZPOOL_NAME
export ZPOOL_IMPORT_PATH=$ZPOOL_IMPORT_PATH
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# mount 
mount -t proc none /proc
mount -t sysfs none /sys

# Disable kernel log
echo 0 > /proc/sys/kernel/printk
clear

# Add mdev (for use disk by UUID,LABEL, etc...)
# ref: https://wiki.gentoo.org/wiki/Custom_Initramfs
echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s

# Load modules
for m in $MODULES ; do
  modprobe $m
done

# decrypt

# mount
zpool import -R $ROOT $ZPOOL_NAME

# cleanup
umount /proc
umount /sys

# switch
exec switch_root $ROOT "${INIT}"
EOF

chmod u+x init

# Create the initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../eclosion-initramfs.img

echo "[+] initramfs created at $WORKDIR/../eclosion-initramfs.img"

exit 0
