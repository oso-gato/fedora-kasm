# fedora-kasm — instructions for Claude Code

Objective: run Claude Code; VS Code and Obsidian are the primary interfaces.
The remote-access stack is how you reach the workstation — never optimize it
at the expense of the workstation itself.

BEFORE ANY CHANGE: read README.md. The "Build Principles" table is BINDING —
follow it verbatim, no exceptions without an explicit user waiver recorded in
the Packages table. Every added/removed package must update the Packages table
in the same commit. Validate per principle 9 before declaring success.

Image-specific: WEB-ONLY (kasmvncserver rpm Conflicts: tigervnc-server — never
try to add a native-VNC bridge here). KasmVNC rpm is an F41 build running on a
newer base: re-run the feasibility gate on every FEDORA_VERSION or
KASMVNC_VERSION bump before committing.
