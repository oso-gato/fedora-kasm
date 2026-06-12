#!/bin/bash
# Build-time install for fedora-kasm. Official sources only; fact-checked live
set -euxo pipefail

DNF="dnf -y --setopt=install_weak_deps=False"

# ---- vendor dnf repos -------------------------------------------------------
curl -fsSL https://pkgs.tailscale.com/stable/fedora/tailscale.repo \
    -o /etc/yum.repos.d/tailscale.repo

cat > /etc/yum.repos.d/claude-code.repo <<'EOF'
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://downloads.claude.ai/keys/claude-code.asc
EOF

curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo \
    -o /etc/yum.repos.d/gh-cli.repo

cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

cat > /etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

# ---- user core (before KasmVNC so group adds work) -------------------------
useradd -m -u 1000 -s /bin/bash core
printf 'core ALL=(ALL) NOPASSWD: /usr/sbin/tailscaled, /usr/bin/tailscale\n' \
    > /etc/sudoers.d/tailscale && chmod 440 /etc/sudoers.d/tailscale

# ---- KasmVNC (official kasmtech .rpm; F41 build, verified on F44) ------------
curl -fsSL -o /tmp/kasmvncserver.rpm \
    "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_${KASMVNC_FLAVOR}_${KASMVNC_VERSION}_x86_64.rpm"
$DNF install /tmp/kasmvncserver.rpm
rm /tmp/kasmvncserver.rpm
getent group kasmvnc-cert >/dev/null && usermod -aG kasmvnc-cert core || true

# ---- minimal XFCE + X plumbing + Electron runtime + apps (Fedora repos) ------
$DNF install \
    xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-terminal Thunar \
    dbus-x11 xorg-x11-xauth xdpyinfo xterm \
    mesa-dri-drivers mesa-libgbm \
    dejavu-sans-fonts google-noto-sans-fonts adwaita-icon-theme \
    nss atk at-spi2-atk cups-libs gtk3 alsa-lib libnotify libsecret \
    xdg-utils gnome-keyring iptables-nft nftables openssl \
    firefox \
    tailscale claude-code gh code 1password 1password-cli mosh \
    tmux fastfetch git sudo procps-ng glibc-langpack-en less nano

# ---- rclone (vendor rpm) ----------------------------------------------------
curl -fsSL -o /tmp/rclone.rpm \
    "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.rpm"
$DNF install /tmp/rclone.rpm
rm -f /tmp/rclone.rpm

# ---- Obsidian: developer AppImage, LATEST at build (user decision) -----------
OBSIDIAN_VERSION=$(curl -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
    | grep -oP '"tag_name":\s*"v\K[0-9.]+')
echo "Resolved Obsidian latest: ${OBSIDIAN_VERSION}"
curl -fsSL -o /tmp/Obsidian.AppImage \
    "https://github.com/obsidianmd/obsidian-releases/releases/download/v${OBSIDIAN_VERSION}/Obsidian-${OBSIDIAN_VERSION}.AppImage"
sha256sum /tmp/Obsidian.AppImage   # recorded in the build log for every build
chmod +x /tmp/Obsidian.AppImage
( cd /tmp && ./Obsidian.AppImage --appimage-extract >/dev/null )
mv /tmp/squashfs-root /opt/obsidian
chmod -R a+rX /opt/obsidian
rm /tmp/Obsidian.AppImage
cat > /usr/share/applications/obsidian.desktop <<EOF
[Desktop Entry]
Name=Obsidian
Exec=/opt/obsidian/obsidian --no-sandbox %u
Icon=/opt/obsidian/obsidian.png
Type=Application
Categories=Office;
MimeType=x-scheme-handler/obsidian;
X-AppImage-Version=${OBSIDIAN_VERSION}
EOF

# ---- Electron apps need --no-sandbox in a rootless container -----------------
for app in 1password; do
    desk="/usr/share/applications/${app}.desktop"
    [ -f "$desk" ] && sed -i 's|^Exec=\(\S*\)|Exec=\1 --no-sandbox|' "$desk" || true
done

dbus-uuidgen --ensure
dnf clean all
rm -rf /var/cache/dnf /var/cache/libdnf5
