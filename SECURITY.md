# Security Advisory & Dependency Upgrades for OIS

**Type:** Dependency Upgrade & Vulnerability Mitigation

## Overview
This document outlines a major overhaul of the underlying dependencies used by the OIS game executable (`ois.exe`) and its server counterpart (`ois_server.exe`). By scraping the raw binary data of the original application, it was discovered that the game was compiled with highly outdated libraries, many of which had reached End-of-Life (EOL) and contained documented Common Vulnerabilities and Exposures (CVEs).

This update replaces these legacy libraries with modern, patched versions to ensure client security, prevent arbitrary code execution, and improve overall engine stability.

## Dependency Version Mapping

Below is the comprehensive map of the original dependencies shipped with OIS (v1.0.8) and the newly updated targets.

| Component / Library | Original Version | Updated Version | Primary Function |
| :--- | :--- | :--- | :--- |
| **Game Executable** | 1.0.8 | 1.0.8 | Core Client |
| **Cocos2d-x Engine** | 3.15.1 | 3.15.1 (Dependencies Updated) | Game Engine |
| **OpenSSL** (`libcrypto` / `libssl`)*† | 1.1.0c | **1.1.1zh** | Cryptography & TLS |
| **cURL** (`libcurl.dll`) | 7.52.1 | **8.21.0** | HTTP / Network Transfers |
| **SQLite** (`sqlite3.dll`) | 3.7.15.1 | *3.53.4* | Local Database Storage |
| **zlib** (`zlib1.dll`) | 1.2.5 | **1.3.2** | Data Compression |
| **libwebsockets*** | 2.1.0 | **2.4.2** | Real-time Server Networking |
| **libtiff** | 4.0.3 | **4.7.2** | Image Parsing |
| **FMOD Studio*** (`fmod.dll`) | 1.04 | **2.0.1.23** | Audio Engine |
| **OpenAL** (`OpenAL32.dll`) | 1.16.0 | **1.25.2** | Spatial Audio |
| **libmpg123** | 1.20.1 | **1.33.67* | MP3 Decoding |
| **libvorbis** | 1.3.4 | **1.3.7** | OGG Audio Decoding |

*\*Note: While these libraries have been upgraded to the highest stable versions compatible with the legacy engine architecture, some residual risks remain, which are mitigated at the network layer via firewall rules.*

*†**OpenSSL provenance:** the OpenSSL 1.1.1 branch reached End-of-Life in September 2023. Releases past 1.1.1w are not available from the OpenSSL project as free public downloads — official 1.1.1 fixes are distributed only through the OpenSSL Corporation's paid Extended LTS programme. The `libcrypto-1_1.dll` / `libssl-1_1.dll` shipped here are built from the publicly available [kzalewski/openssl-1.1.1](https://github.com/kzalewski/openssl-1.1.1) community backport, which carries the 3.0-series security fixes into the 1.1.1 tree and versions them accordingly. This is a legitimate and actively maintained source, but it is a **third-party backport, not an upstream OpenSSL release**, and it is not FIPS validated. The patch also ships `libcrypto-3.dll` / `libssl-3.dll` from the OpenSSL 3.x line for the components that link against the newer ABI.*

---

## Why This is Important for OIS

Leaving legacy binaries in modern environments exposes the client and user systems to several attack vectors. Here is a breakdown of why these specific updates are critical for OIS:

### 1. Network & Cryptography Security (OpenSSL & cURL)
* **The Threat:** The original OpenSSL (1.1.0c) and cURL (7.52.1) date back to 2016. In the years since, numerous high-severity vulnerabilities have been discovered, including memory leaks, certificate bypasses, and protocol downgrade attacks.
* **The Fix:** Updating to **OpenSSL 1.1.1zh** and **cURL 8.21.0** ensures that any telemetry, multiplayer handshakes, or server requests made by OIS are using modern TLS. This prevents Man-in-the-Middle (MITM) attacks and secures communication between `ois.exe` and `ois_server.exe`. cURL 8.21.0 (released 24 June 2026) alone closed 18 separate CVEs, one of which had been present in libcurl since 2001.

### 2. Preventing Arbitrary Code Execution (Media Libraries)
* **The Threat:** Media parsers are common targets for exploits. Libraries like `libtiff` (4.0.3) and `libmpg123` (1.20.1) are notorious for heap-buffer overflows. A maliciously crafted image or audio file loaded by the game engine could have allowed attackers to execute arbitrary code on the host machine.
* **The Fix:** Bumping `libtiff` to **4.7.2**, `libvorbis` to **1.3.7**, and `libmpg123` to **1.33.6** patches these memory corruption bugs, hardening the game client against modified or malicious game assets.

