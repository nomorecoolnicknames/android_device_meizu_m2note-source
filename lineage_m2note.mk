# lineage_m2note — LineageOS 16.0 product for the Meizu M2 Note (M571, MT6753, arm64).
# Donor: lineage_m5c.mk @77e62e0.

# This product owns Pie-specific HAL modules and packaging. Fail before module
# selection if a cloud worker accidentally combines it with another platform.
ifneq ($(PLATFORM_SDK_VERSION),28)
$(error lineage_m2note requires LineageOS 16.0 / Android SDK 28)
endif

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, device/meizu/m2note/device.mk)

DEVICE_PACKAGE_OVERLAYS += device/meizu/m2note/overlay

PRODUCT_NAME := lineage_m2note
PRODUCT_DEVICE := m2note
PRODUCT_BRAND := meizu
PRODUCT_MANUFACTURER := Meizu
PRODUCT_MODEL := M2 Note
PRODUCT_RELEASE_NAME := m2note
TARGET_OTA_ASSERT_DEVICE := m2note,m571,M571H
PRODUCT_BUILD_PROP_OVERRIDES += \
    PRODUCT_NAME=lineage_m2note \
    PRODUCT_DEVICE=m2note \
    TARGET_DEVICE=m2note

LINEAGE_BUILD := m2note

# Marshmallow blobs (BSP alps-mp-m0.mp1-V2.39.1_wtk6753.65u.m0_P16) -> API 23.
# Stage A: real vendor partition WITHOUT VNDK (BoardConfig.mk).
PRODUCT_SHIPPING_API_LEVEL := 23
PRODUCT_FULL_TREBLE_OVERRIDE := false

# profman SIGBUS on the m681/m5c build hosts (m5c/m681 lesson). TEMPORARY.
PRODUCT_USE_PROFILE_FOR_BOOT_IMAGE := false

PRODUCT_GMS_CLIENTID_BASE := android-meizu

# Bring-up ADB defaults (m681/m5c pattern).
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.secure=0 \
    ro.debuggable=1 \
    ro.adb.secure=0 \
    persist.sys.usb.config=adb \
    persist.service.adb.enable=1
