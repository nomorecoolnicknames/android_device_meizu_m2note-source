# BoardConfig.mk for the Meizu M5c (m5c, model M710H) — MT6737M, arm64, 2 GB RAM.
# LineageOS 16.0 (Android 9 Pie) skeleton, Treble stage A: a REAL /vendor
# partition on custom (mmcblk0p17, exactly 512 MiB), NO VNDK.
#
# Modeled on device/meizu/m95 (standalone Pie BoardConfig in this tree) and
# device/meizu/m681 (the Treble stage A vendor-partition block).  Sources of
# truth: the working LOS 14.1 tree on the forge box
# (/srv/forge/android/m5c/los14.1-m5c-patched/device/meizu/m5c — board/*.mk,
# PlatformConfig.mk, all values boot the device daily on the
# lineage-14.1-20260827 ROM) and its M5C_LOS16_TREBLE_PLAN.md.

DEVICE_PATH := device/meizu/m5c

# Architecture — arm64 quad Cortex-A53 (MT6737M).
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53

TARGET_2ND_ARCH := arm
# Pie combo makefiles ignore armv7-a-neon on an armv8-a primary and warn;
# armv8-a is the correct 2nd-arch variant (m95 gunwest parse gate, 2026-07-26).
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53
TARGET_USES_64_BIT_BINDER := true

# Platform
TARGET_BOARD_PLATFORM := mt6737m
TARGET_BOOTLOADER_BOARD_NAME := mt6737m
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
BOARD_NAME := m5c
BOARD_USES_MTK_HARDWARE := true
MTK_HARDWARE := true

# Kernel — geometry is the 14.1 board/kernel.mk one (boots the device daily).
# The MTK boot-header board tag is "mt6737" (14.1 BOARD_MKBOOTIMG_ARGS).
# androidboot.hardware=mt6735 matches the rc/fstab suffix the live 14.1
# device uses (init.mt6735.rc, fstab.mt6735) — same lesson as the m681 port,
# where androidboot.hardware was REQUIRED for init to import the platform rc.
# buildvariant= is appended by build/make automatically — do not set it here.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 androidboot.selinux=permissive androidboot.hardware=mt6735
# Boot geometry MUST reproduce the addresses of the proven 14.1 image:
#   kernel 0x40080000, ramdisk 0x44000000, tags 0x4e000000.
# The earlier base 0x40078000 (taken from the recovery block) plus the
# 0x00080000 kernel offset landed the kernel at 0x400f8000 - 0x78000 off.
# The MTK loader jumps exactly where the header says, so the kernel never ran:
# no pstore, no last_kmsg, no expdb entry from 4.9 at all, just a boot loop.
# ramdisk and tags happened to come out right with the old base; they do not
# with the correct one, hence all four values move together.
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_OFFSET := 0x00080000
BOARD_RAMDISK_OFFSET := 0x04000000
BOARD_KERNEL_TAGS_OFFSET := 0x0e000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_MKBOOTIMG_ARGS := --kernel_offset $(BOARD_KERNEL_OFFSET) --ramdisk_offset $(BOARD_RAMDISK_OFFSET) --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) --board mt6737

TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
# Prebuilt lane: our 4.9.188 kernel, gzip -n -9 of arch/arm64/boot/Image
# glued with the byte-exact STOCK DTB (captures/20260817-los-first-boot/
# dtb_stock.dtb, 69427 B — project rule: the 4.9 kernel runs with the stock
# DTB byte-for-byte, never the tree-built one).
#
# Provenance of the file now in prebuilt-kernel/ (2026-09-03, display lane):
#   worktree k49-worktrees/piedisp, branch pie-disp, HEAD ae73519c1
#   Linux version 4.9.188-m5c+ #11 SMP PREEMPT Thu Sep  3 18:27:08 MSK 2026
#   md5 349ddd90ad0e60a1ad35270b3e61eb8d
# It carries, on top of the 13 display commits ported from 14.1:
#   ab80fb63a  ion: ION_MM_SET/GET_SF_BUF_INFO (the LOS16 scroll lag:
#              frame median 200-250 ms -> 38 ms, Invalid command(4) 2040 -> 0)
#   e856673d3  ion: the same for the 32-bit compat path
#   b13478280  ion: compat union offset fix (camera lane d8a8dc5bc) + the
#              layout BUILD_BUG_ONs re-pointed at it, and ret_copy checked
#   235dc9759  ion: build-time gate on the ion_mm_data layout
#   840fd40ef  bt: stpbt .write_iter (BT lane 12196ff80)
#   3dda5aeb6  sched: CONFIG_CPUSETS (see rootdir/forge-cpuset.rc)
#   ae73519c1  disp: forge-bornsig probe (tearing lane, zero cost per frame)
# The previous comment named pie-config d0f794f8d; that branch has since lost
# the SMI fix (smi_legacy.c / mmsys_config) and must NOT be built from —
# pie-disp carries it (mtk-smi.c +20, smi_legacy.c +15 against pie-config).
#
# Packaging gate held on this file:
#   strings Image.gz-dtb | grep -c mt6735m-mmc   == 2
#   strings Image.gz-dtb | grep -c mediatek,msdc == 0
# (i.e. the stock DTB is inside, the tree-built DTB is NOT).  Beware: grep -c
# returns 1 on ZERO matches, and zero is what the msdc gate wants — under
# set -e that kills the checking script exactly when it succeeds.
TARGET_KERNEL_SOURCE :=
TARGET_KERNEL_CONFIG :=
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt-kernel/Image.gz-dtb
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb

# Гейт свежести prebuilt-ядра.  Файл выше кладётся в дерево РУКАМИ и молча
# устаревает: 2026-09-03 здесь лежало ядро от 28 августа, и чистая сборка
# отгрузила бы ROM без единой правки того дня.  Инвентарь по файлам
# /system и /vendor этого не ловит — ядро в эти разделы не входит.
# Правило, которое человек должен помнить, уже один раз не сработало;
# это — правило, которое валит сборку.  Подробности несовпадения уходят в
# stderr (видны в логе как есть), в stdout — короткий маркер.
# Проверено негативно: с ядром от 28 августа make останавливается с кодом 2.
forge_kernel_check := $(shell $(DEVICE_PATH)/tools/check_prebuilt_kernel.sh \
        $(TARGET_PREBUILT_KERNEL) $(DEVICE_PATH)/prebuilt-kernel/EXPECTED.txt)
ifneq ($(strip $(forge_kernel_check)),)
$(error $(forge_kernel_check))
endif

# Partitions — 14.1 board/filesystem.mk + the p86 partition map.
# recovery: fastboot getvar says 32 MiB; the 14.1 BoardConfig's 20 MiB is a
# known contradiction (M5C_LOS16_TREBLE_PLAN.md §1.1 — ground truth getvar).
BOARD_BOOTIMAGE_PARTITION_SIZE := 16777216
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 1610612736
BOARD_CACHEIMAGE_PARTITION_SIZE := 419430400
BOARD_USERDATAIMAGE_PARTITION_SIZE := 12831948800
BOARD_FLASH_BLOCK_SIZE := 131072

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USES_MKE2FS := true
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4

# --- Treble stage A (mirrors m681 BoardConfig.mk vendor block) -------------
# /vendor is a REAL partition: custom = mmcblk0p17, exactly 512 MiB, never
# mounted by LOS 14.1 — the same size as m681's custom(p3) byte for byte.
# TARGET_COPY_OUT_VENDOR=vendor is what makes the difference: it builds a
# vendor.img and removes the ramdisk /vendor -> /system/vendor symlink.
# Stage A ONLY: PRODUCT_FULL_TREBLE_OVERRIDE stays false and
# PRODUCT_SHIPPING_API_LEVEL stays 25 (lineage_m5c.mk), so VNDK enforcement
# is NOT turned on — it is unreachable for this blob set (134 of 403 vendor
# ELFs need framework libs, plan §6.2) and is not required for a vendor
# partition (PRODUCT_USE_VNDK gates on shipping API level, not on Treble).
TARGET_COPY_OUT_VENDOR := vendor
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_PARTITION_SIZE := 536870912

# A-only — no slots, no dynamic partitions.  fastboot is DEAD on this device
# (writes no partition); flashing is TWRP/dd over by-name only.
AB_OTA_UPDATER := false
BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/fstab.mt6735
TARGET_RECOVERY_PIXEL_FORMAT := BGRA_8888
TARGET_SCREEN_WIDTH := 720
TARGET_SCREEN_HEIGHT := 1280

# System props
TARGET_SYSTEM_PROP := $(DEVICE_PATH)/system.prop

# SELinux: runtime stays androidboot.selinux=permissive for bring-up (same
# as 14.1 and the m681/m95 ports).  Pie public-policy neverallows reject
# Oreo-era MTK vendor rules; skip build-time assertions until an enforcing
# build is attempted (same flag the mt6755-common layer uses).
SELINUX_IGNORE_NEVERALLOWS := true

# Seccomp (mediacodec policy carried from 14.1; the MTK omx lesson from m681:
# without the vendor seccomp policy the omx service hits SIGSYS and bootloops).
BOARD_SECCOMP_POLICY := $(DEVICE_PATH)/seccomp

# Wi-Fi — MTK conn_soc (MT6735 CONSYS).  Same control path 14.1 proves live
# (/dev/wmtWifi write 1/0), wired the m681 way for the Pie wifi stack.
BOARD_WLAN_DEVICE := MediaTek
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_mt66xx
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_mt66xx
WIFI_DRIVER_STATE_CTRL_PARAM := /dev/wmtWifi
WIFI_DRIVER_STATE_ON := 1
WIFI_DRIVER_STATE_OFF := 0

# Bluetooth — same CONSYS; the HIDL service arrives with the stage-4 lane.
BOARD_HAVE_BLUETOOTH := true
BOARD_HAVE_BLUETOOTH_MTK := true
BOARD_BLUETOOTH_DOES_NOT_USE_RFKILL := true

# RIL bridge anchor (hardware/ril/libril/librilmtk_force_needed.c): the m95
# default isMalSupported does not exist in the m5c M-era stock libril — our
# librilimp exports exactly the 8 non-MAL symbols mtk-ril.so imports
# (fact-checked with nm -D 2026-08-28, see M5C_LOS16_TREE_BRINGUP.md).
# isEpdgSupport is one of those 8.
FORGE_LIBRILMTK_KEEP_ANCHOR := isEpdgSupport

# Vendor-blob ABI shim. libvcodecdrv.so (Flyme / Android 7.1) imports
# __pthread_gettid, dropped from bionic in Pie; the missing symbol breaks the
# dlopen chain of /vendor/lib/egl/libGLES_mali.so, so the 32-bit zygote aborts
# with couldn't find an OpenGL ES implementation and the boot never finishes.
# The 64-bit path is unaffected, which is why bootanimation ran while the
# framework did not. See shims/pthread_gettid_shim.c.
# Three 32-bit blobs import the symbol (nm -D -u over proprietary/lib):
# libvcodecdrv is the boot blocker, reached through the Mali dlopen chain;
# libMtkOmxVdecEx and libmtkjpeg would trip later on video decode and JPEG.
# All three take the same shim. The 64-bit blobs are clean.
TARGET_LD_SHIM_LIBS += \
    /system/lib/libvcodecdrv.so|/system/vendor/lib/libshim_vcodec.so \
    /system/lib/libMtkOmxVdecEx.so|/system/vendor/lib/libshim_vcodec.so \
    /system/lib/libmtkjpeg.so|/system/vendor/lib/libshim_vcodec.so

# GPS blobs (N-era, ELF32 only), the m95/m681 pattern:
#  - /vendor/bin/mtk_agpsd links seven ICU-56 ucnv_* exports (readelf
#    --dyn-syms 2026-09-03: UCNV_FROM_U_CALLBACK_STOP_56, UCNV_TO_U_CALLBACK_
#    STOP_56, ucnv_close_56, ucnv_convertEx_56, ucnv_open_56,
#    ucnv_setFromUCallBack_56, ucnv_setToUCallBack_56); Pie ships ICU 60+ and
#    the daemon dies at the linker with "cannot locate symbol UCNV_FROM_U_
#    CALLBACK_STOP_56". libmtkshim_icu (vendor/mediatek/symbols/icu.cpp) is
#    the thin forwarder set; m5c is already in vendor/mediatek/Android.mk's
#    device filter, so only the wiring is new here.
#  - /vendor/bin/mnld: its libmnl.so destroys a mutex twice per session stop,
#    which Pie's FORTIFY turns into SIGABRT; libmnld_shim (shims/pthread.c)
#    is the no-op interposer, queued before libc for the whole process.
# Consumer paths are realpath()'d by the linker at parse time, so on this
# real-/vendor-partition image the canonical /vendor/... spelling is used.
# Executable consumers: the linker matches the exe's /proc/self/exe path.
TARGET_LD_SHIM_LIBS += \
    /vendor/bin/mtk_agpsd|/vendor/lib/libmtkshim_icu.so \
    /vendor/bin/mnld|/vendor/lib/libmnld_shim.so

# Peripherals lane 2026-09-03 (forge-peripherals.mk; evidence in
# M5C_LOS16_PERIPHERALS_20260903.md).  Measured with blobsym.py over the
# LOS 16 out tree, both ABIs; every pair below closes a real "cannot locate
# symbol" the linker would otherwise hit:
#  - audio.primary.mt6737m.so: 11 MTK AudioSystem::*VoiceUnlock* statics that
#    AOSP libmedia never exported -> libshim_audio_m5c (shims/audio_voiceunlock.c).
#  - camera HAL closure: libcam_utils (2 GraphicBuffer ctors), libmtk_mmutils
#    (GraphicBuffer(w,h,fmt,usage)), libmmsdkservice.feature (createBufferQueue
#    with IGraphicBufferAlloc, BufferItemConsumer ctor + setName, and the
#    libui GraphicBuffer(ANativeWindowBuffer*,bool)) -> the m95 gui/ui thunks.
# The linker realpath()s the consumer half and matches the loaded library's
# realpath, so 32- and 64-bit consumers are separate pairs (no ${LIB}).
TARGET_LD_SHIM_LIBS += \
    /vendor/lib/hw/audio.primary.mt6737m.so|/vendor/lib/libshim_audio_m5c.so \
    /vendor/lib64/hw/audio.primary.mt6737m.so|/vendor/lib64/libshim_audio_m5c.so \
    /vendor/lib/libcam_utils.so|/vendor/lib/libmtkshim_gui.so \
    /vendor/lib64/libcam_utils.so|/vendor/lib64/libmtkshim_gui.so \
    /vendor/lib/libmtk_mmutils.so|/vendor/lib/libmtkshim_gui.so \
    /vendor/lib64/libmtk_mmutils.so|/vendor/lib64/libmtkshim_gui.so \
    /vendor/lib/libmmsdkservice.feature.so|/vendor/lib/libmtkshim_gui.so \
    /vendor/lib/libmmsdkservice.feature.so|/vendor/lib/libmtkshim_ui.so \
    /vendor/lib64/libmmsdkservice.feature.so|/vendor/lib64/libmtkshim_gui.so \
    /vendor/lib64/libmmsdkservice.feature.so|/vendor/lib64/libmtkshim_ui.so

# --- Stage 4: telephony via the MTK Oreo HIDL RIL (vendor/mediatek/ril) -----
# FACT (readelf, 2026-09-03, M5C_LOS16_TREE_BRINGUP.md): the stock mtk-ril.so
# has no RIL_Init (only RIL_InitSocket), so the AOSP rild can never host it;
# the stock mtkrild needs seven MTK entry points (RIL_registerSocket,
# RIL_queryMyChannelId, ...) that the AOSP-Pie libril lacks, so with our
# librilmtk it registered the vendor RIL with the STOCK (socket-only) libril
# and Pie telephony never saw an IRadio. vendor/mediatek/ril's rild.c does
# RIL_InitSocket -> RIL_registerSocket and its libril publishes IRadio 1.0.
# BOARD_PROVIDES_LIBRIL skips hardware/ril/libril entirely (incl. its
# librilmtk-SONAME build and the FORGE_LIBRILMTK_KEEP_ANCHOR hook above,
# which is now inert); ENABLE_VENDOR_RIL_SERVICE (device.mk) swaps rild.
# TARGET_SPECIFIC_HEADER_PATH puts MTK's telephony/ril.h (RIL_Env with the
# MTK proxy/channel slots) ahead of hardware/ril's — m681 BoardConfig.mk:208.
BOARD_PROVIDES_LIBRIL := true
TARGET_SPECIFIC_HEADER_PATH := vendor/mediatek/include

# VINTF device manifest (peripherals lane 2026-09-03).  Without it
# hwservicemanager answers getTransport() EMPTY for every vendor HAL and
# HalDeviceManager.isSupported() concludes there is no Wi-Fi vendor HAL, so
# the MTK combo driver is never powered up and wlan0 never appears.  See the
# comment at the top of manifest.xml.
DEVICE_MANIFEST_FILE := device/meizu/m5c/manifest.xml
