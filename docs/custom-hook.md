# Custom Hook
Custom hook serve to boot any system but it need to be written in a bash script.  
This example is based on my wiki found here: https://github.com/szorfein/Gentoo-ZFS/wiki   
To create a custom hook, start create a little script:

    $ touch custom

For help, you can use variables from the `/etc/eclosion/eclosion.conf` and few functions are available too like `rescueShell`, `gpg_with_luks`...

```sh
# Clear previous message
clear 

# Declare few variables
USB_MOUNTPOINT=/mnt/usb
PATH_KEY=/root/key.gpg # the normal path if you use eclosion with --external-key
ZPOOL_DEV=/dev/disk/by-id/ata-STXX-2GH_WXXN
KEY_OFFSET=2048
KEY_SIZE=8192

# create the directory your need
mkdir -p $USB_MOUNTPOINT

# Decrypt the boot partition (cryptboot) with the function gpg_with_luks or manually
# $CRYPTBOOT variable is available in the config file /etc/eclosion/eclosion.conf
gpg_with_luks $PATH_KEY $CRYPTBOOT cryptboot
#gpg -qd $PATH_KEY | cryptsetup -v --key-file=- open --type luks $CRYPTBOOT cryptboot

# Check if the block device /dev/mapper/cryptboot exist
[ -b /dev/mapper/cryptboot ] || rescueShell "Fail to open cryptboot, open him and exit"

# Mount the encrypted boot partition
mount -t ext4 /dev/mapper/cryptboot $USB_MOUNTPOINT

# decrypt an other key in cryptboot
gpg_with_luks $PATH_KEY $USB_MOUNTPOINT/key.img lukskey
#gpg -qd $PATH_KEY | cryptsetup -v --key-file=- open --type luks $USB_MOUNTPOINT/key.img lukskey
          
# Check if the block device /dev/mapper/lukskey exist
[ -b /dev/mapper/lukskey ] || rescueShell "lukskey fail, open it and exit"

# use 'lukskey' to open the final crypted device with offset, external header, etc...
cryptsetup -v --header $USB_MOUNTPOINT/header.img --key-file=/dev/mapper/lukskey --keyfile-offset=$KEY_OFFSET --keyfile-size=$KEY_SIZE --type luks $ZPOOL_DEV zfs-enc
                
# Check if the block device /dev/mapper/zfs-enc exist
[ -b /dev/mapper/zfs-enc ] || rescueShell "Fail to decrypt zfs-enc"

# demount / close other partition/device if need
cryptsetup close lukskey
```

When you've done, place the script at `/etc/eclosion/custom`.

    $ sudo cp custom /etc/eclosion/custom

And start the initram creation with `eclosion`.

    $ sudo eclosion --kernel 4.14.80-gentoo --gpg --luks --usb --external-key /root/key.gpg --keymap fr --custom

+ `--gpg` -> add `gpg2` with agent to the image.
+ `--luks` -> add `cryptsetup`.
+ `--usb` -> add support for usb, load modules `uas`, `ehci`, `xhci`, etc... at start.
+ `--external-key /root/key.gpg` -> copy your key located at `/root/key.gpg` to the image in the `/root/` directory.  
+ `--custom` -> add the script `/etc/eclosion/custom` to the image.
