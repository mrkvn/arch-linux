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
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | gdisk $drive
n # new partition
1 # partition number 1
  # default - start at beginning of disk
+512M # 512 MB boot parttion
ef00 # Partition Type - Hex Code or GUID
n # new partition
2 # partion number 2
  # default, start immediately after preceding partition
  # default, extend partition to end of disk
  # default, 8300. Partition Type - Hex Code or GUID
p # print the in-memory partition table
w # write the partition table
Y # confirm
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
btrfs sub create /mnt/@abs && \
btrfs sub create /mnt/@tmp && \
btrfs sub create /mnt/@srv && \
btrfs sub create /mnt/@snapshots && \
btrfs sub create /mnt/@btrfs && \
btrfs sub create /mnt/@log && \
btrfs sub create /mnt/@cache
umount /mnt
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@ /dev/mapper/crypt /mnt
mkdir -p /mnt/{boot,home,var/cache,var/log,.snapshots,.swapvol,btrfs,var/tmp,var/abs,srv}
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@home /dev/mapper/crypt /mnt/home  && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@abs /dev/mapper/crypt /mnt/var/abs && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@tmp /dev/mapper/crypt /mnt/var/tmp && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@srv /dev/mapper/crypt /mnt/srv && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@log /dev/mapper/crypt /mnt/var/cache && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@cache /dev/mapper/crypt /mnt/var/log && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@snapshots /dev/mapper/crypt /mnt/.snapshots && \
mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvolid=5 /dev/mapper/crypt /mnt/btrfs

# Disable copy-on-write (CoW) on database/VMs
mkdir -p /mnt/var/lib/{mysql,postgres,machines,} && \
chattr +C /mnt/var/lib/{mysql,postgres,machines}

# Mount EFI
mount $drive"1" /mnt/boot

# base install
pacstrap /mnt base base-devel linux linux-firmware intel-ucode grub efibootmgr os-prober ntfs-3g networkmanager network-manager-applet wireless_tools \
    dialog mtools dosfstools linux-headers bluez bluez-utils cups alsa-utils pulseaudio pulseaudio-bluetooth git reflector \
    xdg-utils xdg-user-dirs xorg nvidia nvidia-utils xfce4 xfce4-goodies tlp iwd sbsigntools fd zsh sshguard firewalld nautilus libsecret gnome-keyring go btrfs-progs \
    ripgrep bat docker docker-compose libvirt qemu openssh refind rustup rust-analyzer powertop unrar lrzip unzip zip p7zip lzip lzop ncompress ttf-roboto ttf-roboto-mono \
    ttf-dejavu ttf-liberation ttf-fira-code ttf-hanazono ttf-fira-mono ttf-opensans ttf-hack noto-fonts noto-fonts-emoji ttf-font-awesome ttf-droid \
    adobe-source-code-pro-fonts adobe-source-han-sans-otc-fonts adobe-source-han-serif-otc-fonts man yarn nodejs systemd-swap wget zsh-completions \
    gvim htop xclip python2-pip python-pip gnome-calculator sxhkd maim psensor stow tmux git-lfs unclutter xcape pigz pbzip2 zstd neovim flatpak dbus-broker haveged \
    irqbalance snapper apparmor

# fstab
genfstab -U /mnt > /mnt/etc/fstab

# Copy post-install system configuration script to new /root
cp -rfv post-chroot.sh /mnt/root
chmod a+x /mnt/root/post-chroot.sh

# chroot
echo "After chrooting into newly installed OS, please run the post-chroot.sh by executing ./post-chroot.sh"
echo "Press any key to chroot..."
read tmpvar
arch-chroot /mnt /bin/bash

# Finish
echo "If post-chroot.sh is successful, you will now have a fully working bootable Arch Linux system installed."
echo "The only thing left is to reboot into the new system."
echo "IMPORTANT: After reboot, run the init.sh script located in your home directory and reboot again."
echo "Press any key to reboot or Ctrl+C to cancel..."
read tmpvar
reboot
