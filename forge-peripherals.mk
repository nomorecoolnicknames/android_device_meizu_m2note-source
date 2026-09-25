# forge-peripherals.mk — LOS 16 peripheral HAL lane for the Meizu M5c
# (2026-09-03).  Included from device.mk.  Journal + runtime evidence:
# device/meizu/m5c/M5C_LOS16_PERIPHERALS_20260903.md (forge 14.1 tree).
#
# Starting point (FACT, out tree 2026-09-03 morning): the legacy hw modules
# were all installed by m5c-vendor-blobs.mk — audio.primary/camera/sensors/
# lights.mt6737m.so, vibrator.default.so — but NOT ONE HIDL service of this
# lane existed, so every framework consumer hit "hwservicemanager: Cannot
# find entry ...".  Static measurement first (blobsym.py: non-weak UND symbols
# minus every defined dynamic symbol of the image, plus DT_NEEDED presence,
# both ABIs): camera.mt6737m, sensors.mt6737m, libhwm, vibrator.default and
# lights.mt6737m have ZERO unresolved symbols on Pie, so the generic AOSP
# passthrough wrappers are enough for them; the two exceptions are handled
# with real modules + shims below.

# --- Wi-Fi ------------------------------------------------------------------
# MTK CONSYS (BoardConfig.mk: BOARD_WLAN_DEVICE MediaTek, driver state via
# /dev/wmtWifi).  libwifi-hal-mt66xx comes from vendor/mediatek/wlan (m5c is in
# that tree's device filter).  The supplicant service definition and the
# /dev/wmtWifi regroup live in rootdir/forge-connectivity.rc.
PRODUCT_PACKAGES += \
    android.hardware.wifi@1.0-service \
    wpa_supplicant \
    hostapd \
    wificond \
    lib_driver_cmd_mt66xx \
    libwpa_client

# wpa_supplicant.conf template: ISupplicant::addInterface copies it into
# /data/vendor/wifi/wpa on first use and rejects wlan0 without one (m95 lesson:
# "Conf file does not exists", supplicant dies 0.15 s after start).
PRODUCT_COPY_FILES += \
    external/wpa_supplicant_8/wpa_supplicant/wpa_supplicant_template.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf \
    device/meizu/m5c/rootdir/forge-connectivity.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-connectivity.rc

# --- Sensors / lights / vibrator --------------------------------------------
# Generic AOSP passthrough services over the legacy modules (hw_get_module by
# ro.board.platform=mt6737m).  sensors.mt6737m.so ships in BOTH ABIs here, so
# the m681-only 64-bit .mtk variants are not needed; lights.mt6737m.so is our
# own 14.1 source build (device/meizu/m5c/liblights, md5-identical), talking
# to /sys/class/leds/{lcd-backlight,red,green,blue}; vibrator.default.so is
# the AOSP module (timed_output first, LED class fallback) and the pie-config
# kernel has CONFIG_MTK_VIBRATOR=y.
PRODUCT_PACKAGES += \
    android.hardware.sensors@1.0-impl \
    android.hardware.sensors@1.0-service \
    android.hardware.light@2.0-impl \
    android.hardware.light@2.0-service \
    android.hardware.vibrator@1.0-impl \
    android.hardware.vibrator@1.0-service

# --- Camera + torch ---------------------------------------------------------
# camera.mt6737m.so is a HAL1 module; provider@2.4's default impl wraps it via
# camera.device@1.0-impl (both -impl and -service are required: the service
# binary is only the passthrough registrar — m681 lesson, provider crashlooping
# on "Could not get passthrough implementation").  The torch path also goes
# through the provider (setTorchMode on the module), which is what made the
# 14.1 flashlight work.  Three libraries in the HAL's DT_NEEDED closure import
# Nougat-era libgui/libui constructors that Pie removed — libcam_utils
# (GraphicBuffer ctors), libmtk_mmutils (GraphicBuffer(w,h,fmt,usage)),
# libmmsdkservice.feature (createBufferQueue w/ IGraphicBufferAlloc,
# BufferItemConsumer ctor/setName, GraphicBuffer(ANativeWindowBuffer*,bool)) —
# exactly the seven thunks vendor/mediatek/symbols/{gui,ui}.cpp export.  Paired
# in BoardConfig.mk TARGET_LD_SHIM_LIBS.
PRODUCT_PACKAGES += \
    android.hardware.camera.provider@2.4-impl \
    android.hardware.camera.provider@2.4-service \
    libmtkshim_gui \
    libmtkshim_ui

# --- Audio ------------------------------------------------------------------
# android.hardware.audio@2.0-service + -impl already come from device.mk
# (placed by hand 2026-08-29).  audio.primary.mt6737m.so had 28 unresolved
# symbols: 17 are TiXml*/compress_* from two libraries that simply are not in
# the image (Pie builds them only on request), 11 are MTK voice-unlock statics
# on android::AudioSystem that AOSP never had -> no-op shim, see
# shims/audio_voiceunlock.c and the BoardConfig.mk pair.
# libtinycompress is the device-local build (tinycompress/Android.mk): the
# platform module needs generated_kernel_headers, impossible with a prebuilt
# kernel, and its genrule failure stops the whole ninja queue.
PRODUCT_PACKAGES += \
    libtinyxml \
    libtinycompress_m5c \
    libshim_audio_m5c

