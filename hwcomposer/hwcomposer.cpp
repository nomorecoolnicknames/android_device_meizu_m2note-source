/*
 * m2note source HWC 1.1 — v273: DDP overlay present, fb stride source-truth
 *
 * DESIGN INTENT
 * -------------
 * v213 used CPU memcpy → fb0 + FBIOPAN_DISPLAY.  That path has two problems:
 *   (a) ~4 MB of CPU bandwidth every frame (lag/thermal)
 *   (b) FBIOPAN waits for the panel vblank, blocking SF's present path
 *
 * v214/v215 added an experimental MediaTek session/overlay path:
 *   /dev/mtk_disp_mgr  →  DISP_IOCTL_SET_INPUT_BUFFER  →  OVL0 DMA
 * The CPU does no pixel work at all.  The OVL0 hardware reads the
 * SurfaceFlinger-composited FRAMEBUFFER_TARGET buffer directly.
 *
 * v216 proved the safe fallback boots cleanly but is still visibly laggy because
 * every frame is copied by CPU into fb0. v217 returned to the hardware DDP
 * present path and removed the suspect SF-facing present-fence dependency that
 * showed up in v215c freeze evidence. v220 fixes the kernel-facing DDP contract:
 * src_pitch is a pixel stride, not a byte pitch, and all unused OVL slots are
 * explicitly disabled every frame so stale boot/SF layers cannot keep scanning.
 * v273 keeps v240's no-hot-gralloc overlay path, but restores the real
 * allocation stride without calling gralloc_extra in the hot path.  Runtime
 * evidence showed SurfaceFlinger allocating 1080 (1088) x 1920 while v241
 * submitted src_pitch=1080; fb0 line_length is the kernel-backed stride for
 * the primary framebuffer allocation, so this module derives pixel stride from
 * fb0 line_length / bytes-per-pixel and falls back to display width only when
 * fbdev exposes no usable stride.
 *
 * COMPOSITION MODEL (safe baseline, same as v213)
 * ------------------------------------------------
 * hwc_prepare()   — forces every app layer to HWC_FRAMEBUFFER so SF GLES-
 *                   composites everything into the single FRAMEBUFFER_TARGET.
 * hwc_set()       — presents that ONE FB_TARGET layer through OVL0 by default,
 *                   while still sending all four OVL slots to the kernel so
 *                   slots 1-3 are actively disabled. fb0 remains the fallback
 *                   path when overlay setup fails or
 *                   persist/debug.forge.m2note.overlay_hwc=0 is set.
 *
 * FALLBACK
 * --------
 * The module always presents something. If the overlay path fails, it
 * falls back to the v213/v216 fb0 memcpy path.
 *
 * AUTHORITATIVE SOURCES
 * ---------------------
 *   kernel header : drivers/misc/mediatek/video/include/disp_session.h
 *   kernel handler: drivers/misc/mediatek/video/mt6735/videox/mtk_disp_mgr.c
 *   RE spec       : export/m2note_flash_captures/v213_hwc_blob_re.md
 *   gralloc_extra : vendor/mediatek/libgralloc_extra/include/ui/gralloc_extra.h
 *   ion           : system/core/libion/include/ion/ion.h
 *
 * Every struct/ioctl used here is cross-referenced to kernel header line numbers
 * in block comments above its first use.
 */

#define LOG_TAG "hwcomposer.mt6753"

#include <hardware/hardware.h>
#include <hardware/hwcomposer.h>
#include <hardware/gralloc.h>

/* gralloc_extra: gralloc_extra_query, GRALLOC_EXTRA_GET_ION_FD,
 * GRALLOC_EXTRA_GET_FORMAT, GRALLOC_EXTRA_GET_STRIDE               */
#include <ui/gralloc_extra.h>

/* ion_open, ion_close, ion_import, ion_share, ion_free             */
#include <ion/ion.h>

/* sync_wait — used in fb0 fallback path to drain FB_TARGET acquireFenceFd   */
#include <sync/sync.h>

/* disp_session.h types used below — included verbatim from kernel tree via
 * LOCAL_C_INCLUDES in Android.mk.  All struct/enum names match exactly.      */
#include <disp_session.h>

#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <linux/fb.h>
#include <pthread.h>
#include <time.h>

#include <cutils/log.h>
#include <cutils/properties.h>

/* =========================================================================
 * Constants
 * ========================================================================= */

/* Maximum overlay layers we will ever submit.
 * MT6753 primary OVL0 has 4 hardware layers (maxLayerNum == 4 from GET_SESSION_INFO).
 * We cap hard at 4 regardless of what the kernel reports, to match the blob's
 * observed behaviour and avoid array overruns (RE §5, §9 rule 1).            */
#define MAX_OVL_LAYERS   4

/* We only ever use layer slot 0 in the safe single-layer baseline.           */
#define FB_TARGET_LAYER  0

/* MULTI-OVL (v462): with true multi-OVL composition we reserve one OVL slot
 * for the FB_TARGET (GLES of the top chrome) and offload up to the remaining
 * three to hardware overlay.  See HWC_MULTI_OVL_60FPS.md §3.                  */
#define MAX_OVERLAY_APP_LAYERS  (MAX_OVL_LAYERS - 1)

/* OVL hardware ROI limits (kernel drivers/.../dispsys/mt6753/ddp_ovl.h:9-10). */
#define OVL_MAX_WIDTH    4095
#define OVL_MAX_HEIGHT   4095

/* MULTI-OVL freeze watchdog (v462b) tunables.
 *   CANARY_FRAMES     : first N multi frames are validated synchronously.
 *   CANARY_TIMEOUT_MS : per-canary-frame block-wait budget for frame-done.
 *   FREEZE_TIMEOUT_NS : a presented frame whose frame-done fence stays unsignalled
 *                       this long means the DDP pipeline stalled -> revert.
 *   WATCHDOG_POLL_MS  : watchdog thread poll cadence.                         */
#define MULTI_OVL_CANARY_FRAMES      3
#define MULTI_OVL_CANARY_TIMEOUT_MS  300
#define MULTI_OVL_FREEZE_TIMEOUT_NS  1000000000ULL   /* 1 s */
#define MULTI_OVL_WATCHDOG_POLL_MS   100

/* Native panel dimensions — used as fallback when GET_SESSION_INFO fails.    */
#define PANEL_W_DEFAULT  1080
#define PANEL_H_DEFAULT  1920

/* =========================================================================
 * Device state
 * ========================================================================= */
struct hwc_ctx {
    hwc_composer_device_1_t base;      /* MUST be first: HAL upcasts via pointer */

    const hwc_procs_t  *procs;
    pthread_t           vsync_thread;
    volatile bool       vsync_running;
    volatile bool       vsync_enabled;
    bool                use_hw_vsync;

    const gralloc_module_t *gralloc;

    /* ---- overlay path (primary present) ---- */
    int          disp_fd;           /* /dev/mtk_disp_mgr               */
    int          ion_client;        /* ion_open() client fd             */
    uint32_t     session_id;        /* filled by CREATE_SESSION         */
    uint32_t     max_layer_num;     /* from GET_SESSION_INFO            */
    uint32_t     display_w;         /* panel width  from GET_SESSION_INFO */
    uint32_t     display_h;         /* panel height from GET_SESSION_INFO */
    bool         overlay_ok;        /* true = overlay path operational  */
    bool         use_present_fence; /* opt-in legacy present fence path  */

    /* ---- MULTI-OVL (v462): true DDP multi-layer hardware composition ---- */
    bool             use_multi_ovl;     /* persist/debug.forge.m2note.multi_ovl */
    volatile bool    multi_ovl_failed;  /* latched off on any multi-path failure
                                         * (set from hwc_set OR watchdog thread) */
    uint32_t         multi_ovl_max;     /* max app layers to offload, 1..MAX_OVERLAY_APP_LAYERS
                                         * (persist/debug.forge.m2note.multi_ovl_max);
                                         * a runtime OVL-bandwidth tuning knob — the stock
                                         * blob caps overlay layers under bandwidth/overlap
                                         * pressure (getBandwidthLimit + ovl_overlap_limit),
                                         * so lower this if the A/B shows overlay underflow. */

    /* ---- MULTI-OVL freeze watchdog (v462b) ----
     * A silent DDP present freeze (frames stop, no ioctl error) would NOT trip
     * the ioctl-error fallback, and this device cannot be recovered by the user
     * with a cold power cycle.  So the module self-detects a stalled pipeline
     * via the per-frame scanout (frame-done) fence and latches multi_ovl_failed
     * WITHOUT needing any external reboot.  Two layers:
     *   (1) canary — the first few multi frames block-wait their frame-done
     *       fence with a short timeout, so a broken multi config reverts within
     *       ~one frame while SurfaceFlinger is still healthy.
     *   (2) watchdog thread — polls the most recent frame's fence; if it has
     *       not signalled within the freeze timeout, latches back to single-OVL.
     *   The watchdog runs on its OWN thread (never in the vsync thread, whose
     *   WAIT_FOR_VSYNC can itself block if the panel TE stalls).              */
    pthread_t        watchdog_thread;
    volatile bool    watchdog_running;
    pthread_mutex_t  watchdog_mutex;    /* guards watchdog_fence + last_present_ns */
    int              watchdog_fence;    /* dup of most recent frame-done fence, -1=none */
    uint64_t         last_present_ns;   /* monotonic ts of most recent multi present */
    uint64_t         freeze_latch;      /* # times the freeze watchdog latched */

    /* Mutex protecting SET_INPUT_BUFFER + TRIGGER_SESSION pair.
     * Must be held for the atomic submit window (RE §9 rule 2).        */
    pthread_mutex_t overlay_mutex;

    /* ---- fb0 fallback path (kept intact from v213) ---- */
    int          fb_fd;
    uint8_t     *fb_mem;
    size_t       fb_page_bytes;
    size_t       fb_total_bytes;
    uint32_t     xres, yres;
    uint32_t     line_length;
    uint32_t     num_pages;
    uint32_t     cur_page;
    struct fb_var_screeninfo var;
    int          blank_req;

    /* ---- statistics (readable via hwc_dump) ---- */
    uint64_t     overlay_present;   /* frames via OVL0 overlay          */
    uint64_t     overlay_fail;      /* per-frame ioctl failures         */
    uint64_t     multi_present;     /* frames w/ >=1 real overlay layer  */
    uint64_t     multi_fail;        /* multi-OVL path failures           */
    uint32_t     last_overlay_count;/* # real overlay layers last frame  */
    uint64_t     fb_fallback;       /* frames via fb0 memcpy fallback   */
    uint64_t     present_pan;       /* fb0 page-flips                   */
    uint64_t     present_copy;      /* fb0 memcpy calls                 */
    uint64_t     present_skip_copy; /* fb0 fb-in-fb skips               */
    uint64_t     present_lock_fail; /* gralloc lock failures            */
    uint64_t     vsync_hw;          /* kernel WAIT_FOR_VSYNC callbacks  */
    uint64_t     vsync_synth;       /* synthetic fallback callbacks      */
    uint64_t     vsync_hw_fail;     /* WAIT_FOR_VSYNC ioctl failures     */

    uint32_t     last_src_w;
    uint32_t     last_src_h;
    uint32_t     last_stride_px;
    uint32_t     last_pitch_bytes;
    uint32_t     last_alloc_size;
    uint32_t     last_vstride;
    uint64_t     metadata_bypass;
};

/* =========================================================================
 * Format + rotation helpers
 * ========================================================================= */

/*
 * hal_to_disp_format — map HAL_PIXEL_FORMAT_* to DISP_FORMAT_*
 *
 * DISP_FORMAT values from disp_session.h lines 54–71:
 *   DISP_FORMAT_RGB565   = MAKE_DISP_FORMAT_ID(1,2)  = 0x0102
 *   DISP_FORMAT_RGB888   = MAKE_DISP_FORMAT_ID(2,3)  = 0x0203
 *   DISP_FORMAT_BGR888   = MAKE_DISP_FORMAT_ID(3,3)  = 0x0303
 *   DISP_FORMAT_ARGB8888 = MAKE_DISP_FORMAT_ID(4,4)  = 0x0404
 *   DISP_FORMAT_ABGR8888 = MAKE_DISP_FORMAT_ID(5,4)  = 0x0504
 *   DISP_FORMAT_RGBA8888 = MAKE_DISP_FORMAT_ID(6,4)  = 0x0604
 *   DISP_FORMAT_BGRA8888 = MAKE_DISP_FORMAT_ID(7,4)  = 0x0704
 *   DISP_FORMAT_YUV422   = MAKE_DISP_FORMAT_ID(8,2)  = 0x0802
 *   DISP_FORMAT_XRGB8888 = MAKE_DISP_FORMAT_ID(9,4)  = 0x0904
 *   DISP_FORMAT_XBGR8888 = MAKE_DISP_FORMAT_ID(10,4) = 0x0a04
 *   DISP_FORMAT_RGBX8888 = MAKE_DISP_FORMAT_ID(11,4) = 0x0b04
 *   DISP_FORMAT_BGRX8888 = MAKE_DISP_FORMAT_ID(12,4) = 0x0c04
 *
 * The FB_TARGET from SurfaceFlinger on this device is RGBA_8888 in practice.
 * We default to DISP_FORMAT_RGBA8888 for any unrecognised format.
 */
static DISP_FORMAT hal_to_disp_format(int hal_fmt)
{
    switch (hal_fmt) {
    case HAL_PIXEL_FORMAT_RGBA_8888:  return DISP_FORMAT_RGBA8888;
    case HAL_PIXEL_FORMAT_RGBX_8888:  return DISP_FORMAT_RGBX8888;
    case HAL_PIXEL_FORMAT_RGB_888:    return DISP_FORMAT_RGB888;
    case HAL_PIXEL_FORMAT_RGB_565:    return DISP_FORMAT_RGB565;
    case HAL_PIXEL_FORMAT_BGRA_8888:  return DISP_FORMAT_BGRA8888;
    case HAL_PIXEL_FORMAT_YV12:       return DISP_FORMAT_YV12;
    /* YCbCr_422_I / UYVY — no direct constant but YUV422 is close */
    case HAL_PIXEL_FORMAT_YCbCr_422_I: return DISP_FORMAT_YUV422;
    default:
        ALOGW("v273: unknown HAL format 0x%x, using RGBA8888", hal_fmt);
        return DISP_FORMAT_RGBA8888;
    }
}

/*
 * hwc_transform_to_disp_orientation — map Android HWC transform to
 * DISP_ORIENTATION for the layer_rotation field.
 *
 * DISP_ORIENTATION enum from disp_session.h lines 47–51:
 *   DISP_ORIENTATION_0   = 0  (no rotation)
 *   DISP_ORIENTATION_90  = 1  (90° CCW)
 *   DISP_ORIENTATION_180 = 2  (180°)
 *   DISP_ORIENTATION_270 = 3  (270° CCW)
 *
 * Android HWC transform constants (hardware/hwcomposer_defs.h):
 *   HWC_TRANSFORM_FLIP_H  = 1  (flip horizontal)
 *   HWC_TRANSFORM_FLIP_V  = 2  (flip vertical)
 *   HWC_TRANSFORM_ROT_90  = 4  (rotate 90° CCW)
 *   HWC_TRANSFORM_ROT_180 = 3  (= FLIP_H | FLIP_V)
 *   HWC_TRANSFORM_ROT_270 = 7  (= FLIP_H | FLIP_V | ROT_90)
 *
 * OVL0 hardware supports pure rotations (0/90/180/270) via the
 * DISP_REG_OVL_Ln_CON[8:9] register field (RE §3.1).  Pure flips
 * (FLIP_H, FLIP_V) are NOT supported by OVL0 natively; those cases
 * fall back to DISP_ORIENTATION_0.  In the safe single-layer baseline
 * all layers are GLES-composited by SF so the FB_TARGET's transform
 * is always 0; this function exists for correctness and future use.
 *
 * SAFE DEFAULT: In the safe baseline, layer_rotation is always set to
 * DISP_ORIENTATION_0.  SF has already composited whatever rotation
 * was needed into the FB_TARGET pixel data.  See ROTATION section of
 * the implementation report for the full discussion.
 */
static DISP_ORIENTATION hwc_transform_to_disp_orientation(uint32_t transform)
{
    switch (transform) {
    case 0:                          return DISP_ORIENTATION_0;
    case HWC_TRANSFORM_ROT_90:       return DISP_ORIENTATION_90;
    case HWC_TRANSFORM_ROT_180:      return DISP_ORIENTATION_180;
    case HWC_TRANSFORM_ROT_270:      return DISP_ORIENTATION_270;
    /* Pure flips: OVL0 has no flip register bit; treat as no-op.
     * SF's compositor will have already handled the flip for FB_TARGET. */
    case HWC_TRANSFORM_FLIP_H:       return DISP_ORIENTATION_0;
    case HWC_TRANSFORM_FLIP_V:       return DISP_ORIENTATION_180;
    default:                         return DISP_ORIENTATION_0;
    }
}

static uint64_t monotonic_ns()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static uint64_t elapsed_us(uint64_t start_ns, uint64_t end_ns)
{
    return (end_ns > start_ns) ? ((end_ns - start_ns) / 1000ULL) : 0ULL;
}

static uint32_t clamp_positive_u32(int value, uint32_t fallback)
{
    return (value > 0) ? (uint32_t)value : fallback;
}

/* =========================================================================
 * Overlay session lifecycle
 * ========================================================================= */

/*
 * overlay_session_open — open /dev/mtk_disp_mgr + ION, create primary session,
 * set mode, query info.  Called once from hwc_device_open().
 *
 * Returns true on full success; false on any failure (caller falls back to fb0).
 *
 * STRUCTS / IOCTLS used (all from disp_session.h):
 *
 *   disp_session_config  (lines 162–172, 9 fields, sizeof == 36 bytes on AArch64):
 *     type, device_id, mode, session_id, user,
 *     present_fence_idx, dc_type, need_merge, tigger_mode
 *   DISP_IOCTL_CREATE_SESSION   = DISP_IOW(201, disp_session_config)  line 367
 *   DISP_IOCTL_SET_SESSION_MODE = DISP_IOW(209, disp_session_config)  line 377
 *
 *   disp_session_info  (lines 273–294):
 *     session_id, maxLayerNum, displayWidth, displayHeight, vsyncFPS, …
 *   DISP_IOCTL_GET_SESSION_INFO = DISP_IOW(208, disp_session_info)   line 374
 *
 * Kernel handler: _ioctl_create_session (mtk_disp_mgr.c line 528)
 *   copies full disp_session_config to/from user; fills session_id on return.
 * Kernel handler: _ioctl_get_info (mtk_disp_mgr.c line 1858)
 *   copies full disp_session_info to/from user.
 */
static bool overlay_session_open(hwc_ctx *d)
{
    /* 1. Open /dev/mtk_disp_mgr
     * DISP_SESSION_DEVICE = "mtk_disp_mgr"  (disp_session.h line 4)          */
    d->disp_fd = open("/dev/mtk_disp_mgr", O_RDWR);
    if (d->disp_fd < 0) {
        ALOGE("v273: open /dev/mtk_disp_mgr failed: %s", strerror(errno));
        return false;
    }

    /* 2. Open ION client (libion: system/core/libion/include/ion/ion.h)       */
    d->ion_client = ion_open();
    if (d->ion_client < 0) {
        ALOGE("v273: ion_open() failed: %s", strerror(errno));
        close(d->disp_fd);
        d->disp_fd = -1;
        return false;
    }

    /*
     * 3. Create primary session
     *    disp_session_config (disp_session.h line 162):
     *      .type       = DISP_SESSION_PRIMARY  (enum value 1, line 113)
     *      .device_id  = 0
     *      .mode       = DISP_SESSION_DIRECT_LINK_MODE (enum value 1, line 127)
     *      .user       = SESSION_USER_HWC (enum value 0, line 140)
     *    All other fields zeroed.
     *    Kernel fills .session_id on return (handler line 541: copy_to_user).
     */
    disp_session_config cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.type      = DISP_SESSION_PRIMARY;
    cfg.device_id = 0;
    cfg.mode      = DISP_SESSION_DIRECT_LINK_MODE;
    cfg.user      = SESSION_USER_HWC;

    if (ioctl(d->disp_fd, DISP_IOCTL_CREATE_SESSION, &cfg) < 0) {
        ALOGE("v273: DISP_IOCTL_CREATE_SESSION failed: %s", strerror(errno));
        ion_close(d->ion_client);
        close(d->disp_fd);
        d->disp_fd = -1;
        d->ion_client = -1;
        return false;
    }
    d->session_id = cfg.session_id;
    ALOGI("v273: session created, session_id=0x%08x", d->session_id);

    /*
     * 4. Set session mode to DIRECT_LINK
     *    Re-uses same disp_session_config; only session_id + mode matter here.
     *    Kernel handler: _ioctl_set_session_mode (mtk_disp_mgr.c line 2403)
     */
    memset(&cfg, 0, sizeof(cfg));
    cfg.session_id = d->session_id;
    cfg.mode       = DISP_SESSION_DIRECT_LINK_MODE;
    cfg.user       = SESSION_USER_HWC;
    if (ioctl(d->disp_fd, DISP_IOCTL_SET_SESSION_MODE, &cfg) < 0) {
        /* Non-fatal: session was created; continue without explicit mode set. */
        ALOGW("v273: DISP_IOCTL_SET_SESSION_MODE failed (non-fatal): %s",
              strerror(errno));
    }

    /*
     * 5. Query session info — get maxLayerNum, displayWidth, displayHeight
     *    disp_session_info (disp_session.h lines 273–294).
     *    We must set .session_id before the ioctl; kernel fills the rest.
     *    Kernel handler: _ioctl_get_info (mtk_disp_mgr.c line 1858)
     */
    disp_session_info info;
    memset(&info, 0, sizeof(info));
    info.session_id = d->session_id;
    if (ioctl(d->disp_fd, DISP_IOCTL_GET_SESSION_INFO, &info) < 0) {
        ALOGE("v273: DISP_IOCTL_GET_SESSION_INFO failed: %s", strerror(errno));
        /* Destroy session and bail */
        memset(&cfg, 0, sizeof(cfg));
        cfg.session_id = d->session_id;
        ioctl(d->disp_fd, DISP_IOCTL_DESTROY_SESSION, &cfg);
        ion_close(d->ion_client);
        close(d->disp_fd);
        d->disp_fd = -1;
        d->ion_client = -1;
        return false;
    }

    /* Cap maxLayerNum to our compile-time safe limit (RE §9 rule 1)           */
    d->max_layer_num = (info.maxLayerNum > 0 && info.maxLayerNum <= MAX_OVL_LAYERS)
                       ? info.maxLayerNum : MAX_OVL_LAYERS;
    d->display_w = (info.displayWidth  > 0) ? info.displayWidth  : PANEL_W_DEFAULT;
    d->display_h = (info.displayHeight > 0) ? info.displayHeight : PANEL_H_DEFAULT;

    ALOGI("v273: session info: maxLayer=%u display=%ux%u vsync=%u",
          d->max_layer_num, d->display_w, d->display_h, info.vsyncFPS);

    return true;
}

/*
 * overlay_session_close — destroy the primary session and close fds.
 * Called from hwc_device_close().
 *
 * DISP_IOCTL_DESTROY_SESSION = DISP_IOW(202, disp_session_config)  line 368
 * Kernel handler: _ioctl_destroy_session (mtk_disp_mgr.c line 573)
 */
static void overlay_session_close(hwc_ctx *d)
{
    if (d->disp_fd >= 0 && d->session_id != 0) {
        disp_session_config cfg;
        memset(&cfg, 0, sizeof(cfg));
        cfg.session_id = d->session_id;
        cfg.type       = DISP_SESSION_PRIMARY;
        cfg.device_id  = 0;
        ioctl(d->disp_fd, DISP_IOCTL_DESTROY_SESSION, &cfg);
        d->session_id = 0;
    }
    if (d->ion_client >= 0) {
        ion_close(d->ion_client);
        d->ion_client = -1;
    }
    if (d->disp_fd >= 0) {
        close(d->disp_fd);
        d->disp_fd = -1;
    }
}

/* =========================================================================
 * fb0 fallback helpers (preserved from v213)
 * ========================================================================= */

static buffer_handle_t fb_target_handle(hwc_display_contents_1_t *c)
{
    if (!c) return NULL;
    for (size_t i = 0; i < c->numHwLayers; i++) {
        if (c->hwLayers[i].compositionType == HWC_FRAMEBUFFER_TARGET)
            return c->hwLayers[i].handle;
    }
    if (c->numHwLayers)
        return c->hwLayers[c->numHwLayers - 1].handle;
    return NULL;
}

/*
 * fb0_present — v213 CPU-copy path; used when overlay is unavailable or
 * when a per-frame ioctl fails.
 */
static void fb0_present(hwc_ctx *d, hwc_display_contents_1_t *c)
{
    buffer_handle_t h = fb_target_handle(c);
    if (!h || !d->gralloc || !d->fb_mem) {
        d->present_lock_fail++;
        return;
    }

    void *src = NULL;
    int rv = d->gralloc->lock(d->gralloc, h,
                              GRALLOC_USAGE_SW_READ_OFTEN,
                              0, 0, d->xres, d->yres, &src);
    if (rv != 0 || !src) {
        d->present_lock_fail++;
        return;
    }

    uint8_t *src8 = (uint8_t *)src;
    bool in_fb = (src8 >= d->fb_mem && src8 < d->fb_mem + d->fb_total_bytes);
    uint32_t pan_page;

    if (in_fb) {
        pan_page = (uint32_t)((src8 - d->fb_mem) / d->fb_page_bytes);
        if (pan_page >= d->num_pages) pan_page = d->cur_page;
        d->present_skip_copy++;
    } else {
        uint8_t *dst = d->fb_mem + (size_t)d->cur_page * d->fb_page_bytes;
        int ge_stride = 0;
        uint32_t src_stride_bytes = d->line_length;

        if (gralloc_extra_query(h, GRALLOC_EXTRA_GET_STRIDE, &ge_stride) == GRALLOC_EXTRA_OK &&
            ge_stride > 0) {
            src_stride_bytes = (uint32_t)ge_stride * 4U;
        }

        if (src_stride_bytes >= d->line_length) {
            for (uint32_t y = 0; y < d->yres; y++) {
                memcpy(dst + (size_t)y * d->line_length,
                       src8 + (size_t)y * src_stride_bytes,
                       d->line_length);
            }
        } else {
            const uint32_t visible_bytes = d->xres * 4U;
            const uint32_t copy_bytes = (src_stride_bytes < visible_bytes) ?
                                        src_stride_bytes : visible_bytes;

            for (uint32_t y = 0; y < d->yres; y++) {
                uint8_t *row = dst + (size_t)y * d->line_length;
                memcpy(row, src8 + (size_t)y * src_stride_bytes, copy_bytes);
                if (copy_bytes < d->line_length)
                    memset(row + copy_bytes, 0, d->line_length - copy_bytes);
            }
        }
        pan_page = d->cur_page;
        d->present_copy++;
        d->cur_page = (d->cur_page + 1) % d->num_pages;
    }

    d->gralloc->unlock(d->gralloc, h);

    d->var.yoffset  = pan_page * d->yres;
    d->var.activate = FB_ACTIVATE_VBL;
    ioctl(d->fb_fd, FBIOPAN_DISPLAY, &d->var);
    d->present_pan++;
    d->fb_fallback++;
}

