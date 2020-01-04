# Custom Hook
Custom hook serve to boot any system but it need to be written in a bash script.  
This example is based on my wiki found here: https://github.com/szorfein/Gentoo-ZFS/wiki   
To create a custom hook, start create a little script:

    $ touch custom

```sh
# Clear previous message
clear 

# Declare few variables
USB_MOUNTPOINT=/mnt/usb
PATH_KEY=/root/key.gpg # the normal path if you use eclosion with --external-key
CRYPTBOOT_DEV=/dev/disk/by-id/usb-Multiple_Card_Reader_XX-0:0-part2
ZPOOL_DEV=/dev/disk/by-id/ata-STXX-2GH_WXXN
KEY_OFFSET=2048
KEY_SIZE=8192

# create the directory your need
mkdir -p $USB_MOUNTPOINT

# decrypt the boot partition (cryptboot)
gpg -qd $PATH_KEY | cryptsetup -v --key-file=- open --type luks $CRYPTBOOT_DEV cryptboot

# check if the block device /dev/mapper/cryptboot exist
[ ! -b /dev/mapper/cryptboot ] && rescueShell "cryptboot doesn't exist"

# mount the encrypted boot partition
mount -t ext4 /dev/mapper/cryptboot $USB_MOUNTPOINT

# decrypt an other key in cryptboot
gpg -qd $PATH_KEY | cryptsetup -v --key-file=- open --type luks $USB_MOUNTPOINT/key.img lukskey 
          
[ ! -b /dev/mapper/lukskey ] && rescueShell "lukskey fail too"

# use 'lukskey' to open the final crypted device with offset, external header, etc...
cryptsetup -v --header $USB_MOUNTPOINT/header.img --key-file=/dev/mapper/lukskey --keyfile-offset=$KEY_OFFSET --keyfile-size=$KEY_SIZE --type luks $ZPOOL_DEV zfs-enc
                
[ ! -b /dev/mapper/zfs-enc ] && rescueShell "Fail to decrypt zfs-enc"

# demount / close if need
cryptsetup close lukskey
```

When you've done, place the script at `/etc/eclosion/custom`.

    $ sudo cp custom /etc/eclosion/custom

And start the initram creation with `eclosion`.

    $ sudo eclosion --kernel 4.14.80-gentoo --gpg --luks --external-key /root/key.gpg --keymap fr --custom

+ `--custom` -> add the script `/etc/eclosion/custom` to the image.
+ `--external-key /root/key.gpg` -> copy your key located at `/root/key.gpg` to the image in the `/root/` directory.  
+ `--gpg` -> add `gpg2` with agent to the image.
+ `--luks` -> add `cryptsetup`.
