# Objects in Space - Modernized 32-Bit Dependencies & Community Patch

A community-maintained package of modernized 32-bit runtime dependencies and automated deployment scripts for Objects in Space. This package addresses outdated and vulnerable libraries, trims a set of dependency files the game never actually needed, and offers an optional Windows Firewall configuration to reduce the exposure of one legacy networking component that can't be fully replaced without the game's source.

---

## What This Patch Does

* Updates core dependencies with modern, patched 32-bit builds — cURL, zlib, SQLite, libtiff, libvorbis, libmpg123, FMOD, OpenAL, and libwebsockets.
* Rebuilds `libcurl.dll` from source against Windows' native TLS (Schannel) instead of bundling a third-party OpenSSL for it, which removes ten supporting files the previous packaging approach pulled in unnecessarily.
* Verifies every installed file against a SHA256 manifest before and after copying.
* Includes an opt-in script to restrict inbound network exposure for the one component (`libwebsockets`) that can't be fully modernized without recompiling the game from source.

Full technical detail, including exactly which files changed and why, is in [SECURITY.md](SECURITY.md).

---

## Installation Instructions

1. Download the latest release, or download this repository as a zip archive.
2. Extract the entire archive to a folder on your computer such as your Desktop. Do not run the script directly from inside the compressed zip file.
3. Double-click **Patch_OIS.bat**.
4. Follow the on-screen prompts:
   * The script will locate your default Steam installation of Objects in Space.
   * It will copy the required DLLs and remove files that are no longer needed (see [SECURITY.md](SECURITY.md) for exactly which ones and why — some are restored from a backup if Steam reverts them, others are removed outright).
   * You will be given a prompt to apply recommended Windows Firewall rules for added security.

---

## Antivirus & Windows Security Notes

* This package no longer ships any MinGW-runtime files (`libwinpthread-1.dll`, `libgcc_s_dw2-1.dll`, and others) — those were artifacts of an earlier build approach and have been removed entirely. Some Windows 11 installs with Smart App Control enabled would silently block those unsigned files, surfacing as a "Bad Image" or "part of this app has been blocked" error; that failure mode should no longer occur with this release.
* If your security software flags anything else in this package, please check the SHA256 against `manifest.txt` before assuming it's a false positive, and report it on the Steam discussion thread linked below either way.
* **Firewall Implementation:** the batch script uses a native PowerShell process to configure firewall rules without dropping any temporary executable files on your system.

---

## Community and Support

If you experience game crashes, bugs, or deployment issues after applying the patch, please check the Steam Community Discussions for Objects in Space to report them or seek help from other players.
https://steamcommunity.com/app/824070/discussions/0/573795849686060451/