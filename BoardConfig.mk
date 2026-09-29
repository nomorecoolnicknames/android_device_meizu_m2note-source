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

# This product uses a pinned prebuilt kernel.
# Android 13 additionally requires working BPF and cgroup support; a kernel image alone is not a boot guarantee.
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

# The para partition holds the bootloader control block; it is not a partition named misc.
AB_OTA_UPDATER := false
BOARD_USES_RECOVERY_AS_BOOT := false

# No system_ext / product partitions on this GPT — fold them into /system.
TARGET_COPY_OUT_SYSTEM_EXT := system/system_ext
TARGET_COPY_OUT_PRODUCT := system/product

# Keep vendor HAL and firmware inputs specific to the M2 Note stock baseline.
TARGET_COPY_OUT_VENDOR := vendor
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_PARTITION_SIZE := 536870912

# Full Treble + VNDK (owner's directive 2026-09-24: "all of them Treble",
# same shape as m95).  Until 2026-09-24 this block said "VNDK stays OFF" — a
# change of direction from the LOS 15.1 tree, which had set
# BOARD_VNDK_VERSION := current and never reached full Treble (TRB-FULL =
# "error" in the 2026-07-06 matrix: no /vendor/etc/vintf/manifest.xml, Q/R GSIs
# died early; M2NOTE_SUBSYSTEM_STATUS_2026-07-06.md via factbase §3.2).  The
# reason given then still holds — these are Marshmallow blobs with no VNDK
# compliance — and it is now paid on the vendor side.  Measured before the
# switch (meizu-fleet/tools/treble_blob_audit.py over m2note-vendor-blobs.mk
# against the VNDK 33 lists of the m95 build): 818 of 879 vendor ELFs have an
# unresolved DT_NEEDED closure in the vendor or sphal namespace, 111 missing
# sonames; the vendor copies in device.mk bring that to 591 / 108.  The rest is
# the shim lane — designs/TREBLE_M5S_M2NOTE_20260924.md §4.  The first
# manifest failure named above is closed here (DEVICE_MANIFEST_FILE, and
# manifest.xml now carries a target-level and every served HAL).
#
# PRODUCT_FULL_TREBLE_OVERRIDE: PRODUCT_SHIPPING_API_LEVEL is not set, so
# nothing turns Treble on by itself.  It also switches
# PRODUCT_ENFORCE_VINTF_MANIFEST on (build/make/core/config.mk:684-693), and
# with it libhidl refuses to register any HIDL service the device manifest does
# not declare as hwbinder (system/libhidl/transport/ServiceManagement.cpp:
# 851-862) — see manifest.xml.
PRODUCT_FULL_TREBLE_OVERRIDE := true

# VNDK "current" (= 33), the same value m95 ships.  NOT 30: m95 tried
# BOARD_VNDK_VERSION := 30 first and rejected it on two hard soong walls
# (vendor apexes in hardware/interfaces, and a vendor_snapshot module this
# workspace does not have) — device/meizu/m95/BoardConfig.mk "Treble + VNDK 30".
# m95's PRODUCT_EXTRA_VNDK_VERSIONS := 30 is NOT carried over: it exists there
# only to boot the new system against an already-built v30 vendor.img; the only
# vendor ever built for this device is the 15.1 one (VNDK 27), and /system here
# has no room to spare (1536 MiB, see the report's size section).
BOARD_VNDK_VERSION := current

# SELinux split follows PRODUCT_FULL_TREBLE (PRODUCT_SEPOLICY_SPLIT, same
# config.mk block): the vendor image gets vendor_sepolicy.cil built from
# system/sepolicy/vendor plus BOARD_VENDOR_SEPOLICY_DIRS.  No device policy is
# carried yet (runtime is permissive via cmdline); the device dir is the place
# for it when the rc lane lands.

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
