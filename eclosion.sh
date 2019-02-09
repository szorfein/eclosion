#!/bin/sh

WORKDIR=/usr/share/eclosion
ZPOOL_NAME="zfsforninja"
ROOT=/mnt/root
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
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
module="zfs zavl zunicode icp zcommon znvpair spl"

dobin() {
  local lib bin
  bin=$(which $1)
  cp -a $bin .$bin
  for lib in $(ldd $bin | sed -nre 's,.* (/.*lib.*/.*.so.*) .*,\1,p' -e 's,.*(/lib.*/ld.*.so.*) .*,\1,p') ; do
    echo "[+] Copying lib $lib to .$lib ..."
    cp -a $lib .$lib
  done
}

for bin in $bins ; do
  dobin $bin
done

# TODO: copy binary and modules
# TODO: install keymap for future use of gpg 
# TODO: copy GCC deps libgcc_s.so.1

# Create the init
cat > init << EOF
#!/bin/sh

# TODO: Later from /proc/cmdline
INIT=/lib/systemd/systemd
ZPOOL_NAME=$ZPOOL_NAME
export ZPOOL_IMPORT_PATH=$ZPOOL_IMPORT_PATH
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# mount 
mount -t proc none /proc
mount -t sysfs none /sys
# Disable kernel log
echo 0 > /proc/sys/kernel/printk
clear

# Create device nodes
mknod /dev/null c 1 3
mknod /dev/tty c 5 0
mdev -s

# load module
modprobe zfs

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
#find . -print0 | cpio --null -ov --format=newc | gzip -9 > /boot/eclosion-initramfs.img

exit 0
