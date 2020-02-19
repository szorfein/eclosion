# Config file
`eclosion` come with a tool `eclosion-gen-conf`. After an install, you have to launch the script.

    $ eclosion-gen-conf

The script try to detect few things automatically. 

```txt
Check your zpool name...        zerus/ROOT/gentoo
Check your kernel...            4.19.82-gentoo
Detect partitions...            /dev/sdc1
Detect init...                  /lib/systemd/systemd
Check the cmdline...            init=/lib/systemd/systemd root=ZFS=zerus/ROOT/gentoo ${CUSTOM_CMDLINE}
Check eclosion args...          --kernel 4.19.82-gentoo ${CUSTOM_ECLOSION_ARGS}
```
In the file generated at `/etc/eclosion/eclosion.conf`, you have few field to customize yourself like:

```sh
ZPOOL=zerus/ROOT/gentoo
CUSTOM_CMDLINE="quiet"
CUSTOM_ECLOSION_ARGS="--gpg --keymap fr"
```
All other lines will be erase (update) each time the script is called (even if the script ask before anyways), so don't edit them, instead, please, post an issue if something is incorrect [here](https://github.com/szorfein/eclosion/issues).

## Tips
In the config file, the variable `KERNEL=` follow the index on `eselect kernel list`, so if you want change the kernel, just execute `eselect kernel set X`. `eclosion_gen_conf` will change the variable automatically.   