/* =========================================================================
 * Vsync thread
 * ========================================================================= */
static void *hwc_vsync_thread(void *arg)
{
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(arg);
    const int64_t period_ns = 16666667LL; /* 1e9/60 */
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int64_t next = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;

    while (d->vsync_running) {
        int64_t event_ns = 0;
        bool hw_vsync = false;
        bool want_vsync = d->vsync_enabled;

        if (!want_vsync) {
            struct timespec idle;
            clock_gettime(CLOCK_MONOTONIC, &idle);
            idle.tv_nsec += 50000000LL;
            if (idle.tv_nsec >= 1000000000LL) {
                idle.tv_sec++;
                idle.tv_nsec -= 1000000000LL;
            }
            clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &idle, NULL);
            next = (int64_t)monotonic_ns();
            continue;
        }

        if (want_vsync && d->use_hw_vsync &&
            d->overlay_ok && d->disp_fd >= 0 && d->session_id != 0) {
            disp_session_vsync_config vc;
            memset(&vc, 0, sizeof(vc));
            vc.session_id = d->session_id;

            if (ioctl(d->disp_fd, DISP_IOCTL_WAIT_FOR_VSYNC, &vc) == 0) {
                event_ns = (int64_t)monotonic_ns();
                next = event_ns;
                hw_vsync = true;
                d->vsync_hw++;
            } else {
                d->vsync_hw_fail++;
                ALOGW_IF((d->vsync_hw_fail <= 5) || ((d->vsync_hw_fail % 120) == 0),
                         "v273: WAIT_FOR_VSYNC failed (%llu): %s",
                         (unsigned long long)d->vsync_hw_fail, strerror(errno));
            }
        }

        if (!hw_vsync) {
            next += period_ns;
            struct timespec t;
            t.tv_sec  = next / 1000000000LL;
            t.tv_nsec = next % 1000000000LL;
            clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &t, NULL);
            event_ns = next;
            d->vsync_synth++;
        }

        if (d->procs && d->procs->vsync)
            d->procs->vsync(d->procs, 0, event_ns);
    }
    return NULL;
}

/* =========================================================================
 * MULTI-OVL (v462): true DDP multi-layer hardware composition
 *
 * See HWC_MULTI_OVL_60FPS.md for the full design + kernel evidence.  Summary:
 *   - The kernel primary path exposes 4 hardware OVL layers (layer_id 0..3,
 *     Z bottom->top).  layer_id maps directly to ovl_config[layer_id]
 *     (primary_display.c:6880-6886).  [FACT F1/F2]
 *   - CONFIG_ALL_IN_TRIGGER_STAGE is defined, so every frame must send all 4
 *     slots (used enabled, unused disabled) or a stale slot keeps scanning.
 *     [FACT F4]
 *   - OVL cannot scale (crop only) -> eligible layers must be 1:1. [FACT F5]
 *   - src_pitch is a PIXEL stride; kernel multiplies by Bpp. [FACT F3]
 *   - Per-pixel alpha via sur_aen; coefficients via src_alpha/dst_alpha.
 *     [FACT F6]  X-channel (RGBX/...) alpha auto-forced opaque by the kernel.
 *     [FACT F7]
 *   - Each overlay layer needs its own PREPARE_INPUT_BUFFER carrying its
 *     layer_id + dmabuf fd. [FACT F8]
 *
 * We offload the BOTTOM contiguous run of overlay-eligible layers (the big
 * full-screen wallpaper/workspace on a home swipe) and keep the FB_TARGET on
 * top holding the GLES composition of the remaining chrome.  Gated behind
 * persist/debug.forge.m2note.multi_ovl (default off); any failure latches back
 * to the proven single-OVL path.
 * ========================================================================= */

/*
 * gralloc_disp_format — map a gralloc buffer's HAL format to DISP_FORMAT,
 * restricted to the plain packed RGB(A) formats OVL can scan directly.
 * Returns DISP_FORMAT_UNKNOWN on query failure or any unsupported format
 * (YUV / compressed), which makes the layer ineligible for overlay.
 */
static DISP_FORMAT gralloc_disp_format(buffer_handle_t h)
{
    int hal_fmt = 0;
    if (gralloc_extra_query(h, GRALLOC_EXTRA_GET_FORMAT, &hal_fmt) != GRALLOC_EXTRA_OK)
        return DISP_FORMAT_UNKNOWN;
    switch (hal_fmt) {
    case HAL_PIXEL_FORMAT_RGBA_8888:
    case HAL_PIXEL_FORMAT_RGBX_8888:
    case HAL_PIXEL_FORMAT_RGB_888:
    case HAL_PIXEL_FORMAT_RGB_565:
    case HAL_PIXEL_FORMAT_BGRA_8888:
        return hal_to_disp_format(hal_fmt);
    default:
        return DISP_FORMAT_UNKNOWN;
    }
}

/*
 * layer_transform_supported_by_ovl — keep the first multi-OVL bring-up to
 * transforms that preserve source/destination axes.  ROT_180 is the one this
 * device may expose when ro.sf.hwrotation=180 reaches HWC1 as a layer transform;
 * 90/270 are left on GLES until the rotated geometry path is proven separately.
 */
static bool layer_transform_supported_by_ovl(uint32_t transform)
{
    switch (transform) {
    case 0:
    case HWC_TRANSFORM_ROT_180:
        return true;
    default:
        return false;
    }
}

/*
 * HWC2On1Adapter on this Oreo tree passes planeAlpha==0 for normal visible
 * HWC2 layers.  Treat that legacy bridge value as opaque for the two blending
 * modes this HWC can express in hardware (NONE and PREMULT) when a real buffer
 * has a visible region.  COVERAGE and any nonzero/non-255 plane alpha still
 * stay on GLES.
 */
static uint8_t layer_effective_plane_alpha(const hwc_layer_1_t *l)
{
    if (!l)
        return 0;
    if (l->planeAlpha == 0 &&
        (l->blending == HWC_BLENDING_NONE ||
         l->blending == HWC_BLENDING_PREMULT) &&
        l->visibleRegionScreen.numRects > 0) {
        return 255;
    }
    return l->planeAlpha;
}

/*
 * layer_reject_reason — return NULL if the layer can go to a hardware OVL slot,
 * else a short static string naming the first failed rule.  Conservative first
 * cut (HWC_MULTI_OVL_60FPS.md §3.4): no axis-swapping transform, 1:1 (OVL has
 * no scaler), plain RGB(A), NONE/PREMULT blend, opaque plane alpha, within
 * panel bounds. The reason string is what hwc_prepare logs so an A/B can see
 * WHY a layer was kept on GLES without correlating dumpsys SurfaceFlinger.
 */
static const char *layer_reject_reason(const hwc_layer_1_t *l,
                                       uint32_t panel_w, uint32_t panel_h)
{
    if (!l)                                        return "null";
    if (l->compositionType != HWC_FRAMEBUFFER)     return "comp!=FB";
    if (l->flags & HWC_SKIP_LAYER)                 return "SKIP_LAYER";
    if (!l->handle)                                return "no-handle";   /* dim/solid-colour layer */
    if (l->handle->numFds < 1)                     return "no-dmabuf";
    if (!layer_transform_supported_by_ovl(l->transform)) return "transform";
    if (layer_effective_plane_alpha(l) != 255)     return "planeAlpha<255";

    /* Only NONE + PREMULT are overlay-eligible.  Ghidra of the stock blob
     * (DispDevice::updateOverlayInputs @0x28b78) shows it enables per-pixel
     * alpha ONLY for blending==0x105 (PREMULT); everything else gets sur_aen=0.  */
    if (l->blending != HWC_BLENDING_NONE &&
        l->blending != HWC_BLENDING_PREMULT)       return "blend!=NONE/PREMULT";

    /* 1:1 — OVL cannot scale (FACT F5).  sourceCrop is integer at API 1.1.    */
    int sc_w = l->sourceCrop.right  - l->sourceCrop.left;
    int sc_h = l->sourceCrop.bottom - l->sourceCrop.top;
    int df_w = l->displayFrame.right  - l->displayFrame.left;
    int df_h = l->displayFrame.bottom - l->displayFrame.top;
    if (sc_w <= 0 || sc_h <= 0)                    return "empty-src";
    if (sc_w != df_w || sc_h != df_h)              return "scaled";      /* likely: parallax wallpaper */
    if (sc_w > OVL_MAX_WIDTH || sc_h > OVL_MAX_HEIGHT) return "too-big";

    if (l->displayFrame.left < 0 || l->displayFrame.top < 0)                return "off-screen";
    if ((uint32_t)l->displayFrame.right  > panel_w)                         return "df-right>panel";
    if ((uint32_t)l->displayFrame.bottom > panel_h)                         return "df-bottom>panel";
    if (l->sourceCrop.left < 0 || l->sourceCrop.top < 0)                    return "neg-crop";

    if (gralloc_disp_format(l->handle) == DISP_FORMAT_UNKNOWN)              return "fmt";
    return NULL;
}

static inline bool layer_overlay_eligible(const hwc_layer_1_t *l,
                                          uint32_t panel_w, uint32_t panel_h)
{
    return layer_reject_reason(l, panel_w, panel_h) == NULL;
}

/*
 * fill_layer_alpha — set the OVL alpha/blend fields of one disp_input_config
 * from the HWC blending mode.  Register meaning is FACT F6 (ddp_ovl.c:541-623):
 *   aen       = plane/const-alpha enable
 *   sur_aen   = per-pixel (surface) alpha enable
 *   src_alpha = source coefficient selector   (ONE / SRC / SRC_INVERT)
 *   dst_alpha = destination coefficient selector
 * CONFIRMED (unknown U1 resolved) by ghidra of the stock blob
 * DispDevice::updateOverlayInputs @0x28b78:
 *     if (blending == 0x105 / PREMULT) { sur_aen=1; src_alpha=0(ONE); dst_alpha=2(SRC_INVERT); }
 *     else                             { sur_aen=0; }
 * i.e. premultiplied source-over for PREMULT, per-pixel alpha OFF otherwise.
 * NONE is an opaque overwrite (aen=0; the kernel also forces this for X-channel
 * formats, FACT F7).  COVERAGE never reaches here (eligibility rejects it, as
 * the stock does).  Plane alpha is always 0xFF because eligibility rejects
 * planeAlpha!=255.
 */
static void fill_layer_alpha(disp_input_config *ic, int32_t blending)
{
    ic->alpha = 0xFF;
    if (blending == HWC_BLENDING_NONE) {
        ic->alpha_enable = 0;
        ic->sur_aen      = 0;
        ic->src_alpha    = DISP_ALPHA_ONE;
        ic->dst_alpha    = DISP_ALPHA_ONE;
    } else { /* PREMULT (the only other eligible mode) — stock 0x105 path */
        ic->alpha_enable = 1;
        ic->sur_aen      = 1;
        ic->src_alpha    = DISP_ALPHA_ONE;
        ic->dst_alpha    = DISP_ALPHA_SRC_INVERT;
    }
}

/*
 * fill_common_input — the fields common to every enabled slot.  Geometry,
 * format, stride and alpha are filled by the callers.
 */
static void fill_common_input(disp_input_config *ic, uint32_t layer_id,
                              uint32_t frm_seq)
{
    ic->layer_id        = layer_id;
    ic->layer_enable    = 1;
    ic->buffer_source   = DISP_BUFFER_ION;
    ic->src_phy_addr    = NULL;
    ic->src_direct_link = 0;
    ic->src_use_color_key = 0;
    ic->src_color_key   = 0;
    ic->layer_rotation  = DISP_ORIENTATION_0;   /* callers may overwrite for app layers */
    ic->layer_type      = DISP_LAYER_2D;
    ic->video_rotation  = DISP_ORIENTATION_0;
    ic->isTdshp         = 0;
    ic->identity        = DISP_NO_USE_LAEYR_ID;
    ic->connected_type  = 0;
    ic->security        = DISP_NORMAL_BUFFER;
    ic->frm_sequence    = frm_seq;
    ic->yuv_range       = DISP_YUV_BT601_FULL;
}

/*
 * overlay_prepare_slot — dup the buffer's dmabuf fd, run PREPARE_INPUT_BUFFER
 * for this layer_id, and write ic->next_buff_idx.  On success returns the dup'd
 * fd in *out_dup_fd (caller closes after SET_INPUT) and the scanout release
 * fence in *out_rel_fence (caller hands to SF).  Returns false on any failure.
 */
