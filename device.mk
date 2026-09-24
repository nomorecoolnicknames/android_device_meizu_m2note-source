#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# device.mk — Meizu M2 Note (m2note, M571) on LineageOS 20.0.
#
# Scope discipline, same as the m5c/m5s lanes: a package appears below only if
# the module name was verified to exist in THIS tree (2026-09-16).  Everything
# the LOS 15.1 tree shipped that Android 13 no longer provides — or that this
# port has not reached yet — is in the "NOT WIRED YET" block with the reason.
#
# Reminder, because it governs how to read everything below: Android 13 will not
# start on the 3.18 kernel this tree ships (no BPF_SYSCALL, no CGROUP_BPF).
# See prebuilt-kernel/PROVENANCE.md §3.

LOCAL_PATH := device/meizu/m2note

# ---------------------------------------------------------------------------
# Soong namespaces (device-tree isolation)
#
# FACT (measured 2026-09-16): Soong parses every Android.bp in the workspace
# for every product and has no TARGET_DEVICE guard, so a bp module declared in
# one device tree lands in installs-<product>.mk of ALL products — a plain
# `m nothing` for lineage_m5s carried 51 install-rule lines from
# device/meizu/m95 (27 modules), two of them colliding with real m5s blobs
# (vendor/lib{,64}/libperfservicenative.so, via the `stem:` of
# libm95shim_perfservice).  Modules of a namespace reach Make only for the
# products that list that namespace here
# (build/soong/cmd/soong_build/main.go:99-112 -> android/namespace.go:204 ->
# android/androidmk.go:919).  Each tree carries a root Android.bp with
# `soong_namespace {}`; this line is the other half of the pair.
# ---------------------------------------------------------------------------
PRODUCT_SOONG_NAMESPACES += \
    device/meizu/m2note \
    vendor/meizu/m2note

# Vendor blobs.
$(call inherit-product-if-exists, vendor/meizu/m2note/m2note-vendor.mk)

# ---------------------------------------------------------------------------
# Full Treble: vendor-side copies of libraries the blobs NEED
# ---------------------------------------------------------------------------
# With Treble (BoardConfig.mk) a vendor process sees only /vendor, LLNDK and
# public VNDK.  FACT (meizu-fleet/tools/treble_blob_audit.py over
# m2note-vendor-blobs.mk, VNDK 33 lists of the m95 build, 2026-09-25): 818 of
# 879 vendor ELFs had an unresolved closure, 111 missing sonames.  The entries
# below are the ones Android 13 can build for /vendor from source; with them
# the same audit gives 591 / 108.  What remains (libnativehelper,
# libandroid_runtime, libskia, libstagefright, libmedia, ..., GPU in sphal,
# and a long tail of SYSTEM binaries that the 15.1 extraction put into this
# vendor set — screencap, dex2oat, e2fsck, the TEE's alipayapp) is the shim /
# blob-list lane: designs/TREBLE_M5S_M2NOTE_20260924.md §4.
#
#  * libstdc++.vendor — bionic's small libstdc++ (bionic/libc/Android.bp,
#    vendor_available: true); 773 closures, the largest single gap.
#  * libgui_vendor + libm2noteshim_gui — libgui.so for 113 closures, m95
#    lesson 6 (shims/Android.bp says why a forwarder and not a copy).
#  * libcamera_client_vendor — m95 lesson 7: the vendor build of
#    libcamera_client (stem libcamera_client, frameworks/av branch
#    meizu-legacy-vendor), 87 closures.  Still missing for libsource.so: the
#    N-form getCameraInfo(int, android::CameraInfo*)
#    (…13getCameraInfoEiPNS_10CameraInfoE) — design doc §5, wall (b).
#  * libtinycompress, libtinyxml — both vendor: true (external/tinycompress,
#    external/tinyxml); NEEDed by audio.primary.mt6753.so (lib and lib64),
#    audit of the audio HAL closure, designs/treble-m5s-m2note/keyroots.txt.
#    m95 installs libtinycompress for the same reason.
#  * librilutils — vendor: true in hardware/ril/librilutils; NEEDed by mtkrild
#    and the RIL closure (10).
PRODUCT_PACKAGES += \
    libstdc++.vendor \
    libgui_vendor \
    libm2noteshim_gui \
    libcamera_client_vendor \
    libtinycompress \
    libtinyxml \
    librilutils

