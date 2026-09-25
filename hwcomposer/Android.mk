# forge_hwc: replacement hwcomposer for the m5c on the forge 4.9 kernel.
# The vendor hwcomposer.mt6737m.so (built for 3.18) stalls frames against
# this kernel; keep it renamed to .forgebak and install this module instead.
#
# disp_session_uapi.h must stay a byte-for-byte copy of
#   kernel-m5c-4.9-lc/drivers/misc/mediatek/video/include/disp_session.h
# (the _IOW numbers encode struct sizes; a drifted copy silently changes
# the ioctl numbers — the exact failure class p47..p69 were about).

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := hwcomposer.mt6737m
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_MODULE_TAGS := optional
# LOS16/Treble: hwcomposer module must live in /vendor/lib*/hw (composer
# passthrough runs in a vendor process; hw_get_module searches vendor first).
LOCAL_VENDOR_MODULE := true
LOCAL_MULTILIB := both
LOCAL_SRC_FILES := forge_hwc.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)
LOCAL_SHARED_LIBRARIES := liblog libdl
LOCAL_CFLAGS := -Wall -Wno-unused-parameter -DLOG_TAG=\"forge-hwc\"
include $(BUILD_SHARED_LIBRARY)
