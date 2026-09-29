# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
# lineage_m2note.mk — product definition for the Meizu M2 Note (m2note, M571).

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
