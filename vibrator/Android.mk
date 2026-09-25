# vibrator.mt6737m — the Pie libhardware vibrator module built under the
# platform name (peripherals lane 2026-09-03).
#
# FACT (smoke run on the live LOS 16, 13:09): android.hardware.vibrator@1.0-
# service exits 1 at once.  The vibrator.default.so it wraps is the STOCK
# Flyme (Android M era) copy from m5c-vendor-blobs.mk and knows only
# /sys/class/timed_output/vibrator/enable — but the 4.9 pie-config kernel has
# no timed_output class at all: the MTK vibrator is a LED-class device,
# /sys/class/leds/vibrator/{activate,duration,state} (FACT, ls on device).
# Pie's hardware/libhardware/modules/vibrator/vibrator.c handles exactly that
# LED fallback (LED_DEVICE "/sys/class/leds/vibrator", vibrator.c:99).
#
# Built under vibrator.mt6737m instead of replacing the blob: hw_get_module
# probes ro.hardware.vibrator, ro.hardware (mt6735), ro.product.board (m5c),
# ro.board.platform (mt6737m) BEFORE "default", so this module wins without
# a second rule for vendor/lib/hw/vibrator.default.so (PRODUCT_COPY_FILES
# silently shadows a same-named built module — the hwcomposer/md_ctrl
# lesson recorded at the top of device.mk).  Same naming as lights.mt6737m.
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := vibrator.mt6737m
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_SRC_FILES := ../../../../hardware/libhardware/modules/vibrator/vibrator.c
LOCAL_C_INCLUDES := hardware/libhardware/include
LOCAL_SHARED_LIBRARIES := liblog libcutils
LOCAL_CFLAGS := -Wall -Werror
LOCAL_MULTILIB := both
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)
