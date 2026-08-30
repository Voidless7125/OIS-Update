# Security Advisory & Dependency Upgrades for OIS

**Type:** Dependency Upgrade & Vulnerability Mitigation

## Overview
This document outlines a major overhaul of the underlying dependencies used by the OIS game executable (`ois.exe`) and its server counterpart (`ois_server.exe`). By scraping the raw binary data of the original application, it was discovered that the game was compiled with highly outdated libraries, many of which had reached End-of-Life (EOL) and contained documented Common Vulnerabilities and Exposures (CVEs).

This update replaces these legacy libraries with modern, patched versions, and rebuilds cURL from source against Windows' native TLS stack rather than bundling a third-party OpenSSL, which removed ten files from the package that the game never actually needed.

## Dependency Version Mapping

| Component / Library | Original Version | Updated Version | Primary Function |
| :--- | :--- | :--- | :--- |
| **Game Executable** | 1.0.8 | 1.0.8 | Core Client |
| **Cocos2d-x Engine** | 3.15.1 | 3.15.1 (Dependencies Updated) | Game Engine |
| **cURL** (`libcurl.dll`) | 7.52.1 | **8.21.0** | HTTP / Network Transfers |
| **OpenSSL** (`libcrypto-1_1` / `libssl-1_1`)† | 1.1.0c | **1.1.1zh** | TLS for `libwebsockets` only — see below |
| **SQLite** (`sqlite3.dll`) | 3.7.15.1 | **3.53.4** | Local Database Storage |
| **zlib** (`zlib1.dll`) | 1.2.5 | **1.3.2** | Data Compression |
| **libwebsockets*** | 2.1.0 | **2.4.2** | Real-time Server Networking |
| **libtiff** | 4.0.3 | **4.7.2** | Image Parsing |
| **FMOD Studio*** (`fmod.dll`) | 1.04 | **2.0.1.23** | Audio Engine |
| **OpenAL** (`OpenAL32.dll`) | 1.16.0 | **1.25.2** | Spatial Audio |
| **libmpg123** | 1.20.1 | **1.33.7** | MP3 Decoding |
| **libvorbis** | 1.3.4 | **1.3.7** | OGG Audio Decoding |

*\*Note: `libwebsockets` and FMOD 2.0 are the two remaining libraries whose residual risk is mitigated at the network layer via firewall rules rather than eliminated outright — see "Residual Risk" below.*

---

## cURL: rebuilt against Schannel, not shipped from a MinGW distribution

Earlier builds of this patch sourced `libcurl.dll` from a standard MinGW/MSYS2 distribution package. That build was linked against OpenSSL and pulled in the OpenSSL 3.x line plus ten supporting runtime files (`libcrypto-3.dll`, `libgcc_s_dw2-1.dll`, `libiconv-2.dll`, `libintl-8.dll`, `libnghttp2-14.dll`, `libpsl-5.dll`, `libssl-3.dll`, `libunistring-5.dll`, `libwinpthread-1.dll`, `libzstd.dll`) that the game itself never called into — they existed purely to satisfy curl's own default feature set (HTTP/2, IDN, brotli, PSL, etc.), none of which OIS's networking code exercises.