# HALs the framework compatibility matrix of target-level 3 marks
# optional="false" (hardware/interfaces/compatibility_matrices/
# compatibility_matrix.3.xml): audio + audio.effect (>= 4.0 — Android 13's
# client knows only 4.0..7.1, frameworks/av/media/libaudiohal/
# FactoryHalHidl.cpp), drm, gatekeeper, composer, mapper, media.omx.  Composer
# and mapper are already installed below; omx comes from base_vendor.mk.
# Same choices as m95 (device/meizu/m95/device.mk, "Treble HAL backbone"):
#  * audio@6.0-impl + audio.effect@6.0-impl: loaded by the multi-version
#    android.hardware.audio@2.0-service already in this file.  Whether the
#    Marshmallow audio.primary.mt6753.so survives the 6.0 wrapper is NOT known
#    (m95 needed a Nougat-layout guard in hardware/interfaces) — HYPOTHESIS.
#  * drm@1.0-impl/-service + drm@1.4-service.clearkey (ships its own VINTF
#    fragment).
#  * gatekeeper@1.0-service.software (ships its own VINTF fragment): without
#    any IGatekeeper LockSettingsService throws (m95 18.1 evidence).
PRODUCT_PACKAGES += \
    android.hardware.audio@6.0-impl \
    android.hardware.audio.effect@6.0-impl \
    android.hardware.drm@1.0-impl \
    android.hardware.drm@1.0-service \
    android.hardware.drm@1.4-service.clearkey \
    android.hardware.gatekeeper@1.0-service.software

# ---------------------------------------------------------------------------
# Screen: 1080x1920, density 420 -> xxhdpi
# ---------------------------------------------------------------------------
# FACT: live getprop [ro.sf.lcd_density]: [420] (capture
# export/m2note_flash_captures/runtime/v212_live_20260620-080956/getprop.txt),
# panel nt35532_fhd_dsi_vdo_sharp on the live cmdline (capture v194).
# 420 dpi is the xxhdpi bucket, not xhdpi — this is the one place the m2note
# and m5s device trees genuinely must differ in resources.
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi

PRODUCT_CHARACTERISTICS := phone

DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay

# ---------------------------------------------------------------------------
# Dalvik / ART heap
# ---------------------------------------------------------------------------
# 2 GB RAM.  Set by inherit rather than by hand: on the m95 port a wrong
# inherit path silently left the 16 MB default growth limit and system_server
# OOM'd.
#
# FACT: there is no phone-XXHDPI-*-dalvik-heap.mk in this tree — the only
# 2048 MB phone profile is phone-xhdpi-2048-dalvik-heap.mk
# (ls frameworks/native/build/*dalvik-heap.mk: hdpi-512, hdpi, xhdpi-1024,
#  xhdpi-2048, xhdpi-4096, xhdpi-6144, plus tablet variants).  The "xhdpi" in
# those filenames is historical naming, not a resource bucket the file enforces:
# the makefile only sets dalvik.vm.heap* sizes.  PRODUCT_AAPT_PREF_CONFIG above
# is what actually picks xxhdpi resources for this 420 dpi panel.
$(call inherit-product, frameworks/native/build/phone-xhdpi-2048-dalvik-heap.mk)

# ---------------------------------------------------------------------------
# Kernel — prebuilt only (see BoardConfig.mk and prebuilt-kernel/PROVENANCE.md)
# ---------------------------------------------------------------------------
M2NOTE_EFFECTIVE_KERNEL_PREBUILT := $(strip $(TARGET_PREBUILT_KERNEL))
ifneq ($(M2NOTE_EFFECTIVE_KERNEL_PREBUILT),)
PRODUCT_COPY_FILES += \
    $(M2NOTE_EFFECTIVE_KERNEL_PREBUILT):kernel
endif

# ---------------------------------------------------------------------------
# Ramdisk / fstab
# ---------------------------------------------------------------------------
# A13 first-stage init reads /fstab.<androidboot.hardware> out of the boot
# ramdisk.  ro.hardware on this device is mt6735, not mt6753.
#
# This is a sensitive spot on THIS handset specifically.  FACT: on 2026-07-07 a
# full OTA left the device without adb, and the offline root cause was a
# ramdisk whose init.rc had lost "import /init.usb.rc" and "start ueventd" and
# whose init.mt6735.rc had lost "mount_all /fstab.mt6735" — the tree had drifted
# onto a system/core branch (sfos-hybris-15.1) with a different ramdisk shape.
# Whether the initfix zip repaired it was never recorded.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6735:$(TARGET_COPY_OUT_RAMDISK)/fstab.mt6735 \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6735:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.mt6735

# Init fragment with the m95 NVRAM/Bluetooth lesson, carried ahead of the rc
# lane (NOT WIRED YET below): the BT address publisher.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/init.m2note.nvram.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.m2note.nvram.rc \
    $(LOCAL_PATH)/rootdir/m2note-bdaddr.sh:$(TARGET_COPY_OUT_VENDOR)/bin/m2note-bdaddr.sh

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
# Keys are mtk-kpd, touch is mtk-tpd, headset detection is ACCDET, AVRCP is the
# Bluetooth remote-control layout.  These .kl files come out of the stock blob
# set and are installed from the DEVICE tree here, which is why the five
# vendor/usr/keylayout entries are excluded from m2note-vendor-blobs.mk — two
# PRODUCT_COPY_FILES rules for one destination is the mechanism by which a blob
# once silently replaced a source-built hwcomposer on the m5c.
#
# NOT carried: fpc1020_input.kl.  This unit has no fingerprint sensor.
# NOT carried: *.bak-volswap.  Those are editor backups of mtk-kpd.kl and
# Vendor_2454_Product_6500.kl left in the 15.1 blob directory; installing a
# backup file into an image is never right.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/keylayout/mtk-kpd.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/mtk-kpd.kl \
    $(LOCAL_PATH)/configs/keylayout/mtk-tpd.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/mtk-tpd.kl \
    $(LOCAL_PATH)/configs/keylayout/ACCDET.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/ACCDET.kl \
    $(LOCAL_PATH)/configs/keylayout/AVRCP.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/AVRCP.kl \
    $(LOCAL_PATH)/configs/keylayout/Vendor_2454_Product_6500.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/Vendor_2454_Product_6500.kl

# ---------------------------------------------------------------------------
# Media / audio configs
# ---------------------------------------------------------------------------
# Same caveat as the m5s tree: media_codecs.xml <Include>s three
# media_codecs_google_*.xml that are not copied here; on 15.1 they came from
# frameworks/av into /system/etc, and in A13 they live in the media APEX.
# HYPOTHESIS to check on the first full build: if libstagefright logs
# "Failed to open file media_codecs_google_audio.xml", copy them explicitly.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    $(LOCAL_PATH)/configs/media_codecs_mediatek_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_mediatek_video.xml \
    $(LOCAL_PATH)/configs/media_profiles_V1_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml \
    $(LOCAL_PATH)/configs/audio/audio_device.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_device.xml \
    $(LOCAL_PATH)/configs/audio/audio_effects.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects.xml \
    $(LOCAL_PATH)/configs/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    $(LOCAL_PATH)/configs/audio/a2dp_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/a2dp_audio_policy_configuration.xml

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/seccomp/mediacodec.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy

# ---------------------------------------------------------------------------
# Wi-Fi / thermal / AGPS configs
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/wifi/wpa_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf \
    $(LOCAL_PATH)/configs/wifi/wpa_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant_overlay.conf \
    $(LOCAL_PATH)/configs/wifi/p2p_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant_overlay.conf \
    $(LOCAL_PATH)/configs/thermal/thermal.conf:$(TARGET_COPY_OUT_VENDOR)/etc/.tp/thermal.conf \
    $(LOCAL_PATH)/configs/thermal/thermal.off.conf:$(TARGET_COPY_OUT_VENDOR)/etc/.tp/thermal.off.conf \
    $(LOCAL_PATH)/configs/thermal/thermal_policy:$(TARGET_COPY_OUT_VENDOR)/etc/.tp/.thermal_policy \
    $(LOCAL_PATH)/configs/thermal/ht120.mtc:$(TARGET_COPY_OUT_VENDOR)/etc/.tp/.ht120.mtc \
    $(LOCAL_PATH)/configs/agps_profiles_conf2.xml:$(TARGET_COPY_OUT_VENDOR)/etc/agps_profiles_conf2.xml

# wpa_supplicant service with the AIDL interface name the A13 framework asks
# for (m95 lesson 161682f; nothing else in this image defines the service —
# see the header of that rc).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/init.m2note.wifi.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.m2note.wifi.rc

# ---------------------------------------------------------------------------
# Permissions — only hardware that exists on this unit
# ---------------------------------------------------------------------------
# No fingerprint (this unit has none), no NFC.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/handheld_core_hardware.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/handheld_core_hardware.xml \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.location.gps.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.location.gps.xml \
    frameworks/native/data/etc/android.hardware.telephony.gsm.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.gsm.xml \
    frameworks/native/data/etc/android.hardware.camera.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.front.xml \
    frameworks/native/data/etc/android.hardware.camera.autofocus.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.autofocus.xml \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.host.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml

# ---------------------------------------------------------------------------
# HIDL / HAL backbone
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    hwservicemanager \
    vndservicemanager

# Graphics.  surfaceflinger aborts without a composer.  composer@2.1-service
# hw_get_module()s hwcomposer.$(ro.board.platform) = hwcomposer.mt6753 and wraps
# the HWC1.1 module through libhwc2on1adapter.
#
# HONEST STATE OF THE DISPLAY PATH ON THIS DEVICE.  The 15.1 build did NOT run
# the stock blob: it ran a source-built HWC1 whose present path does a per-row
# memcpy honouring line_length stride, and the properties that drove it
# (debug.sf.disable_hwc=0, debug.composition.type=gpu, ...) were live-validated
# on 2026-06-20.  Neither that HWC nor those properties are in this tree.
# The blob hwcomposer.mt6753.so IS installed from the vendor set, so the first
# A13 attempt would use the blob — a path this handset has never run.
# The 2026-06-19 captures (v207 "stock_hwc_bootanim_stuck") record what happened
# the last time the stock HWC was tried on 15.1: the boot animation stuck.
# HYPOTHESIS: the same will happen on A13, and the source HWC1 has to be ported.
PRODUCT_PACKAGES += \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.mapper@2.0-impl \
    libhwc2on1adapter

# Keystore.  A13 keystore2 needs a KeyMint (AIDL) instance or it aborts with
# "no viable keymaster device found".  The AOSP default is pure software.
# NOTE: the 15.1 tree used BOARD_USE_SOFT_GATEKEEPER; the A13 equivalent of that
# decision is exactly this package plus the absence of any TEE HAL.
PRODUCT_PACKAGES += \
    android.hardware.security.keymint-service

# Bluetooth.
PRODUCT_PACKAGES += \
    android.hardware.bluetooth@1.0-impl \
    android.hardware.bluetooth@1.1-service

