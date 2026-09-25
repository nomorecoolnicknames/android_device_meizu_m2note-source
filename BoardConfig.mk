# BoardConfig.mk for the Meizu M2 Note (m2note, model M571) — MT6753, arm64,
# 8x Cortex-A53.  LineageOS 16.0 (Android 9 Pie), Treble stage A: a REAL
# /vendor partition on custom, NO VNDK.
#
# Donor: device/meizu/m5c @77e62e0 (LOS 16.0, boots on the M5c), through the
# MT6753 adaptations made for the m5s (a9-trees/m5s, same SoC).  The m2note
# differs from both in what matters most here: it runs a 3.18.19 kernel (not
# 4.9), its partition NUMBERS differ, its panel is 1080x1920, it uses the
# legacy android_usb gadget, and it is the only one of the three with a live
# history (LOS 15.1 reached sys.boot_completed on it).  Sources of truth:
#   - live 15.1 captures   /srv/forge/android/export/m2note_flash_captures/
#   - the LOS 15.1 tree    /srv/forge/android/meizu_m6/rom-lineage-15.1-meizu_m6-experimental/device/meizu/m2note
#   - kernel tree          /srv/forge/android/m2note/kernel-m2note-3.18-adapt
#   - the LOS 20 report    meizu-fleet/trees/M2NOTE_LOS20_TREE.md
# Nothing in this tree has been built or run on the device (README.md).

DEVICE_PATH := device/meizu/m2note

# Architecture — arm64, 8x Cortex-A53 (MT6753).
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53
TARGET_USES_64_BIT_BINDER := true

# Platform.  FACT (live getprop, capture runtime/v212_live_20260620-080956):
# [ro.board.platform]: [mt6753], [ro.hardware]: [mt6735].
TARGET_BOARD_PLATFORM := mt6753
TARGET_BOOTLOADER_BOARD_NAME := mt6753
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
BOARD_NAME := m2note
BOARD_USES_MTK_HARDWARE := true
MTK_HARDWARE := true

# Kernel / boot.img geometry.  FACT: header of the image that last reached
# sys.boot_completed on this handset (sha256 9b25c1e0...3a3f, four-way identity,
# runtime/v181_15.1_v178_regdump_20260618-121109/):
#   kernel 0x40080000, ramdisk 0x44000000, second 0x40f00000, tags 0x4e000000,
#   page 2048, header v0, name "m2note".
# Its cmdline was
#   bootopt=64S3,32N2,64N2 firmware_class.path=/system/vendor/firmware
#   androidboot.selinux=permissive buildvariant=eng m2note.disable_md1=1
# Two deliberate changes (FACT for why):
#   - firmware_class.path -> /vendor/firmware: /vendor is a real partition here;
#     modem images sit in /vendor/etc/firmware and firmware-link/ adds the
#     /vendor/firmware -> etc/firmware symlink (m5c layout);
#   - m2note.disable_md1=1 DROPPED: it is the "cmdline-gated MD1 isolation" of
#     kernel commit 44275ddc (ccci_util_lib_fo.c:297-308, 524) — that proven boot
#     ran WITH THE MODEM SWITCHED OFF.  A9 wants the modem.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 firmware_class.path=/vendor/firmware androidboot.selinux=permissive androidboot.hardware=mt6735
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_OFFSET := 0x00080000
BOARD_RAMDISK_OFFSET := 0x04000000
BOARD_KERNEL_TAGS_OFFSET := 0x0e000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_MKBOOTIMG_ARGS := --kernel_offset $(BOARD_KERNEL_OFFSET) --ramdisk_offset $(BOARD_RAMDISK_OFFSET) --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) --board m2note

TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
# Prebuilt lane: 3.18.19+ #108 — the kernel of that same proven image
# (pages [2048, 2048+7654977) of it), sha256 87f5ec53...4080, md5 c98b27fe...
# (identical to los20/device/meizu/m2note/prebuilt-kernel, PROVENANCE.md there).
# Built from /srv/forge/android/m2note/kernel-m2note-3.18-adapt (m2note_defconfig).
# What this kernel is: the v178 "pmic rail trace" debug build — the LAST one that
# booted, not a release kernel.  3.18 is fine for Pie (m95 and the M6 run LOS 16
# on 3.18).  FACT (m2note_defconfig): CONFIG_USB_G_ANDROID=y, no USB_CONFIGFS —
# hence the legacy USB path in rootdir/; CONFIG_CPUSETS=y; CONFIG_SECCOMP_FILTER=y.
TARGET_KERNEL_SOURCE :=
TARGET_KERNEL_CONFIG :=
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt-kernel/Image.gz-dtb
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb

