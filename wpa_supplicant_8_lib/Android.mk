# lib_driver_cmd_mt66xx for m5c — MTK private driver-command library for
# wpa_supplicant/hostapd (BOARD_WPA_SUPPLICANT_PRIVATE_LIB /
# BOARD_HOSTAPD_PRIVATE_LIB in BoardConfig.mk).
# Sources are the LOS16-adapted pair from device/meizu/m681 (zero-initialized
# nlattr arrays for the Pie warning set); the 14.1 m5c copy differs only in
# ifdef-gated feature blocks (CONFIG_MTK_P2P_SIGMA, CONFIG_MEDIATEK_WIFI_BEAM)
# that are never enabled here. Runtime fit for the gen2 MT6735 CONSYS driver
# is verified at the wifi bring-up stage.
# Guard: this module must exist exactly once per product; device/meizu/m5c
# subdir makefiles are only included for TARGET_DEVICE=m5c (device Android.mk),
# the inner guard is belt-and-braces.
ifeq ($(TARGET_DEVICE),m5c)
LOCAL_PATH := $(call my-dir)

ifeq ($(WPA_SUPPLICANT_VERSION),VER_0_8_X)

    WPA_SUPPL_DIR = external/wpa_supplicant_8
    WPA_SRC_FILE :=

ifneq ($(BOARD_WPA_SUPPLICANT_DRIVER),)
    CONFIG_DRIVER_$(BOARD_WPA_SUPPLICANT_DRIVER) := y
endif

ifneq ($(BOARD_HOSTAPD_DRIVER),)
    CONFIG_DRIVER_$(BOARD_HOSTAPD_DRIVER) := y
endif

include $(WPA_SUPPL_DIR)/wpa_supplicant/android.config

WPA_SUPPL_DIR_INCLUDE = $(WPA_SUPPL_DIR)/src \
	$(WPA_SUPPL_DIR)/src/common \
	$(WPA_SUPPL_DIR)/src/drivers \
	$(WPA_SUPPL_DIR)/src/l2_packet \
	$(WPA_SUPPL_DIR)/src/utils \
	$(WPA_SUPPL_DIR)/src/wps \
	$(WPA_SUPPL_DIR)/wpa_supplicant

ifdef CONFIG_DRIVER_NL80211
WPA_SUPPL_DIR_INCLUDE += external/libnl/include
WPA_SRC_FILE += mediatek_driver_cmd_nl80211.c
endif

ifeq ($(TARGET_ARCH),arm)
L_CFLAGS += -mabi=aapcs-linux
endif

ifdef CONFIG_ANDROID_LOG
L_CFLAGS += -DCONFIG_ANDROID_LOG
endif

include $(CLEAR_VARS)
LOCAL_MODULE := lib_driver_cmd_mt66xx
LOCAL_PROPRIETARY_MODULE := true
LOCAL_SHARED_LIBRARIES := libc libcutils
LOCAL_CFLAGS := $(L_CFLAGS)
LOCAL_SRC_FILES := $(WPA_SRC_FILE)
LOCAL_C_INCLUDES := $(WPA_SUPPL_DIR_INCLUDE)
include $(BUILD_STATIC_LIBRARY)

endif

endif