# Sensors / lights / vibrator / memtrack / power over the legacy hw modules.
PRODUCT_PACKAGES += \
    android.hardware.sensors@1.0-impl \
    android.hardware.sensors@1.0-service \
    android.hardware.light@2.0-impl \
    android.hardware.light@2.0-service \
    android.hardware.vibrator@1.0-impl \
    android.hardware.vibrator@1.0-service \
    vibrator.default \
    android.hardware.memtrack@1.0-impl \
    android.hardware.memtrack@1.0-service

# 2026-09-25, Treble: every service above is declared in manifest.xml, so it
# must actually be able to serve (a declared-but-unserved HAL hangs its
# client).  The @1.0 impls load legacy hw modules via hw_get_module
# (hardware/interfaces/vibrator/1.0/default/Vibrator.cpp:72,
# memtrack/1.0/default/Memtrack.cpp:77).  FACT (m2note-vendor-blobs.mk):
# memtrack.mt6753.so IS in the set, but the -impl that loads it was missing, so
# the service could only exit; there is no vibrator.* module (the 5 776-byte
# AOSP vibrator.default.so blob was excluded on purpose, see the header of
# that file).
#  * memtrack@1.0-impl — added, it picks memtrack.mt6753.so.
#  * vibrator.default — the A13 AOSP module (hardware/libhardware/modules/
#    vibrator, proprietary: true) instead of the M-era copy; it drives
#    /sys/class/timed_output/vibrator/enable.  HYPOTHESIS: the kernel exposes
#    timed_output; check `ls /sys/class/timed_output/vibrator` on first boot.

# Camera: camera.mt6753.so is a HAL1 module; provider@2.4's default impl wraps
# it.  Both -impl and -service are required.
# NOTE: on 15.1 the camera on this device did NOT run through the plain blob
# either — there is a source-built "MTK D1 camera island" and a Camera2/HAL3
# adapter in the 15.1 device tree (device/meizu/m2note/mtk/, camera_compat/,
# CAMERA2_HAL3_PLAN.md is 309 KB of it).  None of that is ported here.
PRODUCT_PACKAGES += \
    android.hardware.camera.provider@2.4-impl \
    android.hardware.camera.provider@2.4-service

# GNSS.  ro.hardware.gps=m2note (vendor.prop) selects gps.m2note.so.
# FACT from the 15.1 lane, kept because it is easy to re-break: GPS never
# started there while the feature XML, the ro.hardware.gps property, the GNSS
# service and mtk_agpsd were absent.  All four are needed together.
PRODUCT_PACKAGES += \
    android.hardware.gnss@1.0-impl \
    android.hardware.gnss@1.0-service

PRODUCT_PACKAGES += \
    android.hardware.audio@2.0-service

PRODUCT_PACKAGES += \
    wificond \
    wpa_supplicant \
    hostapd

# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------
PRODUCT_PROPERTY_OVERRIDES += \
    sys.usb.configfs=1 \
    sys.usb.controller=musb-hdrc \
    persist.sys.usb.config=adb \
    sys.usb.ffs.aio_compat=1

# Dexopt profile.  SPACE decision: /system is 1536 MiB here — the tightest of
# the three MT675x Meizus in this fleet — and A13 needs roughly 1710 MiB before
# any device blob.  See the size section of the report.
PRODUCT_PROPERTY_OVERRIDES += \
    pm.dexopt.first-boot=quicken \
    pm.dexopt.boot-after-ota=verify \
    pm.dexopt.install=speed-profile \
    pm.dexopt.bg-dexopt=speed-profile \
    pm.dexopt.ab-ota=speed-profile \
    pm.dexopt.inactive=verify \
    pm.dexopt.shared=speed