# Prebuilt kernel gate (m5c pattern) — proves "image == tree", not "tree is right".
forge_kernel_check := $(shell $(DEVICE_PATH)/tools/check_prebuilt_kernel.sh \
        $(TARGET_PREBUILT_KERNEL) $(DEVICE_PATH)/prebuilt-kernel/EXPECTED.txt)
ifneq ($(strip $(forge_kernel_check)),)
$(error $(forge_kernel_check))
endif

# Partitions.  FACT (recovery session 2026-05-30, by-name.txt + /proc/partitions,
# and sgdisk in GSI_REPARTITION_PLAN_2026-07-03.md:18-20):
#   boot p9 16 MiB, recovery p10 20 MiB (NOT the 22 MiB of the 15.1 tree — a
#   15.1-built recovery would not fit), custom p19 512 MiB, system p23 1536 MiB,
#   cache p24 400 MiB, userdata p25 12 831 948 800.
# CONTRADICTION, recorded both ways: M2NOTE_SUBSYSTEM_STATUS_2026-07-06.md:69
# says "System partition was repartitioned large enough for Q/R candidates".
# The current GPT was not re-read after that.  1536 MiB is the stock minimum, so
# it is a safe upper bound for system.img either way; check before flashing
# (README.md §7): cat /proc/partitions; sgdisk -p /dev/block/mmcblk0.
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

# --- Treble stage A ---------------------------------------------------------
# /vendor is a REAL partition: custom = mmcblk0p19, 512 MiB (FACT: live by-name
# and /proc/partitions), and the 15.1 port already mounted it as /vendor
# (kernel-m2note-3.18-adapt/HANDOFF_NEXT_AGENT.md:30).  VNDK OFF: the 15.1 tree
# set BOARD_VNDK_VERSION := current and full Treble was never reached
# (TRB-FULL = error, M2NOTE_SUBSYSTEM_STATUS_2026-07-06.md:47) — Marshmallow blobs.
TARGET_COPY_OUT_VENDOR := vendor
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_PARTITION_SIZE := 536870912

AB_OTA_UPDATER := false
BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/fstab.mt6735
TARGET_RECOVERY_PIXEL_FORMAT := BGRA_8888
TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 1920

TARGET_SYSTEM_PROP := $(DEVICE_PATH)/system.prop

# SELinux: permissive via cmdline; 201 unique denials in 29 domains on one 15.1
# boot (M2NOTE_FULL_ROM_ASSESSMENT_2026-07-02.md §3) — enforcing is a later lane.
SELINUX_IGNORE_NEVERALLOWS := true

BOARD_SECCOMP_POLICY := $(DEVICE_PATH)/seccomp

# Wi-Fi — MTK CONSYS.  lib_driver_cmd_mt66xx and libwifi-hal-mt66xx come from
# vendor/mediatek (its Android.mk includes EVERYTHING for TARGET_DEVICE=m2note).
BOARD_WLAN_DEVICE := MediaTek
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_mt66xx
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_mt66xx
WIFI_DRIVER_STATE_CTRL_PARAM := /dev/wmtWifi
WIFI_DRIVER_STATE_ON := 1
WIFI_DRIVER_STATE_OFF := 0

BOARD_HAVE_BLUETOOTH := true
BOARD_HAVE_BLUETOOTH_MTK := true
BOARD_BLUETOOTH_DOES_NOT_USE_RFKILL := true

