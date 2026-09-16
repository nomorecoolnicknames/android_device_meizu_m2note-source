#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# BoardConfig.mk — Meizu M2 Note (m2note, M571), MT6753, arm64, 2 GB RAM.
# LineageOS 20.0 (Android 13, SDK 33) staging skeleton.
#
# Method follows the m5c lane (meizu-fleet/trees/M5C_LOS20_TREE.md).  The m2note
# differs from its two siblings in one important way: it is the only one of the
# three that has actually BOOTED a forge ROM recently, so most numbers here are
# live readouts of this handset rather than values carried from a sibling.
#
# THE ONE THING TO KNOW FIRST: Android 13 will not start on the kernel this
# tree ships.  3.18 has no BPF_SYSCALL and no CGROUP_BPF.  See
# prebuilt-kernel/PROVENANCE.md §3 and lineage_m2note.mk.

DEVICE_PATH := device/meizu/m2note

# LineageOS kernel/soong plumbing.
include vendor/lineage/config/BoardConfigLineage.mk

# ---------------------------------------------------------------------------
# Architecture
# ---------------------------------------------------------------------------
# MT6753 = octa Cortex-A53, ARMv8.0-A.  Same reasoning as the m5s tree:
# FACT (build/soong/cc/config/arm64_device.go:29-42, 54-58): armv8-a ->
# -march=armv8-a (no +lse), cortex-a53 -> -mcpu=cortex-a53; no
# -moutline-atomics anywhere in soong's arm64 config.
# FACT (build/soong/android/arch_list.go:21-28): armv8-a is still a legal
# arm64 AND arm variant in Android 13.  No ARMv8.1, no LSE.
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53
TARGET_CPU_VARIANT_RUNTIME := cortex-a53

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a53

# The blob set is 32/64 mixed (1110 files under vendor/meizu/m2note/proprietary,
# lib/ 428 and lib64/ 336), and the MTK daemons ccci_fsd, ccci_mdinit,
# gsm0710muxd, mnld, nvram_daemon, init_thh exist only as 32-bit binaries.
# ro.zygote=zygote64_32 comes from core_64_bit.mk.
TARGET_USES_64_BIT_BINDER := true

# ---------------------------------------------------------------------------
# Platform
# ---------------------------------------------------------------------------
# FACT (live getprop from the running LOS 15.1, capture
# export/m2note_flash_captures/runtime/v212_live_20260620-080956/getprop.txt):
#   [ro.board.platform]: [mt6753]
#   [ro.hardware]:       [mt6735]
#   [ro.hardware.gps]:   [m2note]
#   [ro.sf.lcd_density]: [420]
# ro.board.platform and ro.hardware are different strings and both matter.
TARGET_BOARD_PLATFORM := mt6753
TARGET_BOOTLOADER_BOARD_NAME := mt6753
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
BOARD_NAME := m2note
BOARD_USES_MTK_HARDWARE := true
MTK_HARDWARE := true

TARGET_OTA_ASSERT_DEVICE := m2note,M571

