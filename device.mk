LOCAL_PATH := device/meizu/m2note

# Device makefile for the Meizu M2 Note on LineageOS 16.0.  Donor:
# device/meizu/m5c @77e62e0 via the MT6753 choices of the m5s tree; every
# block says what is m2note-specific and on which evidence.  Nothing here has
# been built or run on the device (README.md).

# Vendor blobs: vendor/meizu/m2note (a9-trees/m2note/vendor/meizu/m2note), list
# generated from the 15.1 stock extraction by meizu-fleet/tools/a9-gen-vendor-blobs.py.
# Hard inherit: a missing vendor tree / proprietary mount must stop the build.
$(call inherit-product, vendor/meizu/m2note/m2note-vendor.mk)

PRODUCT_DEVICE := m2note

# Screen: 1080x1920, 420 dpi (FACT, live getprop capture v212) -> xxhdpi.
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi

# Dalvik heap set explicitly (m95 lesson).  The m2note is a 2 GB phone
# (INFERENCE: model spec; no meminfo capture was checked) — the m5c set that
# boots LOS 16 on 2 GB.
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=8m \
    dalvik.vm.heapgrowthlimit=192m \
    dalvik.vm.heapsize=512m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=8m

# Prebuilt kernel into the target-files "kernel" slot.
M2NOTE_EFFECTIVE_KERNEL_PREBUILT := $(strip $(TARGET_PREBUILT_KERNEL))
ifneq ($(M2NOTE_EFFECTIVE_KERNEL_PREBUILT),)
PRODUCT_COPY_FILES += \
    $(M2NOTE_EFFECTIVE_KERNEL_PREBUILT):kernel
endif

# Ramdisk: fstab + the m5c LOS 16 MTK rc set, except init.mt6735.usb.rc, which
# is the m2note's own legacy-gadget file (rootdir/init.mt6735.usb.rc header).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/fstab.mt6735:root/fstab.mt6735 \
    $(LOCAL_PATH)/rootdir/init.mt6735.rc:root/init.mt6735.rc \
    $(LOCAL_PATH)/rootdir/init.mt6735.usb.rc:root/init.mt6735.usb.rc \
    $(LOCAL_PATH)/rootdir/init.modem.rc:root/init.modem.rc \
    $(LOCAL_PATH)/rootdir/init.project.rc:root/init.project.rc \
    $(LOCAL_PATH)/rootdir/init.recovery.mt6735.rc:root/init.recovery.mt6735.rc \
    $(LOCAL_PATH)/rootdir/ueventd.mt6735.rc:root/ueventd.mt6735.rc \
    $(LOCAL_PATH)/rootdir/enableswap.sh:root/enableswap.sh

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/fstab.mt6735:recovery/root/fstab.mt6735

# Keylayouts — the m2note stock set (vendor/usr/keylayout of the 15.1
# extraction; fpc1020_input.kl is left out: no fingerprint sensor; the two
# *.bak-volswap editor copies are left out).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/keylayout/ACCDET.kl:system/usr/keylayout/ACCDET.kl \
    $(LOCAL_PATH)/keylayout/AVRCP.kl:system/usr/keylayout/AVRCP.kl \
    $(LOCAL_PATH)/keylayout/mtk-kpd.kl:system/usr/keylayout/mtk-kpd.kl \
    $(LOCAL_PATH)/keylayout/mtk-tpd.kl:system/usr/keylayout/mtk-tpd.kl \
    $(LOCAL_PATH)/keylayout/Vendor_2454_Product_6500.kl:system/usr/keylayout/Vendor_2454_Product_6500.kl

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/seccomp/mediacodec.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy

# Permission xmls.  Sensors: FACT, live 15.1 dumpsys sensorservice lists
# accel, magnetometer, orientation, gyro, light, proximity
# (M2NOTE_SUBSYSTEM_STATUS_2026-07-06.md:62) — the gyroscope IS declared (the
# LOS 20 tree left it out without evidence).  No fingerprint (FACT: the 15.1
# tree itself excludes the FPC blobs, "m2note has no fingerprint sensor").
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/handheld_core_hardware.xml:system/etc/permissions/handheld_core_hardware.xml \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:system/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:system/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.location.gps.xml:system/etc/permissions/android.hardware.location.gps.xml \
    frameworks/native/data/etc/android.hardware.telephony.gsm.xml:system/etc/permissions/android.hardware.telephony.gsm.xml \
    frameworks/native/data/etc/android.hardware.camera.xml:system/etc/permissions/android.hardware.camera.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:system/etc/permissions/android.hardware.camera.front.xml \
    frameworks/native/data/etc/android.hardware.camera.autofocus.xml:system/etc/permissions/android.hardware.camera.autofocus.xml \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:system/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:system/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:system/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:system/etc/permissions/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:system/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:system/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:system/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:system/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:system/etc/permissions/android.hardware.usb.host.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:system/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:system/etc/permissions/android.hardware.wifi.direct.xml

PRODUCT_PACKAGES += \
    hwservicemanager \
    vndservicemanager \
    servicemanager

# Graphics.  hwcomposer.mt6753 is the m2note's own 15.1 source HWC 1.1
# (hwcomposer/Android.mk says why, FACT: its UAPI == the 3.18 kernel's); the
# stock blob is left out of the vendor list.  composer@2.1 passthrough wraps it
# through libhwc2on1adapter (m5c stage 3).
PRODUCT_PACKAGES += \
    hwcomposer.mt6753 \
    android.hardware.graphics.composer@2.1-impl \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.mapper@2.0-impl \
    libhwc2on1adapter

# Keymaster: AOSP 3.0 impl (m5c: keystore aborts without a keymaster HAL).
# The m2note set carries keystore.default.so (m5c carries one too and boots).
PRODUCT_PACKAGES += \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service

# Props early init actually reads on this no-first-stage-mount layout
# (/system/build.prop, m5c 2026-08-29).  USB: NO sys.usb.configfs / controller
# here — the m2note kernel has the legacy android_usb gadget, driven by
# rootdir/init.mt6735.usb.rc and the platform init.usb.rc (configfs=0 path).
# sys.usb.ffs.aio_compat=1 (m5c usb-shell 2026-08-29): Pie adbd uses AIO on
# FunctionFS by default, and on the MTK musb path AIO wedged bulk-IN.  Oreo
# adbd (what ran on 15.1) did not use AIO, so 15.1 proves nothing here —
# kept on (review 2026-09-25); harmless where AIO works.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.zygote=zygote64_32 \
    persist.sys.usb.config=adb \
    sys.usb.ffs.aio_compat=1 \
    pm.dexopt.first-boot=quicken \
    pm.dexopt.boot=verify \
    pm.dexopt.install=speed-profile \
    pm.dexopt.bg-dexopt=speed-profile \
    pm.dexopt.ab-ota=speed-profile \
    pm.dexopt.inactive=verify \
    pm.dexopt.shared=speed

# zygote services + cpuset masks (m5c: no first-stage mount -> prop.default is
# never loaded and import /init.${ro.zygote}.rc resolves empty).
PRODUCT_COPY_FILES += \
    device/meizu/m2note/rootdir/forge-zygote.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-zygote.rc \
    device/meizu/m2note/rootdir/forge-cpuset.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-cpuset.rc

# Modem bring-up chain (m5c forge-modem.rc; mux waits for mtk.md1.status=ready
# on this 3.18 kernel — see the file header).
PRODUCT_COPY_FILES += \
    device/meizu/m2note/rootdir/forge-modem.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-modem.rc

PRODUCT_COPY_FILES += \
    device/meizu/m2note/configs/spn-conf.xml:system/etc/spn-conf.xml

# GNSS: stock legacy gps.mt6753.so behind the AOSP gnss@1.0 passthrough (mnld is
# M-era; the m5c source HAL speaks Gen-N).  ro.hardware.gps=m2note (FACT live
# getprop) finds no gps.m2note.so; hw_get_module then falls through to
# ro.board.platform -> gps.mt6753.so.
PRODUCT_PACKAGES += \
    android.hardware.gnss@1.0-impl \
    android.hardware.gnss@1.0-service

$(call inherit-product, device/meizu/m2note/forge-peripherals.mk)

# Telephony: MTK Oreo HIDL rild + libril (vendor/mediatek/ril, built for
# m2note by vendor/mediatek/Android.mk itself); the stock RIL pair is pinned as
# modules in vendor/meizu/m2note/Android.mk.
ENABLE_VENDOR_RIL_SERVICE := true
PRODUCT_PACKAGES += \
    rild \
    librilmtk \
    mtk-ril

PRODUCT_PACKAGES += \
    forge_vendor_firmware_link

# Blob ABI shims paired in BoardConfig.mk TARGET_LD_SHIM_LIBS.  The linker loads
# a shim like a DT_NEEDED library (bionic linker.cpp:1368-1371 @29f0b5db): if
# the file is not in the image, the CONSUMER fails to load — so they must be
# installed (review 2026-09-25: they were paired but not packaged).
PRODUCT_PACKAGES += \
    libshim_vcodec_m2note \
    libshim_icu53_m2note

# Blob modules that vendor/mediatek (included whole for m2note) links by name —
# defined in vendor/meizu/m2note/Android.mk, installed once from here.
PRODUCT_PACKAGES += \
    libged \
    libion_mtk \
    libdpframework
