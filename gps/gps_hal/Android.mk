# gps.mt6737m — MTK Gen-N legacy GPS HAL (hardware/gps.h), from the working
# 14.1 tree (device/meizu/m5c/gps/gps_hal, source unchanged). Talks to the
# Gen-N mnld blob over the abstract sockets mtk_hal2mnl / mtk_mnl2hal.
#
# Pie: built as a VENDOR module so it lands in /vendor/lib{,64}/hw where
# android.hardware.gnss@1.0-impl (hw_get_module, ro.board.platform=mt6737m)
# finds it. The gnss@1.0-service is 64-bit, so the 64-bit variant is the one
# that matters; both are built like every other HAL module in this tree.
# Nothing MTK-specific in the ABI: gps_mtk.h only adds two aiding-data bits
# and the vzw-debug side interface on top of Pie's gps.h/gps_internal.h.
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_PROPRIETARY_MODULE := true
LOCAL_SHARED_LIBRARIES := \
		liblog \
		libcutils \
		libhardware

LOCAL_C_INCLUDES += \
      $(LOCAL_PATH)/inc \
      $(LOCAL_PATH)/inc/hardware \

# MTK 2016 sources: cutils/log.h is deprecated in Pie (#warning), unused
# parameters throughout. Keep them warnings.
LOCAL_CFLAGS += -Wno-error -Wno-unused-parameter -Wno-unused-variable

LOCAL_SRC_FILES += \
	    src/hal2mnl_interface.c \
		  src/hal_mnl_interface_common.c \
		  src/data_coder.c \
		  src/mtk_lbs_utility.c \
		  src/agpsinf.c \
		  src/gpshal.c \
		  src/gpshal_worker.c \
		  src/gpsinf.c \

LOCAL_MODULE := gps.$(TARGET_BOARD_PLATFORM)

LOCAL_MODULE_TAGS := optional

include $(BUILD_SHARED_LIBRARY)
