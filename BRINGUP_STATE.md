# m2note: Android 11 staging, 2026-09-28

Category: **PROPER-FIX** (release-specific product wiring). Not a working ROM.
Derived from this board's own A13 `lineage-20-treble` commit `8ae817b`; no sibling
board image, panel, touch, fstab, partition size or calibration was substituted.
Original detailed board provenance remains in that parent commit.

FACT: 1080x1920, boot 16 MiB, recovery 20 MiB, system 1536 MiB; vendor/custom 512 MiB; arm64 plus arm userspace. Kernel: 3.18.19 #108, sha256 87f5ec53f1bd49cee96a7cdf0cfab25fc0f6e663d56f2e0b9fa95361a07f4080; historical Android 8.1 only.
M2 Note historical boot does not establish working MD1: source
`ccci_util_lib_fo.c:524-530` clears MD_SYS1 with `m2note.disable_md1=1`.
Current product cmdline does not set that isolation flag.

## Patch history

- Hypothesis: an absent A11 target and A13-only service identifiers prevent a
  meaningful A11 source/build lane before any board runtime test.
- Evidence: selected platform is `/srv/forge/android/nx549j/rom-nx549j-lineage-18.1-tissot`,
  SDK literal 30, manifest Android 11 r46 / lineage-18.1. Actual modules are
  Keymaster 3.0 (`hardware/interfaces/keymaster/3.0/default/Android.mk`), ClearKey 1.3
  (`frameworks/av/drm/mediadrm/plugins/clearkey/hidl/Android.bp:100`), Wi-Fi 1.4
  implementation service named `android.hardware.wifi@1.0-service`.
  Supplicant `android.config:332` enables HIDL; Android.mk:1516 chooses 1.3.
- Files / why: `device.mk` selects those actual modules plus the vendor tinycompress
  dependency; `manifest.xml` declares Keymaster 3.0; own Wi-Fi rc declares HIDL
  ISupplicant 1.0..1.3 (no A13 AIDL name). `lineage_m2note.mk` rejects non-SDK30 builds.
  `BoardConfig.mk` keeps the exact prebuilt but provides this board's kernel source
  for A11 `generated_kernel_headers`; `TARGET_FORCE_PREBUILT_KERNEL=true` preserves
  the selected boot image (vendor/lineage/build/tasks/kernel.mk:168-184).
- Kernel header source: /srv/forge/android/m2note/kernel-m2note-3.18-adapt @795d85dc2278036aa7c69541127c5eb2450343d4.
  Recipe must pin the actual working tree, including local changes; this source
  path is an explicit read-only overlay in `targets/android/m2note-a11.json`.
- Expected next marker: SDK30 product parse and headers generation succeed, then
  both audio dependencies link; HIDL service names agree with their manifests.
- Rollback condition: actual SDK30 Make/Soong or VINTF reports incompatible modules;
  keep the failing evidence and repair the specific module, not relaxed checks.
- Verification: fleet source checker for `m2note-a11.json`, XML parse; then Forge-only
  `m nothing`, `libtinycompress`, selected HAL targets. No build completed yet.

## Open board blockers

The selected historical 3.18 kernel lacks the modern BPF/cgroup prerequisites; A11 kernel/runtime compatibility is unproven. SIM remains unknown even after firmware pairing. Legacy android_usb uses the board-specific FunctionFS setup described below; runtime remains untested.
Graphics/GPU, camera, RIL, SELinux and vendor symbol closure remain unvalidated.

## Validation boundary

Source inspection and hash checks only on 2026-09-28. No matching immutable Android
11/13 build image is currently available to this lane; Docker was not launched.
No phone was accessed. No ROM image was produced or booted. `m nothing` and an
artifact manifest with identity-bound runtime evidence remain required.

## Next falsifiable gates

1. Pin the platform project revisions and the exact source/blob/header inputs in
   a Forge ephemeral recipe; output only under `/mnt/ramdisk` with a unique OUT.
2. Run product parse, selected HAL modules, then image targets when RAM is reserved.
3. Verify ELF closure, VINTF, boot header and raw artifact hashes before a separately
   authorized test. Static file existence is not module ABI or board readiness.
4. Never inspect `/proc/aed/current-*` on M2 Note. Use preserved host logs / expdb.

## M2 Note USB source correction (PROPER-FIX)

Hypothesis: selecting configfs for the pinned legacy android_usb kernel and omitting
FunctionFS setup prevents the intended adb path. Evidence: m2note_defconfig and
historical `/home/n8n/m5s_out/m2note_check/.config` have CONFIG_USB_G_ANDROID=y and
no USB_CONFIGFS. Own A9 rootdir/init.mt6735.usb.rc:23-28 mounts FunctionFS and sets
f_ffs/aliases. AOSP system/core/rootdir/init.usb.rc retains legacy configfs=0
triggers, but does not mount this board's adb FunctionFS filesystem.

Files/why: device.mk selects sys.usb.configfs=0 and installs only the board's
FunctionFS setup as vendor init rc; new init.m2note.usb.rc contains those four
existing board actions. It does not redefine adbd or generic USB transitions.
Expected marker: /dev/usb-ffs/adb is mounted and adb enumerates after boot.
Rollback: duplicate FunctionFS mounts in a generated image or a proven different
gadget ABI in the selected kernel. Verification: inspect generated init rc and
exact kernel config before a separately authorized boot. Runtime untested.
