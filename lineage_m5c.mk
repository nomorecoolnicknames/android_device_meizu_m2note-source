# lineage_m5c — LineageOS 16.0 product for the Meizu M5c (MT6737M, arm64).

# arm64: inherit core_64_bit before the phone stack so core_minimal doesn't
# lock us into ro.zygote=zygote32 (same ordering lesson as the m681/m95 ports).
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, device/meizu/m5c/device.mk)

DEVICE_PACKAGE_OVERLAYS += device/meizu/m5c/overlay

PRODUCT_NAME := lineage_m5c
PRODUCT_DEVICE := m5c
PRODUCT_BRAND := meizu
PRODUCT_MANUFACTURER := Meizu
PRODUCT_MODEL := m5c
PRODUCT_RELEASE_NAME := m5c
TARGET_OTA_ASSERT_DEVICE := m5c,m710h
PRODUCT_BUILD_PROP_OVERRIDES += \
    PRODUCT_NAME=lineage_m5c \
    PRODUCT_DEVICE=m5c \
    TARGET_DEVICE=m5c

# Pie: vendor/lineage does not default LINEAGE_BUILD from TARGET_DEVICE.
LINEAGE_BUILD := m5c

# Device shipped with Nougat-era Flyme (API 25 blobs); keeps Treble/VTS
# checks advisory.  Stage A: real vendor partition WITHOUT VNDK — see the
# BoardConfig.mk vendor block.
PRODUCT_SHIPPING_API_LEVEL := 25
PRODUCT_FULL_TREBLE_OVERRIDE := false

# profman SIGBUSes deterministically on this build host (m681 evidence in
# lineage_m681.mk: exact command reproduces by hand, all boot jars pass
# unzip -t).  The boot-image profile is an optimisation, not a requirement.
# TEMPORARY — revisit before any build meant for daily use.
PRODUCT_USE_PROFILE_FOR_BOOT_IMAGE := false

PRODUCT_GMS_CLIENTID_BASE := android-meizu

# Bring-up ADB defaults (m681 pattern).
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.secure=0 \
    ro.debuggable=1 \
    ro.adb.secure=0 \
    persist.sys.usb.config=adb \
    persist.service.adb.enable=1
