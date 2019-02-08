#!/bin/sh

WORKDIR=/usr/share/eclosion
ZPOOL_NAME="zfsforninja"
ROOT=/mnt/root
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
LUKS="no"

[[ ! -d $WORKDIR ]] && mkdir $WORKDIR
cd $WORKDIR
mkdir -p bin lib dev etc mnt/root proc root sbin sys
touch etc/mdev.conf
if [[ $LUKS == "yes" ]] ; then
  mkdir -p share/gnupg
fi
cp -a /dev/{null,urandom,console,tty} .
disks=$(lsblk -l | grep -e "^s" | awk '{print $1}')
for disk in $disks ; do
  echo "cp -a /dev/$disk ."
done

# Copy binaries | static install
source /etc/portage/make.conf
if [ ! -f $WORKDIR/bin/busybox ] ; then
  PKG=sys-apps/busybox
  BUSYBOX_EBUILD=$(ls /usr/portage/$PKG | head -n 1)
  USE="-pam static" ebuild /usr/portage/$PKG/$BUSYBOX_EBUILD clean unpack compile
  (cp /var/tmp/portage/${PKG%/*}/${BUSYBOX_EBUILD%.*}/work/${BUSYBOX_EBUILD%.*}/busybox $WORKDIR/bin)
  USE="-pam static" ebuild /usr/portage/$PKG/$BUSYBOX_EBUILD clean
fi

if [ ! -f $WORKDIR/bin/gnupg ] && [[ $LUKS == "yes" ]] ; then
  PKG=app-crypt/gnupg
  GPG_EBUILD=$(ls /usr/portage/$PKG | head -n 1)
  USE="nls static" ebuild /usr/portage/$PKG/$GPG_EBUILD clean unpack compile
  (cp -a /var/tmp/portage/${PKG%/*}/${GPG_EBUILD%.*}/work/${GPG_EBUILD%.*}/g10/gpg $WORKDIR/bin)
  (cp -a /var/tmp/portage/${PKG%/*}/${GPG_EBUILD%.*}/work/${GPG_EBUILD%.*}/g10/options.skel $WORKDIR/share/gnupg/)
  ebuild /usr/portage/$PKG/$GPG_EBUILD clean
fi

# ZFS bins
zfs_bin="zfs zpool mount.zfs zdb fsck.zfs"
module="zfs zavl zunicode icp zcommon znvpair spl"

# TODO: copy binary and modules
# TODO: make symbolic link of busybox static
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
find . -print0 | cpio --null -ov --format=newc | gzip -9 > /boot/eclosion-initramfs.img

exit 0
