# eclosion
A minimalist and powerfull initramfs for ZFS and gentoo. 

## Features

+ Cryptsetup (external header, offset, loop, and more...)
+ GPG 2 with gpg-agent
+ Full disk encryption (boot + main system)
+ Custom hook
+ External key into the initramfs
+ mdev, devtmpfs and udev
+ No complex doc
+ Simple cmdline (only 2 args required) with no ugly symbols `,+:;({.*_-})`

## Install

    # git clone https://github.com/szorfein/eclosion
    # cd eclosion
    # make install

## Usage
For a hypothetical zpool named `zfsforninja`:

    $ zpool status | grep pool
      pool: zfsforninja

And a kernel version `4.14.80-gentoo`:

    $ ls /lib/modules
      4.14.80-gentoo

### Normal root ZFS

+ Kernel cmdline : ` root=ZFS=zfsforninja/ROOT/gentoo init=/lib/systemd/systemd `
+ Build cmd : ` eclosion.sh --kernel 4.14.80-gentoo `

### Other examples
Full disk encryption with custom hook, external header and gpg key: [doc](https://github.com/szorfein/eclosion/blob/master/docs/custom-hook.md).

## Thanks
+ Gentoo docs: [gentoo-custom-initramfs](https://wiki.gentoo.org/wiki/Custom_Initramfs), [gentoo-custom-initramfs-examples](https://wiki.gentoo.org/wiki/Custom_Initramfs/Examples)
+ LFS docs [LFS](http://www.linuxfromscratch.org/blfs/view/svn/postlfs/initramfs.html)
+ Other initramfs: [mkinitramfs-ll](https://github.com/tokiclover/mkinitramfs-ll), [bliss-initramfs](https://github.com/fearedbliss/bliss-initramfs), [better-initramfs](https://github.com/slashbeast/better-initramfs)
+ [mdev-like-a-boss](https://github.com/slashbeast/mdev-like-a-boss)
+ [zfsonlinux](https://github.com/zfsonlinux/zfs/tree/master/contrib/initramfs)
+ [salsa.debian](https://salsa.debian.org/systemd-team/systemd/tree/master/debian/extra/initramfs-tools)
+ [genkernel-next](https://github.com/Sabayon/genkernel-next)

### Support
Any support will be greatly appreciated, star the repo, coffee, donation... thanks you !   
<a href="https://www.patreon.com/szorfein"><img src="https://img.shields.io/badge/don-patreon-ab69f4"></a>  