# --- Bluetooth -----------------------------------------------------------------
# 32-bit HIDL service (bluetooth_hal/Android.bp) in place of the 64-bit AOSP
# one, which can only register: libbt-vendor.so / libbluetooth_mtk.so exist
# 32-bit only in this blob set.  forge-bluetooth.rc overrides the AOSP service
# definition (same name vendor.bluetooth-1-0), regroups /dev/stpbt and the
# NVRAM BD-address record for user bluetooth, and publishes the factory
# address as persist.service.bdroid.bdaddr (m5c-bdaddr.sh) — without it the
# HAL aborts "No Bluetooth Address!" at the first enable.
PRODUCT_PACKAGES += \
    android.hardware.bluetooth@1.0-service.m5c

PRODUCT_COPY_FILES += \
    device/meizu/m5c/rootdir/forge-bluetooth.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-bluetooth.rc \
    device/meizu/m5c/rootdir/m5c-bdaddr.sh:$(TARGET_COPY_OUT_VENDOR)/bin/m5c-bdaddr.sh \
    device/meizu/m5c/rootdir/m5c-stpbt-perm.sh:$(TARGET_COPY_OUT_VENDOR)/bin/m5c-stpbt-perm.sh

# vibrator.mt6737m (vibrator/Android.mk): Pie vibrator.c with the LED-class
# fallback the 4.9 kernel needs; the stock vibrator.default.so blob only knows
# timed_output and makes vibrator@1.0-service exit 1 (smoke run 2026-09-03).
PRODUCT_PACKAGES += \
    vibrator.mt6737m

# Camera app.  The image shipped only com.android.camera2 (AOSP Camera), whose
# CaptureModule is Camera2-API only; camera.mt6737m.so is a HAL1 module, so the
# device is exposed as LEGACY and the app dies at once with
#   OneCameraCharacteristicsImpl.getSupportedPictureSizes NPE
#   (StreamConfigurationMap has no JPEG output config on the legacy shim)
# — measured 2026-09-03 13:47, Camera keeps stopping.  Snap is LineageOS's
# Camera1-API app and is what the working 14.1 build uses on the same blob.
PRODUCT_PACKAGES += Snap

# --- Media codec configuration ------------------------------------------------
# The LOS 16 image shipped NO media_codecs.xml at all (neither /vendor/etc nor
# /system/etc), so MediaCodecList came up empty: SoundPool could not decode a
# single /system/media/audio/ui/*.ogg and AudioService logged
#   SoundPool: Unable to load sample
#   AudioService: onLoadSoundEffects(), Error -2147483648 while loading samples
# — measured 2026-09-03 14:29, and loadSoundEffects() over binder returned
# false.  No decoders also means no video playback and no camcorder profile.
# The MTK OMX blobs (libMtkOmxCore/VdecEx/Venc/Mp3Dec/...) and
# /system/etc/mtk_omx_core.cfg are already in the image; only the XML that
# names them was missing.  Files are the 14.1 set (device/meizu/m5c/configs on
# the LOS 14.1 tree, where audio and video both work) plus the two AOSP
# includes it references, copied next to it so <Include href=...> resolves in
# the same directory.
PRODUCT_COPY_FILES += \
    device/meizu/m5c/configs/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    device/meizu/m5c/configs/media_codecs_mediatek_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_mediatek_audio.xml \
    device/meizu/m5c/configs/media_codecs_mediatek_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_mediatek_video.xml \
    device/meizu/m5c/configs/media_codecs_google_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_audio.xml \
    device/meizu/m5c/configs/media_codecs_google_video_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_video_le.xml \
    device/meizu/m5c/configs/media_codecs_performance.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_performance.xml \
    device/meizu/m5c/configs/media_profiles.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles.xml

# SoftAP configuration.  configs/ was the one directory of the 14.1 device tree
# that did not make it into the LOS 16 port at all; the audit of all 30 files
# (peripherals lane 2026-09-03) found only two real gaps — the media_* set above
# and these three.  hostapd itself is already built and installed by this
# makefile; without its configuration tethering has nothing to read.  NOT
# runtime-verified: SoftAP was never exercised in this lane.
PRODUCT_COPY_FILES += \
    device/meizu/m5c/configs/hostapd/hostapd_default.conf:$(TARGET_COPY_OUT_VENDOR)/etc/hostapd/hostapd_default.conf \
    device/meizu/m5c/configs/hostapd/hostapd.accept:$(TARGET_COPY_OUT_VENDOR)/etc/hostapd/hostapd.accept \
    device/meizu/m5c/configs/hostapd/hostapd.deny:$(TARGET_COPY_OUT_VENDOR)/etc/hostapd/hostapd.deny