static bool overlay_prepare_slot(hwc_ctx *d, buffer_handle_t handle,
                                 uint32_t layer_id, disp_input_config *ic,
                                 int *out_dup_fd, int *out_rel_fence)
{
    *out_dup_fd = -1;
    *out_rel_fence = -1;

    int buf_fd = (handle->numFds >= 1) ? handle->data[0] : -1;
    if (buf_fd < 0)
        return false;
    int sfd = dup(buf_fd);
    if (sfd < 0) {
        ALOGW("v462: dup(buf_fd=%d) failed: %s", buf_fd, strerror(errno));
        return false;
    }
    ic->src_base_addr = (void *)(intptr_t)sfd;

    disp_buffer_info bi;
    memset(&bi, 0, sizeof(bi));
    bi.session_id = d->session_id;
    bi.layer_id   = layer_id;
    bi.layer_en   = 1;
    bi.ion_fd     = sfd;
    bi.cache_sync = 0;
    bi.fence_fd   = -1;
    bi.interface_fence_fd = -1;
    if (ioctl(d->disp_fd, DISP_IOCTL_PREPARE_INPUT_BUFFER, &bi) < 0) {
        ALOGW("v462: PREPARE_INPUT_BUFFER l%u failed: %s", layer_id, strerror(errno));
        close(sfd);
        return false;
    }
    if (bi.index == 0 || bi.fence_fd < 0) {
        ALOGW("v462: PREPARE l%u invalid index=%u fence=%d", layer_id, bi.index, bi.fence_fd);
        close(sfd);
        if (bi.fence_fd >= 0) close(bi.fence_fd);
        if (bi.interface_fence_fd >= 0) close(bi.interface_fence_fd);
        return false;
    }
    if (bi.interface_fence_fd >= 0) close(bi.interface_fence_fd);
    ic->next_buff_idx = bi.index;
    *out_dup_fd   = sfd;
    *out_rel_fence = bi.fence_fd;
    return true;
}

/*
 * multi_ovl_note_present — after a successful multi present, publish this
 * frame's scanout (frame-done) fence to the watchdog and, for the first few
 * frames, block-wait it as a canary so a broken multi config self-reverts
 * within ~one frame instead of silently freezing the pipeline.  Takes the
 * retire fence fd (still owned by us here; SF gets the original, we dup).
 */
static void multi_ovl_note_present(hwc_ctx *d, int retire_fence_fd)
{
    uint64_t now = monotonic_ns();

    /* Publish a dup to the watchdog thread (it owns/closes it).               */
    int wf = (retire_fence_fd >= 0) ? dup(retire_fence_fd) : -1;
    pthread_mutex_lock(&d->watchdog_mutex);
    if (d->watchdog_fence >= 0)
        close(d->watchdog_fence);
    d->watchdog_fence  = wf;
    d->last_present_ns = now;
    pthread_mutex_unlock(&d->watchdog_mutex);

    /* Canary: validate the first frames actually scan out.                    */
    if (d->multi_present <= MULTI_OVL_CANARY_FRAMES && retire_fence_fd >= 0) {
        int cf = dup(retire_fence_fd);
        if (cf >= 0) {
            if (sync_wait(cf, MULTI_OVL_CANARY_TIMEOUT_MS) < 0) {
                ALOGE("v462: canary frame %llu did not complete within %dms "
                      "-> latching to single-OVL",
                      (unsigned long long)d->multi_present,
                      MULTI_OVL_CANARY_TIMEOUT_MS);
                d->multi_ovl_failed = true;
                d->multi_fail++;
                d->freeze_latch++;
            }
            close(cf);
        }
    }
}

/*
 * hwc_watchdog_thread — independent freeze detector for the multi-OVL path.
 * Polls the most recent frame's scanout fence; if it has not signalled within
 * MULTI_OVL_FREEZE_TIMEOUT_NS the DDP pipeline has stalled, so latch
 * multi_ovl_failed -> the next prepare()/set() reverts to the proven single-OVL
 * path.  Runs on its own thread so a blocked WAIT_FOR_VSYNC (panel TE stall)
 * cannot starve it.  No unbounded waits here: sync_wait uses a 0 (non-blocking)
 * timeout and the loop sleeps a fixed cadence.
 */
static void *hwc_watchdog_thread(void *arg)
{
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(arg);

    while (d->watchdog_running) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        ts.tv_nsec += (long)MULTI_OVL_WATCHDOG_POLL_MS * 1000000L;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL);

        if (!d->use_multi_ovl || d->multi_ovl_failed)
            continue;

        pthread_mutex_lock(&d->watchdog_mutex);
        int wf = d->watchdog_fence;
        uint64_t lp = d->last_present_ns;
        if (wf >= 0) {
            if (sync_wait(wf, 0) == 0) {
                /* frame completed; nothing outstanding                        */
                close(wf);
                d->watchdog_fence = -1;
            } else {
                uint64_t age = monotonic_ns() - lp;
                if (age > MULTI_OVL_FREEZE_TIMEOUT_NS) {
                    ALOGE("v462: freeze watchdog: no frame-done in %llums "
                          "-> latching to single-OVL",
                          (unsigned long long)(age / 1000000ULL));
                    d->multi_ovl_failed = true;
                    d->freeze_latch++;
                    close(wf);
                    d->watchdog_fence = -1;
                }
            }
        }
        pthread_mutex_unlock(&d->watchdog_mutex);
    }
    return NULL;
}

/*
 * hwc_set_multi_ovl — present a frame with real DDP multi-OVL composition.
 *
 *   slots 0..ovl_count-1 : the app overlay layers (bottom->top, layer_id=slot)
 *   slot  ovl_count      : FB_TARGET (GLES of the top chrome), blended on top
 *   slots ovl_count+1..3 : sent disabled (FACT F4)
 *
 * Returns true on success (retire + per-layer release fences assigned).  On any
 * failure it closes everything it opened, latches d->multi_ovl_failed so future
 * frames fall back to the single-OVL path, and returns false (caller -> fb0).
 */
static bool hwc_set_multi_ovl(hwc_ctx *d, hwc_display_contents_1_t *c,
                              hwc_layer_1_t *fb_layer,
                              hwc_layer_1_t **ovl_layers, uint32_t ovl_count,
                              uint32_t frm_seq)
{
    const uint32_t fb_slot = ovl_count;          /* FB_TARGET on top of overlays */

    int dup_fd[MAX_OVL_LAYERS];                  /* dmabuf fds we dup()'d          */
    int rel_fence[MAX_OVL_LAYERS];               /* per-slot scanout release fence */
    for (uint32_t i = 0; i < MAX_OVL_LAYERS; i++) { dup_fd[i] = -1; rel_fence[i] = -1; }
    int present_fence_fd = -1;
    uint32_t present_fence_index = 0xFFFFFFFFU;

    /* All 4 slots present every frame; unused ones disabled (FACT F4).        */
    disp_session_input_config input;
    memset(&input, 0, sizeof(input));
    input.setter           = SESSION_USER_HWC;
    input.session_id       = d->session_id;
    input.config_layer_num = MAX_OVL_LAYERS;
    for (uint32_t layer = 0; layer < MAX_OVL_LAYERS; layer++) {
        input.config[layer].layer_id      = layer;
        input.config[layer].layer_enable  = 0;
        input.config[layer].next_buff_idx = 0xFFFFFFFFU;
        input.config[layer].identity      = DISP_NO_USE_LAEYR_ID;
        input.config[layer].security      = DISP_NORMAL_BUFFER;
    }

    bool ok = true;

    /* Multi-layer composition needs a display-level retire fence.  Per-layer
     * PREPARE_INPUT_BUFFER fences can be tied to individual OVL slots; using
     * the FB_TARGET slot fence as the display retire caused the first proven
     * multi frame to latch the canary even though SET_INPUT/TRIGGER succeeded.
     * Ask the display manager for the primary present fence and feed its index
     * back to TRIGGER_SESSION, matching the kernel's present-fence timeline. */
    {
        disp_present_fence pf;
        memset(&pf, 0, sizeof(pf));
        pf.session_id = d->session_id;
        if (ioctl(d->disp_fd, DISP_IOCTL_GET_PRESENT_FENCE, &pf) < 0) {
            ALOGW("v853: multi GET_PRESENT_FENCE failed: %s", strerror(errno));
            ok = false;
        } else {
            present_fence_fd    = (int)pf.present_fence_fd;
            present_fence_index = pf.present_fence_index;
        }
    }

    /* ---- overlay app layers (slots 0..ovl_count-1) ---- */
    for (uint32_t s = 0; s < ovl_count && ok; s++) {
        hwc_layer_1_t *l = ovl_layers[s];
        DISP_FORMAT fmt = gralloc_disp_format(l->handle);
        int stride_px = 0;
        if (fmt == DISP_FORMAT_UNKNOWN ||
            gralloc_extra_query(l->handle, GRALLOC_EXTRA_GET_STRIDE, &stride_px) != GRALLOC_EXTRA_OK ||
            stride_px <= 0) {
            ALOGW("v462: slot%u bad metadata (fmt=0x%x stride=%d)", s, (unsigned)fmt, stride_px);
            ok = false;
            break;
        }

        disp_input_config *ic = &input.config[s];
        fill_common_input(ic, s, frm_seq);
        ic->layer_rotation = hwc_transform_to_disp_orientation(l->transform);
        ic->src_fmt      = fmt;
        ic->src_pitch    = (uint32_t)stride_px;             /* pixels (FACT F3) */
        ic->src_offset_x = (uint32_t)l->sourceCrop.left;
        ic->src_offset_y = (uint32_t)l->sourceCrop.top;
        ic->src_width    = (uint32_t)(l->sourceCrop.right  - l->sourceCrop.left);
        ic->src_height   = (uint32_t)(l->sourceCrop.bottom - l->sourceCrop.top);
        ic->tgt_offset_x = (uint32_t)l->displayFrame.left;
        ic->tgt_offset_y = (uint32_t)l->displayFrame.top;
        ic->tgt_width    = (uint32_t)(l->displayFrame.right  - l->displayFrame.left);
        ic->tgt_height   = (uint32_t)(l->displayFrame.bottom - l->displayFrame.top);
        fill_layer_alpha(ic, l->blending);

        if (!overlay_prepare_slot(d, l->handle, s, ic, &dup_fd[s], &rel_fence[s])) {
            ok = false;
            break;
        }
    }

    /* ---- FB_TARGET (slot ovl_count, on top, per-pixel source-over) ---- */
    if (ok) {
        DISP_FORMAT disp_fmt = hal_to_disp_format(HAL_PIXEL_FORMAT_RGBA_8888);
        uint32_t bpp_bytes = (uint32_t)(disp_fmt & DISP_FORMAT_BPP_MASK);
        if (bpp_bytes == 0) bpp_bytes = 4;
        uint32_t fb_stride_px = (d->line_length >= bpp_bytes) ? (d->line_length / bpp_bytes) : 0;
        uint32_t src_stride_px = fb_stride_px ? fb_stride_px : d->display_w;
        if (src_stride_px < d->display_w) src_stride_px = d->display_w;

        disp_input_config *ic = &input.config[fb_slot];
        fill_common_input(ic, fb_slot, frm_seq);
        ic->src_fmt      = disp_fmt;
        ic->src_pitch    = src_stride_px;
        ic->src_offset_x = 0;
        ic->src_offset_y = 0;
        ic->src_width    = d->display_w;
        ic->src_height   = d->display_h;
        ic->tgt_offset_x = 0;
        ic->tgt_offset_y = 0;
        ic->tgt_width    = d->display_w;
        ic->tgt_height   = d->display_h;
        /* FB_TARGET is SF's premultiplied GLES output; blend it over the
         * overlays below so its transparent holes reveal them.               */
        fill_layer_alpha(ic, HWC_BLENDING_PREMULT);

        if (!overlay_prepare_slot(d, fb_layer->handle, fb_slot, ic,
                                  &dup_fd[fb_slot], &rel_fence[fb_slot])) {
            ok = false;
        }
    }

    /* ---- wait each buffer's acquire fence before OVL scans it ---- */
    if (ok) {
        for (uint32_t s = 0; s < ovl_count && ok; s++) {
            hwc_layer_1_t *l = ovl_layers[s];
            if (l->acquireFenceFd >= 0) {
                if (sync_wait(l->acquireFenceFd, 100) < 0) {
                    ALOGW("v462: slot%u acquire fence wait failed: %s", s, strerror(errno));
                    ok = false;
                }
                close(l->acquireFenceFd);
                l->acquireFenceFd = -1;
            }
        }
    }
    if (ok && fb_layer->acquireFenceFd >= 0) {
        if (sync_wait(fb_layer->acquireFenceFd, 100) < 0) {
            ALOGW("v462: FB_TARGET acquire fence wait failed: %s", strerror(errno));
            ok = false;
        }
        close(fb_layer->acquireFenceFd);
        fb_layer->acquireFenceFd = -1;
    }

    /* ---- SET_INPUT + TRIGGER (atomic under overlay_mutex) ---- */
    if (ok) {
        pthread_mutex_lock(&d->overlay_mutex);
        int set_ret = ioctl(d->disp_fd, DISP_IOCTL_SET_INPUT_BUFFER, &input);
        if (set_ret < 0) {
            pthread_mutex_unlock(&d->overlay_mutex);
            ALOGW("v462: SET_INPUT_BUFFER failed: %s", strerror(errno));
            ok = false;
        } else {
            /* kernel took its own refs on the dmabufs; drop ours             */
            for (uint32_t i = 0; i < MAX_OVL_LAYERS; i++) {
                if (dup_fd[i] >= 0) { close(dup_fd[i]); dup_fd[i] = -1; }
            }
            disp_session_config trig;
            memset(&trig, 0, sizeof(trig));
            trig.type              = DISP_SESSION_PRIMARY;  /* FACT F9: never 0 */
            trig.session_id        = d->session_id;
            trig.present_fence_idx = present_fence_index;
            trig.dc_type           = DISP_OUTPUT_UNKNOWN;
            trig.tigger_mode       = TRIGGER_NORMAL;
            trig.user              = SESSION_USER_HWC;
            int trig_ret = ioctl(d->disp_fd, DISP_IOCTL_TRIGGER_SESSION, &trig);
            pthread_mutex_unlock(&d->overlay_mutex);
            if (trig_ret < 0) {
                ALOGW("v462: TRIGGER_SESSION failed: %s", strerror(errno));
                ok = false;
            }
        }
    }

    if (!ok) {
        /* Latch back to the single-OVL path; clean up everything we opened.   */
        for (uint32_t i = 0; i < MAX_OVL_LAYERS; i++) {
            if (dup_fd[i]   >= 0) close(dup_fd[i]);
            if (rel_fence[i] >= 0) close(rel_fence[i]);
        }
        if (present_fence_fd >= 0) close(present_fence_fd);
        d->multi_ovl_failed = true;
        d->multi_fail++;
        d->overlay_fail++;
        ALOGE("v462: multi-OVL failed (%u overlay layers) -> latching to single-OVL",
              ovl_count);
        return false;
    }

    /* ---- success: hand release fences to SF ---- */
    for (uint32_t s = 0; s < ovl_count; s++) {
        ovl_layers[s]->releaseFenceFd = rel_fence[s];   /* SF owns it now       */
        rel_fence[s] = -1;
    }
    /* HWC2On1Adapter waits the display retire fence.  Publish the primary
     * present fence for the whole frame and close FB_TARGET's per-layer release
     * fence; the adapter ignores FB_TARGET release fences in favour of retire. */
    if (c->retireFenceFd >= 0) close(c->retireFenceFd);
    c->retireFenceFd = present_fence_fd;
    present_fence_fd = -1;
    if (rel_fence[fb_slot] >= 0) {
        close(rel_fence[fb_slot]);
        rel_fence[fb_slot] = -1;
    }
    fb_layer->releaseFenceFd = -1;

    d->multi_present++;
    d->overlay_present++;                /* also a successful overlay present   */
    d->last_overlay_count = ovl_count;

    /* Publish this frame's scanout fence to the freeze watchdog + canary-check
     * the first few frames (retire fence is still valid in our process here). */
    multi_ovl_note_present(d, c->retireFenceFd);

    if (d->multi_present <= 30 || (d->multi_present % 300) == 0) {
        ALOGI("v462: multi-OVL frame=%llu seq=%u ovl_layers=%u fb_slot=%u",
              (unsigned long long)d->multi_present, frm_seq, ovl_count, fb_slot);
    }
    return true;
}

