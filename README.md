# Meizu M2 Note · Android 11

Device configuration for **Meizu M2 Note (m2note, MT6753)**. Branch: **`lineage-18.1`**.

**Status:** development sources; a complete ROM built from this public branch has not been validated on the device.

## Components

**Source / integration** describes what this tree provides; **working status** describes tests, not file presence. Unverified does not mean unsupported hardware.

| Subsystem | Implementation / source | Source / integration | Working status |
|---|---|---|---|
| Boot / partitions | [Board configuration](BoardConfig.mk); [Kernel checksum](prebuilt-kernel/EXPECTED.txt) | External `Image.gz-dtb` prebuilt required | Not tested on this branch |
| Display / composition | [Composer / mapper services](device.mk) | Legacy vendor HWC through Android wrapper services | Not tested on this branch |
| GPU | [Graphics packages and ABI integration](device.mk) | Vendor Mali userspace; kernel GPU driver lives in the kernel tree | Not tested on this branch |
| Touch / buttons | [Input integration](device.mk) | Kernel input driver plus Android layouts | Not tested on this branch |
| Wi-Fi | [MTK Wi-Fi integration](rootdir/etc/init/init.m2note.wifi.rc) | MTK transport / firmware and supplicant integration | Not tested on this branch |
| Bluetooth | [HCI / vendor integration](device.mk) | Platform wrapper plus vendor Bluetooth libraries | Not tested on this branch |
| Mobile network | [Radio packages and properties](device.mk) | RIL integration; proprietary modem firmware remains required | Not tested on this branch |
| Camera | [Camera packages / wrapper](device.mk) | Legacy vendor camera HAL; no complete open camera driver stack | Not tested on this branch |
| Audio output / microphone | [Audio integration](device.mk) | Vendor primary HAL with compatibility support | Not tested on this branch |
| Sensors | [Sensor services and permissions](device.mk) | Vendor sensor HAL; declared sensors still need individual tests | Not tested on this branch |
| GPS / GNSS | [GNSS integration](device.mk) | Service currently disabled while vendor dependencies are resolved | Not tested on this branch |
| Power / charging / suspend | [Power and health integration](device.mk) | Android services plus board-specific kernel drivers | Not tested on this branch |
| SELinux | [Security / boot settings](BoardConfig.mk) | Development configuration | Enforcing operation not validated |
| Vendor ABI compatibility | [Shim declarations](shims/Android.bp); [Placeholder implementation](shims/stub.cpp) | Partial; placeholder symbols are not functional HAL replacements | Integration incomplete |

## Building

Use a matching LineageOS 18.1 source checkout, with this tree at `device/meizu/m2note`. Required inputs:

- The matching vendor tree, firmware, board configuration files and platform compatibility changes. This repository alone is not a complete ROM checkout.
- A board-specific `prebuilt-kernel/Image.gz-dtb` matching [EXPECTED.txt](prebuilt-kernel/EXPECTED.txt). The kernel binary is not included; [the checksum check](tools/check_prebuilt_kernel.sh) rejects a missing or different input.
- Referenced device files absent from this export, including `configs/agps_profiles_conf2.xml`, `configs/audio/a2dp_audio_policy_configuration.xml`, `configs/audio/audio_device.xml`. Restore the matching inputs before building.
- This branch forces the prebuilt kernel route even though a source path and defconfig are also declared.

With those inputs in place, the product is:

```sh
source build/envsetup.sh
lunch lineage_m2note-userdebug
mka bacon
```

## Next steps

Complete missing build inputs, produce a reproducible ROM, then test boot and each subsystem on this device.

The [ReMeizu overview](https://github.com/nomorecoolnicknames/remeizu/blob/main/PROJECT_STATUS.md) tracks the whole device family; the [source index](https://github.com/nomorecoolnicknames/remeizu/blob/main/SOURCE_INDEX.md) links related device, common and kernel trees.

## Credits

Based on Android, CyanogenMod / LineageOS and MediaTek device support, with contributors retained in Git history. Keep the original copyright and license notices. Vendor firmware and libraries are separate inputs with their own licenses.
