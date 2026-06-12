#!/usr/bin/env bash
# Spin up the fedora-kasm container the right way.
#   VNC_PW      (required) web login password for user 'core'
#   IMAGE       (optional) defaults to local build; or ghcr.io/<owner>/fedora-kasm:latest
#   TAILSCALE_ENABLE (default 1), TS_AUTHKEY (optional, unattended join)
#
# WEB-ONLY image (no native VNC :5900 — the KasmVNC rpm conflicts with
# tigervnc-server on Fedora; use fedora-tigervnc for web+native).
# Host port 6801 (6800 is taken by the Debian kasm container on this host).
# Health at run time: OCI images drop Containerfile HEALTHCHECK; the 401 auth
# gate + post-401 RST make curl -f lie, so probe http_code != 000.
set -euo pipefail

: "${VNC_PW:?set VNC_PW (web login password)}"
IMAGE="${IMAGE:-localhost/fedora-kasm:latest}"

exec podman run -d --name fedora-kasm --shm-size=1g \
    --cap-add=NET_ADMIN --device /dev/net/tun \
    --security-opt label=disable \
    -e VNC_PW="$VNC_PW" \
    -e TAILSCALE_ENABLE="${TAILSCALE_ENABLE:-1}" \
    ${TS_AUTHKEY:+-e TS_AUTHKEY="$TS_AUTHKEY"} \
    -p 6801:6800 \
    -v fedora-kasm-data:/home/core \
    --health-cmd 'bash -c "[ $(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:6800/) != 000 ]"' \
    --health-interval 30s --health-timeout 5s --health-start-period 30s \
    --restart=always \
    "$IMAGE"
