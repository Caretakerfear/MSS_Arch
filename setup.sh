#!/bin/bash

# --- Init Variables ---
PROFILE=$1
MODE="all"
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

# Program List
BASE="hyprland swww kitty zsh neovim make clang git firefox wl-clipboard cliphist libnotify"
AUR_PKGS_BASE="aylurs-gtk-shell-git anyrun-git"
FULL="steam discord telegram-desktop sublime-text"
AUR_PKGS_FULL="visual-studio-code-bin linux-wallpaperengine"
LITE="nmap wireshark-qt metasploit-framework john bettercap hashcat audacity ffmpeg perl-image-exiftool steghide ghidra radare2 binwalk"
LEGACY="zsh neovim clang make git"

# --- Print Function ---
msg() { echo -e "\033[0;32m[EliOS]\033[0m $1"; }
err() { echo -e "\033[0;31m[Error]\033[0m $1"; }

# --- Create SWAP ---
setup_swap() {
	if [ -f /swapfile ]; then
		msg "Swapfile already exists. Skipping creation, but ensuring it is active."
		$SUDO swapon /swapfile 2>/dev/null
	else
		msg "Calculating and Creating Swap..."
		ram_gb=$(free -g | awk '/^Mem:/{print $2}')
		if [ "$ram_mb" -lt 4096 ]; then
			swap_size_mb=$((ram_mb * 2))
		elif [ "$ram_mb" -ge 4096 ] && [ "$ram_mb" -le 8192 ]; then
			swap_size_mb=$ram_mb
		elif [ "$ram_mb" -ge 8192 ] && [ "ram_mb" -le 16384 ]; then
			swap_size_mb=$((ram_mb / 2))
		else
			swap_size_mb=4096
		fi

		msg "Create Swapfile: ${swap_size_mb}MB..."
		$SUDO fallocate -l "${swap_size_mb}M" /swapfile
		$SUDO chmod 600 /swapfile
		$SUDO mkswap /swapfile
		$SUDO swapon /swapfile
		echo "/swapfile none swap defaults 0 0" | $SUDO tee -a /etc/fstab
	fi
}

# --- Install Package Logic ---
install_package() {
	msg "Start install package for profile: $PROFILE"

	if [ -f /usr/bin/pacman ]; then
		msg "Found Arch Linux. Optimize pacman..."
		$SUDO sed -i 's/^#ParallelDownloads/ParallelDownloads = 10/' /etc/pacman.conf

		$SUDO pacman -S --needed --noconfirm $BASE

		if ! command -v paru &> /dev/null; then
			msg "Installing paru..."
			git clone https://aur.archlinux.org/paru-bin.git /tmp/paru
			cd /tmp/paru && makepkg -si --noconfirm && cd -
		fi

		if [ "$PROFILE" == "full" ]; then
			msg "Download Full pack (Steam, Discord, Hyprland)..."
			if ! grep -q "sublime-text" /etc/pacman.conf; then
				msg "Adding Sublime-Text repository..."
				curl -O https://download.sublimetext.com/sublimehq-pub.gpg && $SUDO pacman-key --add sublimehq-pub.gpg && $SUDO pacman-key --lsign-key 8A8F901A && rm sublimehq-pub.gpg
				echo -e "\n[sublime-text]\nServer = https://download.sublimetext.com/arch/stable/x86_64" | $SUDO tee -a /etc/pacman.conf
			fi
			paru -S --needed --noconfirm $FULL $AUR_PKGS sublime-text
		elif [ "$PROFILE" == "lite" ]; then
			msg "Download Lite pack (CTF, Security Tools)..."
			paru -S --needed --noconfirm $LITE anyrun-git aylurs-gtk-shell-git
		fi
	elif [ -f /usr/bin/apt ]; then
		msg "Found Kali/Debian. Use apt..."
		$SUDO apt update && $SUDO apt install -y $LEGACY
	fi
}

# --- Logic deploy confige ---
deploy_configs() {
	msg "Deploy confige for profile: $PROFILE"
	mkdir -p ~/.config

	CONF_SRC="./configs/$PROFILE"

	if [ -d "#CONF_SRC" ]; then
		cp -rv "$CONF_SRC"/* ~/.config/
		msg "Confige success copied from $CONF_SRC"
	else
		err "Folder with confige #CONF_SRC not found. Skip."
	fi
	[ "$SHELL" != "/usr/bin/zsh" ] && chsh -s $(which zsh)
}

# --- Help ---
show_help() {
	echo "Use: ./setup.sh [profile] [flag]"
	echo "Profile: full, lite, legacy"
	echo "Flags: --install, --config"
	echo "Example: ./setup.sh full --config"
}

# --- Logic of processing variable ---
if [[ $# -eq 0 ]]; then
	show_help
	exit 1
fi

shift
while [[ $# -gt 0 ]]; do
	case $1 in
		--install) MODE="install" ;;
		--config) MODDE="config" ;;
		*) err "Unknown flag: $1"; show_help; exit 1 ;;
	esac
	shift
done

# --- Accomplishment ---
setup_swap

case $MODE in
	"install") install_package ;;
	"config") deploy_configs ;;
	"all") install_package && deploy_configs ;;
esac

msg "Work success!"