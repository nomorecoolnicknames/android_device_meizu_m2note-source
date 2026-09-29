# Meizu M2 Note: LineageOS 18.1

Device configuration, init rules, SELinux policy and compatibility code for Android 11.
Place this tree at `device/meizu/m2note` in the matching LineageOS source tree.

The build requires the referenced common and MediaTek platform trees, matching kernel
source/headers and prebuilt image where selected, and this board’s proprietary inputs.
Use `proprietary-files.txt`, dependency manifests and kernel checks provided by this branch.
Prebuilt firmware and complete ROM images are not supplied by this repository.

After providing those inputs, select `lunch lineage_m2note-userdebug`.
These sources remain under development; compiling them does not certify all hardware
or establish a tested installable release.

Retain the copyright and license notices in individual files.
