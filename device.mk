LOCAL_PATH := device/meizu/m2note


$(call inherit-product, vendor/meizu/m2note/m2note-vendor.mk)

PRODUCT_DEVICE := m2note

# Screen: 1080x1920, 420 dpi (FACT, live getprop capture v212) -> xxhdpi.
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi

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

PRODUCT_PACKAGES += \
    hwcomposer.mt6753 \
    android.hardware.graphics.composer@2.1-impl \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.mapper@2.0-impl \
    libhwc2on1adapter

PRODUCT_PACKAGES += \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service

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

PRODUCT_PACKAGES += \
    libshim_vcodec_m2note \
    libshim_icu53_m2note

# Blob modules that vendor/mediatek (included whole for m2note) links by name —
# defined in vendor/meizu/m2note/Android.mk, installed once from here.
PRODUCT_PACKAGES += \
    libged \
    libion_mtk \
    libdpframework
