#!/bin/bash

# Sources
# https://gist.github.com/Th3Whit3Wolf/2f24b29183be7f8e9c0b05115aefb693
# https://github.com/krushndayshmookh/krushn-arch
echo "-------------------"
echo "mrkvn's Arch Config"
echo "-------------------"
echo ""

# export some variables
echo "Computer Setup ----------------------"
read -p 'Username: ' username
export USER=$username
read -p 'Hostname: ' hostname
export HOST=$hostname
read -p 'Timezone (e.g. Europe/London): ' timezone
export TZ=$timezone

# root password
echo "Root Password ---"
passwd

# locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# timezone
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime  && \
hwclock --systohc

# hostname
echo $HOST > /etc/hostname

# user
echo "User Password ---"
useradd -mg users -G wheel $USER && \
passwd $USER
echo "$USER ALL=(ALL) ALL" >> /etc/sudoers && \
echo "Defaults timestamp_timeout=0" >> /etc/sudoers

# hosts
cat << EOF >> /etc/hosts
# <ip-address>	<hostname.domain.org>	<hostname>
127.0.0.1	localhost
::1		localhost
127.0.1.1	$HOST.localdomain	$HOST
EOF

# Network Manager iwd backend
cat << EOF >> /etc/NetworkManager/conf.d/nm.conf
[device]
wifi.backend=iwd
EOF

# Preventing snapshot slowdowns
echo 'PRUNENAMES = ".snapshots"' >> /etc/updatedb.conf

# fix the mkinitcpio.conf to contain what we actually need
sed -i 's/BINARIES=()/BINARIES=("\/usr\/bin\/btrfs")/' /etc/mkinitcpio.conf && \
sed -i 's/#COMPRESSION="lz4"/COMPRESSION="lz4"/' /etc/mkinitcpio.conf && \
sed -i 's/#COMPRESSION_OPTIONS=()/COMPRESSION_OPTIONS=(-9)/' /etc/mkinitcpio.conf && \
sed -i 's/^HOOKS.*/HOOKS=(base systemd autodetect modconf block sd-encrypt filesystems keyboard fsck)/' /etc/mkinitcpio.conf

mkinitcpio -p linux &&

# Autosign Kernel
mkdir /etc/pacman.d/hooks && cat << EOF > /etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-hardened
Target = linux-zen
Target = linux-xanmod
Target = linux-xanmod-cacule
Target = linux-xanmod-git
Target = linux-xanmod-lts
Target = linux-xanmod-rt
Target = linux-xanmod-anbox

[Action]
Description = Signing kernel with Machine Owner Key for Secure Boot
When = PostTransaction
Exec = /usr/bin/fd vmlinuz /boot -x /usr/bin/sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output {} {}
Depends = sbsigntools
Depends = fd
EOF

# Update rEFInd ESP on update
cat << EOF > /etc/pacman.d/hooks/refind.hook
[Trigger]
Operation=Upgrade
Type=Package
Target=refind

[Action]
Description = Updating rEFInd on ESP
When=PostTransaction
Exec=/usr/bin/refind-install --shim /usr/share/shim-signed/shimx64.efi --localkeys
EOF

# Create zram
cat << EOF > /etc/systemd/swap.conf
#  This file is part of systemd-swap.
#
# Entries in this file show the systemd-swap defaults as
# specified in /usr/share/systemd-swap/swap-default.conf
# You can change settings by editing this file.
# Defaults can be restored by simply deleting this file.
#
# See swap.conf(5) and /usr/share/systemd-swap/swap-default.conf for details.
zram_enabled=1
zswap_enabled=0
swapfc_enabled=0
zram_size=\$(( RAM_SIZE / 4 ))
EOF

# Automatic logout
cat << EOF > /etc/profile.d/shell-timeout.sh
TMOUT="\$(( 60*30 ))";
[ -z "\$DISPLAY" ] && export TMOUT;
case \$( /usr/bin/tty ) in
	/dev/tty[0-9]*) export TMOUT;;
esac
EOF

# Prepare gnome-keyring-daemon
cat <<EOF > /etc/pam.d/login
#%PAM-1.0

auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login
auth       optional     pam_gnome_keyring.so
account    include      system-local-login
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start
EOF