# ---------------------------------------------------------------------------
# NOT WIRED YET — every item here is a known gap, with the reason
# ---------------------------------------------------------------------------
# 0. THE KERNEL.  3.18 has no BPF_SYSCALL and no CGROUP_BPF symbol at all, so
#    A13's bpfloader cannot run and boot stops before zygote.  Everything below
#    is downstream of fixing that.  prebuilt-kernel/PROVENANCE.md §3.
# 1. The source-built HWC1.  See the graphics block above.
# 2. The MTK D1 camera island / Camera2-HAL3 adapter from the 15.1 tree.
# 3. The Wi-Fi vendor HAL service.  A13 has no standalone
#    android.hardware.wifi@1.0-service module; the device tree must define its
#    own cc_binary.  manifest.xml already declares IWifi, and a declared but
#    unserved HAL hangs its client (m681 light@2.0 lesson).
#    CORRECTION 2026-09-25 (FACT): the standalone service DOES exist, as a
#    kati module — hardware/interfaces/wifi/1.6/default/Android.mk:96
#    (LOCAL_MODULE := android.hardware.wifi@1.0-service), and m95 installs it.
#    It links the static libwifi-hal, which for BOARD_WLAN_DEVICE := MediaTek
#    is libwifi-hal-mt66xx (frameworks/opt/net/wifi/libwifi_hal/Android.mk:
#    123-125); m95 builds its own (device/meizu/m95/wifi_hal).  The service
#    ships a VINTF fragment (IWifi 1.6): when it is wired, drop the IWifi 1.2
#    entry from manifest.xml in the same change.
# 4. lib_driver_cmd_mt66xx / libwifi-hal-mt66xx come from vendor/mediatek, not
#    present here.  libwpa_client does not exist in A13.
# 5. Telephony.  SIM/RIL is broken on this handset even on 15.1
#    (gsm.sim.state=ABSENT,ABSENT with a live modem, 2026-07-06 matrix).  A13
#    additionally wants IRadio 1.6 / AIDL.  This is a research item, not a
#    porting item.
#    FACT (2026-09-24, nm -D --defined-only): proprietary/vendor/lib{,64}/
#    mtk-ril.so export RIL_InitSocket and NO RIL_Init (DT_NEEDED librilmtk.so
#    only), and this tree has no librilimp module.  So the m95 telephony
#    scheme (hardware/ril branch meizu-legacy-vendor, BOARD_USES_MTK_LEGACY_RIL
#    + librilmtk + a renamed librilimp, device/meizu/m95 7c49535/2922847) does
#    not apply: its rild loads mtk-ril.so and calls RIL_Init.
# 6. LD shims.  The 15.1 tree declared a 13-entry TARGET_LD_SHIM_LIBS
#    (libmtkshim_gui/_audio/_camera/_binder/_ui).  The mechanism survives on
#    LOS 20, the shim sources do not live in this tree, and their symbol sets
#    are Oreo-era.  Nothing is declared until they are rebuilt and re-measured.
# 7. sepolicy — nothing carried.  Runtime permissive via cmdline.  For scale:
#    the 15.1 build logged 201 unique denials across 29 domains in one boot.
# 8. rootdir rc files.  20 vendor .rc files were deliberately EXCLUDED from the
#    blob install list (see vendor/meizu/m2note/m2note-vendor-blobs.mk) because
#    they are Oreo-era init syntax; the device-side init.mt6735.rc /
#    ueventd.mt6735.rc from the 15.1 tree are not carried either.  This is the
#    single largest remaining chunk of work after the kernel.
#    Carried ahead of that lane: rootdir/etc/init/init.m2note.wifi.rc
#    (wpa_supplicant with the AIDL interface; do not port a second
#    `service wpa_supplicant`) and rootdir/etc/init/init.m2note.nvram.rc (m95
#    Bluetooth-address lesson, 2026-09-24).  The latter needs nvram_daemon
#    running (service.nvram_init=Ready); the stock nvram_daemon.rc starts it
#    only on sys.boot_completed=1.
# 9. recovery/TWRP — this tree does nothing with recovery.img beyond the
#    partition size and TARGET_RECOVERY_FSTAB.