# Vendor-blob ABI shims — measured on THIS blob set (readelf, 2026-09-25):
#  - __pthread_gettid (dropped from bionic in Pie) is imported by
#    lib/libvcodecdrv.so, lib/libMtkOmxVdec.so, lib/libmtkjpeg.so,
#    lib/libvcodec_utility.so and lib64/libvcodec_utility.so -> libshim_vcodec_m2note
#    (the m5c shim source; on the m5c the libvcodecdrv hole broke the Mali
#    dlopen chain and with it the 32-bit zygote).
#  - ICU *_53 (Pie ships ICU 60, external/icu uvernum.h:61): mtk_agpsd needs 7
#    ucnv_* symbols; libdrmmtkutil, libmzplayer, libtaglib add ucnv_toUnicode_53
#    and ucnv_fromUChars_53 -> libshim_icu53_m2note (the m681 icu.cpp pattern,
#    _53 names).
#  - camera closure: libcam_utils / libmtk_mmutils / libmmsdkservice.feature /
#    libcam.client import GraphicBuffer / BufferQueue symbols that
#    vendor/mediatek/symbols/{gui,ui}.cpp export (same set as m5s/m5c).
# NOT needed here (FACT, same pass): no VoiceUnlock imports in
# audio.primary.mt6753.so (m5c/m5s had them); libnvram.so has no DT_NEEDED
# libfs_mgr.so.
TARGET_LD_SHIM_LIBS += \
    /vendor/lib/libvcodecdrv.so|/vendor/lib/libshim_vcodec_m2note.so \
    /vendor/lib/libMtkOmxVdec.so|/vendor/lib/libshim_vcodec_m2note.so \
    /vendor/lib/libmtkjpeg.so|/vendor/lib/libshim_vcodec_m2note.so \
    /vendor/lib/libvcodec_utility.so|/vendor/lib/libshim_vcodec_m2note.so \
    /vendor/lib64/libvcodec_utility.so|/vendor/lib64/libshim_vcodec_m2note.so \
    /vendor/bin/mtk_agpsd|/vendor/lib/libshim_icu53_m2note.so \
    /vendor/lib/libdrmmtkutil.so|/vendor/lib/libshim_icu53_m2note.so \
    /vendor/lib64/libdrmmtkutil.so|/vendor/lib64/libshim_icu53_m2note.so \
    /vendor/lib/libmzplayer.so|/vendor/lib/libshim_icu53_m2note.so \
    /vendor/lib64/libmzplayer.so|/vendor/lib64/libshim_icu53_m2note.so \
    /vendor/lib/libtaglib.so|/vendor/lib/libshim_icu53_m2note.so \
    /vendor/lib64/libtaglib.so|/vendor/lib64/libshim_icu53_m2note.so \
    /vendor/lib/libcam_utils.so|/vendor/lib/libmtkshim_gui.so \
    /vendor/lib64/libcam_utils.so|/vendor/lib64/libmtkshim_gui.so \
    /vendor/lib/libmtk_mmutils.so|/vendor/lib/libmtkshim_gui.so \
    /vendor/lib64/libmtk_mmutils.so|/vendor/lib64/libmtkshim_gui.so \
    /vendor/lib/libcam.client.so|/vendor/lib/libmtkshim_gui.so \
    /vendor/lib64/libcam.client.so|/vendor/lib64/libmtkshim_gui.so \
    /vendor/lib/libmmsdkservice.feature.so|/vendor/lib/libmtkshim_gui.so \
    /vendor/lib/libmmsdkservice.feature.so|/vendor/lib/libmtkshim_ui.so \
    /vendor/lib64/libmmsdkservice.feature.so|/vendor/lib64/libmtkshim_gui.so \
    /vendor/lib64/libmmsdkservice.feature.so|/vendor/lib64/libmtkshim_ui.so

# --- Telephony via the MTK Oreo HIDL RIL (vendor/mediatek/ril), m5c recipe ---
# FACT (readelf 2026-09-25): mtk-ril.so (both ABIs) exports RIL_InitSocket and
# no RIL_Init.  librilmtk.so here exports IMS_RIL_onUnsolicitedResponseSocket
# and IMS_RILA_register but NOT IMS_isRilRequestFromIms / RIL_UpdateToVT — and
# that is harmless: the MTK libril @6dd7c54b defines IMS_isRilRequestFromIms and
# IMS_RIL_onUnsolicitedResponseSocket itself (ril/libril/ril.cpp:1102-1110) and
# never references RIL_UpdateToVT.  mtk-ril's ifc_* imports are all in
# system/core @e7f32da.  RIL_InitialAttachApn layout: see README.md (needs the
# MTK_RIL_IAA_NO_ROAMING_PROTOCOL patch to vendor/mediatek, as on the m5c).
BOARD_PROVIDES_LIBRIL := true
TARGET_SPECIFIC_HEADER_PATH := vendor/mediatek/include

DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml
