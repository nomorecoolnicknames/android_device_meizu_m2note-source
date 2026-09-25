LOCAL_PATH := device/meizu/m5c

# Vendor blobs, ported from the working 14.1 tree.  m5c-vendor-blobs.mk keeps
# its protective comments: the md_ctrl and hwcomposer blobs are DELIBERATELY
# absent there — each used to shadow a module this project builds from source
# (md_ctrl sources / forge_hwc) and each broke boot in its own way (FORTIFY
# crash loop -> WDT reboot; GameDetector abort -> black screen).  Do not
# re-add them when regenerating the list.
$(call inherit-product-if-exists, vendor/meizu/m5c/m5c-vendor.mk)

PRODUCT_DEVICE := m5c

# Screen: 720x1280 -> xhdpi.
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xhdpi

# Dalvik heap for a 720p / 2 GB RAM phone (AOSP phone-xhdpi-2048 profile).
# Set explicitly after the m95 lesson: a wrong inherit-if-exists path leaves
# the 16 MB default growth limit and system_server OOMs.
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=8m \
    dalvik.vm.heapgrowthlimit=192m \
    dalvik.vm.heapsize=512m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=8m

# Prebuilt kernel into the target-files "kernel" slot (m681/14.1 pattern):
# bacon/target_files generation must not emit an empty ":kernel" rule.
M5C_EFFECTIVE_KERNEL_PREBUILT := $(strip $(TARGET_PREBUILT_KERNEL))
ifneq ($(M5C_EFFECTIVE_KERNEL_PREBUILT),)
PRODUCT_COPY_FILES += \
    $(M5C_EFFECTIVE_KERNEL_PREBUILT):kernel
endif

# Ramdisk: fstab (vendor = custom!) plus the N-era MTK rc set carried over
# from 14.1 as the porting base.  The rc files are NOT yet ported to Pie
# init — stage 2 of M5C_LOS16_TREBLE_PLAN.md owns that rework (the plan
# explicitly kills the "ramdisk shared with stock" rule at 15.1+).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/fstab.mt6735:root/fstab.mt6735 \
    $(LOCAL_PATH)/rootdir/init.mt6735.rc:root/init.mt6735.rc \
    $(LOCAL_PATH)/rootdir/init.mt6735.usb.rc:root/init.mt6735.usb.rc \
    $(LOCAL_PATH)/rootdir/init.modem.rc:root/init.modem.rc \
    $(LOCAL_PATH)/rootdir/init.project.rc:root/init.project.rc \
    $(LOCAL_PATH)/rootdir/init.recovery.mt6735.rc:root/init.recovery.mt6735.rc \
    $(LOCAL_PATH)/rootdir/ueventd.mt6735.rc:root/ueventd.mt6735.rc \
    $(LOCAL_PATH)/rootdir/enableswap.sh:root/enableswap.sh

# Recovery also needs the fstab at its own path.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/fstab.mt6735:recovery/root/fstab.mt6735

# Keylayouts — device-verified input set from 14.1 (touch GT917D via
# mtk-tpd/mtk-tpd-kpd, keys mtk-kpd, headset ACCDET).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/keylayout/mtk-kpd.kl:system/usr/keylayout/mtk-kpd.kl \
    $(LOCAL_PATH)/keylayout/mtk-tpd.kl:system/usr/keylayout/mtk-tpd.kl \
    $(LOCAL_PATH)/keylayout/mtk-tpd-kpd.kl:system/usr/keylayout/mtk-tpd-kpd.kl \
    $(LOCAL_PATH)/keylayout/ACCDET.kl:system/usr/keylayout/ACCDET.kl

# MTK omx vendor seccomp policy (m681 evidence: SIGSYS -> crash_dump storm
# -> OOM/bootloop without it).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/seccomp/mediacodec.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy

# Permission xmls — only hardware that exists AND works on this unit
# (component matrix 2026-08-28).  No fingerprint/NFC/gyroscope: the hardware
# is physically absent on this device.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/handheld_core_hardware.xml:system/etc/permissions/handheld_core_hardware.xml \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:system/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:system/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.location.gps.xml:system/etc/permissions/android.hardware.location.gps.xml \
    frameworks/native/data/etc/android.hardware.telephony.gsm.xml:system/etc/permissions/android.hardware.telephony.gsm.xml \
    frameworks/native/data/etc/android.hardware.camera.xml:system/etc/permissions/android.hardware.camera.xml \
    frameworks/native/data/etc/android.hardware.camera.autofocus.xml:system/etc/permissions/android.hardware.camera.autofocus.xml \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:system/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:system/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:system/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:system/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:system/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:system/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:system/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:system/etc/permissions/android.hardware.usb.host.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:system/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:system/etc/permissions/android.hardware.wifi.direct.xml

# Treble HAL backbone — core plumbing only.  Per-HAL services (composer,
# audio, camera provider, wifi, bt, gnss, ...) arrive with their bring-up
# stages (plan §5) so each failure is attributable to one change.
PRODUCT_PACKAGES += \
    hwservicemanager \
    vndservicemanager \
    servicemanager

# Stage 3 (plan §4): graphics lane. surfaceflinger aborts with
# "failed to get hwcomposer service" without these (tombstone 2026-08-29).
# forge_hwc (HWC1.1, device/meizu/m5c/hwcomposer) is loaded by the
# composer@2.1 passthrough via hw_get_module(ro.board.platform=mt6737m)
# and wrapped by libhwc2on1adapter automatically (HWC1 -> HWC2).
# gralloc.mt6737m.so blob is already in /vendor/lib*/hw (blobs.mk);
# allocator/mapper are the standard passthrough wrappers over it.
PRODUCT_PACKAGES += \
    hwcomposer.mt6737m \
    android.hardware.graphics.composer@2.1-impl \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.mapper@2.0-impl \
    libhwc2on1adapter

# keystore aborts with "no viable keymaster device found" because no
# keymaster HAL is registered (hwservicemanager: cannot find
# android.hardware.keymaster@3.0/@4.0::IKeymasterDevice/default).
# The AOSP 3.0 default impl is a pure software keymaster (libsoftkeymaster*),
# no TEE needed - enough to get past the boot blocker.
PRODUCT_PACKAGES += \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service

# USB/adb under Pie: nobody in the N-era usb rc sets the configfs knobs, and
# a late setprop misses the "on boot && property:" combined triggers (they
# fire once, at boot). Static props arm the AOSP init.usb.configfs.rc path
# from the start. UDC name is a FACT from the live 4.9 kernel (/sys/class/udc).
# 2026-08-29 hard-won fact: on this no-first-stage-mount device the ONLY prop
# file early init actually loads is /system/build.prop (PRODUCT_PROPERTY_
# OVERRIDES). /system/etc/prop.default and /vendor/default.prop are NEVER read
# (property_load_boot_defaults runs before /system and /vendor are mounted),
# so PRODUCT_(SYSTEM_)DEFAULT_PROPERTY_OVERRIDES values silently vanish.
# ro.zygote additionally cannot come from ANY prop file (import resolves
# during early init.rc parsing) - the zygote services are therefore declared
# in rootdir/forge-zygote.rc (vendor rc, parsed inside mount_all).
PRODUCT_PROPERTY_OVERRIDES += \
    ro.zygote=zygote64_32 \
    sys.usb.configfs=1 \
    sys.usb.controller=musb-hdrc \
    persist.sys.usb.config=adb \
    sys.usb.ffs.aio_compat=1 \
    pm.dexopt.first-boot=quicken \
    pm.dexopt.boot=verify \
    pm.dexopt.install=speed-profile \
    pm.dexopt.bg-dexopt=speed-profile \
    pm.dexopt.ab-ota=speed-profile \
    pm.dexopt.inactive=verify \
    pm.dexopt.shared=speed

# Device half of the P configfs gadget + zygote services (see rootdir files).
PRODUCT_COPY_FILES += \
    device/meizu/m5c/rootdir/forge-usb-gadget.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-usb-gadget.rc \
    device/meizu/m5c/rootdir/forge-zygote.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-zygote.rc \
    device/meizu/m5c/rootdir/forge-cpuset.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-cpuset.rc

# Blob ABI shim for libvcodecdrv.so (see BoardConfig.mk TARGET_LD_SHIM_LIBS).
PRODUCT_PACKAGES += \
    libshim_vcodec

# com.android.bluetooth aborts in hci_layer_android.cc: Check failed:
# btHci != nullptr - no IBluetoothHci service is registered. The AOSP
# default HAL wraps the vendor libbt-vendor.so, same pattern as the
# graphics and keymaster HALs above.
PRODUCT_PACKAGES += \
    android.hardware.bluetooth@1.0-impl

# Blob shims ported from m95: libfs_mgr.so stub (Pie has no such .so, and
# nvram_daemon/mnld die at the linker without it, stalling the modem chain)
# and the MTK RIL net symbol.
PRODUCT_PACKAGES += \
    libfs_mgr_m5c_shim \
    libmtkshim_net

# GPS blob shims (see BoardConfig.mk TARGET_LD_SHIM_LIBS): ICU-56 forwarders
# for mtk_agpsd and the pthread_mutex_destroy interposer for mnld. Without
# the packages the linker pairs silently no-op (m681 lesson).
PRODUCT_PACKAGES += \
    libmtkshim_icu \
    libmnld_shim

# Modem bring-up chain as a vendor rc. Placed on the live device by hand on
# 2026-08-29 (/vendor/etc/init/forge-modem.rc); this makes the build carry it.
PRODUCT_COPY_FILES += \
    device/meizu/m5c/rootdir/forge-modem.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/forge-modem.rc

# Operator names by MCC/MNC for the status bar. Lost together with the whole
# configs/ directory when the tree was ported from 14.1; without it the shade
# shows the raw PLMN or nothing where "Beeline" belongs. Read by the framework
# from /system/etc, not from vendor. Restored 2026-09-03 from the 14.1 tree,
# md5 481b9ce7148a9b62d2fc0cbad8f6db03, byte-identical to what is running on
# the device.
#
# NB: configs/ was lost WHOLESALE when the tree was ported, and it is being
# restored by TWO lanes, on purpose: this line (sim/RIL) and the media_codecs*/
# media_profiles/hostapd block in forge-peripherals.mk (peripherals). Neither
# is redundant - the directory is shared, the lines are not. Do not "tidy up"
# one of them into the other without asking both lanes.
PRODUCT_COPY_FILES += \
    device/meizu/m5c/configs/spn-conf.xml:system/etc/spn-conf.xml

# GNSS: the legacy gps.h HAL built from the 14.1 sources (device/meizu/m5c/gps)
# behind the AOSP gnss@1.0 passthrough service. Without these the daemons
# (mnld, mtk_agpsd) run but the framework has no IGnss to bind to.
PRODUCT_PACKAGES += \
    gps.mt6737m \
    android.hardware.gnss@1.0-impl \
    android.hardware.gnss@1.0-service

# Peripheral HALs (Wi-Fi, sensors, lights, vibrator, camera/torch, audio
# blob deps + shim) — separate file so the lane stays reviewable as one unit.
$(call inherit-product, device/meizu/m5c/forge-peripherals.mk)

# Stage 4: MTK Oreo HIDL rild + libril from vendor/mediatek/ril instead of the
# AOSP rild (see BoardConfig.mk). hardware/ril/rild/Android.mk:3 is
# `ifndef ENABLE_VENDOR_RIL_SERVICE`, vendor/mediatek/ril/rild/Android.mk:1 is
# `ifeq (...,true)`. The two stock blobs are pinned as modules
# (vendor/meizu/m5c/Android.mk) because the MTK libril links them by name.
ENABLE_VENDOR_RIL_SERVICE := true
PRODUCT_PACKAGES += \
    rild \
    librilmtk \
    mtk-ril

# Modem firmware reachability: /vendor/firmware -> etc/firmware symlink in the
# vendor image (see firmware-link/Android.mk and rootdir/ueventd.mt6735.rc).
PRODUCT_PACKAGES += \
    forge_vendor_firmware_link
