# Security Advisory & Dependency Upgrades for OIS

**Type:** Dependency Upgrade & Vulnerability Mitigation

## Overview
This document outlines a major overhaul of the underlying dependencies used by the OIS game executable (`ois.exe`) and its server counterpart (`ois_server.exe`). By scraping the raw binary data of the original application, it was discovered that the game was compiled with highly outdated libraries, many of which had reached End-of-Life (EOL) and contained documented Common Vulnerabilities and Exposures (CVEs). 

This update replaces these legacy libraries with modern, patched versions to ensure client security, prevent arbitrary code execution, and improve overall engine stability.

## Dependency Version Mapping

Below is the comprehensive map of the original dependencies shipped with OIS (v1.0.8) and the newly updated targets.

| Component / Library | Original Version | Updated Version | Primary Function |
| :--- | :--- | :--- | :--- |
| **Game Executable** | 1.0.8 | 1.0.8+ (Patched) | Core Client |
| **Cocos2d-x Engine** | 3.15.1 | 3.15.1 (Dependencies Updated) | Game Engine |
| **OpenSSL** (`libcrypto` / `libssl`) | 1.1.0c | **1.1.1w** | Cryptography & TLS |
| **cURL** (`libcurl.dll`) | 7.52.1 | **8.21.0** | HTTP / Network Transfers |
| **SQLite** (`sqlite3.dll`) | 3.7.15 | **3.53.3** | Local Database Storage |
| **zlib** (`zlib1.dll`) | 1.2.5 | **1.3.2** | Data Compression |
| **libwebsockets** | 2.1.0 | **2.4.2** | Real-time Server Networking |
| **libtiff** | 4.0.3 | **4.7.2** | Image Parsing |
| **FMOD Studio** (`fmod.dll`) | 1.04 | **2.0.1.xx** | Audio Engine |
| **OpenAL** (`OpenAL32.dll`) | 1.16.0 | **1.25.2** | Spatial Audio |
| **libmpg123** | 1.20.1 | **1.33.6** | MP3 Decoding |
| **libvorbis** | 1.3.4 | **1.3.7** | OGG Audio Decoding |

---

## Why This is Important for OIS

Leaving legacy binaries in modern environments exposes the client and user systems to several attack vectors. Here is a breakdown of why these specific updates are critical for OIS:

### 1. Network & Cryptography Security (OpenSSL & cURL)
*   **The Threat:** The original OpenSSL (1.1.0c) and cURL (7.52.1) date back to 2016. In the years since, numerous high-severity vulnerabilities have been discovered, including memory leaks, certificate bypasses, and protocol downgrade attacks.
*   **The Fix:** Updating to **OpenSSL 1.1.1w** and **cURL 8.21.0** ensures that any telemetry, multiplayer handshakes, or server requests made by OIS are utilizing modern TLS standards. This prevents Man-in-the-Middle (MITM) attacks and ensures secure communication between `ois.exe` and `ois_server.exe`.

### 2. Preventing Arbitrary Code Execution (Media Libraries)
*   **The Threat:** Media parsers are common targets for exploits. Libraries like `libtiff` (4.0.3) and `libmpg123` (1.20.1) are notorious for heap-buffer overflows. A maliciously crafted image or audio file loaded by the game engine could have allowed attackers to execute arbitrary code on the host machine.
*   **The Fix:** Bumping `libtiff` to **4.7.2**, `libvorbis` to **1.3.7**, and `libmpg123` to **1.33.6** patches these memory corruption bugs, heavily hardening the game client against modified or malicious game assets. 

### 3. Data Integrity & Memory Safety (SQLite & zlib)
*   **The Threat:** The original `zlib 1.2.5` is vulnerable to memory corruption bugs (such as the well-known CVE-2018-25032) when decompressing certain payloads. `SQLite 3.7.15` lacked modern memory safety and query sanitization features.
*   **The Fix:** Moving to **zlib 1.3.2** and **SQLite 3.53.3** ensures that local save files, cached data, and compressed game assets are handled safely without risking client crashes or database injection vectors.

### 4. Engine Stability & Modern OS Compatibility
*   **The Benefit:** Beyond security, libraries like **FMOD 2.0.1.xx** and **OpenAL 1.25.2** provide better compatibility with modern audio drivers, reducing crashes on contemporary operating systems. 

## Conclusion
By updating the underlying dependency chain without breaking the primary Cocos2d-x engine hooks, this project modernizes OIS. The game client is now significantly more resilient against network-based attacks, asset manipulation, and runtime crashes. Users running `ois.exe` can do so securely on modern hardware.
