# GPS for LOS 16 m5c: only the legacy gps.h HAL module is built from source
# here (gps_hal/, the 14.1 Gen-N source HAL that proved NMEA end-to-end on
# 2026-08-27). mnld / libmnl / mtk_agpsd / libcurl are the Gen-N BLOBS from
# vendor/meizu/m5c (m5c-vendor-blobs.mk), not the 14.1 mtk_mnld sources.
LOCAL_PATH := $(call my-dir)

include $(LOCAL_PATH)/gps_hal/Android.mk
