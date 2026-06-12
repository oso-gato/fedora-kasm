#!/bin/bash
# PID 1 (core). Web-only KasmVNC desktop on :1 (the kasmvncserver rpm
# Conflicts: tigervnc-server, so no native-VNC bridge — see fedora-tigervnc).
# Passwords seeded at runtime, never in image layers.
set -euo pipefail

: "${VNC_PW:?VNC_PW must be set (web login password for user core)}"

export HOME=/home/core DISPLAY=:1 XAUTHORITY="$HOME/.Xauthority"

# --- web password (KasmVNC basic-auth user 'core', owner perms) ---
printf '%s\n%s\n' "$VNC_PW" "$VNC_PW" | kasmvncpasswd -u core -wo
chmod 600 "$HOME/.kasmpasswd"

# --- TLS cert: generate a persistent self-signed pair on first run -----------
# (the Debian .deb ships a snakeoil cert; the Fedora rpm may not — we always
# pass our own, generated into the home volume.)
mkdir -p "$HOME/.vnc"
if [ ! -f "$HOME/.vnc/self.crt" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$HOME/.vnc/self.key" -out "$HOME/.vnc/self.crt" \
        -subj "/CN=fedora-kasm" >/dev/null 2>&1
    chmod 600 "$HOME/.vnc/self.key"
fi

# --- KasmVNC server on :1 (no-op xstartup; XFCE launched explicitly below) ---
printf '#!/bin/sh\nexit 0\n' > "$HOME/.vnc/xstartup"
chmod +x "$HOME/.vnc/xstartup"
vncserver :1 -depth 24 -geometry "${VNC_RESOLUTION:-1280x800}" \
    -websocketPort 6800 -sslOnly -interface 0.0.0.0 \
    -cert "$HOME/.vnc/self.crt" -key "$HOME/.vnc/self.key" \
    -FrameRate "${MAX_FRAME_RATE:-24}" -BlacklistThreshold 0 -select-de manual

for i in $(seq 1 60); do
    xdpyinfo -display :1 >/dev/null 2>&1 && break
    sleep 0.5
done
xdpyinfo -display :1 >/dev/null 2>&1 || { echo "FATAL: X :1 did not come up"; exit 1; }

# --- desktop session + keyring on the same display ---
eval "$(gnome-keyring-daemon --start --components=secrets,pkcs11 2>/dev/null)" || true
dbus-launch --exit-with-session startxfce4 >"$HOME/.vnc/xfce.log" 2>&1 &

# --- tailnet: ON by default; auth persists in ~/.tailscale (home volume) ------
if [ "${TAILSCALE_ENABLE:-1}" = "1" ]; then
    TS_FLAGS=""
    [ -e /dev/net/tun ] || TS_FLAGS="--tun=userspace-networking"
    sudo /usr/sbin/tailscaled --statedir="$HOME/.tailscale" $TS_FLAGS \
        >"$HOME/.vnc/tailscaled.log" 2>&1 &
    (
        sleep 3
        sudo tailscale up --ssh --hostname=fedora-kasm \
            ${TS_AUTHKEY:+--auth-key="$TS_AUTHKEY"} \
            >"$HOME/.vnc/tailscale-up.log" 2>&1 &
        shown=""
        for i in $(seq 1 120); do
            if ip=$(tailscale ip -4 2>/dev/null) && [ -n "$ip" ]; then
                printf '\n##############################################################\n'
                printf '##  TAILNET JOINED:  %s\n' "$ip"
                printf '##  web : https://%s:6800   (core / $VNC_PW)\n' "$ip"
                printf '##############################################################\n\n'
                break
            fi
            url=$(grep -oE 'https://login\.tailscale\.com/[A-Za-z0-9/]+' \
                  "$HOME/.vnc/tailscale-up.log" 2>/dev/null | head -1 || true)
            if [ -n "$url" ] && [ "$url" != "$shown" ]; then
                shown="$url"
                printf '\n##############################################################\n'
                printf '##  ACTION REQUIRED — AUTHENTICATE THIS CONTAINER TO YOUR\n'
                printf '##  TAILNET. Open this link in a browser:\n'
                printf '##\n##      %s\n##\n' "$url"
                printf '##  (waiting; container logs will confirm once joined)\n'
                printf '##############################################################\n\n'
            fi
            sleep 5
        done
    ) &
fi

# --- supervise: vncserver forks, so poll the Xvnc PID file ---
trap 'vncserver -kill :1 >/dev/null 2>&1 || true; exit 0' TERM INT
while true; do
    pidfile=$(ls "$HOME"/.vnc/*:1.pid 2>/dev/null | head -1)
    if [ -z "$pidfile" ] || ! kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        echo "FATAL: Xvnc (:1) died"; exit 1
    fi
    sleep 5
done