# ---------------------------------------------------------------------------
# Kernel — PREBUILT 3.18, and it is a PLACEHOLDER
# ---------------------------------------------------------------------------
# Full provenance, including the four-way sha256 chain that proves this exact
# image booted this exact handset, is in prebuilt-kernel/PROVENANCE.md.
# Summary:
#   md5      c98b27fec7f9452420f15bab39973ea1
#   sha256   87f5ec53f1bd49cee96a7cdf0cfab25fc0f6e663d56f2e0b9fa95361a07f4080
#   size     7 654 977 B
#   version  Linux version 3.18.19+ (n8n@n8nagent) #108 SMP PREEMPT
#            Thu Jun 18 11:02:00 CDT 2026
#   source   export/m2note_flash_captures/runtime/
#            v181_15.1_v178_regdump_20260618-121109/
#            boot-after-v181-v178-readback-p9-16m.img  (kernel section)
#
# *** ANDROID 13 WILL NOT BOOT ON THIS KERNEL. ***
# FACT: "# CONFIG_BPF_SYSCALL is not set" in the config of this 3.18 line
# (/home/n8n/m5s_out/m2note_check/.config:165), and CONFIG_CGROUP_BPF is not
# even a symbol in this kernel — grep over
# /srv/forge/android/m2note/kernel-m2note-3.18-adapt/init/Kconfig finds
# "config BPF_SYSCALL" at :1529 and nothing for CGROUP_BPF.  cgroup-BPF is a
# 4.10 feature.  Compare the m5s 4.9, whose init/Kconfig:1281 does define it
# and whose built config has CONFIG_CGROUP_BPF=y.
# INFERENCE: A13 netd/bpfloader needs both; without them boot stops before
# zygote.  The fix is a kernel port, not a tree change.
#
# FACT (appended-DTB gate, run on the copy in this tree):
#   DTB at offset 7 587 015, 67 962 B, md5 8b477a6c3c16eb6ea20288de272cd10c,
#   sha256 33a8779d0dd68e134b19ac4ff922c4b6d5e219e677087c5ad8885490653bc980;
#   key counts "mt6753-mmc" = 2, "mediatek,msdc\0" = 0.
# NOTE that this is NOT the m5c rule restated.  On m5c the project insists on
# the byte-identical STOCK DTB because that tree's own DTS spells the eMMC node
# "mediatek,msdc" while the driver binds "mediatek,mt6735m-mmc".  The m2note
# kernel tree has no such defect: FACT,
#   kernel-m2note-3.18-adapt/arch/arm64/boot/dts/mt6753.dtsi:37,45
#   compatible = "mediatek,mt6753-mmc"
# so a tree-built DTB is already correct here — and the DTB in the proven boot
# image is exactly that.  Do not copy the m5c "stock DTB only" rule onto this
# device without re-deriving it.
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_SOURCE :=
TARGET_KERNEL_CONFIG :=
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt-kernel/Image.gz-dtb
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb

forge_kernel_check := $(shell $(DEVICE_PATH)/tools/check_prebuilt_kernel.sh \
        $(TARGET_PREBUILT_KERNEL) $(DEVICE_PATH)/prebuilt-kernel/EXPECTED.txt)
ifneq ($(strip $(forge_kernel_check)),)
$(error $(forge_kernel_check))
endif

# Boot geometry — read out of the header of the image that demonstrably booted
# this handset (and cross-checked against three other readbacks of p9 plus the
# 2026-05-30 full-partition dump; all agree):
#   kernel_addr  0x40080000   ramdisk_addr 0x44000000
#   second_addr  0x40f00000   tags_addr    0x4e000000
#   pagesize     2048         board name   "m2note"
# The LOS 15.1 tree expressed this as --base 0x40078000 with compensating
# offsets; the canonical decomposition below yields the SAME absolute
# addresses.  The MTK loader jumps exactly where the header says — on the m5c,
# mixing a 0x40078000 base with the wrong offsets put the kernel 0x78000 off
# and it never ran at all.
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_OFFSET := 0x00080000
BOARD_RAMDISK_OFFSET := 0x04000000
BOARD_KERNEL_TAGS_OFFSET := 0x0e000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_MKBOOTIMG_ARGS := \
    --kernel_offset $(BOARD_KERNEL_OFFSET) \
    --ramdisk_offset $(BOARD_RAMDISK_OFFSET) \
    --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) \
    --board m2note
#
# cmdline.  FACT, from the proven image's own header:
#   bootopt=64S3,32N2,64N2 firmware_class.path=/system/vendor/firmware
#   androidboot.selinux=permissive
# Two changes here:
#  * firmware_class.path moves to /vendor/firmware, because this tree puts
#    /vendor on a REAL partition instead of inside /system (see below).
#  * androidboot.hardware=mt6735 is spelled out.  The live cmdline gets it from
#    the DTB /chosen node (FACT: capture v194 identity.txt shows
#    "androidboot.hardware=mt6735" in /proc/cmdline while the boot.img header
#    does not carry it), and relying on the DTB for something init needs to find
#    fstab.mt6735 is a dependency worth making explicit.
# buildvariant= is appended by build/make automatically — do not set it here.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 firmware_class.path=/vendor/firmware androidboot.selinux=permissive androidboot.hardware=mt6735

