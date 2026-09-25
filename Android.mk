LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),m2note)
include $(call all-makefiles-under,$(LOCAL_PATH))
# NOTHING from vendor/mediatek is included here, unlike the m5s/m5c trees:
# vendor/mediatek/Android.mk @6dd7c54b already includes ALL of its
# subdirectories for TARGET_DEVICE in {k5fpr, m2note} (symbols without
# GUI_ONLY, combo_loader, wlan/wifi_hal + wpa_supplicant_8_lib, ril, libgem,
# libgralloc_extra, mmsdk_feature, nfc, thermal_managerlib, init).  Including
# any of them again would define those modules twice.  For the same reason this
# tree has NO lib_driver_cmd_mt66xx of its own (vendor/mediatek/wlan builds it).
# device/meizu/m3_meizu_m6-common lists m2note in its top Android.mk, but all
# three of its subdir makefiles (libbt-vendor-mtk, libxlog, wpa_supplicant) are
# guarded "ifneq ($(TARGET_DEVICE),m2note)", so it contributes no module here —
# hence the device-local libbt-vendor/.
endif
