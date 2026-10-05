# Meizu M2 Note · Android 9

Device configuration for **Meizu M2 Note (m2note, MT6753)**. Branch: **`lineage-16.0`**.

**Status:** development sources; a complete ROM built from this public branch has not been validated on the device.

## Components

**Source / integration** describes what this tree provides; **working status** describes tests, not file presence. Unverified does not mean unsupported hardware.

| Subsystem | Implementation / source | Source / integration | Working status |
|---|---|---|---|
| Boot / partitions | [Board configuration](BoardConfig.mk); [Kernel checksum](prebuilt-kernel/EXPECTED.txt) | Source-built native 3.18.19 kernel with own DTB required | Not tested on this branch |
| Display / composition | [MTK HWC](hwcomposer/hwcomposer.cpp) | HWC source; vendor gralloc/GPU libraries required | Not tested on this branch |
| GPU | [Graphics packages and ABI integration](device.mk) | Vendor Mali userspace; kernel GPU driver lives in the kernel tree | Not tested on this branch |
| Touch / buttons | [Input integration](device.mk) | Kernel input driver plus Android layouts | Not tested on this branch |
| Wi-Fi | [MTK Wi-Fi integration](BoardConfig.mk) | MTK transport / firmware and supplicant integration | Not tested on this branch |
| Bluetooth | [HCI / vendor integration](libbt-vendor/libbt-vendor-mtk.c) | Custom service or vendor interface | Not tested on this branch |
| Mobile network | [Radio packages and properties](device.mk) | RIL integration; proprietary modem firmware remains required | Not tested on this branch |
| Camera | [Camera packages / wrapper](device.mk) | Legacy vendor camera HAL; no complete open camera driver stack | Not tested on this branch |
| Audio output / microphone | [Audio integration](device.mk) | Vendor primary HAL with compatibility support | Not tested on this branch |
| Sensors | [Sensor services and permissions](device.mk) | Vendor sensor HAL; declared sensors still need individual tests | Not tested on this branch |
| GPS / GNSS | [GNSS integration](device.mk) | Legacy vendor GPS HAL | Not tested on this branch |
| Power / charging / suspend | [Power and health integration](device.mk) | Android services plus board-specific kernel drivers | Not tested on this branch |
| SELinux | [Security / boot settings](BoardConfig.mk) | Development configuration | Enforcing operation not validated |

## Native kernel

This branch selects native MT6753 Linux 3.18.19 at [`be248340`](https://github.com/ReMeizu/android_kernel_meizu_mt6753/commit/be24834072fcafa234e61092b7f8b6a0f60a5b78), with own DTB and ashmem seek support. Kernel source: [`m2note-3.18-native`](https://github.com/ReMeizu/android_kernel_meizu_mt6753/tree/m2note-3.18-native), `m2note_defconfig`. The full Android 9 userdebug ROM completed compilation on 2 October 2026; its ZIP/boot/signature/identity checks passed. Physical boot and component operation remain untested for this kernel/userspace pair.

## Building

Use a matching LineageOS 16.0 source checkout, with this tree at `device/meizu/m2note`. Required inputs:

- The matching vendor tree, firmware, board configuration files and platform compatibility changes. This repository alone is not a complete ROM checkout.
- A board-specific `prebuilt-kernel/Image-native-318.gz-dtb` matching [EXPECTED.txt](prebuilt-kernel/EXPECTED.txt). The kernel binary is not included; [the checksum check](tools/check_prebuilt_kernel.sh) rejects a missing or different input.
- Referenced device files absent from this export, including `keylayout/ACCDET.kl`, `keylayout/AVRCP.kl`, `keylayout/Vendor_2454_Product_6500.kl`. Restore the matching inputs before building.

With those inputs in place, the product is:

```sh
source build/envsetup.sh
lunch lineage_m2note-userdebug
mka bacon
```

The matching Android 9 userdebug checkout completed a full ROM. The public repository omits kernel binaries and restricted vendor/board inputs; restore those exact inputs before building. Artifact acceptance does not establish hardware support.

## Next steps

Restore the documented external inputs for independent rebuilds, then validate boot, recovery and each subsystem on the device.

The [ReMeizu overview](https://github.com/nomorecoolnicknames/remeizu/blob/main/PROJECT_STATUS.md) tracks the whole device family; the [source index](https://github.com/nomorecoolnicknames/remeizu/blob/main/SOURCE_INDEX.md) links related device, common and kernel trees.

## Credits

Based on Android, CyanogenMod / LineageOS and MediaTek device support, with contributors retained in Git history. Keep the original copyright and license notices. Vendor firmware and libraries are separate inputs with their own licenses.