# ---------------------------------------------------------------------------
# Partitions — A-only, no slots, no dynamic partitions
# ---------------------------------------------------------------------------
# All of this is a LIVE readout of THIS handset, not a scatter and not a
# sibling's numbers.
#
# FACT, by-name map (recovery session 2026-05-30,
# export/m2note_flash_captures/manual-recovery-after-black-screen-20260530-120901/
# recovery/by-name.txt):
#   p1 proinfo  p2 nvram   p3 devinfo  p4 rstinfo  p5 protect1  p6 protect2
#   p7 lk       p8 para    p9 boot     p10 recovery p11 logo    p12 expdb
#   p13 seccfg  p14 oemkeystore p15 secro p16 keystore p17 tee1 p18 tee2
#   p19 custom  p20 frp    p21 nvdata  p22 metadata p23 system  p24 cache
#   p25 userdata p26 flashinfo
# NOTE how different this is from m5c/m5s (para=p6, boot=p7, recovery=p8,
# expdb=p10, custom=p17).  Never carry partition numbers between these devices.
#
# FACT, sizes (same session, recovery/proc_partitions.txt, KiB):
#   p8 para 3072   p9 boot 16384   p10 recovery 20480   p12 expdb 10240
#   p19 custom 524288   p20 frp 1024   p21 nvdata 32768   p22 metadata 39168
#   p23 system 1572864  p24 cache 409600  p25 userdata 12531200
#   p26 flashinfo 16384 ; mmcblk0 15267840 KiB = 14.56 GiB (16 GB class)
#
# FACT, the same three big ones at sector granularity from an sgdisk print
# (GSI_REPARTITION_PLAN_2026-07-03.md, "Current hard facts"):
#   23 system   start=1474560 end=4620287  3145728 sectors = 1 610 612 736 B
#   24 cache    start=4620288 end=5439487   819200 sectors =   419 430 400 B
#   25 userdata start=5439488 end=30501887 25062400 sectors = 12 831 948 800 B
#
# TWO CONTRADICTIONS WITH THE LOS 15.1 TREE, resolved in favour of the device:
#  1. board/filesystem.mk of that tree says
#     BOARD_RECOVERYIMAGE_PARTITION_SIZE := 23068672 (22 MiB).  The device says
#     p10 = 20480 KiB = 20 971 520 B (20 MiB).  20 MiB is used here.  A recovery
#     image built to 22 MiB would not fit the partition.
#  2. That tree says BOARD_USERDATAIMAGE_PARTITION_SIZE := 10737385472
#     (10 GiB).  The device says 12 831 948 800 B.  The device wins.
BOARD_BOOTIMAGE_PARTITION_SIZE := 16777216
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 20971520
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 1610612736
BOARD_CACHEIMAGE_PARTITION_SIZE := 419430400
BOARD_USERDATAIMAGE_PARTITION_SIZE := 12831948800
BOARD_FLASH_BLOCK_SIZE := 131072

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USES_MKE2FS := true
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4

# A-only.  Install path on this device is TWRP sideload; the project rule is
# "sideload only, never `adb shell dd`" because the PTY mangles the stream
# (FACT: HANDOFF_NEXT_AGENT.md:216-232).
# FACT worth keeping next to the partition table: forced recovery on m2note is
# the BCB flag "boot-recovery" in `para` = mmcblk0p8, NOT in a partition called
# misc, and it is cleared with dd if=/dev/zero bs=1 count=32.
AB_OTA_UPDATER := false
BOARD_USES_RECOVERY_AS_BOOT := false

# No system_ext / product partitions on this GPT — fold them into /system.
TARGET_COPY_OUT_SYSTEM_EXT := system/system_ext
TARGET_COPY_OUT_PRODUCT := system/product

# ---------------------------------------------------------------------------
# Vendor partition / VNDK
# ---------------------------------------------------------------------------
# Decision: REAL /vendor on custom (p19), VNDK OFF.
#
# FACT: custom = mmcblk0p19, 524 288 KiB = 512 MiB (by-name.txt +
#   proc_partitions.txt above).
# FACT: the LOS 15.1 port already mounts it as /vendor — "/custom mounted as
#   /vendor" (HANDOFF_NEXT_AGENT.md:30), and the 15.1 BoardConfig carries
#   TARGET_COPY_OUT_VENDOR := vendor with the same 512 MiB size.
# FACT: the blob payload carried here is 363 MiB / 1110 files, which fits
#   512 MiB with ~150 MiB of slack.  (This is tighter than on the m5s, whose
#   set is 240 MiB — m2note's camera and modem sets are much larger.)
TARGET_COPY_OUT_VENDOR := vendor
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_PARTITION_SIZE := 536870912

