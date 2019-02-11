#!/bin/sh

ECLODIR=$(pwd)
ECLODIR_STATIC=$ECLODIR/static
WORKDIR=/tmp/eclosion
ZPOOL_NAME=zfsforninja
ROOT=/mnt/root
ZPOOL_IMPORT_PATH=/dev/disk/by-id

# TODO get kv LUKS from cmdline
kv=4.14.83-gentoo
LUKS="no"

[[ ! -d $WORKDIR ]] && mkdir $WORKDIR
[[ ! -d $ECLODIR_STATIC ]] && mkdir -p $ECLODIR_STATIC
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
if [ ! -x $ECLODIR_STATIC/busybox ] ; then
  echo "[+] Install busybox"
  PKG=sys-apps/busybox
  BUSYBOX_EBUILD=$(ls /usr/portage/$PKG | head -n 1)
  USE="-pam static" ebuild /usr/portage/$PKG/$BUSYBOX_EBUILD clean unpack compile
  (cp /var/tmp/portage/${PKG%/*}/${BUSYBOX_EBUILD%.*}/work/${BUSYBOX_EBUILD%.*}/busybox $ECLODIR_STATIC/busybox)
  ebuild /usr/portage/$PKG/$BUSYBOX_EBUILD clean
elif ldd $ECLODIR_STATIC/busybox >/dev/null ; then
  echo "[-] Busybox is not static"
  exit 1
else
  echo "[+] Busybox found"
fi

cp -a $ECLODIR_STATIC/busybox $BUSYBOX_BIN
BUSY_BIN=$(type -p $BUSYBOX_BIN)
BUSY_APPS=/tmp/busybox-apps
$BUSY_BIN --list-full > $BUSY_APPS

# To avoid busybox create a symbolic link of busybox
mv bin/busybox .

for bin in $(grep -e '^bin/[a-z]' $BUSY_APPS) ; do
  ln -s busybox $bin 
done
for sbin in $(grep -e '^sbin/[a-z]' $BUSY_APPS) ; do
  ln -s ../bin/busybox $sbin
done

# Replace few link by program
rm bin/busybox && mv busybox bin/
rm sbin/blkid

#######################################################
# ZFS

# ZFS bins
bins="blkid zfs zpool mount.zfs zdb fsck.zfs"
# from /usr/share/initramfs-tools/hooks/zfs
modules="zlib_deflate spl savl zcommon znvpair zunicode zfs icp"

doBin() {
  local lib bin link
  bin=$(which $1 2>/dev/null)
  [[ $? -ne 0 ]] && bin=$1
  for lib in $(lddtree -l $bin 2>/dev/null | sort -u) ; do
    echo "[+] Copying lib $lib to .$lib ..."
    if [ -h $lib ] ; then
      link=$(readlink $lib)
      echo "Found a link $lib == ${lib%/*}/$link"
      cp -a $lib .$lib
      cp -a ${lib%/*}/$link .${lib%/*}/$link
    elif [ -x $lib ] ; then
      echo "Found binary $lib"
      cp -a $lib .$lib
    fi
  done
}

doMod() {
  # TODO get kv from cmdline
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
search_lib=$(find /usr/lib* -type f | grep libgcc_s.so.1 | head -n 1)
if [[ -n $search_lib ]] ; then
  mkdir -p .${search_lib%/*} && doBin $search_lib
  echo "mv .${search_lib} .lib64/ && rm -rf .${search_lib%/*}"
else
  echo "[-] libgcc_s.so.1 no found on the system..."
  exit 1
fi

# Add kernel modules
cp /lib/modules/$kv/modules.{builtin,order} ./lib/modules/$kv
depmod -b . $kv

# Create the init
cat > init << EOF
#!/bin/sh

# TODO: Later from /proc/cmdline
INIT=/lib/systemd/systemd
ROOT=$ROOT
MODULES="zfs"
ZPOOL_NAME=$ZPOOL_NAME
export ZPOOL_IMPORT_PATH=$ZPOOL_IMPORT_PATH
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

rescueShell() {
  echo "Something went wrong. Dropping you to a shell."
  exec /bin/sh -lim
}

# Disable kernel log
echo 0 > /proc/sys/kernel/printk
clear

mkdir -p dev/pts proc run sys $ROOT

# mount for mdev 
# https://git.busybox.net/busybox/plain/docs/mdev.txt
mount -t proc proc /proc
mount -t sysfs sysfs /sys

if grep -q devtmpfs /proc/filesystems; then
  mount -t devtmpfs devtmpfs /dev
else
  mount -t tmpfs -o exec,mode=755 tmpfs /dev
fi

# Add mdev (for use disk by UUID,LABEL, etc...)
echo >/dev/mdev.seq
[ -x /sbin/mdev ] && MDEV=/sbin/mdev || MDEV="/bin/busybox mdev"
echo $MDEV > /proc/sys/kernel/hotplug
mdev -s

mount -t tmpfs -o mode=755,size=1% tmpfs /run

# zpool import refuse to import without a valid mtab
# https://github.com/zfsonlinux/pkg-zfs/blob/snapshot/debian/wheezy/0.6.3-35-4c7b7e-wheezy/scripts/zfs-initramfs/scripts/zfs
[ ! -f /proc/mounts ] && mount proc /proc
[ ! -f /etc/mtab ] && cat /proc/mounts > /etc/mtab

# Load modules
for m in $MODULES ; do
  echo "[*] Loading $m"
  modprobe $m
done

echo $$ >/run/${0##*/}.pid
# modprobe zfs

# decrypt

# mount
zpool import -R $ROOT $ZPOOL_NAME
if [ $? -eq 0 ] ; then
  echo "[+] $ZPOOL_NAME has been imported at $ROOT"
else
  rescueShell
fi

zfs mount -a

rm /run/${0##*/}.pid

# cleanup
umount /proc
umount /sys
umount /dev

# switch
exec switch_root /mnt/root ${INIT}

# If the switch has fail
rescueShell
EOF

chmod u+x init

# Create the initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../eclosion-initramfs.img

cd ..
echo "[+] initramfs created at $(pwd)/eclosion-initramfs.img"
#rm -rf $WORKDIR

exit 0