### 3. Data Integrity & Memory Safety (SQLite & zlib)
* **The Threat:** The original `zlib 1.2.5` is vulnerable to memory corruption bugs (such as CVE-2018-25032) when compressing certain payloads. `SQLite 3.7.15.1` lacked modern memory safety and parser hardening.
* **The Fix:** Moving to **zlib 1.3.2** (released 17 February 2026, incorporating the fixes from the 7ASecurity audit of zlib) and **SQLite 3.53.4** ensures that local save files, cached data, and compressed game assets are handled safely without risking client crashes or database corruption.

### 4. Engine Stability & Modern OS Compatibility
* **The Benefit:** Beyond security, libraries like **FMOD 2.0.1.x** and **OpenAL 1.25.2** provide better compatibility with modern audio drivers, reducing crashes on contemporary operating systems.
* **Caveat:** FMOD Studio 2.0 is an ABI-breaking release relative to the 1.x line, so this is the single riskiest substitution in the table. It is included because it has been tested working against this build of `ois.exe`; if you encounter audio-related crashes, restoring `fmod.dll` from the `Original\` folder is the first thing to try.

---

## Residual Risk: libwebsockets

`libwebsockets` is upgraded from 2.1.0 to 2.4.2, but 2.4.x is itself long out of support. It is the newest version that remains ABI-compatible with the shipped `ois.exe`; moving further requires recompiling the game, which is not possible without the source.

Because of this, the patch installer offers to add two Windows Firewall rules that block **inbound** connections to `ois.exe` and `ois_server.exe`. This is the mitigation the note in the table above refers to. Outbound-initiated connections are unaffected, so normal play and client-side multiplayer connections continue to work.

---

## Files Intentionally Not Shipped

Some DLLs were part of earlier patch packages and have since been removed on purpose. They are **not** deleted from your game folder by default. When the installer sees a file that a previous version installed but the current manifest no longer lists, it restores the stock copy from the `Original\` baseline folder if one exists, and otherwise leaves the existing file untouched. Deletion happens only for names explicitly listed in `obsolete.txt`.

| File | Status | Reason |
| :--- | :--- | :--- |
| `iconv.dll` | No longer shipped | Not required; `libiconv-2.dll` covers the engine's needs. Stock copy restored where available. |
| `steam_api.dll` | No longer shipped | Valve SDK binary. Redistributing it is unnecessary and it is a frequent false-positive trigger for antivirus engines. Steam maintains its own copy. |
| `libogg.dll` | Removed | Superseded by `ogg.dll`. |

---

## Integrity Verification

Every release ships a `manifest.txt` containing the SHA256 of each file:

```
<scope> <sha256> <filename>
```

`scope` is `game` for files installed into the game folder and `tool` for scripts and documentation. The installer verifies every file against this manifest before copying and again after, and it writes a copy of the game-scope entries to `OIS_Update.manifest.txt` inside your game folder.

Updates use this manifest to download **only the files whose hash changed**, rather than the whole repository archive. A typical two-DLL update transfers a few hundred kilobytes.

You can regenerate the manifest after changing files with `Make_Manifest.bat`, or verify any single file yourself:

```
certutil -hashfile "libcurl.dll" SHA256
```

---

## Important: Steam File Verification Reverts This Patch

Using **Properties → Installed Files → Verify integrity of game files** in Steam will restore every vanilla DLL and silently undo this patch. Steam has no knowledge of it and treats the updated libraries as corrupted files.

**If you verify your files, click the "Repair Objects in Space Patch" shortcut afterwards.** The installer offers to create it on your Desktop and Start Menu. It compares every file in your game folder against `OIS_Update.manifest.txt` and puts back anything Steam reverted, prompting for Administrator rights only if your game lives somewhere your account cannot write.

The shortcut points at a copy of the package under `%LOCALAPPDATA%\OIS-Update`, so it keeps working after you delete the folder you extracted the patch into. The health check stays offline unless you choose its full-installer prompt; that installer then offers a separate yes/no online update check. Remove the shortcut with `OIS_Health_Check.bat -remove-shortcut`.

Running `Patch_OIS.bat` again does the same job, and is what you want if you also need to pick up a newer patch version.

*Advanced:* `OIS_Health_Check.bat -install-task` registers a SYSTEM-level scheduled task that performs the same check silently at every logon. It is not installed by default and is not recommended for most people: it requires Administrator rights, it fires at logon rather than when verification actually happens, and a background process that rewrites DLLs in a game folder is the kind of thing security software is designed to flag. Remove it with `-remove-task`.

---

## Conclusion
By updating the underlying dependency chain without breaking the primary Cocos2d-x engine hooks, this project modernizes OIS. The game client is significantly more resilient against network-based attacks, asset manipulation, and runtime crashes, with the remaining `libwebsockets` exposure contained at the firewall layer. Users running `ois.exe` can do so far more safely on modern hardware.