cat <<EOF > /etc/pam.d/passwd
#%PAM-1.0

#password	required	pam_cracklib.so difok=2 minlen=8 dcredit=2 ocredit=2 retry=3
#password	required	pam_unix.so sha512 shadow use_authtok
password	required	pam_unix.so sha512 shadow nullok
password	optional	pam_gnome_keyring.so
EOF

# Setup the user & configure the bootloader
su $USER -Pc "cd &&\
git clone https://aur.archlinux.org/yay.git && \
cd yay && \
makepkg -si && \
cd && \
rm -rf ~/yay && \

# Sign bootloader & kernel for Secure Boot

yay --noremovemake --nodiffmenu -S shim-signed && \
sudo refind-install --shim /usr/share/shim-signed/shimx64.efi --localkeys && \
sudo sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output /boot/vmlinuz-linux /boot/vmlinuz-linux && \

# Configure rEFInd
sed -i 's/#resolution 3/resolution 1920 1080/' /boot/EFI/refind/refind.conf && \
sed -i 's/#use_graphics_for osx,linux/use_graphics_for linux/' /boot/EFI/refind/refind.conf && \
sed -i 's/#scanfor internal,external,optical,manual/scanfor manual,external/' /boot/EFI/refind/refind.conf

# Add rEFInd Manual Stanza
read -p 'Reenter the same drive you entered earlier. e.g. /dev/sda: ' drive

cat << EOF >> /boot/EFI/refind/refind.conf

menuentry "Arch Linux" {
    icon     /EFI/refind/icons/os_arch.png
    volume   "Arch Linux"
    loader   /vmlinuz-linux
    initrd   /initramfs-linux.img
    options  "rd.luks.name=$(blkid $drive"2" | cut -d " " -f2 | cut -d '=' -f2 | sed 's/\"//g')=crypt root=/dev/mapper/crypt rootflags=subvol=@ resume=/dev/mapper/crypt rw quiet add_efi_memmap initrd=\intel-ucode.img"
    submenuentry "Boot - fallback" {
        initrd /initramfs-linux-fallback.img
    }
    submenuentry "Boot - terminal" {
        add_options "systemd.unit=multi-user.target"
    }
}
EOF

# Zsh hooks
cat << EOF > /etc/pacman.d/hooks/zsh.hook
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/bin/*
[Action]
Depends = zsh
When = PostTransaction
Exec = /usr/bin/install -Dm644 /dev/null /var/cache/zsh/pacman
EOF


# Make scripts to start service, firewall, & setup snapshots
cat << EOF >> /home/$USER/init.sh
#!bin/bash

sudo umount /.snapshots
sudo rm -r /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir /.snapshots
sudo mount -a
sudo chmod 750 -R /.snapshots
sudo chmod a+rx /.snapshots
sudo chown :wheel /.snapshots
sudo snapper -c root create --description "Fresh Install"
sudo sed -i 's/^TIMELINE_MIN_AGE.*/TIMELINE_MIN_AGE="1800"/' /etc/snapper/configs/root && \
sudo sed -i 's/^TIMELINE_LIMIT_HOURLY.*/TIMELINE_LIMIT_HOURLY="0"/' /etc/snapper/configs/root && \
sudo sed -i 's/^TIMELINE_LIMIT_DAILY.*/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root && \
sudo sed -i 's/^TIMELINE_LIMIT_WEEKLY.*/TIMELINE_LIMIT_WEEKLY="0"/' /etc/snapper/configs/root && \
sudo sed -i 's/^TIMELINE_LIMIT_MONTHLY.*/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root && \
sudo sed -i 's/^TIMELINE_LIMIT_YEARLY.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
sudo systemctl enable --now NetworkManager NetworkManager-wait-online \
    NetworkManager-dispatcher sshd systemd-swap
rm /home/$USER/init.sh
EOF
chown $USER /home/$USER/init.sh

echo "========================================================================"
echo "Installation Done. If you want to do anything else, you may now do so..."
echo "IMPORTANT: After reboot, run init.sh located in your home directory."
echo "If you want to reboot now, run the following commands:"
echo "# exit"
echo "# umount -R /mnt"
echo "# reboot"
