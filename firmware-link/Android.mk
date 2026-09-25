# /vendor/firmware -> etc/firmware, for ueventd's firmware fallback.
# See rootdir/ueventd.mt6735.rc (top comment) for the evidence: the MD image
# in /vendor/etc/firmware is invisible to both the kernel's fw_path[] and
# ueventd's default firmware_directories, and the modem never boots
# (MD_BOOT_HS1_FAIL). The symlink puts the images on ueventd's default path
# without moving them away from where ccci_mdinit (/custom/etc/firmware)
# looks. Marker file + LOCAL_POST_INSTALL_CMD is the same shape as the
# libfs_mgr.so symlink in shims/Android.mk; ln -sfn only if nothing installs
# a real /vendor/firmware directory.
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := forge_vendor_firmware_link
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_TAGS := optional
LOCAL_PROPRIETARY_MODULE := true
LOCAL_SRC_FILES := firmware-link.txt
LOCAL_MODULE_PATH := $(TARGET_OUT_VENDOR)/etc/forge
LOCAL_POST_INSTALL_CMD := if [ ! -d $(TARGET_OUT_VENDOR)/firmware ]; then ln -sfn etc/firmware $(TARGET_OUT_VENDOR)/firmware; fi
include $(BUILD_PREBUILT)
