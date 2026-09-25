LOCAL_PATH := $(call my-dir)

# Blob ABI shims for the m2note — only what THIS blob set imports (readelf over
# the 15.1 stock extraction, 2026-09-25).  Paired in BoardConfig.mk.

# __pthread_gettid, dropped from bionic in Pie (m5c source, unchanged).
# FACT: imported by lib/libvcodecdrv.so, lib/libMtkOmxVdec.so, lib/libmtkjpeg.so,
# lib/libvcodec_utility.so, lib64/libvcodec_utility.so.
include $(CLEAR_VARS)
LOCAL_MODULE        := libshim_vcodec_m2note
LOCAL_MODULE_TAGS   := optional
LOCAL_PROPRIETARY_MODULE := true
LOCAL_SRC_FILES     := pthread_gettid_shim.c
LOCAL_MULTILIB      := both
LOCAL_SHARED_LIBRARIES := libc
include $(BUILD_SHARED_LIBRARY)

# ICU *_53 forwarders (the m681 vendor/mediatek/symbols/icu.cpp pattern with
# the m2note's version suffix).  FACT: mtk_agpsd imports 7 ucnv_* *_53
# symbols; libdrmmtkutil/libmzplayer/libtaglib add ucnv_toUnicode_53 and
# ucnv_fromUChars_53; Pie ships ICU 60.
include $(CLEAR_VARS)
LOCAL_MODULE := libshim_icu53_m2note
LOCAL_SRC_FILES := icu53.cpp
LOCAL_SHARED_LIBRARIES := libicuuc
LOCAL_C_INCLUDES := external/icu/icu4c/source/common
LOCAL_MULTILIB := both
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)
