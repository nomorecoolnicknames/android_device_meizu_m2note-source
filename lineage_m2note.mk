#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# lineage_m2note.mk — product definition for the Meizu M2 Note (m2note, M571).
#
# SoC MT6753, octa Cortex-A53 arm64, 2 GB RAM, 1080x1920 (density 420),
# 16 GB eMMC, panel nt35532_fhd_dsi_vdo_sharp.
#
# ===========================================================================
# STATUS — READ BEFORE USING THIS PRODUCT
# ===========================================================================
# ANDROID 13 DOES NOT BOOT ON THIS DEVICE TODAY, and the reason is the kernel,
# not this makefile.
#
# FACT: the m2note runs a 3.18.19 kernel.  Its config has
# "# CONFIG_BPF_SYSCALL is not set", and the symbol CONFIG_CGROUP_BPF does not
# exist in that kernel at all (grep over
# /srv/forge/android/m2note/kernel-m2note-3.18-adapt/init/Kconfig finds
# "config BPF_SYSCALL" at :1529 and nothing for CGROUP_BPF; cgroup-BPF landed
# upstream in 4.10).
# INFERENCE: Android 13's netd starts bpfloader, which needs both the bpf(2)
# syscall and the BPF_CGROUP_INET_* attach points.  Without them netd never
# comes up and nothing past post-fs-data runs.  No device tree can work around
# that.
#
# So this tree is deliberately a *staging* tree: it is where the Android-13
# side of the m2note port (blobs, fstab, VINTF, overlays, partition sizes) gets
# done while the 3.18 -> 4.9 kernel port runs as its own lane — "Фронт C, after
# m5s" in the fleet plan, replaying the C1 checklist that m5c and m5s already
# codified, with m2note's own addresses.
#
# What DOES work on this handset today is LineageOS 15.1 on that 3.18 kernel:
# sys.boot_completed=1, adb, Wi-Fi, camera, audio — with SIM/RIL broken
# (FACT: /srv/forge/android/m2note/kernel-m2note-3.18-adapt/
#  HANDOFF_NEXT_AGENT.md:3-12 and M2NOTE_SUBSYSTEM_STATUS_2026-07-06.md).
# "Buildable" and "working" are different claims and this file makes only the
# first one.
# ===========================================================================
#
# Deliberately NOT set here:
#   PRODUCT_SHIPPING_API_LEVEL — leaving it undefined keeps PRODUCT_USE_VNDK
#   false (build/make/core/config.mk:721-737).  Note that the LOS 15.1 tree for
#   this handset DID set BOARD_VNDK_VERSION := current and aimed at full
#   Treble; that goal was never validated (TRB-FULL was "error" in the
#   2026-07-06 subsystem matrix: no /vendor/etc/vintf/manifest.xml, Q/R GSIs
#   died early).  See BoardConfig.mk for why this tree does not repeat it.

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from m2note device
$(call inherit-product, device/meizu/m2note/device.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_m2note
PRODUCT_DEVICE := m2note
PRODUCT_BRAND := Meizu
PRODUCT_MANUFACTURER := Meizu
PRODUCT_MODEL := M2 Note

PRODUCT_GMS_CLIENTID_BASE := android-meizu

# 1080x1920 panel.
TARGET_BOOT_ANIMATION_RES := 1080

PRODUCT_BUILD_PROP_OVERRIDES += \
    TARGET_DEVICE=m2note \
    PRODUCT_NAME=m2note
