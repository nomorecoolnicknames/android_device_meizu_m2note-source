# libtinycompress for the m2note (m5c source; FACT: audio.primary.mt6753.so NEEDED libtinycompress.so).
#
# audio.primary.mt6737m.so has DT_NEEDED libtinycompress.so (compress_open/
# compress_write/... for offload playback) and no such library was in the
# image.  The platform module external/tinycompress can't be used here: its
# Android.bp pulls header_libs generated_kernel_headers, whose genrule runs
# `make -C $(TARGET_KERNEL_SOURCE) headers_install` — and this device builds
# with a prebuilt kernel (BoardConfig.mk: TARGET_KERNEL_SOURCE empty), so the
# genrule fails ("make: *** O=...: No such file or directory") and ninja stops
# the whole queue (build log 2026-09-03 12:44, took the linker with it).
#
# Same sources, same soname, compiled against bionic's own uapi copies of
# sound/compress_params.h + compress_offload.h + asound.h instead.  Built under
# a unique module name with an install-time symlink at the wanted filename —
# the house rule for filename stubs (shims/Android.mk), since naming the
# module libtinycompress outright collides with the Soong module.
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := libtinycompress_m2note
LOCAL_SRC_FILES := \
    ../../../../external/tinycompress/compress.c \
    ../../../../external/tinycompress/utils.c
LOCAL_C_INCLUDES := external/tinycompress/include
LOCAL_CFLAGS := -Wall -Wno-macro-redefined -Wno-unused-function
LOCAL_LDFLAGS := -Wl,-soname,libtinycompress.so
LOCAL_SHARED_LIBRARIES := libcutils libutils
LOCAL_POST_INSTALL_CMD := mkdir -p $(TARGET_OUT_VENDOR)/lib $(TARGET_OUT_VENDOR)/lib64 \
    && ln -sf libtinycompress_m2note.so $(TARGET_OUT_VENDOR)/lib/libtinycompress.so \
    && ln -sf libtinycompress_m2note.so $(TARGET_OUT_VENDOR)/lib64/libtinycompress.so
LOCAL_MULTILIB := both
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)
