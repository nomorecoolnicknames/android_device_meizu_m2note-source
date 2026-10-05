# Meizu M2 Note / MT6753 board configuration for LineageOS 16.0.
# Native Linux 3.18 kernel and own DTB are supplied separately; see README.md.

# Meizu M2 Note / MT6753 board configuration for LineageOS 16.0.

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

TARGET_BOARD_PLATFORM := mt6753
TARGET_BOOTLOADER_BOARD_NAME := mt6753
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
BOARD_NAME := m2note
BOARD_USES_MTK_HARDWARE := true
MTK_HARDWARE := true

BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 firmware_class.path=/vendor/firmware androidboot.selinux=permissive androidboot.hardware=mt6735
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_OFFSET := 0x00080000
BOARD_RAMDISK_OFFSET := 0x04000000
BOARD_KERNEL_TAGS_OFFSET := 0x0e000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_MKBOOTIMG_ARGS := --kernel_offset $(BOARD_KERNEL_OFFSET) --ramdisk_offset $(BOARD_RAMDISK_OFFSET) --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) --board m2note

TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
# Use the pinned MT6753 prebuilt with its matching board DTB.
# The checksum and appended-DTB checks below are required.
TARGET_KERNEL_SOURCE :=
TARGET_KERNEL_CONFIG :=
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt-kernel/Image-native-318.gz-dtb
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb

# Prebuilt kernel gate (m5c pattern) — proves "image == tree", not "tree is right".
forge_kernel_check := $(shell $(DEVICE_PATH)/tools/check_prebuilt_kernel.sh \
        $(TARGET_PREBUILT_KERNEL) $(DEVICE_PATH)/prebuilt-kernel/EXPECTED.txt)
ifneq ($(strip $(forge_kernel_check)),)
$(error $(forge_kernel_check))
endif

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

# The stock custom partition supplies /vendor without changing the partition table.
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

BOARD_PROVIDES_LIBRIL := true
TARGET_SPECIFIC_HEADER_PATH := vendor/mediatek/include

DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml
