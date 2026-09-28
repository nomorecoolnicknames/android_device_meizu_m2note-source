# m2note: Android 13 source checkpoint, 2026-09-28

Category: **PROPER-FIX** (restore a missing source-built dependency).

## Patch history

- Hypothesis: vendor audio cannot link without `libtinycompress.so` installed.
- Evidence: `readelf -d` on this board's proprietary `vendor/lib{,64}/hw/audio.primary.mt6753.so`
  reports DT_NEEDED `libtinycompress.so`; neither vendor blob list installs it.
  Current `/srv/forge/android/los20/external/tinycompress` HEAD `d155968` uses
  `device_kernel_headers`, defined in `build/soong/Android.bp:49` as `kernel_headers`.
  `cc/kernel_headers.go:27-35` exports configured header directories; it does not
  invoke `generated_kernel_includes`. The optional extended-compress defaults
  only set a cflag (`vendor/lineage/build/soong/Android.bp:342-358`).
- Files / why: `device.mk` restores `libtinycompress` and corrects a stale explanation
  that confused the current header module with `generated_kernel_headers`.
- Expected next marker: built vendor lib and lib64 copies satisfy the audio DT_NEEDED;
  this alone does not imply the HAL wrapper or kernel offload ioctls work.
- Rollback condition: current pinned module graph actually reintroduces a header
  generation dependency or post-link inspection shows ABI mismatch; fix the cause
  instead of marking omitted audio dependencies as ready.
- Verification: `readelf -d <proprietary>/vendor/lib64/hw/audio.primary.mt6753.so`;
  inspect the exact platform module above; build `libtinycompress` in the pinned
  Forge recipe, then ELF-check both vendor ABIs. Build not run here.

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
