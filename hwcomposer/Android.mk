LOCAL_PATH := $(call my-dir)

# m2note source HWC 1.1 (direct-framebuffer present; replacement for the
# crashing/corrupting vendor blob). Build it under the MT6753 loader name so
# system images install the same module that manual runtime tests used.
include $(CLEAR_VARS)

LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_PROPRIETARY_MODULE   := true
LOCAL_MODULE               := hwcomposer.mt6753
LOCAL_MODULE_TAGS          := optional
LOCAL_MULTILIB             := 64
LOCAL_SRC_FILES            := hwcomposer.cpp
LOCAL_SHARED_LIBRARIES     := liblog libcutils libhardware libion libgralloc_extra libsync
LOCAL_HEADER_LIBRARIES     := libhardware_headers
LOCAL_C_INCLUDES           := \
    $(LOCAL_PATH) \
    vendor/mediatek/libgralloc_extra/include \
    system/core/include \
    frameworks/native/libs/nativewindow/include \
    frameworks/native/libs/nativebase/include \
    frameworks/native/libs/arect/include \
    system/core/libion/include \
    system/core/libion/kernel-headers \
    system/core/libsync/include
# disp_session.h is copied into $(LOCAL_PATH) from the kernel tree
# (drivers/misc/mediatek/video/include/disp_session.h; self-contained, no deps).
LOCAL_CFLAGS               := -DLOG_TAG=\"hwcomposer.mt6753\" -Wall -Werror \
    -Wno-unused-function -Wno-unused-variable -Wno-unused-parameter

include $(BUILD_SHARED_LIBRARY)

# Safe standalone probe (debug only): dlopens the module and drives open()/init.
include $(CLEAR_VARS)
LOCAL_MODULE        := m2hwc_probe
LOCAL_MODULE_TAGS   := optional
LOCAL_MULTILIB      := 64
LOCAL_SRC_FILES     := m2hwc_probe.cpp
LOCAL_SHARED_LIBRARIES := liblog libdl libhardware
LOCAL_HEADER_LIBRARIES := libhardware_headers
LOCAL_CFLAGS        := -Wall
include $(BUILD_EXECUTABLE)