/* =========================================================================
 * HWC operations
 * ========================================================================= */

/*
 * hwc_prepare — decide per-layer composition.
 *
 * Baseline (multi-OVL off, or nothing eligible): force every app layer to
 * HWC_FRAMEBUFFER so SF GLES-composites everything into one FRAMEBUFFER_TARGET,
 * presented via overlay layer 0 (the proven single-OVL path).
 *
 * MULTI-OVL (v462, HWC_MULTI_OVL_60FPS.md §3.1): when enabled and healthy, mark
 * the BOTTOM contiguous run of overlay-eligible layers HWC_OVERLAY (up to
 * MAX_OVERLAY_APP_LAYERS = 3, reserving one OVL slot for FB_TARGET).  The run is
 * taken from slot 0 upward and stops at the first ineligible layer, so the
 * remaining (GLES) layers stay Z-contiguous and the single FB_TARGET can
 * represent them on top.  If the bottom-most layer is ineligible, nothing is
 * offloaded and behaviour is byte-identical to the baseline.
 */
static int hwc_prepare(hwc_composer_device_1_t *dev, size_t numDisplays,
                       hwc_display_contents_1_t **displays)
{
    if (!displays) return 0;
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(dev);

    for (size_t dpy = 0; dpy < numDisplays; dpy++) {
        hwc_display_contents_1_t *c = displays[dpy];
        if (!c) continue;

        /* Baseline: everything (except FB_TARGET) to GLES.                    */
        for (size_t i = 0; i < c->numHwLayers; i++) {
            hwc_layer_1_t *l = &c->hwLayers[i];
            if (l->compositionType != HWC_FRAMEBUFFER_TARGET)
                l->compositionType = HWC_FRAMEBUFFER;
        }

        /* Multi-OVL bottom-band offload — primary display only.               */
        if (dpy != HWC_DISPLAY_PRIMARY)                     continue;
        if (!d->use_multi_ovl || d->multi_ovl_failed || !d->overlay_ok) continue;

        uint32_t pw = d->display_w ? d->display_w : PANEL_W_DEFAULT;
        uint32_t ph = d->display_h ? d->display_h : PANEL_H_DEFAULT;
        uint32_t cap = d->multi_ovl_max;
        if (cap > MAX_OVERLAY_APP_LAYERS) cap = MAX_OVERLAY_APP_LAYERS;

        /* Rate-limited per-layer diagnostics: while multi-OVL is armed, log each
         * app layer's overlay verdict + the exact reject reason ~once/2s so an
         * A/B can see WHY layers stayed on GLES (e.g. a scaled parallax wallpaper
         * -> "scaled", or a solid-colour bottom layer -> "no-handle") without
         * correlating dumpsys SurfaceFlinger.                                   */
        static uint32_t dbg_seq = 0;
        bool do_log = ((dbg_seq++ % 120) == 0);

        bool run_open = true;                 /* still extending the bottom run   */
        uint32_t assigned = 0;
        for (size_t i = 0; i < c->numHwLayers; i++) {
            hwc_layer_1_t *l = &c->hwLayers[i];
            if (l->compositionType == HWC_FRAMEBUFFER_TARGET) break;  /* FB_TARGET is last */
            if (!run_open && !do_log) break;  /* nothing more to decide or log    */

            const char *rej = layer_reject_reason(l, pw, ph);
            if (run_open) {
                if (rej == NULL && assigned < cap) {
                    l->compositionType = HWC_OVERLAY;
                    assigned++;
                    if (assigned >= cap) run_open = false;   /* bandwidth cap hit */
                } else {
                    run_open = false;          /* first ineligible ends the run   */
                }
            }
            if (do_log) {
                int scw = l->sourceCrop.right  - l->sourceCrop.left;
                int sch = l->sourceCrop.bottom - l->sourceCrop.top;
                int dfw = l->displayFrame.right  - l->displayFrame.left;
                int dfh = l->displayFrame.bottom - l->displayFrame.top;
                int hal_fmt = -1;
                if (l->handle)
                    gralloc_extra_query(l->handle, GRALLOC_EXTRA_GET_FORMAT, &hal_fmt);
                ALOGI("v462: prep L%zu %-7s blend=0x%x tf=%u pa=%u effpa=%u fmt=0x%x src=%dx%d dst=%dx%d@(%d,%d) : %s",
                      i, (l->compositionType == HWC_OVERLAY) ? "OVERLAY" : "GLES",
                      l->blending, l->transform, l->planeAlpha,
                      layer_effective_plane_alpha(l), hal_fmt,
                      scw, sch, dfw, dfh, l->displayFrame.left, l->displayFrame.top,
                      rej ? rej : "eligible");
            }
        }
        if (do_log)
            ALOGI("v462: prep summary: offloaded %u app layer(s) (cap=%u, numHwLayers=%zu)",
                  assigned, cap, c->numHwLayers);
    }
    return 0;
}

/*
 * hwc_set — present one frame via the MTK overlay (or fb0 fallback).
 *
 * Overlay path sequence (RE §2 / v213_hwc_blob_re.md §2.2–2.4):
 *
 *  A. Optional GET_PRESENT_FENCE — disabled by default in v217 because v215c
 *     freeze evidence repeatedly stalled around present_fence_w. When enabled
 *     for A/B testing it returns present_fence_fd + present_fence_index.
 *     DISP_IOCTL_GET_PRESENT_FENCE = DISP_IOW(216, disp_present_fence)
 *       disp_present_fence (disp_session.h lines 311–317):
 *         .session_id          (input)
 *         .present_fence_fd    (output: fence fd)
 *         .present_fence_index (output: index fed back into TRIGGER)
 *     Kernel handler: _ioctl_prepare_present_fence (mtk_disp_mgr.c line 740)
 *
 *  B. Build disp_session_input_config with config_layer_num = 4
 *     disp_session_input_config (disp_session.h lines 232–237):
 *       .setter          = SESSION_USER_HWC (0)      (line 140)
 *       .session_id      = d->session_id
 *       .config_layer_num = 4   (OVL0 has 4 slots; only slot 0 is enabled)
 *       .config[0]       = disp_input_config for the FB_TARGET layer
 *       .config[1..3]    = disabled slots, sent every frame to clear stale OVL
 *
 *     disp_input_config (disp_session.h lines 181–214):
 *       .layer_id        = 0
 *       .layer_enable    = 1
 *       .buffer_source   = DISP_BUFFER_ION (0)       (line 98)
 *       .src_base_addr   = (void*)(intptr_t)ion_share_fd
 *                          (the ION shared fd, cast to pointer as the blob does)
 *       .src_phy_addr    = NULL  (kernel uses ION path when buffer_source=ION)
 *       .src_direct_link = 0
 *       .src_fmt         = DISP_FORMAT_RGBA8888 (or from gralloc_extra_query)
 *       .src_pitch       = stride in pixels (kernel multiplies by Bpp)
 *       .src_offset_x/y  = 0
 *       .src_width/height= d->display_w / d->display_h
 *       .tgt_offset_x/y  = 0
 *       .tgt_width/height= d->display_w / d->display_h
 *       .layer_rotation  = DISP_ORIENTATION_0  (safe default — see report §ROTATION)
 *       .layer_type      = DISP_LAYER_2D (0)         (line 75)
 *       .video_rotation  = DISP_ORIENTATION_0
 *       .isTdshp         = 0
 *       .next_buff_idx   = index returned by PREPARE_INPUT_BUFFER
 *       .identity        = -1 (DISP_NO_USE_LAEYR_ID)
 *       .connected_type  = 0
 *       .security        = DISP_NORMAL_BUFFER (0)    (line 88)
 *       .alpha_enable    = 1
 *       .alpha           = 0xFF
 *       .sur_aen         = 0
 *       .src_alpha       = DISP_ALPHA_ONE (0)        (line 106)
 *       .dst_alpha       = DISP_ALPHA_ONE (0)
 *       .frm_sequence    = incremented per frame
 *       .yuv_range       = DISP_YUV_BT601_FULL (0)  (line 119)
 *
 *  C. SET_INPUT_BUFFER — submit layer config to kernel (zero-copy)
 *     DISP_IOCTL_SET_INPUT_BUFFER = DISP_IOW(206, disp_session_input_config)
 *     Kernel handler: _ioctl_set_input_buffer (mtk_disp_mgr.c line 1613)
 *     Mutex is held from here through TRIGGER (RE §9 rule 2). v220 always
 *     sends disabled slots 1-3 because set_primary_buffer() only updates the
 *     layer IDs present in config[]; otherwise old OVL state can keep scanning.
 *
 *  D. TRIGGER_SESSION — kick OVL0 DMA hardware pipeline
 *     DISP_IOCTL_TRIGGER_SESSION = DISP_IOW(203, disp_session_config)
 *     disp_session_config fields used by trigger (handler line 616+):
 *       .session_id        = d->session_id
 *       .present_fence_idx = fence_index from step A, or 0xFFFFFFFF when the
 *                            SF-facing present fence path is disabled
 *       .dc_type           = DISP_OUTPUT_UNKNOWN (0)  (line 149)
 *       .tigger_mode       = TRIGGER_NORMAL (0)       (line 156)
 *     Kernel updates the present fence only when the index is not -1, then
 *     kicks the OVL0/RDMA/DSI pipeline.
 *
 *  E. Return a real display retire fence. Android 8 runs this HWC1 module
 *     through HWC2On1Adapter, which closes FRAMEBUFFER_TARGET release fences and
 *     waits on the display retire fence instead. With the legacy present-fence
 *     path disabled, use the PREPARE_INPUT_BUFFER release fence as retire fence.
 */
