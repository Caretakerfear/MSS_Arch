#!/bin/bash

# --- Initialization ---
msg() { echo -e "\033[0;32m[EliOS Installer]\033[0m $1"; }
err() { echo -e "\033[0;31m[Error]\033[0m $1"; }

# --- Input Data ---
read -p "Enter Target Drive (e.g., /dev/nvme0n1 or /dev/sda): " DRIVE
read -p "Enter Username: " USERNAME
read -s -p "Enter User Password: " USERPASS
echo

# --- 1. Smart Partitioning (Non-destructive) ---
msg "Finding free space on $DRIVE..."

# Create 512M FAT32 partition for Boot in free space
# 0:0:+512M means: use next partition number, start at next free block, size 512M
sgdisk --new=0:0:+512M --typecode=0:ef00 --change-name=0:ELIOS_BOOT "$DRIVE"

# Create Root partition in the remaining free space
sgdisk --new=0:0:0 --typecode=0:8300 --change-name=0:ELIOS_ROOT "$DRIVE"

# Find partition numbers dynamically
BOOT_NUM=$(sgdisk -p "$DRIVE" | grep "ELIOS_BOOT" | tail -1 | awk '{print $1}')
ROOT_NUM=$(sgdisk -p "$DRIVE" | grep "ELIOS_ROOT" | tail -1 | awk '{print $1}')

# Set partition paths
PART_PRE=""
[[ "$DRIVE" == *"nvme"* ]] && PART_PRE="p"

BOOT_PART="${DRIVE}${PART_PRE}${BOOT_NUM}"
ROOT_PART="${DRIVE}${PART_PRE}${ROOT_NUM}"

# --- 2. Formatting (Only ELIOS partitions!) ---
msg "Formatting EliOS partitions ($BOOT_PART, $ROOT_PART)..."
mkfs.fat -F32 "$BOOT_PART"
mkfs.ext4 -F "$ROOT_PART"

# --- 3. Mounting ---
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

# --- 4. Base Installation ---
msg "Installing base system packages..."
sed -i 's/^#ParallelDownloads/ParallelDownloads = 10/' /etc/pacman.conf

pacstrap /mnt base linux-lts linux-firmware networkmanager grub efibootmgr pipewire wireplumber glibc systemd sudo git

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
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# GRUB Installation
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=EliOS
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
EOF

msg "EliOS base installed into free space successfully!"
umount -R /mnt