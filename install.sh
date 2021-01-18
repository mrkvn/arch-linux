#!/bin/bash

# Sources
# https://gist.github.com/Th3Whit3Wolf/2f24b29183be7f8e9c0b05115aefb693
# https://github.com/krushndayshmookh/krushn-arch

echo "-------------------"
echo "mrkvn's Arch Config"
echo "-------------------"
echo ""

# Set up network connection
read -p 'Are you connected to internet? [y/N]: ' neton
if ! [ $neton = 'y' ] && ! [ $neton = 'Y' ]
then
    echo "Connect to internet to continue..."
    exit
fi

# Set time
timedatectl set-ntp true

# Set country for pacman
read -p 'Country to be used for mirrorlist. e.g. North Macedonia: ' country
reflector -c "$country" -a 12 --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syyy

# Filesystem mount warning
echo "---------------------------------------------------------------------------------"
lsblk
echo "---------------------------------------------------------------------------------"
read -p 'From the above, which drive to install arch linux to? e.g. /dev/sda: ' drive

echo "This script will create and format the partitions as follows:"
echo $drive"1 - 512Mib will be mounted as /boot"
echo $drive"2 - rest of space will be mounted as @ - BTRFS"
read -p 'Continue? [y/N]: ' fsok
if [ $fsok = 'n' ] && [ $fsok = 'N' ]
then
    echo "Edit the script to continue..."
    exit
fi

# Partition
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk $drive
g # new gpt disk 
n # new partition
  # default partition 1
  # default - first sector
+512M # 512 MB boot parttion
Yes # confirm to remove signature
t # Filesystem type
1 # EFI System Type
n # new partition
  # default partition 2
  # default - first sector
  # default - last sector
Yes # confirm to remove signature
p # print partition table
w # write and quit
EOF


# encrypt partition
echo "Encryption Password ---"
cryptsetup luksFormat --perf-no_read_workqueue --perf-no_write_workqueue --type luks2 --cipher aes-xts-plain64 --key-size 512 --iter-time 2000 --pbkdf argon2id --hash sha3-512 $drive"2"
echo "Open Encrypted Drive ---"
cryptsetup --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent open $drive"2" crypt


# Format the partitions
mkfs.fat -F32 $drive"1"
mkfs.btrfs /dev/mapper/crypt

# Create/Mount Subvolumes (btrfs)
mount /dev/mapper/crypt /mnt
btrfs sub create /mnt/@ && \
btrfs sub create /mnt/@home && \
btrfs sub create /mnt/@var_abs && \
btrfs sub create /mnt/@var_tmp && \
btrfs sub create /mnt/@srv && \
btrfs sub create /mnt/@snapshots && \
btrfs sub create /mnt/@var_log && \
btrfs sub create /mnt/@var_cache
umount /mnt
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@ /dev/mapper/crypt /mnt
mkdir -p /mnt/{boot,home,var/cache,var/log,.snapshots,.swapvol,btrfs,var/tmp,var/abs,srv}
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@home /dev/mapper/crypt /mnt/home  && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@var_abs /dev/mapper/crypt /mnt/var/abs && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@var_tmp /dev/mapper/crypt /mnt/var/tmp && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@srv /dev/mapper/crypt /mnt/srv && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@var_log /dev/mapper/crypt /mnt/var/log && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@var_cache /dev/mapper/crypt /mnt/var/cache && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@snapshots /dev/mapper/crypt /mnt/.snapshots && \

# Disable copy-on-write (CoW) on database/VMs
mkdir -p /mnt/var/lib/{mysql,postgres,machines,} && \
chattr +C /mnt/var/lib/{mysql,postgres,machines}

# Mount EFI
mount $drive"1" /mnt/boot

# base install
pacstrap /mnt base base-devel linux linux-firmware intel-ucode efibootmgr networkmanager network-manager-applet dialog mtools dosfstools linux-headers \
bluez bluez-utils cups alsa-utils pulseaudio pulseaudio-bluetooth git reflector iwd sbsigntools fd zsh nautilus libsecret gnome-keyring go btrfs-progs \
openssh refind unrar lrzip unzip zip p7zip lzip lzop ncompress man systemd-swap wget pigz pbzip2 zstd snapper

# fstab
genfstab -U /mnt > /mnt/etc/fstab

# Copy post-install system configuration script to new /root
cp -rfv post-chroot.sh /mnt/root
chmod a+x /mnt/root/post-chroot.sh

# chroot
echo "========================================================================================================="
echo "After pressing ENTER, run ./root/post-chroot.sh. Press ENTER to proceed..."
read tmpvar
arch-chroot /mnt /bin/bash

