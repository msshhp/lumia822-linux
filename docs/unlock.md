# Bootloader unlock (Spec A, written from inside Windows 10 Mobile)

> [!CAUTION]
> This writes the phone's primary boot loaders (SBL2, SBL3, UEFI) and partition table. The Lumia 822
> (RM-845) has **no public emergency (EDE) flash loader** - its root key hash is
> `A0AE29AC24C843250D2DD0FFD409A649B4E4A09ED3B1A78413FB2B94B7476AAB` - so a bad write that only shows up
> after a reboot is a **permanent brick**. Done once on one phone, successfully. No warranty.
> If anything differs from what is described here, stop.

## Why not just use WPinternals?

WPinternals unlocks Spec A phones (MSM8960) by flashing patched boot loaders through the phone's
emergency download mode, which needs an emergency loader signed for the phone's root key hash. None is
public for the RM-845. The same images can be written from inside Windows instead: Windows 10 Mobile lets a
SYSTEM process open `\\.\PhysicalDrive0` for raw writes.

**Never run the WPinternals GUI "Unlock bootloader" on this phone.** Its `RestoreBackupPartitions`
step re-points TZ, WINSECAPP, UEFI and RPM at the `BACKUP_*` partitions, which on the tested phone held
**older** copies than the primaries, and its EFIESP step installs a Windows Phone 8.1 EFIESP that breaks W10M.

## What you need

| Input | Where from |
|---|---|
| FFU for your phone | e.g. `RM845_3051.50009.1446.0077_RETAIL_nam_usa_100_77_460421_prd_signed.ffu` (Lumia firmware archives). Check that the FFU's SBL1/2/3, UEFI, TZ and RPM are byte-identical to your phone's (from the dump below) before using it. |
| Lumia 822 **engineering SBL3** | `Engineering-SBL3-Lumia-822.bin`, circulated in the WPinternals community. Not distributed here. |
| WPinternals source | `git clone https://github.com/ReneLergner/WPinternals external/WPinternals` (tested at commit `d270cace796bfe74d1719ba3201bddadb3c508dd`). Its `WPinternals/Assets/SBA` is the Secure-Boot-off UEFI variable store. |
| Tools | `tools/windows/disktool.c` (raw disk read/write with read-back verify), `tools/dotnet/imggen` |

### Phone access

1. Developer mode, Device Portal and Device Discovery on. Pair from the PC (Device Portal in a browser at
   `https://<phone IP>`, or with curl) and sideload apps through Device Portal's app manager.
2. **Interop Tools** (v2.1.24): This Device -> Interop Unlock -> Interop/Cap Unlock. Then in its registry
   editor `HKLM\SOFTWARE\Microsoft\MTP`: set `DataStore` = `C:\` and add REG_SZ `MTPDataStore` = `C:\`;
   reboot. Explorer now shows the whole `C:` drive over USB (MTP), incl. `EFIESP` and `Data`.
   `tools/windows/mtp.ps1` (ls/get/put/rm) scripts that.
3. **CMD Injector** (v4.0.6.0): while the app is open, `cmd.exe` runs as SYSTEM on TCP port 9999.
   `tools/windows/pcmd.ps1` / `pr.sh` send commands (set `LUMIA_WP_IP` to the phone's Wi-Fi IP).
   Keep the phone on the charger with the lock screen timeout at "never": the shell dies when it sleeps.
4. Build the phone tools (ARM32 Windows, kernel32 only, unsigned - Windows 10 Mobile runs them as SYSTEM
   from CMD Injector) with llvm-mingw:

```bash
CC=$LLVM_MINGW/bin/armv7-w64-mingw32-clang.exe; RT=$($CC -print-libgcc-file-name)
$CC -O2 -nostdlib -ffreestanding -fno-builtin -Wl,--entry=mainCRTStartup -Wl,--subsystem,console \
    -o disktool.exe tools/windows/disktool.c -lkernel32 "$RT"
$CC -O2 -nostdlib -ffreestanding -fno-builtin -Wl,--entry=mainCRTStartup -Wl,--subsystem,console \
    -o recv.exe tools/windows/recv.c -lkernel32 -lws2_32 "$RT"
