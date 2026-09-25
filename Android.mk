LOCAL_PATH := $(call my-dir)

# Guarded so sibling products in this shared tree (m681, m95, ...) never
# scan m5c subdir makefiles.
ifeq ($(TARGET_DEVICE),m5c)
include $(call all-makefiles-under,$(LOCAL_PATH))
# Stage 4 (2026-09-03): the MTK Oreo HIDL rild + libril. vendor/mediatek/
# Android.mk only pulls symbols/ and wlan/ for the meizu_m6-family products,
# so vendor/mediatek/ril must be included explicitly (m681/meizu_m6 do the
# same). Its makefiles are themselves gated on BOARD_PROVIDES_LIBRIL /
# ENABLE_VENDOR_RIL_SERVICE, both set for m5c.
include vendor/mediatek/ril/Android.mk
endif
