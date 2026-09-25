# hwcomposer.mt6753 for the m2note — the m2note's OWN source HWC 1.1 from the
# LOS 15.1 tree (device/meizu/m2note/hwcomposer, copied unchanged), NOT the
# m5c forge_hwc: forge_hwc carries the 4.9 disp_session UAPI, which differs
# from the m2note 3.18 kernel's in 626 lines; this source's disp_session.h is
# byte-identical to kernel-m2note-3.18-adapt HEAD
# drivers/misc/mediatek/video/include/disp_session.h (FACT, cmp 2026-09-25).
# It is the HWC that 15.1 ran on this handset (system.prop v212 notes, "panel
# functional; HWC and gralloc HALs run", M2NOTE_SUBSYSTEM_STATUS DISP-HWC).
# The stock hwcomposer.mt6753.so blob is left out of the vendor list.
# libgralloc_extra: linked against the vendor/mediatek source module (defined for
# m2note), but at runtime the BLOB copy is what lands in /vendor/lib* — the
# vendor list installs it and PRODUCT_COPY_FILES wins the expected "overriding
# commands" — exactly the 15.1 state (device_m2note.mk:497-510).  This HWC calls
# only gralloc_extra_query, which the blob exports (FACT, readelf).
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
