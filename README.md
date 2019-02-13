# eclosion
An initramfs for ZFS and gentoo. 

## Status
+ Can boot on a normal zfs system (without encryption) for now...
Still under building | testing :)

## Usage

You do not need to define a pool with `bootfs`.

### 1. Normal root ZFS

    $ zpool status | grep pool
      pool: zfsforninja

+ Kernel cmdline : ` root=ZFS=zfsforninja/ROOT/gentoo `
+ Build cmd : ` ./eclosion.sh --kernel 4.14.80-gentoo `

## Thanks
+ https://wiki.gentoo.org/wiki/Custom_Initramfs
+ https://github.com/tokiclover/mkinitramfs-ll
+ http://www.linuxfromscratch.org/blfs/view/svn/postlfs/initramfs.html
+ https://wiki.gentoo.org/wiki/Custom_Initramfs/Examples
+ https://github.com/slashbeast/mdev-like-a-boss
+ https://github.com/slashbeast/better-initramfs
+ https://github.com/zfsonlinux/zfs/tree/master/contrib/initramfs
+ https://salsa.debian.org/systemd-team/systemd/tree/master/debian/extra/initramfs-tools
