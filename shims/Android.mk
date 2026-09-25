LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE        := libshim_vcodec
LOCAL_MODULE_TAGS   := optional
LOCAL_PROPRIETARY_MODULE := true
LOCAL_SRC_FILES     := pthread_gettid_shim.c
LOCAL_MULTILIB      := both
LOCAL_SHARED_LIBRARIES := libc
include $(BUILD_SHARED_LIBRARY)

# libfs_mgr.so stub for libnvram (ported from device/meizu/m95/shims).
#
# Pie builds libfs_mgr as cc_library_static only, so no libfs_mgr.so exists,
# and every MTK blob with DT_NEEDED libfs_mgr.so fails to load: nvram_daemon
# and mnld die at the linker, which stalls the whole modem chain because
# ccci_mdinit waits on service.nvram_init that nvram_daemon never publishes.
include $(CLEAR_VARS)
LOCAL_MODULE := libfs_mgr_m5c_shim
LOCAL_SRC_FILES := fs_mgr.c
LOCAL_POST_INSTALL_CMD := mkdir -p $(TARGET_OUT_VENDOR)/lib $(TARGET_OUT_VENDOR)/lib64 \
    && ln -sf libfs_mgr_m5c_shim.so $(TARGET_OUT_VENDOR)/lib/libfs_mgr.so \
    && ln -sf libfs_mgr_m5c_shim.so $(TARGET_OUT_VENDOR)/lib64/libfs_mgr.so
LOCAL_MULTILIB := both
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)

# ifc_ipv6_trigger_rs for the MTK RIL blobs (ported from m95).
include $(CLEAR_VARS)
LOCAL_MODULE := libmtkshim_net
LOCAL_SRC_FILES := net.c
LOCAL_MULTILIB := both
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)

# libmnld_shim - no-op pthread_mutex_destroy for mnld (ported from m95,
# shims/pthread.c). Attached to /vendor/bin/mnld through TARGET_LD_SHIM_LIBS;
# executable shims are queued after LD_PRELOAD and before DT_NEEDED
# (bionic/linker/linker_main.cpp), so this definition precedes libc.so for
# every library in the process, libmnl.so included. 32-bit only: mnld is ELF32.
include $(CLEAR_VARS)
LOCAL_MODULE := libmnld_shim
LOCAL_SRC_FILES := pthread.c
LOCAL_MULTILIB := 32
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)

# libshim_audio_m5c - no-op stubs for the eleven MTK voice-unlock statics that
# audio.primary.mt6737m.so imports from android::AudioSystem (peripherals lane
# 2026-09-03, see audio_voiceunlock.c). Attached to the HAL through
# TARGET_LD_SHIM_LIBS; both ABIs because the blob ships in both.
include $(CLEAR_VARS)
LOCAL_MODULE := libshim_audio_m5c
LOCAL_SRC_FILES := audio_voiceunlock.c
LOCAL_MULTILIB := both
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MODULE_TAGS := optional
LOCAL_SHARED_LIBRARIES := libc
include $(BUILD_SHARED_LIBRARY)