static int hwc_set(hwc_composer_device_1_t *dev, size_t numDisplays,
                   hwc_display_contents_1_t **displays)
{
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(dev);
    if (!displays) return 0;

    /* Frame sequence counter — wraps at uint32 max, kernel uses for debug   */
    static uint32_t frm_seq = 0;
    frm_seq++;

    for (size_t dpy = 0; dpy < numDisplays; dpy++) {
        hwc_display_contents_1_t *c = displays[dpy];
        if (!c) continue;

        /* Close any incoming retire fence (we replace it below)              */
        if (c->retireFenceFd >= 0) {
            close(c->retireFenceFd);
            c->retireFenceFd = -1;
        }

        if (dpy != HWC_DISPLAY_PRIMARY) {
            /* Non-primary displays: no-op; close layer fences.               */
            for (size_t i = 0; i < c->numHwLayers; i++) {
                hwc_layer_1_t *l = &c->hwLayers[i];
                if (l->acquireFenceFd >= 0) {
                    close(l->acquireFenceFd);
                    l->acquireFenceFd = -1;
                }
                l->releaseFenceFd = -1;
            }
            continue;
        }

        /* ---- Primary display ---- */

        /* Find the FRAMEBUFFER_TARGET layer                                  */
        hwc_layer_1_t *fb_layer = NULL;
        for (size_t i = 0; i < c->numHwLayers; i++) {
            if (c->hwLayers[i].compositionType == HWC_FRAMEBUFFER_TARGET) {
                fb_layer = &c->hwLayers[i];
                break;
            }
        }

        /* Collect the HWC_OVERLAY layers (marked by hwc_prepare's bottom-band
         * pass), in Z order = slot order.  Empty unless multi-OVL is active.  */
        hwc_layer_1_t *ovl_layers[MAX_OVERLAY_APP_LAYERS];
        uint32_t ovl_count = 0;
        for (size_t i = 0; i < c->numHwLayers && ovl_count < MAX_OVERLAY_APP_LAYERS; i++) {
            if (c->hwLayers[i].compositionType == HWC_OVERLAY)
                ovl_layers[ovl_count++] = &c->hwLayers[i];
        }

        /* Close acquire fences for the GLES (HWC_FRAMEBUFFER) layers only —
         * those were already consumed by SF's compositor.  HWC_OVERLAY layers
         * keep their acquire fence so the multi-OVL path can wait on it, and
         * their release fence is filled by that path.                        */
        for (size_t i = 0; i < c->numHwLayers; i++) {
            hwc_layer_1_t *l = &c->hwLayers[i];
            if (l->compositionType != HWC_FRAMEBUFFER_TARGET &&
                l->compositionType != HWC_OVERLAY) {
                if (l->acquireFenceFd >= 0) {
                    close(l->acquireFenceFd);
                    l->acquireFenceFd = -1;
                }
                l->releaseFenceFd = -1;
            }
        }

        /* Try overlay path if open and we have a valid FB_TARGET handle      */
        bool used_overlay = false;
        bool attempted_overlay_path = false;

        /* v217 self-heal: if the overlay path has failed many times and has never
         * once presented a frame, give up on it permanently and use the fb0 path
         * (stable, laggy) instead of retrying a broken path every vsync. This keeps
         * a buggy overlay build from looping failures rather than degrading. */
        if (d->overlay_ok && d->overlay_present == 0 && d->overlay_fail >= 60) {
            ALOGE("v217: overlay failed %llu times and never presented — latching to fb0",
                  (unsigned long long)d->overlay_fail);
            d->overlay_ok = false;
        }

        /* MULTI-OVL (v462): when hwc_prepare offloaded >=1 app layer, present
         * via the multi-OVL path.  On failure it latches multi_ovl_failed and
         * returns false, so the next frame's prepare() reverts to all-GLES and
         * the single-OVL block below resumes; this frame falls to fb0.        */
        if (d->overlay_ok && ovl_count > 0 && fb_layer && fb_layer->handle) {
            attempted_overlay_path = true;
            used_overlay = hwc_set_multi_ovl(d, c, fb_layer, ovl_layers, ovl_count, frm_seq);
        }

        if (!used_overlay && ovl_count == 0 && d->overlay_ok && fb_layer && fb_layer->handle) {
            attempted_overlay_path = true;
            uint64_t frame_start_ns = monotonic_ns();
            uint64_t acquire_wait_us = 0;
            uint64_t prepare_us = 0;
            uint64_t set_us = 0;
            uint64_t trigger_us = 0;
            int ion_share_fd = -1;
            int release_fence_fd = -1;   /* v215c: per-layer release fence from PREPARE */
            bool ioctl_ok = false;
            int present_fence_fd = -1;
            uint32_t present_fence_index = 0xFFFFFFFFU;

            /* ---- Step A: optional GET_PRESENT_FENCE ----
             * v217 default skips the SF-facing present fence. v215c freeze
             * evidence repeatedly showed present_fence_w during system stalls.
             * The layer release fence from PREPARE_INPUT_BUFFER is still
             * returned below to protect FB_TARGET reuse. */
            if (d->use_present_fence) {
                disp_present_fence pf;
                memset(&pf, 0, sizeof(pf));
                pf.session_id = d->session_id;

                if (ioctl(d->disp_fd, DISP_IOCTL_GET_PRESENT_FENCE, &pf) < 0) {
                    ALOGW("v217: GET_PRESENT_FENCE failed: %s", strerror(errno));
                    d->overlay_fail++;
                    goto overlay_fail_label;
                }
                present_fence_fd    = (int)pf.present_fence_fd;
                present_fence_index = pf.present_fence_index;
            }

            /* ---- Step B: get the buffer's live dmabuf fd ----
             * v217 keeps the v215 ion_import fix:
             * gralloc_extra_query(GET_ION_FD) returns the ion fd VALUE from when
             * the buffer was allocated (valid only in the allocator process);
             * ion_import() of that number in the composer fails EBADF, so the
             * overlay bailed to fb0 every frame. The native_handle's first fd
             * (data[0]) is the SAME buffer's dmabuf fd, duplicated into THIS
             * process by the HWComposer marshalling -> always valid here. We
             * dup() it so our close() after SET_INPUT releases only our own ref,
             * never SurfaceFlinger's handle fd. The kernel PREPARE_INPUT_BUFFER
             * does ion_import_dma_buf() on it and takes its own reference. */
            {
                int buf_fd = (fb_layer->handle->numFds >= 1)
                             ? fb_layer->handle->data[0] : -1;
                if (buf_fd < 0) {
                    ALOGW("v215: FB_TARGET handle has no dmabuf fd (numFds=%d)",
                          fb_layer->handle->numFds);
                    d->overlay_fail++;
                    if (present_fence_fd >= 0) close(present_fence_fd);
                    goto overlay_fail_label;
                }
                ion_share_fd = dup(buf_fd);
                if (ion_share_fd < 0) {
                    ALOGW("v215: dup(buf_fd=%d) failed: %s", buf_fd, strerror(errno));
                    d->overlay_fail++;
                    if (present_fence_fd >= 0) close(present_fence_fd);
                    goto overlay_fail_label;
                }
            }

            /* ---- FB_TARGET metadata ----
             * The safe baseline forces all app layers through GLES into one
             * FRAMEBUFFER_TARGET.  On Android 8 the legacy MTK gralloc_extra
             * module reloads /vendor/lib64/hw/gralloc.mt6753.so and emits bad
             * ION custom DMA/cache-sync calls when queried from the HWC hot path.
             * The primary display session already gives the authoritative target
             * geometry, and SurfaceFlinger provides the target as RGBA.  Keep the
             * DDP path source-truth simple: dmabuf fd from native_handle, primary
             * session dimensions, RGBA8888, and fbdev's line_length-derived
             * pixel stride. */
            int hal_fmt = HAL_PIXEL_FORMAT_RGBA_8888;
            DISP_FORMAT disp_fmt = hal_to_disp_format(hal_fmt);
            uint32_t bpp_bytes = (uint32_t)(disp_fmt & DISP_FORMAT_BPP_MASK);
            if (bpp_bytes == 0) bpp_bytes = 4;
            uint32_t fb_stride_px = (d->line_length >= bpp_bytes)
                                    ? (d->line_length / bpp_bytes) : 0;
            uint32_t src_stride_px = fb_stride_px ? fb_stride_px : d->display_w;
            if (src_stride_px < d->display_w)
                src_stride_px = d->display_w;
            uint32_t src_w = d->display_w;
            uint32_t src_h = d->display_h;
            uint32_t alloc_size = 0;
            uint32_t reported_vstride = d->display_h;
            uint32_t pitch_bytes = src_stride_px * bpp_bytes;
            d->metadata_bypass++;

            if (src_w == 0 || src_h == 0 || src_stride_px == 0) {
                ALOGW("v273: invalid FB_TARGET geometry fmt=0x%x w=%u h=%u stride=%u fb_stride=%u line_length=%u alloc=%u",
                      hal_fmt, src_w, src_h, src_stride_px, fb_stride_px,
                      d->line_length, alloc_size);
                close(ion_share_fd);
                if (present_fence_fd >= 0) close(present_fence_fd);
                d->overlay_fail++;
                goto overlay_fail_label;
            }

            d->last_src_w = src_w;
            d->last_src_h = src_h;
            d->last_stride_px = src_stride_px;
            d->last_pitch_bytes = pitch_bytes;
            d->last_alloc_size = alloc_size;
            d->last_vstride = reported_vstride;

            /* ---- Step B cont.: Build disp_session_input_config ---- */
            disp_session_input_config input;
            memset(&input, 0, sizeof(input));
            input.setter          = SESSION_USER_HWC;    /* line 140 */
            input.session_id      = d->session_id;
            input.config_layer_num = MAX_OVL_LAYERS;     /* slot0 on, slots1-3 off */

            for (uint32_t layer = 0; layer < MAX_OVL_LAYERS; layer++) {
                input.config[layer].layer_id = layer;
                input.config[layer].layer_enable = 0;
                input.config[layer].next_buff_idx = 0xFFFFFFFFU;
                input.config[layer].identity = DISP_NO_USE_LAEYR_ID;
                input.config[layer].security = DISP_NORMAL_BUFFER;
            }

            disp_input_config *ic = &input.config[FB_TARGET_LAYER];

            ic->layer_id      = FB_TARGET_LAYER;         /* line 182 */
            ic->layer_enable  = 1;                       /* line 183 */
            ic->buffer_source = DISP_BUFFER_ION;         /* line 184; value 0, line 98 */
            ic->src_base_addr = (void *)(intptr_t)ion_share_fd; /* line 185: ION shared fd */
            ic->src_phy_addr  = NULL;                    /* line 186: unused for ION */
            ic->src_direct_link = 0;                     /* line 187 */
            ic->src_fmt       = disp_fmt;                /* line 188 */
            ic->src_use_color_key = 0;                   /* line 189 */
            ic->src_color_key = 0;                       /* line 190 */
            ic->src_pitch     = src_stride_px;           /* line 191: pixels, not bytes */
            ic->src_offset_x  = 0;                       /* line 192 */
            ic->src_offset_y  = 0;                       /* line 192 */
            ic->src_width     = src_w;                   /* line 193 */
            ic->src_height    = src_h;                   /* line 193 */
            ic->tgt_offset_x  = 0;                       /* line 195 */
            ic->tgt_offset_y  = 0;                       /* line 195 */
            ic->tgt_width     = d->display_w;            /* line 196 */
            ic->tgt_height    = d->display_h;            /* line 196 */
            /*
             * ROTATION FIELD — SAFE DEFAULT:
             * We set layer_rotation = DISP_ORIENTATION_0 (value 0, line 47).
             * In the single-layer baseline all composition (including rotation)
             * is done by SF's GLES compositor into the FB_TARGET buffer.  The
             * FB_TARGET buffer content is already correctly oriented for the
             * panel.  We do NOT apply an additional hardware rotation here.
             * See implementation report §ROTATION for the full discussion.
             */
            ic->layer_rotation = DISP_ORIENTATION_0;    /* line 197; value 0 */
            ic->layer_type     = DISP_LAYER_2D;          /* line 198; value 0, line 75 */
            ic->video_rotation = DISP_ORIENTATION_0;    /* line 199 */
            ic->isTdshp        = 0;                      /* line 201 */
            ic->next_buff_idx  = 0;                      /* line 203: no separate fence slot */
            ic->identity       = DISP_NO_USE_LAEYR_ID;  /* line 204; disp_session.h line 8 */
            ic->connected_type = 0;                      /* line 205 */
            ic->security       = DISP_NORMAL_BUFFER;     /* line 206; value 0, line 88 */
            ic->alpha_enable   = 1;                      /* line 207 */
            ic->alpha          = 0xFF;                   /* line 208: fully opaque */
            ic->sur_aen        = 0;                      /* line 209 */
            ic->src_alpha      = DISP_ALPHA_ONE;         /* line 210; value 0, line 106 */
            ic->dst_alpha      = DISP_ALPHA_ONE;         /* line 211; value 0 */
            ic->frm_sequence   = frm_seq;                /* line 212 */
            ic->yuv_range      = DISP_YUV_BT601_FULL;   /* line 213; value 0, line 119 */

            /* ---- Step B.5 (v214 REVIEW FIX): PREPARE_INPUT_BUFFER ----
             * REQUIRED. The kernel set_primary_buffer() does NOT resolve the
             * buffer from src_base_addr/ion fd; it gets the MVA via
             * disp_sync_query_buf_info(next_buff_idx) (mtk_disp_mgr.c:1542). The
             * buffer must first be registered with PREPARE_INPUT_BUFFER (ioctl
             * 204 -> disp_sync_prepare_buf maps the ion fd -> MVA -> index). With
             * next_buff_idx=0 unprepared, dst_mva==0 and the kernel DISABLES the
             * layer (mtk_disp_mgr.c:1548) -> black screen (no fault, no fallback).
             */
            {
                disp_buffer_info bi;
                memset(&bi, 0, sizeof(bi));
                bi.session_id = d->session_id;
                bi.layer_id   = FB_TARGET_LAYER;
                bi.layer_en   = 1;
                bi.ion_fd     = ion_share_fd;
                bi.cache_sync = 0;
                bi.fence_fd = -1;
                bi.interface_fence_fd = -1;
                uint64_t t_prepare0 = monotonic_ns();
                if (ioctl(d->disp_fd, DISP_IOCTL_PREPARE_INPUT_BUFFER, &bi) < 0) {
                    ALOGW("v217: PREPARE_INPUT_BUFFER failed: %s", strerror(errno));
                    close(ion_share_fd);
                    if (present_fence_fd >= 0) close(present_fence_fd);
                    d->overlay_fail++;
                    goto overlay_fail_label;
                }
                prepare_us = elapsed_us(t_prepare0, monotonic_ns());
                if (bi.index == 0 || bi.fence_fd < 0) {
                    ALOGW("v273: PREPARE_INPUT_BUFFER returned invalid index/fence index=%u fence=%d",
                          bi.index, bi.fence_fd);
                    close(ion_share_fd);
                    if (present_fence_fd >= 0) close(present_fence_fd);
                    if (bi.fence_fd >= 0) close(bi.fence_fd);
                    if (bi.interface_fence_fd >= 0) close(bi.interface_fence_fd);
                    d->overlay_fail++;
                    goto overlay_fail_label;
                }
                ic->next_buff_idx = bi.index;        /* MVA now resolvable */
                /* v215c FIX (user-visible lag + periodic freeze):
                 * bi.fence_fd is THIS buffer's RELEASE fence — it signals when
                 * OVL0 has finished scanning the buffer out. Hand it to SF as the
                 * layer releaseFenceFd so SF will NOT let the GPU recomposite into
                 * this FB_TARGET buffer until the overlay is done with it.
                 * v214/v215b threw it away (releaseFenceFd = -1) -> SF returned the
                 * buffer to the GPU immediately -> GPU and OVL0 raced on the 2
                 * FB_TARGET buffers -> stutter + multi-second SF stalls. */
                release_fence_fd = bi.fence_fd;
                if (bi.interface_fence_fd >= 0) close(bi.interface_fence_fd);
            }

            /* v217 correctness: PREPARE_INPUT_BUFFER takes an ION fd, not the
             * FB_TARGET acquire fence. Wait for SF/GPU to finish the composed
             * buffer before OVL0 scans it out. This is not the old fb0-copy
             * serialization; the CPU still does no pixel copy. */
            if (fb_layer->acquireFenceFd >= 0) {
                uint64_t t_acq0 = monotonic_ns();
                int wait_ret = sync_wait(fb_layer->acquireFenceFd, 100);
                acquire_wait_us = elapsed_us(t_acq0, monotonic_ns());
                if (wait_ret < 0) {
                    ALOGW("v217: FB_TARGET acquire fence wait failed/timeout: %s",
                          strerror(errno));
                    close(ion_share_fd);
                    if (present_fence_fd >= 0) close(present_fence_fd);
                    if (release_fence_fd >= 0) close(release_fence_fd);
                    close(fb_layer->acquireFenceFd);
                    fb_layer->acquireFenceFd = -1;
                    d->overlay_fail++;
                    goto overlay_fail_label;
                }
                close(fb_layer->acquireFenceFd);
                fb_layer->acquireFenceFd = -1;
            }

            /* ---- Step C: SET_INPUT_BUFFER ---- */
            /* Lock covers SET_INPUT_BUFFER + TRIGGER atomically (RE §9 rule 2) */
            pthread_mutex_lock(&d->overlay_mutex);
            uint64_t t_set0 = monotonic_ns();
            int set_ret = ioctl(d->disp_fd, DISP_IOCTL_SET_INPUT_BUFFER, &input);
            set_us = elapsed_us(t_set0, monotonic_ns());
            if (set_ret < 0) {
                pthread_mutex_unlock(&d->overlay_mutex);
                ALOGW("v217: SET_INPUT_BUFFER failed: %s", strerror(errno));
                close(ion_share_fd);
                if (present_fence_fd >= 0) close(present_fence_fd);
                if (release_fence_fd >= 0) close(release_fence_fd);
                d->overlay_fail++;
                goto overlay_fail_label;
            }

            /* The kernel now holds a reference to ion_share_fd's underlying
             * dma-buf.  We can close our fd — kernel keeps the ref open until
             * it is done with the buffer after the hardware flip.             */
            close(ion_share_fd);
            ion_share_fd = -1;

            /* ---- Step D: TRIGGER_SESSION ---- */
            /*
             * disp_session_config for TRIGGER (disp_session.h line 162):
             *   .session_id        = d->session_id
             *   .present_fence_idx = returned from GET_PRESENT_FENCE
             *   .dc_type           = DISP_OUTPUT_UNKNOWN (0)  line 149
             *   .tigger_mode       = TRIGGER_NORMAL (0)       line 156
             * Kernel: _ioctl_trigger_session_config (mtk_disp_mgr.c line 616)
             *   calls primary_display_update_present_fence + primary_display_trigger
             */
            disp_session_config trig;
            memset(&trig, 0, sizeof(trig));
            /* v215 FIX (kernel OOPS root cause, FACT from last_kmsg panic):
             * .type is the index into cached_session_input[] in the kernel's
             * primary_display_merge_session_cmd (primary_display.c:6329-6330):
             *   cached_session_input[config->type - 1] = captured_...[config->type - 1]
             * v214 left .type == 0 (memset) so the kernel computed
             * cached_session_input[(unsigned)0 - 1] == [0xFFFFFFFF] -> wild OOB
             * address 0x450_0163e4c0 -> do_translation_fault -> die -> panic ->
             * machine_restart on the FIRST trigger. MUST be DISP_SESSION_PRIMARY. */
            trig.type              = DISP_SESSION_PRIMARY;
            trig.session_id        = d->session_id;
            trig.present_fence_idx = present_fence_index;
            trig.dc_type           = DISP_OUTPUT_UNKNOWN;
            trig.tigger_mode       = TRIGGER_NORMAL;
            trig.user              = SESSION_USER_HWC;

            uint64_t t_trig0 = monotonic_ns();
            int trig_ret = ioctl(d->disp_fd, DISP_IOCTL_TRIGGER_SESSION, &trig);
            trigger_us = elapsed_us(t_trig0, monotonic_ns());
            pthread_mutex_unlock(&d->overlay_mutex);

            if (trig_ret < 0) {
                ALOGW("v217: TRIGGER_SESSION failed: %s", strerror(errno));
                if (present_fence_fd >= 0) close(present_fence_fd);
                if (release_fence_fd >= 0) close(release_fence_fd);
                d->overlay_fail++;
                goto overlay_fail_label;
            }

            /* ---- Step E: Retire fence ----
             * HWC2On1Adapter ignores FB_TARGET release fences and waits on the
             * display retire fence. With present fences disabled, use PREPARE's
             * scanout release fence as the retire fence so SF does not start the
             * next composition against a buffer still owned by OVL0. */
            if (d->use_present_fence) {
                c->retireFenceFd = present_fence_fd;
                present_fence_fd = -1;   /* ownership transferred to SF */
            } else {
                if (present_fence_fd >= 0)
                    close(present_fence_fd);
                present_fence_fd = -1;
                c->retireFenceFd = release_fence_fd;
                release_fence_fd = -1;   /* ownership transferred to SF */
            }

            if (fb_layer->acquireFenceFd >= 0) {
                close(fb_layer->acquireFenceFd);
                fb_layer->acquireFenceFd = -1;
            }
            fb_layer->releaseFenceFd = d->use_present_fence ? release_fence_fd : -1;
            if (d->use_present_fence)
                release_fence_fd = -1;   /* ownership transferred to SF */

            d->overlay_present++;
            used_overlay = true;
            ioctl_ok = true;
            (void)ioctl_ok;

            uint64_t total_us = elapsed_us(frame_start_ns, monotonic_ns());
            if (d->overlay_present <= 30 || total_us > 33000ULL) {
                ALOGW("v273: overlay frame=%llu seq=%u acq_us=%llu prep_us=%llu set_us=%llu trig_us=%llu total_us=%llu rel_fd=%d present_fence=%d geom=%ux%u stride_px=%u pitch_B=%u fb_line=%u alloc=%u vstride=%u metadata_bypass=%llu",
                      (unsigned long long)d->overlay_present, frm_seq,
                      (unsigned long long)acquire_wait_us,
                      (unsigned long long)prepare_us,
                      (unsigned long long)set_us,
                      (unsigned long long)trigger_us,
                      (unsigned long long)total_us,
                      fb_layer->releaseFenceFd,
                      d->use_present_fence ? 1 : 0,
                      d->last_src_w, d->last_src_h, d->last_stride_px,
                      d->last_pitch_bytes, d->line_length, d->last_alloc_size,
                      d->last_vstride,
                      (unsigned long long)d->metadata_bypass);
            }
        }

overlay_fail_label:
        if (!used_overlay) {
            if (attempted_overlay_path && d->overlay_ok) {
                /* A live overlay session with one bad frame should not fall
                 * through to the CPU fb0 path.  The bad-frame evidence is most
                 * commonly an invalid/stale FB_TARGET dmabuf fd during composer
                 * restart; gralloc lock may still hand back a bogus CPU pointer
                 * and the memcpy fallback can crash the composer service.  Keep
                 * the previous scanout for this frame; the next prepare/set
                 * normally recovers through the single-OVL path. */
                if (fb_layer && fb_layer->acquireFenceFd >= 0) {
                    close(fb_layer->acquireFenceFd);
                    fb_layer->acquireFenceFd = -1;
                }
                if (d->overlay_fail <= 5 || (d->overlay_fail % 60) == 0) {
                    ALOGW("v849: overlay frame failed while session is alive; "
                          "skipping unsafe fb0 memcpy fallback");
                }
            } else {
                /* ---- Fallback: fb0 memcpy path (v213) ---- */
                /*
                 * Close the FB_TARGET acquire fence before locking the buffer.
                 * If there's no fence the gralloc lock will just proceed.
                 */
                if (fb_layer && fb_layer->acquireFenceFd >= 0) {
                    /* Wait for SF to finish writing to the FB_TARGET         */
                    sync_wait(fb_layer->acquireFenceFd, 1000);
                    close(fb_layer->acquireFenceFd);
                    fb_layer->acquireFenceFd = -1;
                }
                fb0_present(d, c);
            }
            if (fb_layer) fb_layer->releaseFenceFd = -1;
            c->retireFenceFd = -1;
        }

        /* Ensure all remaining layer fences are closed                       */
        for (size_t i = 0; i < c->numHwLayers; i++) {
            hwc_layer_1_t *l = &c->hwLayers[i];
            if (l->acquireFenceFd >= 0) {
                close(l->acquireFenceFd);
                l->acquireFenceFd = -1;
            }
        }
    }
    return 0;
}

