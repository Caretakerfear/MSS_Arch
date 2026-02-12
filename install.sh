#!/bin/bash

# --- Initialization ---
set -e
msg() { echo -e "\033[0;32m[EliOS Installer]\033[0m $1"; }
err() { echo -e "\033[0;31m[Error]\033[0m $1"; }

# --- Input Data ---
read -p "Enter Target Drive (e.g., /dev/nvme0n1 or /dev/sda): " DRIVE
read -p "Enter Username: " USERNAME
read -s -p "Enter User Password: " USERPASS
echo

if [ ! -b "$DRIVE" ]; then
	err "Disk $DRIVE not found or not able os block device."
	exit 1
fi

echo -e "\033[0;33mWarning!\033[0m It create new tom in free space at $DRIVE."
read -p "Continue? (y/N): " CONFIRM
[[ "$CONFIRM" != "y" ]] && exit 1

# --- 1. Smart Partitioning (Non-destructive) ---
msg "Finding free space on $DRIVE..."
if [[ ! -d /sys/firmware/efi ]]; then
	err "System not booted in UEFI mode."
	exit 1
fi

sgdisk --new=0:0:+512M --typecode=0:ef00 --change-name=0:ELIOS_BOOT "$DRIVE"
sgdisk --new=0:0:0 --typecode=0:8300 --change-name=0:ELIOS_ROOT "$DRIVE"

partprobe "$DRIVE"
sleep 2

# Find partition numbers dynamically
BOOT_PART=$(lsblk -pnlo NAME,PARTLABEL "$DRIVE" | grep "ELIOS_BOOT" | awk '{print $1}')
ROOT_PART=$(lsblk -pnlo NAME,PARTLABEL "$DRIVE" | grep "ELIOS_ROOT" | awk '{print $1}')

if [[ -z "$BOOT_PART" || -z "$ROOT_PART" ]]; then
    err "Failed to identify the created partitions."
    exit 1
fi

# Set partition paths
PART_PRE=""
[[ "$DRIVE" == *"nvme"* ]] && PART_PRE="p"

# --- 2. Formatting (Only ELIOS partitions!) ---
msg "Formatting EliOS partitions ($BOOT_PART, $ROOT_PART)..."
mkfs.fat -F32 "$BOOT_PART"
mkfs.ext4 -F "$ROOT_PART"

# --- 3. Mounting ---
msg "Mounting file system..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

# --- 4. Base Installation ---
msg "Processor Microcode Definition..."
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
UCODE="linux-firmware"
[[ "$CPU_VENDOR" == "GenuineIntel" ]] && UCODE="intel-ucode linux-firmware"
[[ "$CPU_VENDOR" == "AuthenticAMD" ]] && UCODE="amd-ucode linux-firmware"

msg "Installing base system packages..."
sed -i 's/^#ParallelDownloads/ParallelDownloads = 10/' /etc/pacman.conf

pacstrap /mnt base linux-lts linux-firmware networkmanager grub efibootmgr pipewire wireplumber base-devel sudo git $UCODE

# --- 5. Chroot Configuration ---
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "elios-machine" > /etc/hostname

useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
echo "root:$USERPASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# GRUB Installation
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=EliOS --recheck
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
EOF

msg "EliOS base installed into free space successfully!"
umount -R /mnt