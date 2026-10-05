# forge-peripherals.mk — LOS 16 peripheral HALs for the Meizu M2 Note.
# Donor: device/meizu/m5c/forge-peripherals.mk @77e62e0.  Module names follow
# ro.board.platform=mt6753; every block says what the m2note blob set provably
# has (readelf/ls over the 15.1 stock extraction, 2026-09-25).

# --- Wi-Fi ------------------------------------------------------------------
# lib_driver_cmd_mt66xx and libwifi-hal-mt66xx: vendor/mediatek (full include
# for m2note), not the device tree.
PRODUCT_PACKAGES += \
    android.hardware.wifi@1.0-service \
    wpa_supplicant \
    hostapd \
    wificond \
    lib_driver_cmd_mt66xx \
    libwpa_client

PRODUCT_COPY_FILES += \
    external/wpa_supplicant_8/wpa_supplicant/wpa_supplicant_template.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf \
    device/meizu/m2note/rootdir/forge-connectivity.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-connectivity.rc

PRODUCT_PACKAGES += \
    android.hardware.sensors@1.0-impl \
    android.hardware.sensors@1.0-service \
    android.hardware.light@2.0-impl \
    android.hardware.light@2.0-service \
    android.hardware.vibrator@1.0-impl \
    android.hardware.vibrator@1.0-service \
    vibrator.mt6753

# --- Camera -------------------------------------------------------------------
# camera.mt6753.so (MTK HAL1-era) via provider@2.4; GraphicBuffer/BufferQueue
# imports of the closure paired with libmtkshim_gui/ui in BoardConfig.mk.
PRODUCT_PACKAGES += \
    android.hardware.camera.provider@2.4-impl \
    android.hardware.camera.provider@2.4-service \
    libmtkshim_gui \
    libmtkshim_ui \
    Snap

# --- Audio ------------------------------------------------------------------
# audio.primary.mt6753.so NEEDED (FACT, readelf): libtinycompress.so,
# libtinyxml.so (not in the set) — device-local libtinycompress_m2note (the
# platform module needs kernel headers a prebuilt kernel cannot give).  No
# VoiceUnlock imports here, so no audio shim.  The HAL service is declared
# explicitly (m5c's tree does not declare it at all — hand-placed there).
PRODUCT_PACKAGES += \
    android.hardware.audio@2.0-service \
    android.hardware.audio@2.0-impl \
    android.hardware.audio@4.0-impl \
    android.hardware.audio.effect@2.0-impl \
    android.hardware.audio.effect@4.0-impl \
    audio.r_submix.default \
    audio.usb.default \
    libtinyxml \
    libtinycompress_m2note

# Audio configuration: the LOS 15.1 m2note set.  audio_device.xml goes to
# /system/etc because the HAL opens exactly that path (FACT: strings
# lib/hw/audio.primary.mt6753.so -> /system/etc/audio_device.xml) and the blob
# set has no copy of it.
PRODUCT_COPY_FILES += \
    device/meizu/m2note/configs/audio/audio_device.xml:system/etc/audio_device.xml \
    device/meizu/m2note/configs/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    device/meizu/m2note/configs/audio/a2dp_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/a2dp_audio_policy_configuration.xml \
    device/meizu/m2note/configs/audio/audio_effects.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects.xml \
    frameworks/av/services/audiopolicy/config/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml \
    frameworks/av/services/audiopolicy/config/default_volume_tables.xml:$(TARGET_COPY_OUT_VENDOR)/etc/default_volume_tables.xml \
    frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/usb_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/usb_audio_policy_configuration.xml

# --- Bluetooth ----------------------------------------------------------------
# The stock 64-bit AOSP HIDL service over the device-local libbt-vendor (both
# ABIs, libbt-vendor/).  forge-bluetooth.rc: service override with the NVRAM
# groups, /dev/stpbt ownership, factory BD address.
PRODUCT_PACKAGES += \
    android.hardware.bluetooth@1.0-impl \
    android.hardware.bluetooth@1.0-service \
    libbt-vendor

PRODUCT_COPY_FILES += \
    device/meizu/m2note/rootdir/forge-bluetooth.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-bluetooth.rc \
    device/meizu/m2note/rootdir/m2note-bdaddr.sh:$(TARGET_COPY_OUT_VENDOR)/bin/m2note-bdaddr.sh \
    device/meizu/m2note/rootdir/m2note-stpbt-perm.sh:$(TARGET_COPY_OUT_VENDOR)/bin/m2note-stpbt-perm.sh

# --- Media codecs -------------------------------------------------------------
# The LOS 15.1 m2note set (component names of THIS blob set) + the Google
# includes it references.
PRODUCT_COPY_FILES += \
    device/meizu/m2note/configs/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    device/meizu/m2note/configs/media_codecs_mediatek_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_mediatek_video.xml \
    device/meizu/m2note/configs/media_profiles_V1_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_audio.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_telephony.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_telephony.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_video_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_video_le.xml

# SoftAP (generic hostapd files from the m5c).  NOT runtime-verified.
PRODUCT_COPY_FILES += \
    device/meizu/m2note/configs/hostapd/hostapd_default.conf:$(TARGET_COPY_OUT_VENDOR)/etc/hostapd/hostapd_default.conf \
    device/meizu/m2note/configs/hostapd/hostapd.accept:$(TARGET_COPY_OUT_VENDOR)/etc/hostapd/hostapd.accept \
    device/meizu/m2note/configs/hostapd/hostapd.deny:$(TARGET_COPY_OUT_VENDOR)/etc/hostapd/hostapd.deny

PRODUCT_COPY_FILES += \
    device/meizu/m2note/configs/thermal/thermal.conf:system/etc/.tp/thermal.conf \
    device/meizu/m2note/configs/thermal/thermal.off.conf:system/etc/.tp/thermal.off.conf \
    device/meizu/m2note/configs/thermal/ht120.mtc:system/etc/.tp/.ht120.mtc