As of this release, `libcurl.dll` is built from source via [vcpkg](https://github.com/microsoft/vcpkg) with the `ssl` feature only, which resolves to **Schannel** — Windows' built-in TLS implementation — on this platform, plus `sspi`. This means:

- **No bundled OpenSSL for cURL.** TLS certificate handling and protocol patches now ride Windows Update, not a third-party backport this project has to track.
- **No MinGW runtime dependency.** The build links against MSVC, matching the toolchain used for `ois.exe` itself.
- **Ten files removed outright**, not just left unused — the ones listed above are gone from the package entirely as of this release, not archived or restorable via `Original\`.

`libcurl.dll` and `libcocos2d.dll` share a single `zlib1.dll` — curl was built against the same zlib binary the engine already links, rather than shipping a second, independently-built copy under a different internal name. If you're rebuilding this yourself: MSVC's default `FindZLIB` will happily resolve to a differently-named zlib and produce a `libcurl.dll` whose import table doesn't match what `libcocos2d.dll` expects (`z.dll` vs `zlib1.dll`) — Windows will fail to load it with a "module not found" error that names whichever internal DLL name got baked in. If you hit that, regenerate the import library from the actual shipped `zlib1.dll` rather than letting a package manager build its own.

**A secondary benefit of this rebuild, worth noting for anyone troubleshooting install issues:** the old MinGW-sourced files were unsigned and had no publisher reputation, which some Windows 11 installs with Smart App Control enabled will silently block, surfacing as a "Bad Image" error with no clear cause. That failure mode is now gone along with the files that caused it.

†**OpenSSL provenance (still applies, narrower scope):** the OpenSSL 1.1.1 branch reached End-of-Life in September 2023. Releases past 1.1.1w are not available from the OpenSSL project as free public downloads — official 1.1.1 fixes are distributed only through the OpenSSL Corporation's paid Extended LTS programme. The `libcrypto-1_1.dll` / `libssl-1_1.dll` shipped here are built from the publicly available [kzalewski/openssl-1.1.1](https://github.com/kzalewski/openssl-1.1.1) community backport, which carries the 3.0-series security fixes into the 1.1.1 tree and versions them accordingly. This is a legitimate and actively maintained source, but it is a **third-party backport, not an upstream OpenSSL release**, and it is not FIPS validated. As of this release, the only consumer of these two files is `libwebsockets.dll` — cURL no longer touches OpenSSL at all. Retiring this dependency fully would mean moving `libwebsockets` to Schannel as well, which is a larger undertaking tracked separately (see "Residual Risk" below).

---

## Why This is Important for OIS

### 1. Network & Cryptography Security (cURL)
* **The Threat:** The original cURL (7.52.1) dates back to 2016. In the years since, numerous high-severity vulnerabilities have been discovered, including memory leaks, certificate bypasses, and protocol downgrade attacks.
* **The Fix:** cURL 8.21.0 (released 24 June 2026) closed 18 separate CVEs, one of which had been present in libcurl since 2001. TLS now goes through Schannel, so certificate-chain and protocol fixes arrive via Windows Update on the same cadence as the rest of the OS.

### 2. Preventing Arbitrary Code Execution (Media Libraries)
* **The Threat:** Media parsers are common targets for exploits. Libraries like `libtiff` (4.0.3) and `libmpg123` (1.20.1) are notorious for heap-buffer overflows.
* **The Fix:** Bumping `libtiff` to **4.7.2**, `libvorbis` to **1.3.7**, and `libmpg123` to **1.33.7** patches known memory corruption bugs in these codecs.
* **Open question on `libtiff` specifically:** this file ships in the original stock game and has never appeared in a static import-table trace from `ois.exe`, `ois_server.exe`, or `libcocos2d.dll`. It's possible cocos2d-x loads it dynamically at runtime for certain asset types, or that it's linked in statically elsewhere and this file goes unused — that hasn't been confirmed either way. The version bump is a reasonable precaution regardless of which is true, but until this is verified with a runtime loader trace (Process Monitor with the game actually running), treat the "hardens against malicious TIFF assets" claim as plausible rather than confirmed.

### 3. Data Integrity & Memory Safety (SQLite & zlib)
* **The Threat:** The original `zlib 1.2.5` is vulnerable to memory corruption bugs (such as CVE-2018-25032). `SQLite 3.7.15.1` lacked modern memory safety and parser hardening.
* **The Fix:** zlib **1.3.2** (17 February 2026, incorporating fixes from the 7ASecurity audit) and SQLite **3.53.4** handle local save files, cached data, and compressed assets more safely.

### 4. Engine Stability & Modern OS Compatibility
* **The Benefit:** FMOD 2.0.1.x and OpenAL 1.25.2 improve compatibility with modern audio drivers.
* **Caveat:** FMOD Studio 2.0 is an ABI-breaking release relative to the 1.x line — the single riskiest substitution in this table. If you encounter audio-related crashes, restoring `fmod.dll` from `Original\` is the first thing to try.
* **OpenAL note:** an earlier build of this patch accidentally shipped a debug build of `OpenAL32.dll` compiled with full symbols, at roughly 106 MB. This release replaces it with the official 1.25.2 release binary from openal-soft.org, at roughly 4 MB. That's still noticeably larger than the stock file (~358 KB), and the reason for the gap hasn't been fully run down — if you're auditing this yourself, it's worth diffing the release archive's build variants before assuming the current file is minimal.

---

## Residual Risk: libwebsockets

`libwebsockets` is upgraded from 2.1.0 to 2.4.2, but 2.4.x is itself long out of support. It is the newest version that remains ABI-compatible with the shipped `ois.exe`; moving further requires recompiling the game, which is not possible without the source. This is also, as of this release, the last remaining consumer of the OpenSSL 1.1.1 backport described above.

Because of this, the patch installer offers to add two Windows Firewall rules that block **inbound** connections to `ois.exe` and `ois_server.exe`. Outbound-initiated connections are unaffected, so normal play and client-side multiplayer connections continue to work.

---

## Files Intentionally Not Shipped

Some DLLs were part of earlier patch packages and have since been removed on purpose. Two categories apply, and they're handled differently — worth understanding before you go looking for a file that "should" be there.

**Restored from `Original\` if the manifest no longer lists them, but not force-deleted:**

| File | Status | Reason |
| :--- | :--- | :--- |
| `iconv.dll` | Not shipped by this patch | Ships with stock OIS itself, predates this project entirely. Nothing in the current import graph reaches it; left in place per this project's general policy of not deleting files it didn't put there. |
| `steam_api.dll` | Not shipped by this patch | Valve SDK binary. Redistributing it is unnecessary and it is a frequent false-positive trigger for antivirus engines. Steam maintains its own copy. |
| `libogg.dll` | Removed | Superseded by `ogg.dll`. |

**Removed outright as of this release, not restorable via `Original\`:**

`libcrypto-3.dll`, `libgcc_s_dw2-1.dll`, `libiconv-2.dll`, `libintl-8.dll`, `libnghttp2-14.dll`, `libpsl-5.dll`, `libssl-3.dll`, `libunistring-5.dll`, `libwinpthread-1.dll`, `libzstd.dll` — all ten were artifacts of the previous MinGW-sourced `libcurl.dll` build and are not needed by the Schannel-based rebuild described above. Do not confuse `libiconv-2.dll` (removed, was curl-chain-only) with `iconv.dll` (stock, left alone) — they are different files serving different consumers.

---

## Integrity Verification

Every release ships a `manifest.txt` containing the SHA256 of each file:

```
<scope> <sha256> <filename>
```

`scope` is `game` for files installed into the game folder and `tool` for scripts and documentation. The installer verifies every file against this manifest before copying and again after, and it writes a copy of the game-scope entries to `OIS_Update.manifest.txt` inside your game folder.

Updates use this manifest to download **only the files whose hash changed**, rather than the whole repository archive.

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
This release narrows the update's own footprint as much as it modernizes the game's: rebuilding cURL against Windows' native TLS removed ten files this project itself had introduced and the game never needed, and corrected a debug-build mistake in the OpenAL binary. The remaining `libwebsockets`/OpenSSL 1.1.1 exposure is now the last dependency this project doesn't fully control the security lifecycle of, and it's contained at the firewall layer in the meantime.