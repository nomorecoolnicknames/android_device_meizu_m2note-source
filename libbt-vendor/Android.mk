# libbt-vendor for the m2note — source: device/meizu/m3_meizu_m6-common
# @fe03476 libbt-vendor-mtk (Apache-2.0), copied because that makefile is
# guarded "ifneq ($(TARGET_DEVICE),m2note)" and so builds nothing for this
# product.  It dlopens libbluetoothdrv.so and calls mtk_bt_enable /
# mtk_bt_disable.  FACT (readelf 2026-09-25): the m2note blob set has
# libbluetoothdrv.so in BOTH ABIs exporting mtk_bt_enable, mtk_bt_disable,
# mtk_bt_write, mtk_bt_read, mtk_bt_op — so, unlike the m5c/m5s (32-bit-only
# stock libbt-vendor.so), the stock 64-bit AOSP bluetooth@1.0 service can load it.
ifeq ($(TARGET_DEVICE),m2note)
ifneq ($(BOARD_HAVE_BLUETOOTH_MTK),)

LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_C_INCLUDES := system/bt/hci/include
LOCAL_CFLAGS := -g -c -W -Wall -O2 -D_POSIX_SOURCE
LOCAL_SRC_FILES := libbt-vendor-mtk.c
LOCAL_SHARED_LIBRARIES := libcutils libutils liblog libdl
LOCAL_MODULE := libbt-vendor
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MULTILIB := both

include $(BUILD_SHARED_LIBRARY)

endif
endif
