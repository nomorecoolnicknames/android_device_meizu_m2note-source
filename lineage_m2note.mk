# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
# Device configuration for this Android branch.

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

$(call inherit-product, device/meizu/m2note/device.mk)

$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_m2note
PRODUCT_DEVICE := m2note
PRODUCT_BRAND := Meizu
PRODUCT_MANUFACTURER := Meizu
PRODUCT_MODEL := M2 Note

PRODUCT_GMS_CLIENTID_BASE := android-meizu

TARGET_BOOT_ANIMATION_RES := 1080

PRODUCT_BUILD_PROP_OVERRIDES += \
    TARGET_DEVICE=m2note \
    PRODUCT_NAME=m2note
# Prevent accidentally evaluating this target against a different release.
ifneq ($(PLATFORM_SDK_VERSION),30)
$(error This device branch requires Android 11 / PLATFORM_SDK_VERSION=30)
endif