/* =========================================================================
 * Blank / power
 * ========================================================================= */

/*
 * hwc_blank — screen on/off notification from SurfaceFlinger.
 *
 * The vendor blob (RE §4.3) does NOT issue any power ioctl to the kernel for
 * the primary display.  Panel power transitions are handled implicitly by the
 * kernel session lifecycle.  We follow the same approach.
 *
 * On blank (screen off), we submit zero layers + TRIGGER so OVL0 stops
 * scanning, which allows the kernel/DSI driver to power off the panel cleanly.
 * On unblank (screen on), the next hwc_set() call with a valid FB_TARGET will
 * restart the OVL0 pipeline naturally.
 *
 * IMPORTANT: We do NOT call FBIOBLANK here.  See v213 comment for why:
 * SurfaceFlinger's fbdev-surface path owns panel power; a second FBIOBLANK
 * races it (v208 corruption root cause).
 */
static int hwc_blank(hwc_composer_device_1_t *dev, int /*dpy*/, int blank)
{
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(dev);
    d->blank_req = blank;

    if (!d->overlay_ok) return 0;  /* fallback path: do nothing (v213 behaviour) */

    /* v215d (freeze fix): do NOT submit an empty layer set + TRIGGER on blank.
     * config_layer_num=0 makes the kernel set_primary_buffer return early WITHOUT
     * configuring the path (mtk_disp_mgr.c:1505-1508); the following TRIGGER then
     * runs primary_display_trigger on a stale OVL0 state. That blank-time
     * empty-trigger is the prime suspect for the blank/unblank pipeline wedge
     * (the user-visible freeze when the screen sleeps then wakes). The vendor blob
     * issues NO power ioctl here — SF's fbdev-surface path owns panel power, and
     * the first hwc_set() after unblank restarts OVL0 naturally. So on blank we
     * only record the request (above) and return; on unblank we do nothing. */
    (void)blank;
    /* On unblank: no action needed; next hwc_set() will resume OVL0         */
    return 0;
}

/* =========================================================================
 * Standard HWC ops (unchanged from v213)
 * ========================================================================= */

static int hwc_event_control(hwc_composer_device_1_t *dev, int /*dpy*/,
                              int event, int enabled)
{
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(dev);
    if (event == HWC_EVENT_VSYNC) {
        d->vsync_enabled = (enabled != 0);
        return 0;
    }
    return -EINVAL;
}

static int hwc_query(hwc_composer_device_1_t * /*dev*/, int what, int *value)
{
    switch (what) {
    case HWC_BACKGROUND_LAYER_SUPPORTED: *value = 0;        return 0;
    case HWC_VSYNC_PERIOD:               *value = 16666667; return 0;
    default:                             return -EINVAL;
    }
}

static void hwc_register_procs(hwc_composer_device_1_t *dev,
                                hwc_procs_t const *procs)
{
    reinterpret_cast<hwc_ctx *>(dev)->procs = procs;
}

static int hwc_get_display_configs(hwc_composer_device_1_t * /*dev*/, int dpy,
                                   uint32_t *configs, size_t *numConfigs)
{
    if (dpy != HWC_DISPLAY_PRIMARY) return -EINVAL;
    if (configs && *numConfigs > 0) {
        configs[0]  = 0;
        *numConfigs = 1;
    }
    return 0;
}

/*
 * hwc_get_display_attributes — report display dimensions to SurfaceFlinger.
 *
 * LANDSCAPE SUPPORT:
 * If ro.sf.hwrotation is 90 or 270, the panel is physically rotated and SF
 * must be told about the logical (landscape) dimensions.  We swap w/h when
 * that property is set, as the vendor blob does (RE §6.6 / v213_hwc_blob_re.md
 * §3.3).  The overlay path then presents the SF-composited (already-rotated)
 * buffer at DISP_ORIENTATION_0 — the hardware rotation is baked into the
 * FB_TARGET pixel content by SF's GLES compositor.
 *
 * NOTE: When the overlay path is operational, d->display_w/h come from
 * GET_SESSION_INFO (actual panel native dimensions from kernel), not from the
 * fb0 ioctl.  When in fallback mode, d->xres/yres come from FBIOGET_VSCREENINFO.
 */
