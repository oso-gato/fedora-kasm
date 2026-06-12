# fedora-kasm: Fedora 44 + XFCE + KasmVNC web desktop (:6800). WEB-ONLY:
# the KasmVNC rpm declares Conflicts: tigervnc-server, so the native-VNC
# scraping bridge of the Debian sibling is impossible here (fedora-tigervnc
# covers the dual web+native case). All packages official: Fedora repos,
# vendor dnf repos, or vendor-released artifacts. Obsidian is the developer's
# AppImage resolved to LATEST at build time (user decision 2026-06-12).
# No passwords in any layer — seeded at runtime from VNC_PW.
ARG FEDORA_VERSION=44
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION}

# KasmVNC: newest official Fedora rpm targets F41; verified installing and
# running cleanly on F44 (feasibility gate 2026-06-12). Re-test on base bumps.
ARG KASMVNC_VERSION=1.4.0
ARG KASMVNC_FLAVOR=fedora_fortyone
ARG RCLONE_VERSION=1.74.3

ENV LANG=en_US.UTF-8 DISPLAY=:1

COPY install.sh /tmp/install.sh
RUN KASMVNC_VERSION="${KASMVNC_VERSION}" KASMVNC_FLAVOR="${KASMVNC_FLAVOR}" \
    RCLONE_VERSION="${RCLONE_VERSION}" \
    bash /tmp/install.sh && rm /tmp/install.sh

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 6800
# No HEALTHCHECK: OCI images drop it — health is defined at run time (run.sh).
USER core
WORKDIR /home/core
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