# VNDK stays OFF — and this IS a change of direction from the LOS 15.1 tree,
# so the reason is spelled out rather than assumed.
#
# The 15.1 tree set BOARD_VNDK_VERSION := current and aimed at full Treble.
# FACT: that goal was never reached.  The 2026-07-06 subsystem matrix records
# TRB-FULL as "error": no /vendor/etc/vintf/manifest.xml, and Q/R GSIs died
# early in boot (M2NOTE_SUBSYSTEM_STATUS_2026-07-06.md via factbase §3.2).
# FACT: the blob set is Marshmallow-era MTK, the same generation whose vendor
# ELFs link framework-only libraries; on the m5c that measured 134 of 403 ELFs,
# and every one of them fails at the linker inside a VNDK namespace
# (M5C_LOS16_TREBLE_PLAN.md §6.2).
# FACT (build/make/core/config.mk:721-737): with PRODUCT_SHIPPING_API_LEVEL and
# PRODUCT_FULL_TREBLE both unset, leaving BOARD_VNDK_VERSION undefined is legal
# in A13 and selects the pre-VNDK linking model.
# A vendor PARTITION does not require VNDK; the two are independent knobs, and
# this tree takes the partition without the namespace.
PRODUCT_FULL_TREBLE_OVERRIDE := false

# ---------------------------------------------------------------------------
# Boot / root layout
# ---------------------------------------------------------------------------
# A13 init mounts /system and /vendor in first stage from the ramdisk fstab and
# SwitchRoot()s into /system.
# HYPOTHESIS, the largest untested change on this device: that A13 first-stage
# init finds /fstab.mt6735 in the ramdisk root here.  The 15.1 ROM had a
# related failure already — a ramdisk whose init.rc lost
# "import /init.usb.rc" / "start ueventd" and whose init.mt6735.rc lost
# "mount_all /fstab.mt6735" killed adb outright on 2026-07-07, and whether the
# initfix zip repaired it was never recorded (factbase §3.2, open question 3).
# Ramdisk content on this device is a known live wire, not a formality.
BOARD_ROOT_EXTRA_FOLDERS := nvdata protect_f protect_s

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.mt6735
TARGET_RECOVERY_PIXEL_FORMAT := BGRA_8888
TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 1920

# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------
TARGET_SYSTEM_PROP := $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP := $(DEVICE_PATH)/vendor.prop

# ---------------------------------------------------------------------------
# SELinux
# ---------------------------------------------------------------------------
# Permissive at runtime via kernel cmdline, as on the 15.1 build.  FACT worth
# carrying: that build logged 201 unique denials across 29 domains in a single
# boot (M2NOTE_FULL_ROM_ASSESSMENT_2026-07-02.md §3) — the permissive setting
# is load-bearing here, not cosmetic.
SELINUX_IGNORE_NEVERALLOWS := true

# ---------------------------------------------------------------------------
# Seccomp
# ---------------------------------------------------------------------------
BOARD_SECCOMP_POLICY := $(DEVICE_PATH)/seccomp

# ---------------------------------------------------------------------------
# Graphics
# ---------------------------------------------------------------------------
BOARD_EGL_CFG := $(DEVICE_PATH)/configs/egl.cfg
USE_OPENGL_RENDERER := true

# ---------------------------------------------------------------------------
# Wi-Fi — MTK CONSYS MT6735 combo
# ---------------------------------------------------------------------------
BOARD_WLAN_DEVICE := MediaTek
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_HOSTAPD_DRIVER := NL80211
WIFI_DRIVER_STATE_CTRL_PARAM := /dev/wmtWifi
WIFI_DRIVER_STATE_ON := 1
WIFI_DRIVER_STATE_OFF := 0

# ---------------------------------------------------------------------------
# Bluetooth
# ---------------------------------------------------------------------------
BOARD_HAVE_BLUETOOTH := true
BOARD_HAVE_BLUETOOTH_MTK := true
BOARD_BLUETOOTH_DOES_NOT_USE_RFKILL := true

# ---------------------------------------------------------------------------
# VINTF
# ---------------------------------------------------------------------------
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml

# ---------------------------------------------------------------------------
# Build workarounds
# ---------------------------------------------------------------------------
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_PREBUILT_ELF_FILES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_VENDOR_PROPERTY_NAMESPACE := true