```

Copy both to `C:\Data\Users\Public\Downloads` on the phone (MTP).
`disktool gpt 0` lists partitions, `disktool read 0 <lba> <count> <file>` dumps,
`disktool write 0 <lba> <file>` writes with `FILE_FLAG_NO_BUFFERING|WRITE_THROUGH`, reads back,
compares, and returns non-zero on mismatch.

## 1. Back up

```
disktool.exe read 0 0 34 C:\Data\Users\Public\Downloads\gpt0.bin
disktool.exe read 0 32768 70144 C:\Data\Users\Public\Downloads\sblarea.bin
bcdedit /export C:\Data\Users\Public\Downloads\BCD.backup
```

Copy them to the PC and keep them (with SHA-256 sums). `sblarea.bin` covers LBA 32768-102911
(SBL1/2/3, UEFI, NV areas).

## 2. Generate the images

```bash
# full 0..102911 image from the two dumps
dd if=gpt0.bin of=lba0_102912.img bs=512 && dd if=sblarea.bin of=lba0_102912.img bs=512 seek=32768 conv=notrunc
cd tools/dotnet/imggen && dotnet build -c Release
dotnet bin/Release/net8.0-windows/imggen.dll <ffu> lba0_102912.img Engineering-SBL3-Lumia-822.bin <outdir>
```

imggen runs WPinternals' own code (`LumiaV1UnlockFirmware` equivalent):

1. `GPT.InsertHack()` - SBL1 shrinks to end at LBA 35766, a `HACK` partition is added at 35767 and an
   `IS_UNLOCKED_SBL3` marker partition at LBA 64.
2. `SBL1.GenerateExtraSector(SBL2 header)` -> `HACK.bin`.
3. `SBL2.Patch()`, `SBL3.Patch()` (on the engineering SBL3), `UEFI.Patch()` (on the FFU's UEFI).
4. **Deliberately not called:** `GPT.RestoreBackupPartitions()` (see above).

| Image | LBA | Size |
|---|---|---|
| GPT.bin | 0 | 34 sectors (MBR unchanged) |
| HACK.bin | 35767 | 1 sector |
| SBL2.bin | 36864 | 3000 sectors |
| SBL3.bin | 40960 | 342,308 bytes |
| UEFI.bin | 77824 | 5000 sectors |

Check the new GPT with any GPT viewer before going on.

## 3. Stage 1: write SBL2, SBL3, HACK, UEFI, GPT

Put the new images as `new_<NAME>.bin` and the **original** regions (cut from your backup:
`dd if=sblarea.bin bs=512 skip=$((LBA-32768)) count=N`) as `org_<NAME>.bin` into one folder, then:

```powershell
$env:LUMIA_WP_IP = '<phone IP>'
tools\windows\unlock\upload_and_run.ps1 -ImageDir <folder> -Script run_unlock.cmd
```

It uploads everything over MTP, compares every file size on the phone, and runs
[`run_unlock.cmd`](../tools/windows/unlock/run_unlock.cmd) on the phone: each write is verified by
read-back; on any failure all original regions are written back; it never reboots. Log:
`C:\Data\unlock_log.txt`, must end with `ALL_OK`. A harmless first test: rewrite the all-zero sector 35767
with zeros and check `write ok, verified`.

Before rebooting: `disktool.exe gpt 0` must show SBL1 32768-35766, SBL2 with type `7474...`,
HACK 35767, IS_UNLOCKED_SBL3 64, UEFI 77824.

Reboot. Windows must boot normally. (WPinternals in flash mode, "Info" only, then shows
"Platform Secure Boot: False".)

## 4. Stage 2: Secure-Boot-off UEFI variable store

```bash
dotnet bin/Release/net8.0-windows/imggen.dll nv <outdir>/GPT.bin <WPinternals>/WPinternals/Assets/SBA <nvdir>
```

This renames the old `UEFI_BS_NV` (LBA 98304-98815) to `BACKUP_BS_NV` (new GUIDs) and adds a new
`UEFI_BS_NV` with the original type and GUID at 98816-99327 (an unused, all-zero gap on the tested
phone - check yours), plus the decompressed SBA store `SBA_NV.bin`. Only this first half of WPinternals'
`LumiaUnlockUEFI` is done; its EFIESP replacement is skipped.

Put `SBA_NV.bin`, `GPT_NV.bin` and the stage-1 `new_GPT.bin` (rollback) in a folder:

```powershell
tools\windows\unlock\upload_and_run.ps1 -ImageDir <folder> -Script run_nv.cmd
```

[`run_nv.cmd`](../tools/windows/unlock/run_nv.cmd) writes SBA_NV@98816 then GPT_NV@0, and on failure
writes the stage-1 GPT back. To undo stage 2 later, write the stage-1 GPT back to LBA 0.

Reboot. Windows still boots, and now `bcdedit /set {bd8951c4-eabd-4c6f-aafb-4ddb4eb0469b} testsigning on`
succeeds - continue with [install.md](install.md#3-point-the-volume-down-boot-entry-at-the-loader).

## Lessons

- Claude Code's (or any agent's) safety rules may refuse raw boot-area writes - run the write step yourself.
- MTP drops the phone storage when the screen locks; CMD Injector's shell dies when the phone sleeps.
- **Settings -> Reset this phone wipes the phone**; Interop Tools/MTP/CMD Injector must then be set up again.