static int hwc_get_display_attributes(hwc_composer_device_1_t *dev, int dpy,
                                      uint32_t /*config*/,
                                      const uint32_t *attributes, int32_t *values)
{
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(dev);
    if (dpy != HWC_DISPLAY_PRIMARY) return -EINVAL;

    uint32_t w = d->overlay_ok ? d->display_w : d->xres;
    uint32_t h = d->overlay_ok ? d->display_h : d->yres;

    /* Read ro.sf.hwrotation once per query (property may change at boot)     */
    char prop[PROPERTY_VALUE_MAX] = {};
    property_get("ro.sf.hwrotation", prop, "0");
    int hwrotation = atoi(prop);
    if (hwrotation == 90 || hwrotation == 270) {
        uint32_t tmp = w; w = h; h = tmp;
        ALOGD("v273: hwrotation=%d => reporting w=%u h=%u (swapped)", hwrotation, w, h);
    }

    for (int i = 0; attributes[i] != HWC_DISPLAY_NO_ATTRIBUTE; i++) {
        switch (attributes[i]) {
        case HWC_DISPLAY_VSYNC_PERIOD: values[i] = 16666667; break;
        case HWC_DISPLAY_WIDTH:        values[i] = (int32_t)w; break;
        case HWC_DISPLAY_HEIGHT:       values[i] = (int32_t)h; break;
        case HWC_DISPLAY_DPI_X:        values[i] = 403000;    break;
        case HWC_DISPLAY_DPI_Y:        values[i] = 403000;    break;
        default:                       values[i] = -1;         break;
        }
    }
    return 0;
}

static void hwc_dump(hwc_composer_device_1_t *dev, char *buff, int buff_len)
{
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(dev);
    snprintf(buff, (size_t)buff_len,
             "m2note source HWC1 v462 (DDP multi-OVL; fb stride; present fence property fix; hw-vsync)\n"
             "  overlay: ok=%d present_fence=%d hw_vsync=%d multi_ovl=%d failed=%d session_id=0x%08x maxLayer=%u display=%ux%u\n"
             "  overlay_present=%llu overlay_fail=%llu fb_fallback=%llu\n"
             "  multi_ovl: present=%llu fail=%llu last_layers=%u max=%u freeze_latch=%llu\n"
             "  vsync: hw=%llu synth=%llu hw_fail=%llu enabled=%d\n"
             "  geom: src=%ux%u stride_px=%u pitch_B=%u alloc=%u vstride=%u metadata_bypass=%llu\n"
             "  fb0: %ux%u line_length=%u pages=%u cur=%u\n"
             "  fb0: pan=%llu copy=%llu skip_copy=%llu lock_fail=%llu\n"
             "  blank_req=%d\n",
             (int)d->overlay_ok, (int)d->use_present_fence, (int)d->use_hw_vsync,
             (int)d->use_multi_ovl, (int)d->multi_ovl_failed,
             d->session_id, d->max_layer_num,
             d->display_w, d->display_h,
             (unsigned long long)d->overlay_present,
             (unsigned long long)d->overlay_fail,
             (unsigned long long)d->fb_fallback,
             (unsigned long long)d->multi_present,
             (unsigned long long)d->multi_fail,
             d->last_overlay_count,
             d->multi_ovl_max,
             (unsigned long long)d->freeze_latch,
             (unsigned long long)d->vsync_hw,
             (unsigned long long)d->vsync_synth,
             (unsigned long long)d->vsync_hw_fail,
             (int)d->vsync_enabled,
             d->last_src_w, d->last_src_h, d->last_stride_px,
             d->last_pitch_bytes, d->last_alloc_size, d->last_vstride,
             (unsigned long long)d->metadata_bypass,
             d->xres, d->yres, d->line_length, d->num_pages, d->cur_page,
             (unsigned long long)d->present_pan,
             (unsigned long long)d->present_copy,
             (unsigned long long)d->present_skip_copy,
             (unsigned long long)d->present_lock_fail,
             d->blank_req);
}

/* =========================================================================
 * Module open / close
 * ========================================================================= */

static int hwc_device_close(hw_device_t *dev)
{
    hwc_ctx *d = reinterpret_cast<hwc_ctx *>(dev);

    /* Stop watchdog thread first (it may hold watchdog_mutex briefly)         */
    if (d->watchdog_running) {
        d->watchdog_running = false;
        pthread_join(d->watchdog_thread, NULL);
    }
    if (d->watchdog_fence >= 0) {
        close(d->watchdog_fence);
        d->watchdog_fence = -1;
    }

    /* Stop vsync thread                                                       */
    if (d->vsync_running) {
        d->vsync_running = false;
        pthread_join(d->vsync_thread, NULL);
    }

    /* Destroy overlay session and close fds                                  */
    overlay_session_close(d);

    pthread_mutex_destroy(&d->overlay_mutex);
    pthread_mutex_destroy(&d->watchdog_mutex);

    /* Unmap / close fb0 (fallback path)                                      */
    if (d->fb_mem && d->fb_mem != MAP_FAILED)
        munmap(d->fb_mem, d->fb_total_bytes);
    if (d->fb_fd >= 0)
        close(d->fb_fd);

    free(d);
    return 0;
}

static int hwc_device_open(const hw_module_t *module, const char *name,
                            hw_device_t **device)
{
    if (strcmp(name, HWC_HARDWARE_COMPOSER) != 0) return -EINVAL;

    hwc_ctx *d = (hwc_ctx *)calloc(1, sizeof(hwc_ctx));
    if (!d) return -ENOMEM;

    /* Sentinel values for uninitialised fds                                  */
    d->disp_fd    = -1;
    d->ion_client = -1;
    d->fb_fd      = -1;

    /* ---- HAL device header ---- */
    d->base.common.tag     = HARDWARE_DEVICE_TAG;
    d->base.common.version = HWC_DEVICE_API_VERSION_1_1;
    d->base.common.module  = const_cast<hw_module_t *>(module);
    d->base.common.close   = hwc_device_close;

    d->base.prepare              = hwc_prepare;
    d->base.set                  = hwc_set;
    d->base.eventControl         = hwc_event_control;
    d->base.blank                = hwc_blank;
    d->base.query                = hwc_query;
    d->base.registerProcs        = hwc_register_procs;
    d->base.dump                 = hwc_dump;
    d->base.getDisplayConfigs    = hwc_get_display_configs;
    d->base.getDisplayAttributes = hwc_get_display_attributes;

    /* ---- gralloc module (needed for fb0 fallback path) ---- */
    hw_get_module(GRALLOC_HARDWARE_MODULE_ID,
                  (const hw_module_t **)&d->gralloc);

    /* ---- fb0 fallback path: open + mmap (v213 logic, unchanged) ---- */
    d->fb_fd = open("/dev/graphics/fb0", O_RDWR);
    if (d->fb_fd < 0) d->fb_fd = open("/dev/fb0", O_RDWR);

    /* Defaults in case fb0 open fails or ioctls fail                         */
    d->xres        = PANEL_W_DEFAULT;
    d->yres        = PANEL_H_DEFAULT;
    d->line_length = PANEL_W_DEFAULT * 4;  /* RGBA stride guess               */
    d->num_pages   = 1;

    if (d->fb_fd >= 0) {
        struct fb_fix_screeninfo fix;
        if (ioctl(d->fb_fd, FBIOGET_VSCREENINFO, &d->var) == 0 &&
            ioctl(d->fb_fd, FBIOGET_FSCREENINFO, &fix) == 0 &&
            d->var.xres && d->var.yres) {
            d->xres        = d->var.xres;
            d->yres        = d->var.yres;
            d->line_length = fix.line_length;
            d->num_pages   = d->var.yres_virtual / d->var.yres;
            if (d->num_pages < 1) d->num_pages = 1;
            d->fb_page_bytes  = (size_t)d->line_length * d->yres;
            d->fb_total_bytes = (size_t)d->line_length * d->var.yres_virtual;
            d->fb_mem = (uint8_t *)mmap(0, d->fb_total_bytes,
                                        PROT_READ | PROT_WRITE,
                                        MAP_SHARED, d->fb_fd, 0);
            if (d->fb_mem == MAP_FAILED) d->fb_mem = NULL;
        }
    }
    ALOGI("v461: fb0 %ux%u line_length=%u pages=%u fb_mem=%p",
          d->xres, d->yres, d->line_length, d->num_pages, d->fb_mem);

    /* ---- Overlay + watchdog mutexes ---- */
    pthread_mutex_init(&d->overlay_mutex, NULL);
    pthread_mutex_init(&d->watchdog_mutex, NULL);
    d->watchdog_fence   = -1;
    d->watchdog_running = false;

    /* ---- Overlay path: default on; property can force fallback ---- */
    char overlay_prop[PROPERTY_VALUE_MAX] = {};
    property_get("debug.forge.m2note.overlay_hwc", overlay_prop, "");
    if (overlay_prop[0] == '\0')
        property_get("persist.forge.m2note.overlay_hwc", overlay_prop, "1");

    char present_fence_prop[PROPERTY_VALUE_MAX] = {};
    property_get("debug.forge.m2note.present_fence", present_fence_prop, "");
    if (present_fence_prop[0] == '\0')
        property_get("persist.forge.m2note.present_fence", present_fence_prop, "0");
    d->use_present_fence = (present_fence_prop[0] != '0');

    char hw_vsync_prop[PROPERTY_VALUE_MAX] = {};
    property_get("debug.forge.m2note.hw_vsync", hw_vsync_prop, "");
    if (hw_vsync_prop[0] == '\0')
        property_get("persist.forge.m2note.hw_vsync", hw_vsync_prop, "1");
    d->use_hw_vsync = (hw_vsync_prop[0] != '0');

    /* MULTI-OVL: default ON after v853/v854 live evidence.  The path is still
     * property-gated so recovery/debug can force the old single-OVL behaviour
     * with debug/persist.forge.m2note.multi_ovl=0.                            */
    char multi_ovl_prop[PROPERTY_VALUE_MAX] = {};
    property_get("debug.forge.m2note.multi_ovl", multi_ovl_prop, "");
    if (multi_ovl_prop[0] == '\0')
        property_get("persist.forge.m2note.multi_ovl", multi_ovl_prop, "1");
    d->use_multi_ovl    = (multi_ovl_prop[0] != '0');
    d->multi_ovl_failed = false;

    /* Runtime OVL-bandwidth cap: how many app layers to offload (1..3).
     * Default 2: live v854 proved wallpaper + launcher offload stable, while
     * keeping status/navigation chrome in FB_TARGET.  The stock blob caps
     * overlay layers under bandwidth/overlap pressure; lower this live if an
     * A/B ever shows overlay underflow (tearing, NOT a freeze). */
    char multi_max_prop[PROPERTY_VALUE_MAX] = {};
    property_get("debug.forge.m2note.multi_ovl_max", multi_max_prop, "");
    if (multi_max_prop[0] == '\0')
        property_get("persist.forge.m2note.multi_ovl_max", multi_max_prop, "2");
    {
        int m = atoi(multi_max_prop);
        if (m < 1) m = 1;
        if (m > MAX_OVERLAY_APP_LAYERS) m = MAX_OVERLAY_APP_LAYERS;
        d->multi_ovl_max = (uint32_t)m;
    }

    if (overlay_prop[0] != '0')
        d->overlay_ok = overlay_session_open(d);
    else
        d->overlay_ok = false;

    if (d->overlay_ok) {
        ALOGI("v462: overlay active (OVL0; full-slot disable; pixel pitch; present_fence=%d hw_vsync=%d multi_ovl=%d)",
              (int)d->use_present_fence, (int)d->use_hw_vsync, (int)d->use_multi_ovl);
    } else {
        ALOGW("v462: using fb0 fallback path; overlay prop=%s", overlay_prop);
    }

    /* ---- Vsync thread: kernel WAIT_FOR_VSYNC with synthetic fallback ---- */
    d->vsync_enabled = false;
    d->vsync_running = true;
    if (pthread_create(&d->vsync_thread, NULL, hwc_vsync_thread, d) != 0) {
        ALOGE("v273: vsync thread failed");
        d->vsync_running = false;
    }

    /* ---- MULTI-OVL freeze watchdog thread (only when multi-OVL is armed) ---- */
    if (d->overlay_ok && d->use_multi_ovl) {
        d->watchdog_running = true;
        if (pthread_create(&d->watchdog_thread, NULL, hwc_watchdog_thread, d) != 0) {
            ALOGE("v462: watchdog thread failed — multi-OVL DISABLED for safety");
            d->watchdog_running = false;
            d->use_multi_ovl = false;   /* no self-recovery guarantee -> do not risk it */
        } else {
            ALOGI("v462: multi-OVL freeze watchdog armed (canary=%d frames, freeze=%llums)",
                  MULTI_OVL_CANARY_FRAMES,
                  (unsigned long long)(MULTI_OVL_FREEZE_TIMEOUT_NS / 1000000ULL));
        }
    }

    *device = &d->base.common;
    return 0;
}

/* =========================================================================
 * HAL module descriptor
 * ========================================================================= */

static struct hw_module_methods_t hwc_module_methods = {
    .open = hwc_device_open
};

hwc_module_t HAL_MODULE_INFO_SYM = {
    .common = {
        .tag           = HARDWARE_MODULE_TAG,
        .version_major = 1,
        .version_minor = 1,
        .id            = HWC_HARDWARE_MODULE_ID,
        .name          = "m2note source HWC1 v273 (DDP overlay hw-vsync)",
        .author        = "AndroidForge",
        .methods       = &hwc_module_methods,
        .dso           = NULL,
        .reserved      = {0},
    }
};
