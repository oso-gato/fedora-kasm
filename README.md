# fedora-kasm

## Objective

**Run Claude Code.** The Fedora twin of debian-kasm-tigervnc: a persistent
Claude Code workstation with VS Code and Obsidian as the primary interfaces —
VS Code for code and terminals, Obsidian for the knowledge vault Claude Code
reads and writes — on an XFCE desktop, with gh, rclone, 1Password, and
Firefox alongside.

Claude Code runs inside tmux, so it outlives any single connection — tmux
holds the session whether you opened a terminal on the desktop or arrived
over mosh/ssh from elsewhere; mosh makes the connection resilient,
tmux makes the work survive even a dead one.

Resize the browser window and the desktop reflows with it — KasmVNC drives
the X display's resolution dynamically.

The container joins your tailnet at startup and the desktop is reached
through KasmVNC in the browser (:6800). Web-only on Fedora — the KasmVNC rpm
conflicts with tigervnc-server; if you also want native VNC, fedora-tigervnc
is the sibling for that. TLS: self-signed cert minted into the home volume at
first run (the Fedora rpm, unlike the Debian deb, ships no snakeoil cert).

## Build Principles (binding — follow verbatim for any change to this image)

| # | Principle | Rule |
|---|---|---|
| 1 | BASE | Build only from the official base image `registry.fedoraproject.org/fedora:${FEDORA_VERSION}`. Pinned versions are Containerfile `ARG`s; never inline them. |
| 2 | SOURCES | Every package from an official source, exactly one of: (a) the distro's own repos; (b) the vendor's own package repo; (c) an artifact released by the developer themselves. Never: third-party repos, npm/pip installs, `curl \| sh`. Exceptions only by explicit user waiver, recorded in the Packages table. Current waivers: none. |
| 3 | MINIMAL | Install only what is required (`--setopt=install_weak_deps=False`). Every package must have a row in the Packages table justifying it; adding a package without a row is a violation. |
| 4 | VERIFY FIRST | Before changing any source or version, fact-check it against the live source (web). Gate risky installs (version-mismatched vendor packages, new repos) in a scratch container before editing build files. |
| 5 | NO SECRETS / NO IDENTITY | No passwords, keys, or personal usernames in any layer, file, or commit. Container user is the generic `core` (uid 1000). Credentials enter only as runtime env vars; the entrypoint must fail fast if they are missing. |
| 6 | PINS | Vendor artifact versions are Containerfile `ARG`s — bump there only, after rule 4. |
| 7 | DEPLOY | Only via `./run.sh` — it carries the runtime `--health-cmd` (OCI images silently drop Containerfile HEALTHCHECK), devices, volumes, and restart policy. Never hand-roll `podman run`. Sensitive ports (RDP/VNC/ssh) stay tailnet-only — never publish them with `-p`. |
| 8 | CI | Published via `.github/workflows/build.yml` to GHCR — on push, on the 1st/15th monthly (`--no-cache`), and on manual dispatch. CI uses the built-in token only; never add credentials. |
| 9 | VALIDATE | After any change: build, deploy via run.sh, confirm `(healthy)` plus a functional probe of each access path before declaring success. |

## Packages

| Tier | Package | Pin / source | Class (rule 2) | Why required |
|---|---|---|---|---|
| Core | claude-code | Anthropic dnf repo (downloads.claude.ai/claude-code/rpm/stable) | vendor (b) | the reason this image exists |
| Core | code (VS Code) | Microsoft yum repo | vendor (b) | primary interface for Claude Code: editor + integrated terminal |
| Core | obsidian | latest at build (GitHub API; sha256 logged) — developer AppImage, extracted to /opt | developer (c) | primary interface: the knowledge vault Claude Code reads and writes; developer ships no rpm |
| Toolchain | gh | GitHub rpm repo (cli.github.com) | vendor (b) | GitHub flow for Claude Code's output (delegates VCS to git) |
| Toolchain | git | Fedora current | distro (a) | the VCS engine gh and Claude Code drive |
| Toolchain | rclone | ARG `RCLONE_VERSION` — developer .rpm | developer (c) | vault/file sync |
| Toolchain | 1password, 1password-cli | 1Password rpm repo | vendor (b) | credentials |
| Toolchain | firefox | Fedora current | distro (a) | browser (no ESR rpm exists in Fedora) |
| Toolchain | tmux | Fedora current | distro (a) | the persistence layer Claude Code runs inside — sessions outlive connections |
| Toolchain | mosh | Fedora current | distro (a) | roaming-resilient remote shell (UDP, AEAD-authenticated; bootstraps over ssh) |
| Toolchain | fastfetch | Fedora current | distro (a) | requested |
| Remote access | kasmvncserver | ARG `KASMVNC_VERSION` (rpm flavor ARG `KASMVNC_FLAVOR`) — kasmtech GitHub release rpm | developer (c) | the web desktop server. NOTE: newest Fedora rpm targets F41; verified installing AND running on F44 — RE-RUN that gate (install + `Xvnc -version`) on EVERY base bump and KasmVNC release |
| Desktop & system | tailscale | Tailscale dnf repo | vendor (b) | the tailnet — the only path to non-web ports |
| Desktop & system | XFCE set (xfce4-session, xfwm4, xfce4-panel, xfdesktop, xfce4-terminal, Thunar) | Fedora current | distro (a) | minimal desktop the interfaces run on, no meta-package bloat |
| Desktop & system | X/runtime support (dbus-x11, xorg-x11-xauth, xdpyinfo, xterm, mesa, fonts, gnome-keyring, nss/atk/gtk3/alsa-lib/cups-libs/libnotify/libsecret/xdg-utils) | Fedora current | distro (a) | X plumbing + Electron app runtime requirements |
| Desktop & system | sudo, procps-ng, glibc-langpack-en, less, nano, openssl, iptables-nft, nftables | Fedora current | distro (a) | openssl mints the runtime TLS cert; procps for watchdog+health; iptables/nftables for tailscaled; locale for TUI rendering; non-root admin, pager, small editor |

## Deploy

```sh
VNC_PW='…' [TS_AUTHKEY=…] ./run.sh
```

- Web login `core` / `$VNC_PW` at `https://<host>:6801/` (host port; container :6800).
- Volume: `fedora-kasm-data`. Optional env: `VNC_RESOLUTION` (default 1280x800),
  `MAX_FRAME_RATE` (default 24).
- Tailscale SSH is enabled (`--ssh`): once joined, any tailnet device can
  `ssh core@<hostname>` keylessly — auth is your tailnet identity (lands in
  tmux where the image has the auto-attach drop-in).
- Tailnet join link: `tailscale status` in any terminal inside the container.
