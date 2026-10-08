
LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),m2note)
include $(CLEAR_VARS)
LOCAL_MODULE        := m2note_fit1536_trim
LOCAL_MODULE_CLASS  := ETC
LOCAL_MODULE_TAGS   := optional
LOCAL_SRC_FILES     := fit1536/m2note-fit1536-trim.txt
LOCAL_MODULE_STEM   := m2note-fit1536-trim.txt
LOCAL_MODULE_PATH   := $(TARGET_OUT)/etc
LOCAL_LICENSE_KINDS := SPDX-license-identifier-Apache-2.0
LOCAL_LICENSE_CONDITIONS := notice
LOCAL_OVERRIDES_MODULES := \
    NfcNci \
    ThemePicker \
    Seedvault \
    StorageManager \
    EmergencyInfo \
    Gallery2 \
    NotoSerifCJK-Regular.ttc \
    NotoSansCJK-Regular.ttc
include $(BUILD_PREBUILT)
endif
