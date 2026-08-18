# Installing the OIS Community Patch

## Short version

1. Download the ZIP.
2. **Before extracting**, right-click the ZIP → **Properties** → tick **Unblock** at the bottom → **OK**.
3. Extract it.
4. Run `Patch_OIS.bat`.

Step 2 is the one everyone skips, and it is the one that prevents almost every "Windows blocked this" message.

---

## Why Windows blocks it

Every file downloaded by a browser gets a hidden tag called the **Mark of the Web**, stored as an alternate data stream named `Zone.Identifier`. It records that the file came from the internet.

When you extract a ZIP that carries this tag, Windows copies the tag onto **every extracted file**. Batch files are scripts, so a script tagged as internet-sourced is treated as high risk.

Unblocking the ZIP first removes the tag once, and the extracted files come out clean. Unblocking afterwards means doing it 30 times.

---

## "Smart App Control blocked a file that may be unsafe"

![Smart App Control dialog](docs/sac.png)

Smart App Control (SAC) is a Windows 11 feature that only allows software that is either digitally signed by a known publisher or already reputationally trusted by Microsoft. A community batch file is neither, and there is no way for a small project to satisfy it: **batch files cannot be code-signed at all.** Signing requires a PE executable.

### What works

**Option A — unblock the ZIP first (recommended).** See the short version above. This resolves it for most people.

**Option B — unblock after extracting.** Open PowerShell in the extracted folder and run:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

**Option C — run it from a terminal.** SAC's blocking is largely enforced through the Explorer shell. Opening PowerShell in the folder and running the script directly usually proceeds:

```powershell
cd "C:\path\to\OIS-Update-dev"
.\Patch_OIS.bat
```

**Option D — move the folder out of Downloads.** Some policies apply more aggressively to the Downloads folder. Moving the extracted folder to, for example, `C:\Games\OIS-Patch` and running it there can be enough on its own.

### What we do not recommend

Turning Smart App Control off. It can be disabled under **Windows Security → App & browser control → Smart App Control settings**, but be aware of what that costs you: **once SAC is turned off it cannot be turned back on without reinstalling Windows.** That is a permanent, system-wide reduction in protection, and it is a wildly disproportionate price for running one patch. Use Options A through D instead.

### Deciding whether to trust this

You should not run scripts from the internet just because a README tells you to. Everything here is auditable before you run it:

- `Patch_OIS.bat`, `OIS_Health_Check.bat` and `Make_Manifest.bat` are plain text. Open them in Notepad and read them.
- The DLLs are builds of well-known open source libraries. `manifest.txt` lists a SHA256 for each one, and you can check any of them yourself:

  ```
  certutil -hashfile "libcurl.dll" SHA256
  ```

- Nothing runs in the background. Nothing is installed outside the game folder unless you accept the optional repair shortcut.

---

## Antivirus warnings on the DLLs

Some engines flag freshly compiled builds of networking libraries — `libcurl.dll`, `websockets.dll`, `libcrypto-*.dll` — purely because they are unsigned and rare. This is a reputation heuristic, not a detection of anything malicious.

If your antivirus quarantines a file, verify its SHA256 against `manifest.txt` and, if it matches, restore it and add an exclusion for the game folder. If it does **not** match, do not use it — tell us on the Steam thread.

---

## Running the patch

```
Patch_OIS.bat                 normal install
Patch_OIS.bat -debug          adds per-file comparison detail
Patch_OIS.bat "D:\SteamLibrary\steamapps\common\Objects in Space"
```

The installer finds Steam automatically, including libraries on other drives. Pass the path yourself only if detection fails.

It keeps a copy of your pre-patch DLLs in a `Backup` folder next to the script, taken the first time it sees each file, so that folder holds true originals even after several runs.

---

## After Steam verifies your game files

Steam's **Properties → Installed Files → Verify integrity of game files** restores every vanilla DLL and silently undoes the patch. Steam has no knowledge of it and treats the updated libraries as corrupted.

Accept the **"Repair Objects in Space Patch"** shortcut when the installer offers it. If Steam ever reverts things, one click puts them back. It works offline, from a copy of the package kept in your own AppData, so it keeps working after you delete your Downloads folder.

To create it later:

```
OIS_Health_Check.bat -install-shortcut
```

To check without changing anything, run `OIS_Health_Check.bat` with no arguments.

---

## Uninstalling

Copy the contents of the `Backup` folder back into your game folder, or use Steam's verify integrity — which, for once, is exactly the tool you want.

Then remove the extras:

```
OIS_Health_Check.bat -remove-shortcut
netsh advfirewall firewall delete rule name="OIS_Client_Block_Inbound"
netsh advfirewall firewall delete rule name="OIS_Server_Block_Inbound"
```

The two `netsh` lines need an administrator command prompt.