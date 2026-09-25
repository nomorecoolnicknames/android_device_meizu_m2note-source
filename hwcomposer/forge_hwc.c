/*
 * forge_hwc — hwcomposer.mt6737m for the Meizu m5c on the forge 4.9 kernel.
 *
 * HWC1 (HWC_DEVICE_API_VERSION_1_1) facade over the NATIVE 4.9 mtk_disp_mgr
 * session ABI.  The vendor 3.18-built blob is broken against this kernel
 * (frames stall inside its internal queues, root cause never established);
 * this module replaces it with the minimal correct pipeline:
 *
 *   prepare(): every layer -> HWC_FRAMEBUFFER (SurfaceFlinger composes
 *              everything with GLES into the framebuffer target).
 *   set():     wait FBT acquire fence (the kernel does not consume
 *              src_fence_fd, verified: no reader outside compat conversion)
 *              -> PREPARE_INPUT_BUFFER(204)  ion_fd -> buff idx + release fence
 *              -> GET_PRESENT_FENCE(217)     -> retire fence + idx
 *              -> SET_INPUT_BUFFER(206)      native 12-layer struct, L0 only
 *              -> TRIGGER_SESSION(203)       with present_fence_idx
 *   vsync:     dedicated thread blocking in WAIT_FOR_VSYNC(213).
 *   blank():   FBIOBLANK on fb0 (mtkfb_blank -> primary_display_suspend/resume).
 *
 * Design note: everything version-specific to Android N lives in the thin
 * HWC1 facade at the bottom of this file; the engine (open/session/frame/
 * vsync/power) talks only to the kernel UAPI in disp_session_uapi.h and is
 * meant to be reused behind an HWC2 facade (or hwc2on1adapter) on the
 * LOS 15.1 -> 16 -> 18.1 ladder with this same 4.9 kernel.
 *
 * Buffer handles: ion fd and stride are queried through the vendor
 * libgralloc_extra.so (dlopen, plain C symbol, present in /system/lib{,64}).
 * Fallback when unavailable: fd = handle->data[0], stride = display width
 * (FACT p61: gralloc buffers for the 720-wide panel have pitch 2880 = 720*4).
 */

#define LOG_TAG "forge-hwc"

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>	/* disp_session_uapi.h (kernel copy) uses bool */
#include <malloc.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/system_properties.h>
#include <linux/fb.h>

/*
 * dma-buf sync ioctl, declared locally (the NDK sysroot used by
 * build_standalone.sh has no linux/dma-buf.h).  Used only by the
 * forge-crc probe to invalidate the CPU view before reading; if the
 * kernel/heap rejects it we read anyway - display ion heaps here are
 * uncached for the CPU.
 */
struct forge_dma_buf_sync {
	uint64_t flags;
};
#define FORGE_DMA_BUF_SYNC_READ (1 << 0)
#define FORGE_DMA_BUF_SYNC_START (0 << 2)
#define FORGE_DMA_BUF_SYNC_END (1 << 2)
#define FORGE_DMA_BUF_IOCTL_SYNC _IOW('b', 0, struct forge_dma_buf_sync)

#include <hardware/hardware.h>
#include <hardware/hwcomposer.h>

#include "disp_session_uapi.h"

/* liblog, declared by hand so the module links against libc+liblog+libdl only */
int __android_log_print(int prio, const char *tag, const char *fmt, ...);
#define FLOGI(...) __android_log_print(4 /* INFO */, LOG_TAG, __VA_ARGS__)
#define FLOGW(...) __android_log_print(5 /* WARN */, LOG_TAG, __VA_ARGS__)
#define FLOGE(...) __android_log_print(6 /* ERROR */, LOG_TAG, __VA_ARGS__)

#define DISP_DEV_PATH "/dev/mtk_disp_mgr"
#define FB_DEV_PATH "/dev/graphics/fb0"

/* gralloc_extra_query attribute ids (device/meizu/m5c/libgem/inc/gralloc_extra.h) */
#define GE_GET_ION_FD 1
#define GE_GET_WIDTH 10
#define GE_GET_HEIGHT 11
#define GE_GET_STRIDE 12
#define GE_GET_FORMAT 15

struct forge_hwc {
	hwc_composer_device_1_t base;	/* must stay first */
	const hwc_procs_t *procs;

	int disp_fd;
	int fb_fd;
	unsigned int session;
	int session_ok;

	unsigned int width, height;
	unsigned int vsync_period_ns;
	unsigned int xdpi_1000, ydpi_1000;	/* dpi * 1000, HWC1 convention */

	int (*ge_query)(buffer_handle_t handle, int attribute, void *out);
	void *ge_lib;

	pthread_t vsync_thread;
	pthread_mutex_t lock;
	pthread_cond_t cond;
	volatile int vsync_on;
	volatile int stop;

	/* stats for dump() */
	unsigned int frames;
	unsigned int prepare_fail;
	unsigned int trigger_fail;
	unsigned int acquire_timeouts;
	/*
	 * forge fence-probe (2026-08-25, tear hunt).  Under a heavy scroll a
	 * HEALTHY pipeline must regularly reach set() before the GPU has
	 * finished the buffers (acq_waited > 0 for a visible share of
	 * planes).  If essentially every acquire fence is already signaled
	 * (acq_presignaled ~ 100%) on scenes the GPU cannot possibly finish
	 * that fast, the mali fences are firing early - SurfaceFlinger then
	 * latches half-rendered buffers and the glass shows a stationary
	 * horizontal stitch between two moments of motion, identical with
	 * overlays on and off (matches p80).  Counters are in dump() and a
	 * summary goes to dmesg every 300 frames.
	 */
	unsigned int acq_presignaled;
	unsigned int acq_waited;
	unsigned int acq_nofence;	/* SF handed us NO fence (fd = -1):
					 * with mali lacking native fence
					 * support every plane lands here and
					 * nothing orders the GPU against the
					 * scan-out - a content tear needs no
					 * other explanation then */
	unsigned int acq_wait_us_max;
	unsigned long long acq_wait_us_total;
	/* forge-crc probe results (see engine_crc_probe) */
	unsigned int crc_runs;
	unsigned int crc_dirty_runs;
	/* forge-shear probe results (see engine_shear_probe) */
	unsigned int shear_frames;
	unsigned int shear_motion;
	unsigned int shear_zoned;
	unsigned int shear_hard;
	unsigned int last_buff_idx;
	unsigned int last_pf_idx;
	int fmt_override;	/* debug.forgehwc.fmt, 0 = RGBA8888 */

	/* overlay stats */
	unsigned int ovl_frames;	/* frames with >=1 promoted layer */
	unsigned int gles_frames;	/* frames composed via FBT only */
	unsigned int promoted_total;	/* cumulative promoted layers */
	unsigned int last_novl;		/* planes in last frame */
	int last_fbt_used;
};

/* one plane handed to the kernel OVL */
struct fhwc_plane {
	buffer_handle_t handle;
	int acquire;		/* fence fd, consumed by submit */
	int fmt;		/* DISP_FORMAT_* */
	int32_t blending;	/* HWC_BLENDING_*, 0 for the FBT */
	uint16_t sx, sy, sw, sh;	/* source crop, pixels */
	uint16_t tx, ty;	/* dest offset */
	int release_fd;		/* out: per-plane release fence */
};

static int prop_int(const char *name, int def)
{
	char v[PROP_VALUE_MAX];

	if (__system_property_get(name, v) > 0)
		return atoi(v);
	return def;
}

/*
 * Duplicate the load-bearing markers into dmesg: logcat gets rotated and
 * restarted with the framework, dmesg is what every capture script here
 * already collects.
 */
static void kmsg_log(const char *fmt, ...)
{
	char line[256];
	va_list ap;
	int fd, n;

	fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	if (fd < 0)
		return;
	va_start(ap, fmt);
	n = vsnprintf(line, sizeof(line), fmt, ap);
	va_end(ap);
	if (n > 0)
		write(fd, line, (size_t)(n < (int)sizeof(line) ? n : (int)sizeof(line)));
	close(fd);
}

/* ============================ engine ============================ */

static int engine_wait_fence(struct forge_hwc *hwc, int fd, int timeout_ms)
{
	struct pollfd p;
	int ret;

	if (fd < 0)
		return 0;
	p.fd = fd;
	p.events = POLLIN | POLLERR;
	do {
		ret = poll(&p, 1, timeout_ms);
	} while (ret == -1 && (errno == EINTR || errno == EAGAIN));
	if (ret == 0) {
		hwc->acquire_timeouts++;
		FLOGW("acquire fence %d timed out after %d ms", fd, timeout_ms);
	}
	return ret;
}

static int engine_open_session(struct forge_hwc *hwc)
{
	struct disp_session_config cfg;
	struct disp_session_info info;

	memset(&cfg, 0, sizeof(cfg));
	cfg.type = DISP_SESSION_PRIMARY;
	cfg.device_id = 0;
	cfg.mode = DISP_SESSION_DIRECT_LINK_MODE;
	cfg.user = SESSION_USER_HWC;

	if (ioctl(hwc->disp_fd, DISP_IOCTL_CREATE_SESSION, &cfg) < 0) {
		FLOGE("CREATE_SESSION failed: %s", strerror(errno));
		return -errno;
	}
	hwc->session = cfg.session_id;

	memset(&info, 0, sizeof(info));
	info.session_id = hwc->session;
	if (ioctl(hwc->disp_fd, DISP_IOCTL_GET_SESSION_INFO, &info) < 0) {
		FLOGE("GET_SESSION_INFO failed: %s", strerror(errno));
		return -errno;
	}

	hwc->width = info.displayWidth;
	hwc->height = info.displayHeight;
	/*
	 * MTK convention (measured on device, not guessed): vsyncFPS comes
	 * back as fps*100 — 5850 here, i.e. 58.50 Hz.  Values <= 1000 are
	 * treated as plain Hz just in case another kernel returns those.
	 */
	if (info.vsyncFPS > 1000)
		hwc->vsync_period_ns =
		    (unsigned int)(100000000000ULL / info.vsyncFPS);
	else if (info.vsyncFPS)
		hwc->vsync_period_ns = 1000000000u / info.vsyncFPS;
	else
		hwc->vsync_period_ns = 16666666u;
	if (info.physicalWidthUm && info.physicalHeightUm) {
		hwc->xdpi_1000 = (unsigned int)
		    ((uint64_t)info.displayWidth * 25400000ULL / info.physicalWidthUm);
		hwc->ydpi_1000 = (unsigned int)
		    ((uint64_t)info.displayHeight * 25400000ULL / info.physicalHeightUm);
	}
	if (!hwc->xdpi_1000)
		hwc->xdpi_1000 = hwc->ydpi_1000 =
		    (unsigned int)prop_int("ro.sf.lcd_density", 320) * 1000u;

	/* be explicit about the mode; the vendor HAL did the same (12x mode=1) */
	memset(&cfg, 0, sizeof(cfg));
	cfg.type = DISP_SESSION_PRIMARY;
	cfg.mode = DISP_SESSION_DIRECT_LINK_MODE;
	cfg.session_id = hwc->session;
	cfg.user = SESSION_USER_HWC;
	cfg.present_fence_idx = (unsigned int)-1;
	if (ioctl(hwc->disp_fd, DISP_IOCTL_SET_SESSION_MODE, &cfg) < 0)
		FLOGW("SET_SESSION_MODE failed: %s (continuing)", strerror(errno));

	hwc->session_ok = 1;
	FLOGI("session 0x%x: %ux%u vsyncFPS=%u period=%uns maxLayer=%u vsync=%u dpi=%u.%03u",
	      hwc->session, hwc->width, hwc->height, info.vsyncFPS,
	      hwc->vsync_period_ns, info.maxLayerNum,
	      info.isHwVsyncAvailable, hwc->xdpi_1000 / 1000, hwc->xdpi_1000 % 1000);
	kmsg_log("forge-hwc: session 0x%x %ux%u vsyncFPS=%u period=%uns maxLayer=%u",
		 hwc->session, hwc->width, hwc->height, info.vsyncFPS,
		 hwc->vsync_period_ns, info.maxLayerNum);
	return 0;
}

/* HAL pixel format -> DISP_FORMAT for the overlay path; 0 = not supported */
static int map_hal_format(int hal_fmt)
{
	switch (hal_fmt) {
	case 1:		/* HAL_PIXEL_FORMAT_RGBA_8888 */
		return DISP_FORMAT_RGBA8888;
	case 2:		/* HAL_PIXEL_FORMAT_RGBX_8888 */
		return DISP_FORMAT_RGBX8888;
	case 4:		/* HAL_PIXEL_FORMAT_RGB_565 */
		return DISP_FORMAT_RGB565;
	case 5:		/* HAL_PIXEL_FORMAT_BGRA_8888 */
		return DISP_FORMAT_BGRA8888;
	default:
		return 0;
	}
}

/*
 * Blending -> OVL alpha controls.  Verified against the kernel encoding
 * (mt6735m/ddp_ovl.c: sur_aen -> SURFL_EN bit 15, src/dst_alpha -> the
 * 2-bit blend factor selectors).  PREMULT: out = src + (1-a_s)*dst ->
 * factors ONE / SRC_INVERT; COVERAGE: SRC / SRC_INVERT.
 */
static void fill_blending(struct disp_input_config *c, int32_t blending)
{
	if (blending == 0x0105 /* HWC_BLENDING_PREMULT */) {
		c->alpha_enable = 1;
		c->sur_aen = 1;
		c->src_alpha = DISP_ALPHA_ONE;
		c->dst_alpha = DISP_ALPHA_SRC_INVERT;
	} else if (blending == 0x0405 /* HWC_BLENDING_COVERAGE */) {
		c->alpha_enable = 1;
		c->sur_aen = 1;
		c->src_alpha = DISP_ALPHA_SRC;
		c->dst_alpha = DISP_ALPHA_SRC_INVERT;
	} else {	/* HWC_BLENDING_NONE / FBT: opaque */
		c->alpha_enable = 0;
		c->sur_aen = 0;
		c->src_alpha = DISP_ALPHA_ONE;
		c->dst_alpha = DISP_ALPHA_ONE;
	}
	c->alpha = 0xff;
}

/*
 * forge-crc probe (2026-08-25): the OBJECTIVE tear detector at the content
 * level.  Once a plane is submitted, the buffer belongs to the display
 * until its release fence signals - NOTHING may legitimately write into
 * it.  So: signature 10 rows of every submitted buffer right after
 * TRIGGER, wait ~half a frame, signature them again.  Any difference =
 * the producer (GPU) is still rendering into a buffer we handed to the
 * scan-out - a content tear needs no other explanation, and no eyes are
 * needed.  Enabled with debug.forgehwc.crc=1, samples every 16th frame
 * (the probe stalls set() by crcdelay us on sampled frames - visible
 * hitching while enabled is expected and harmless).
 * dmesg: "forge-crc: ... dirty=..." lines; totals in dump().
 */
static void engine_crc_probe(struct forge_hwc *hwc, struct fhwc_plane *planes,
			     int n)
{
	static unsigned int seq;
	void *map[4] = { NULL, NULL, NULL, NULL };
	size_t maplen[4] = { 0, 0, 0, 0 };
	int fd_of[4] = { -1, -1, -1, -1 };
	unsigned int pitch[4], rows_of[4];
	uint64_t sig0[4][10];
	int k, r, w, delay_us, any_dirty = 0;

	if (!prop_int("debug.forgehwc.crc", 0))
		return;
	if ((seq++ % 16) != 0)
		return;
	delay_us = prop_int("debug.forgehwc.crcdelay", 9000);

	for (k = 0; k < n; k++) {
		int ion_fd = -1, stride_px = (int)hwc->width;
		off_t sz;

		if (hwc->ge_query) {
			if (hwc->ge_query(planes[k].handle, GE_GET_ION_FD, &ion_fd) != 0)
				ion_fd = -1;
			hwc->ge_query(planes[k].handle, GE_GET_STRIDE, &stride_px);
		}
		if (ion_fd < 0 && planes[k].handle->numFds > 0)
			ion_fd = planes[k].handle->data[0];
		if (ion_fd < 0)
			continue;
		sz = lseek(ion_fd, 0, SEEK_END);
		lseek(ion_fd, 0, SEEK_SET);
		if (sz <= 0)
			continue;
		if ((size_t)sz > (size_t)stride_px * 4u * planes[k].sh)
			sz = (off_t)((size_t)stride_px * 4u * planes[k].sh);
		map[k] = mmap(NULL, (size_t)sz, PROT_READ, MAP_SHARED, ion_fd, 0);
		if (map[k] == MAP_FAILED) {
			map[k] = NULL;
			continue;
		}
		maplen[k] = (size_t)sz;
		fd_of[k] = ion_fd;
		pitch[k] = (unsigned int)stride_px * 4u;
		rows_of[k] = maplen[k] / pitch[k];
	}

	for (w = 0; w < 2; w++) {
		if (w == 1)
			usleep(delay_us);
		for (k = 0; k < n; k++) {
			struct forge_dma_buf_sync dbs;

			if (!map[k])
				continue;
			dbs.flags = FORGE_DMA_BUF_SYNC_START | FORGE_DMA_BUF_SYNC_READ;
			ioctl(fd_of[k], FORGE_DMA_BUF_IOCTL_SYNC, &dbs);
			for (r = 0; r < 10; r++) {
				unsigned int row = (rows_of[k] > 1) ?
				    (unsigned int)((uint64_t)r * (rows_of[k] - 1) / 9) : 0;
				const uint64_t *q = (const uint64_t *)
				    ((const char *)map[k] + (size_t)row * pitch[k]);
				unsigned int nw = pitch[k] / 8;
				uint64_t acc = 0;
				unsigned int i;

				for (i = 0; i < nw; i++)
					acc ^= q[i];
				if (w == 0) {
					sig0[k][r] = acc;
				} else if (acc != sig0[k][r]) {
					any_dirty |= 1 << k;
					kmsg_log("forge-crc: seq=%u plane=%d row=%u CHANGED after submit (delay=%dus)",
						 seq - 1, k, row, delay_us);
				}
			}
			dbs.flags = FORGE_DMA_BUF_SYNC_END | FORGE_DMA_BUF_SYNC_READ;
			ioctl(fd_of[k], FORGE_DMA_BUF_IOCTL_SYNC, &dbs);
		}
	}

	hwc->crc_runs++;
	if (any_dirty)
		hwc->crc_dirty_runs++;
	if (any_dirty || (hwc->crc_runs % 32) == 0)
		kmsg_log("forge-crc: runs=%u dirty_runs=%u last_dirty_mask=0x%x",
			 hwc->crc_runs, hwc->crc_dirty_runs, any_dirty);

	for (k = 0; k < n; k++)
		if (map[k])
			munmap(map[k], maplen[k]);
}

/*
 * forge-shear probe (2026-08-27): objective tear detector for content that
 * is ALREADY torn inside the submitted buffer.  The fence counters and the
 * CRC probe proved nobody writes into a buffer after submit (presig is the
 * healthy N pattern - SF latches one vsync after queueBuffer - and 246 CRC
 * runs came back clean), so a tear on the glass must be baked in by the
 * producer (hwui partial update / EGL buffer age are the suspects).
 *
 * Method: signature every row of plane 0 (the app buffer when no FBT is
 * used), then match each probed row of this frame against the previous
 * submitted frame at vertical offsets -SHEAR_D..+SHEAR_D.  During a scroll
 * a healthy frame moves as ONE block: fixed header rows at d=0, the
 * scrolled body below it at one d != 0, boundary at the header edge.  A
 * torn frame shows a boundary at the TEAR row instead (the stale part
 * matches d=0, the fresh part d=s, or two different non-zero d).  The
 * verdict is therefore in the zone-map ROWS: a boundary that sits at the
 * toolbar edge every frame is legit, one that wanders around ~60% height
 * is the tear.  Rows whose signature matches more than one offset
 * (uniform backgrounds) are discarded as ambiguous.
 *
 * Lane rule (2026-08-27 evening A/B, tear2): a zone counts only when it
 * spans >= 2 ADJACENT probed rows.  Single-row matches are aliasing of
 * repeating list items (the A/B showed pairs of single rows 312px apart
 * with offsets differing by exactly 20, invariant to the hwui knobs) and
 * are shown in the map but excluded from zoned/hard.  The kernel WDMA
 * probe applies the same rule so both counters stay comparable.
 *
 * Enabled with debug.forgehwc.shear=N (probe every Nth submit, 1 = every
 * frame; d is only exact between consecutively probed frames, so use 1).
 * Cost: one ~3.5MB uncached read per probed frame, no sleeps.
 * dmesg: "forge-shear:" zone maps + totals; counters in dump().
 */
#define SHEAR_MAX_ROWS 2048
#define SHEAR_D 160
#define SHEAR_MAX_RUNS 5
static void engine_shear_probe(struct forge_hwc *hwc, struct fhwc_plane *planes,
			       int n)
{
	static uint64_t sig_prev[SHEAR_MAX_ROWS], sig_cur[SHEAR_MAX_ROWS];
	static unsigned int prev_rows, prev_pitch, prev_valid, seq, zone_seq;
	struct forge_dma_buf_sync dbs;
	int every = prop_int("debug.forgehwc.shear", 0);
	int ion_fd = -1, stride_px = (int)hwc->width;
	unsigned int pitch, rows, nw, r, i;
	void *map;
	off_t sz;

	if (every <= 0 || n < 1) {
		prev_valid = 0;
		return;
	}
	if ((seq++ % (unsigned)every) != 0)
		return;

	if (hwc->ge_query) {
		if (hwc->ge_query(planes[0].handle, GE_GET_ION_FD, &ion_fd) != 0)
			ion_fd = -1;
		hwc->ge_query(planes[0].handle, GE_GET_STRIDE, &stride_px);
	}
	if (ion_fd < 0 && planes[0].handle->numFds > 0)
		ion_fd = planes[0].handle->data[0];
	if (ion_fd < 0)
		return;
	sz = lseek(ion_fd, 0, SEEK_END);
	if (sz <= 0)
		return;
	pitch = (unsigned int)stride_px * 4u;
	rows = (unsigned int)sz / pitch;
	if (planes[0].sh && rows > planes[0].sh)
		rows = planes[0].sh;
	if (rows > SHEAR_MAX_ROWS)
		rows = SHEAR_MAX_ROWS;
	if (rows < 64)
		return;

	map = mmap(NULL, (size_t)rows * pitch, PROT_READ, MAP_SHARED, ion_fd, 0);
	if (map == MAP_FAILED)
		return;
	dbs.flags = FORGE_DMA_BUF_SYNC_START | FORGE_DMA_BUF_SYNC_READ;
	ioctl(ion_fd, FORGE_DMA_BUF_IOCTL_SYNC, &dbs);
	nw = pitch / 8;
	for (r = 0; r < rows; r++) {
		const uint64_t *q = (const uint64_t *)
		    ((const char *)map + (size_t)r * pitch);
		uint64_t acc = 0;

		for (i = 0; i < nw; i++)
			acc ^= q[i];
		sig_cur[r] = acc;
	}
	dbs.flags = FORGE_DMA_BUF_SYNC_END | FORGE_DMA_BUF_SYNC_READ;
	ioctl(ion_fd, FORGE_DMA_BUF_IOCTL_SYNC, &dbs);
	munmap(map, (size_t)rows * pitch);

	if (prev_valid && prev_rows == rows && prev_pitch == pitch) {
		int run_s[SHEAR_MAX_RUNS], run_e[SHEAR_MAX_RUNS], run_d[SHEAR_MAX_RUNS];
		int nrun = 0, overflow = 0, motion = 0;
		int dset[SHEAR_MAX_RUNS], ndist = 0, ndist_nz = 0;

		for (r = 16; r + 16 < rows; r += 8) {
			int d, found = 0, dm = 0;

			for (d = -SHEAR_D; d <= SHEAR_D; d++) {
				int rr = (int)r + d;

				if (rr < 0 || rr >= (int)rows)
					continue;
				if (sig_cur[r] == sig_prev[rr]) {
					if (found++)
						break;	/* ambiguous row */
					dm = d;
				}
			}
			if (found != 1)
				continue;
			if (nrun && run_d[nrun - 1] == dm) {
				run_e[nrun - 1] = (int)r;
			} else if (nrun < SHEAR_MAX_RUNS) {
				run_s[nrun] = (int)r;
				run_e[nrun] = (int)r;
				run_d[nrun] = dm;
				nrun++;
			} else {
				overflow = 1;
			}
		}

		for (i = 0; i < (unsigned int)nrun; i++) {
			int d = run_d[i], j, seen = 0;

			/* lane rule: single-row runs are list-item aliasing,
			 * they stay in the map but never make a zone */
			if (run_e[i] == run_s[i])
				continue;
			if (d)
				motion = 1;
			for (j = 0; j < ndist; j++)
				if (dset[j] == d)
					seen = 1;
			if (!seen && ndist < SHEAR_MAX_RUNS) {
				dset[ndist++] = d;
				if (d)
					ndist_nz++;
			}
		}

		hwc->shear_frames++;
		if (motion)
			hwc->shear_motion++;
		if (ndist >= 2) {
			hwc->shear_zoned++;
			if (ndist_nz >= 2)
				hwc->shear_hard++;
			/* every 4th zone map, every hard frame */
			if (ndist_nz >= 2 || (zone_seq++ % 4) == 0) {
				char zbuf[160];
				int off = 0;

				for (i = 0; i < (unsigned int)nrun && off < 120; i++)
					off += snprintf(zbuf + off, sizeof(zbuf) - off,
							" %d-%d=%d", run_s[i],
							run_e[i], run_d[i]);
				kmsg_log("forge-shear: seq=%u%s map%s%s",
					 seq - 1, ndist_nz >= 2 ? " HARD" : "",
					 zbuf, overflow ? " +" : "");
			}
		}
		if ((hwc->shear_frames % 64) == 0)
			kmsg_log("forge-shear: frames=%u motion=%u zoned=%u hard=%u",
				 hwc->shear_frames, hwc->shear_motion,
				 hwc->shear_zoned, hwc->shear_hard);
	}

	memcpy(sig_prev, sig_cur, (size_t)rows * sizeof(uint64_t));
	prev_rows = rows;
	prev_pitch = pitch;
	prev_valid = 1;
}

/*
 * Hand n planes (bottom -> top == OVL layer 0 -> n-1) to the kernel in one
 * SET_INPUT + TRIGGER.  Consumes every plane's acquire fence; fills each
 * plane's release_fd and *retire_fence (all owned by the caller).
 */
static int engine_submit(struct forge_hwc *hwc, struct fhwc_plane *planes,
			 int n, int *retire_fence)
{
	struct disp_buffer_info buf;
	struct disp_present_fence pf;
	struct disp_session_input_config *in;
	struct disp_session_config trig;
	int i, k, ret;

	*retire_fence = -1;
	if (n > 4)
		return -EINVAL;

	/* the kernel does not wait src_fence_fd: wait here, then submit */
	for (k = 0; k < n; k++) {
		if (planes[k].acquire >= 0) {
			/* forge fence-probe: distinguish "producer was
			 * already done" from "we actually had to wait" */
			struct pollfd fp;
			int pr;

			fp.fd = planes[k].acquire;
			fp.events = POLLIN | POLLERR;
			pr = poll(&fp, 1, 0);
			if (pr > 0) {
				hwc->acq_presignaled++;
			} else {
				struct timespec a, b;
				unsigned int us;

				hwc->acq_waited++;
				clock_gettime(CLOCK_MONOTONIC, &a);
				engine_wait_fence(hwc, planes[k].acquire, 1200);
				clock_gettime(CLOCK_MONOTONIC, &b);
				us = (unsigned int)((b.tv_sec - a.tv_sec) * 1000000LL +
						    (b.tv_nsec - a.tv_nsec) / 1000);
				hwc->acq_wait_us_total += us;
				if (us > hwc->acq_wait_us_max)
					hwc->acq_wait_us_max = us;
			}
			close(planes[k].acquire);
		} else {
			hwc->acq_nofence++;
			/* rare (13 per session in the 2026-08-27 capture):
			 * say WHICH plane arrives fenceless - the geometry
			 * tells status bar / app / transition surface apart */
			kmsg_log("forge-nofence: #%u plane=%d/%d fmt=%d src=%ux%u dst+%u+%u",
				 hwc->acq_nofence, k, n, planes[k].fmt,
				 planes[k].sw, planes[k].sh,
				 planes[k].tx, planes[k].ty);
		}
		planes[k].acquire = -1;
		planes[k].release_fd = -1;
	}

	/* forge: A/B knob for the content-tear hypothesis.  If the acquire
	 * fences signal EARLY (before the GPU is really done), an extra
	 * fixed delay here gives the GPU time to catch up and the tear on
	 * the glass must disappear/move down - while with honest fences it
	 * only adds latency and changes nothing.  debug.forgehwc.acqdelay
	 * is in microseconds, default 0 (off). */
	{
		int d = prop_int("debug.forgehwc.acqdelay", 0);

		if (d > 0)
			usleep((useconds_t)d);
	}

	in = calloc(1, sizeof(*in));
	if (!in)
		return -ENOMEM;
	in->session_id = hwc->session;
	in->config_layer_num = 4;
	for (i = 0; i < 4; i++) {
		in->config[i].layer_id = (uint8_t)i;
		in->config[i].layer_enable = 0;
		in->config[i].src_fence_fd = -1;
		in->config[i].ext_sel_layer = -1;
	}

	for (k = 0; k < n; k++) {
		struct disp_input_config *c = &in->config[k];
		struct fhwc_plane *p = &planes[k];
		int ion_fd = -1;
		int stride_px = (int)hwc->width;

		int ge_ok = 0;

		if (hwc->ge_query) {
			if (hwc->ge_query(p->handle, GE_GET_ION_FD, &ion_fd) != 0)
				ion_fd = -1;
			ge_ok = (hwc->ge_query(p->handle, GE_GET_STRIDE,
					       &stride_px) == 0);
		}
		/*
		 * forge: say what pitch each plane is actually given.
		 *
		 * A staircase along horizontal edges is what a wrong line
		 * stride looks like, and the fallback here silently uses the
		 * panel width when the gralloc query fails — which is wrong
		 * for any buffer the allocator padded. Print it once per
		 * plane per second so the answer is data, not assumption.
		 */
		{
			static unsigned int fseq;

			if ((fseq++ % 60) == 0)
				kmsg_log("forge-pitch: plane%d ge=%d stride_px=%d fmt=%d w=%d h=%d",
					 k, ge_ok, stride_px, p->fmt,
					 p->sw, p->sh);
		}
		if (ion_fd < 0 && p->handle->numFds > 0)
			ion_fd = p->handle->data[0];
		if (ion_fd < 0) {
			FLOGE("plane %d: no ion fd (numFds=%d)", k, p->handle->numFds);
			continue;	/* leave the plane disabled */
		}

		memset(&buf, 0, sizeof(buf));
		buf.session_id = hwc->session;
		buf.layer_id = (unsigned int)k;
		buf.layer_en = 1;
		buf.ion_fd = ion_fd;
		buf.cache_sync = 0;
		buf.fence_fd = -1;
		buf.interface_fence_fd = -1;
		if (ioctl(hwc->disp_fd, DISP_IOCTL_PREPARE_INPUT_BUFFER, &buf) < 0) {
			hwc->prepare_fail++;
			FLOGE("PREPARE(l%d) failed: %s (ion=%d)", k,
			      strerror(errno), ion_fd);
			continue;
		}
		hwc->last_buff_idx = buf.index;
		p->release_fd = buf.fence_fd;

		c->layer_enable = 1;
		c->buffer_source = DISP_BUFFER_ION;
		c->security = DISP_NORMAL_BUFFER;
		c->src_fmt = (enum DISP_FORMAT)p->fmt;
		c->next_buff_idx = buf.index;
		c->src_pitch = (uint16_t)stride_px;
		c->src_offset_x = p->sx;
		c->src_offset_y = p->sy;
		c->src_width = p->sw;
		c->src_height = p->sh;
		c->tgt_offset_x = p->tx;
		c->tgt_offset_y = p->ty;
		c->tgt_width = p->sw;
		c->tgt_height = p->sh;
		c->frm_sequence = hwc->frames;
		fill_blending(c, p->blending);
	}

	memset(&pf, 0, sizeof(pf));
	pf.session_id = hwc->session;
	pf.present_fence_fd = -1;
	if (ioctl(hwc->disp_fd, DISP_IOCTL_GET_PRESENT_FENCE, &pf) < 0) {
		FLOGW("GET_PRESENT_FENCE failed: %s", strerror(errno));
		pf.present_fence_fd = -1;
		pf.present_fence_index = (unsigned int)-1;
	}
	hwc->last_pf_idx = pf.present_fence_index;

	ret = ioctl(hwc->disp_fd, DISP_IOCTL_SET_INPUT_BUFFER, in);
	free(in);
	if (ret < 0) {
		FLOGE("SET_INPUT_BUFFER failed: %s", strerror(errno));
		goto fail;
	}

	memset(&trig, 0, sizeof(trig));
	trig.type = DISP_SESSION_PRIMARY;
	trig.mode = DISP_SESSION_DIRECT_LINK_MODE;
	trig.session_id = hwc->session;
	trig.user = SESSION_USER_HWC;
	trig.present_fence_idx = pf.present_fence_index;
	trig.tigger_mode = TRIGGER_NORMAL;
	if (ioctl(hwc->disp_fd, DISP_IOCTL_TRIGGER_SESSION, &trig) < 0) {
		hwc->trigger_fail++;
		FLOGE("TRIGGER_SESSION failed: %s", strerror(errno));
		goto fail;
	}

	engine_crc_probe(hwc, planes, n);
	engine_shear_probe(hwc, planes, n);

	hwc->frames++;
	hwc->last_novl = (unsigned int)n;
	if (hwc->frames <= 8 || (hwc->frames % 600) == 0)
		FLOGI("frame #%u: planes=%d pf_idx=%u", hwc->frames, n,
		      pf.present_fence_index);
	if ((hwc->frames % 300) == 0)
		kmsg_log("forge-fence: presig=%u waited=%u nofence=%u wait_avg_us=%llu wait_max_us=%u",
			 hwc->acq_presignaled, hwc->acq_waited, hwc->acq_nofence,
			 hwc->acq_waited ?
			     hwc->acq_wait_us_total / hwc->acq_waited : 0,
			 hwc->acq_wait_us_max);

	*retire_fence = pf.present_fence_fd;
	return 0;

fail:
	if (pf.present_fence_fd >= 0)
		close(pf.present_fence_fd);
	for (k = 0; k < n; k++) {
		if (planes[k].release_fd >= 0) {
			close(planes[k].release_fd);
			planes[k].release_fd = -1;
		}
	}
	return -errno;
}

static void *vsync_thread_fn(void *arg)
{
	struct forge_hwc *hwc = arg;
	struct disp_session_vsync_config vs;
	struct timespec ts_now;
	int64_t ts, last_ts = 0;

	while (1) {
		pthread_mutex_lock(&hwc->lock);
		while (!hwc->vsync_on && !hwc->stop)
			pthread_cond_wait(&hwc->cond, &hwc->lock);
		pthread_mutex_unlock(&hwc->lock);
		if (hwc->stop)
			break;

		memset(&vs, 0, sizeof(vs));
		vs.session_id = hwc->session;
		if (ioctl(hwc->disp_fd, DISP_IOCTL_WAIT_FOR_VSYNC, &vs) < 0) {
			usleep(16666);
			continue;
		}
		ts = (int64_t)vs.vsync_ts;
		if (ts == 0) {
			/* DISP_SLEPT / lcm-disconnected path returns immediately */
			clock_gettime(CLOCK_MONOTONIC, &ts_now);
			ts = (int64_t)ts_now.tv_sec * 1000000000LL + ts_now.tv_nsec;
			usleep(16666);
		}
		if (ts == last_ts) {	/* did not advance: don't spin */
			usleep(16666);
			continue;
		}
		last_ts = ts;
		if (hwc->vsync_on && hwc->procs && hwc->procs->vsync)
			hwc->procs->vsync(hwc->procs, 0, ts);
	}
	return NULL;
}

/* ============================ HWC1 facade ============================ */

static struct forge_hwc *to_hwc(hwc_composer_device_1_t *dev)
{
	return (struct forge_hwc *)dev;
}

/*
 * Can this layer go to a hardware overlay as-is?  Conservative: the OVL has
 * no scaler and no rotator, so any doubt means GLES (always correct).
 * Returns the DISP_FORMAT, or 0 for "compose with GLES".
 */
static int layer_fits_overlay(struct forge_hwc *hwc, hwc_layer_1_t *l)
{
	int hal_fmt = 0, fmt;
	int sw, sh, dw, dh;

	if (l->flags & HWC_SKIP_LAYER)
		return 0;
	if (!l->handle)
		return 0;	/* dim layers / sideband / not yet latched */
	if (l->transform != 0)
		return 0;	/* no rotator */
	if (l->blending != HWC_BLENDING_NONE &&
	    l->blending != HWC_BLENDING_PREMULT &&
	    l->blending != HWC_BLENDING_COVERAGE)
		return 0;

	/* integer, unscaled, fully on-screen */
	sw = l->sourceCropi.right - l->sourceCropi.left;
	sh = l->sourceCropi.bottom - l->sourceCropi.top;
	dw = l->displayFrame.right - l->displayFrame.left;
	dh = l->displayFrame.bottom - l->displayFrame.top;
	if (sw <= 0 || sh <= 0 || sw != dw || sh != dh)
		return 0;	/* scaled (or empty) */
	if (l->sourceCropi.left < 0 || l->sourceCropi.top < 0)
		return 0;
	if (l->displayFrame.left < 0 || l->displayFrame.top < 0 ||
	    l->displayFrame.right > (int)hwc->width ||
	    l->displayFrame.bottom > (int)hwc->height)
		return 0;	/* would need clipping */

	if (!hwc->ge_query)
		return 0;
	if (hwc->ge_query(l->handle, GE_GET_FORMAT, &hal_fmt) != 0)
		return 0;
	fmt = map_hal_format(hal_fmt);
	return fmt;
}

/*
 * Promotion rule: overlays are taken only as a contiguous run from the TOP
 * of the z-ordered list, so the GLES-composed remainder (bottom of the
 * stack) is exactly what the single FBT plane at OVL 0 can represent.
 * If everything fits and there are at most 4 layers, no FBT is used at all.
 */
static int fhwc_prepare(hwc_composer_device_1_t *dev, size_t numDisplays,
			hwc_display_contents_1_t **displays)
{
	struct forge_hwc *hwc = to_hwc(dev);
	hwc_display_contents_1_t *d;
	int i, nlayers, top_run, budget, first_ovl;
	int overlays_on = prop_int("debug.forgehwc.overlays", 1);

	if (!numDisplays || !displays || !displays[0])
		return 0;
	d = displays[0];

	/* indexes of real layers (the FBT is not a candidate) */
	nlayers = 0;
	for (i = 0; i < (int)d->numHwLayers; i++)
		if (d->hwLayers[i].compositionType != HWC_FRAMEBUFFER_TARGET)
			nlayers++;

	/* how many contiguous layers from the top fit an overlay */
	top_run = 0;
	if (overlays_on) {
		for (i = (int)d->numHwLayers - 1; i >= 0; i--) {
			hwc_layer_1_t *l = &d->hwLayers[i];

			if (l->compositionType == HWC_FRAMEBUFFER_TARGET)
				continue;
			if (!layer_fits_overlay(hwc, l))
				break;
			top_run++;
		}
	}

	if (top_run == nlayers && nlayers > 0 && nlayers <= 4)
		budget = nlayers;	/* everything on OVL, no FBT */
	else
		budget = top_run < 3 ? top_run : 3;	/* OVL 0 = FBT */

	/*
	 * forge: cap the number of planes fetched concurrently.
	 *
	 * Each overlay plane has its own fetch FIFO, and with three
	 * full-screen planes live all three underflow: OVL0_INTSTA came back
	 * 0xe03 under a fast animation, bits 9/10/11 being the per-layer
	 * RDMA FIFO underflow of layers 0, 1 and 2. On a single plane the
	 * same register reads 0x3. The picture breaks up toward the bottom
	 * of the frame, where the accumulated fetch deficit shows.
	 *
	 * Demoting a layer does not save the bytes it read — the GLES
	 * remainder arrives as a full-screen FBT plane instead — so what is
	 * being bought here is fewer concurrent fetch streams, not less
	 * traffic. debug.forgehwc.maxplanes exists to find the point where
	 * the underflow bits stop appearing without a rebuild.
	 */
	{
		int maxp = prop_int("debug.forgehwc.maxplanes", 4);

		if (maxp < 0)
			maxp = 0;
		if (budget > maxp)
			budget = maxp;
	}

	/* first (lowest-z) real layer that gets an overlay */
	first_ovl = nlayers - budget;

	nlayers = 0;
	for (i = 0; i < (int)d->numHwLayers; i++) {
		hwc_layer_1_t *l = &d->hwLayers[i];

		if (l->compositionType == HWC_FRAMEBUFFER_TARGET)
			continue;
		if (nlayers >= first_ovl && budget > 0)
			l->compositionType = HWC_OVERLAY;
		else
			l->compositionType = HWC_FRAMEBUFFER;
		nlayers++;
	}
	return 0;
}

static int fhwc_set(hwc_composer_device_1_t *dev, size_t numDisplays,
		    hwc_display_contents_1_t **displays)
{
	struct forge_hwc *hwc = to_hwc(dev);
	hwc_display_contents_1_t *d;
	hwc_layer_1_t *fbt = NULL;
	hwc_layer_1_t *src[4];
	struct fhwc_plane planes[4];
	size_t i;
	int n = 0, gles_used = 0, ret_f = -1;

	if (!numDisplays || !displays || !displays[0])
		return 0;
	d = displays[0];
	d->retireFenceFd = -1;

	for (i = 0; i < d->numHwLayers; i++) {
		hwc_layer_1_t *l = &d->hwLayers[i];

		if (l->compositionType == HWC_FRAMEBUFFER_TARGET)
			fbt = l;
		else if (l->compositionType == HWC_FRAMEBUFFER)
			gles_used = 1;
	}

	memset(planes, 0, sizeof(planes));

	/* OVL 0 = the GLES result, when anything was left to GLES */
	if (gles_used) {
		if (!fbt || !fbt->handle) {
			/* nothing usable this frame */
			if (fbt && fbt->acquireFenceFd >= 0) {
				close(fbt->acquireFenceFd);
				fbt->acquireFenceFd = -1;
			}
			return 0;
		}
		src[n] = fbt;
		planes[n].handle = fbt->handle;
		planes[n].acquire = fbt->acquireFenceFd;
		planes[n].fmt = hwc->fmt_override ?
		    hwc->fmt_override : DISP_FORMAT_RGBA8888;
		planes[n].blending = 0;	/* opaque */
		planes[n].sw = (uint16_t)hwc->width;
		planes[n].sh = (uint16_t)hwc->height;
		n++;
	}

	/* promoted layers, in z order (list order is bottom -> top) */
	for (i = 0; i < d->numHwLayers && n < 4; i++) {
		hwc_layer_1_t *l = &d->hwLayers[i];
		int fmt;

		if (l->compositionType != HWC_OVERLAY)
			continue;
		fmt = layer_fits_overlay(hwc, l);
		if (!fmt) {
			/* changed between prepare and set: should not happen */
			FLOGW("overlay layer no longer eligible, dropping frame plane");
			if (l->acquireFenceFd >= 0) {
				close(l->acquireFenceFd);
				l->acquireFenceFd = -1;
			}
			continue;
		}
		src[n] = l;
		planes[n].handle = l->handle;
		planes[n].acquire = l->acquireFenceFd;
		planes[n].fmt = fmt;
		planes[n].blending = l->blending;
		planes[n].sx = (uint16_t)l->sourceCropi.left;
		planes[n].sy = (uint16_t)l->sourceCropi.top;
		planes[n].sw = (uint16_t)(l->sourceCropi.right - l->sourceCropi.left);
		planes[n].sh = (uint16_t)(l->sourceCropi.bottom - l->sourceCropi.top);
		planes[n].tx = (uint16_t)l->displayFrame.left;
		planes[n].ty = (uint16_t)l->displayFrame.top;
		n++;
	}

	/* FBT unused this frame: its acquire fence is still ours to close */
	if (!gles_used && fbt && fbt->acquireFenceFd >= 0) {
		close(fbt->acquireFenceFd);
		fbt->acquireFenceFd = -1;
	}

	if (n == 0)
		return 0;

	engine_submit(hwc, planes, n, &ret_f);

	for (i = 0; i < (size_t)n; i++) {
		src[i]->acquireFenceFd = -1;	/* consumed by engine_submit */
		src[i]->releaseFenceFd = planes[i].release_fd;
	}
	d->retireFenceFd = ret_f;

	hwc->last_fbt_used = gles_used;
	if (n > (gles_used ? 1 : 0)) {
		hwc->ovl_frames++;
		hwc->promoted_total += (unsigned int)(n - (gles_used ? 1 : 0));
	} else {
		hwc->gles_frames++;
	}
	return 0;
}

static int fhwc_event_control(hwc_composer_device_1_t *dev, int disp,
			      int event, int enabled)
{
	struct forge_hwc *hwc = to_hwc(dev);

	if (disp != 0 || event != HWC_EVENT_VSYNC)
		return -EINVAL;
	pthread_mutex_lock(&hwc->lock);
	hwc->vsync_on = !!enabled;
	pthread_cond_signal(&hwc->cond);
	pthread_mutex_unlock(&hwc->lock);
	return 0;
}

static int fhwc_blank(hwc_composer_device_1_t *dev, int disp, int blank)
{
	struct forge_hwc *hwc = to_hwc(dev);
	int arg = blank ? FB_BLANK_POWERDOWN : FB_BLANK_UNBLANK;

	if (disp != 0)
		return -EINVAL;
	if (hwc->fb_fd < 0)
		return -ENODEV;
	FLOGI("blank(%d)", blank);
	if (ioctl(hwc->fb_fd, FBIOBLANK, arg) < 0) {
		FLOGE("FBIOBLANK(%d) failed: %s", arg, strerror(errno));
		return -errno;
	}
	return 0;
}

static int fhwc_query(hwc_composer_device_1_t *dev, int what, int *value)
{
	struct forge_hwc *hwc = to_hwc(dev);

	switch (what) {
	case HWC_BACKGROUND_LAYER_SUPPORTED:
		*value = 0;
		return 0;
	case HWC_DISPLAY_TYPES_SUPPORTED:
		*value = HWC_DISPLAY_PRIMARY_BIT;
		return 0;
	case HWC_VSYNC_PERIOD:
		*value = (int)hwc->vsync_period_ns;
		return 0;
	default:
		return -EINVAL;
	}
}

static void fhwc_register_procs(hwc_composer_device_1_t *dev,
				const hwc_procs_t *procs)
{
	to_hwc(dev)->procs = procs;
}

static void fhwc_dump(hwc_composer_device_1_t *dev, char *buff, int buff_len)
{
	struct forge_hwc *hwc = to_hwc(dev);

	snprintf(buff, buff_len,
		 "forge-hwc: session=0x%x %ux%u period=%uns frames=%u prepare_fail=%u "
		 "trigger_fail=%u acq_timeout=%u last_idx=%u last_pf=%u "
		 "vsync_on=%d ge=%s "
		 "ovl_frames=%u gles_frames=%u promoted=%u last: planes=%u fbt=%d "
		 "acq: presig=%u waited=%u nofence=%u wait_avg_us=%llu wait_max_us=%u "
		 "crc: runs=%u dirty=%u shear: frames=%u motion=%u zoned=%u hard=%u\n",
		 hwc->session, hwc->width, hwc->height, hwc->vsync_period_ns, hwc->frames,
		 hwc->prepare_fail, hwc->trigger_fail, hwc->acquire_timeouts,
		 hwc->last_buff_idx, hwc->last_pf_idx, hwc->vsync_on,
		 hwc->ge_query ? "yes" : "no",
		 hwc->ovl_frames, hwc->gles_frames, hwc->promoted_total,
		 hwc->last_novl, hwc->last_fbt_used,
		 hwc->acq_presignaled, hwc->acq_waited, hwc->acq_nofence,
		 hwc->acq_waited ? hwc->acq_wait_us_total / hwc->acq_waited : 0,
		 hwc->acq_wait_us_max, hwc->crc_runs, hwc->crc_dirty_runs,
		 hwc->shear_frames, hwc->shear_motion, hwc->shear_zoned,
		 hwc->shear_hard);
}

static int fhwc_get_display_configs(hwc_composer_device_1_t *dev, int disp,
				    uint32_t *configs, size_t *numConfigs)
{
	(void)dev;
	if (disp != 0)
		return -EINVAL;
	if (*numConfigs > 0) {
		configs[0] = 0;
		*numConfigs = 1;
	}
	return 0;
}

static int fhwc_get_display_attributes(hwc_composer_device_1_t *dev, int disp,
				       uint32_t config, const uint32_t *attributes,
				       int32_t *values)
{
	struct forge_hwc *hwc = to_hwc(dev);
	int i;

	if (disp != 0 || config != 0)
		return -EINVAL;
	for (i = 0; attributes[i] != HWC_DISPLAY_NO_ATTRIBUTE; i++) {
		switch (attributes[i]) {
		case HWC_DISPLAY_VSYNC_PERIOD:
			values[i] = (int32_t)hwc->vsync_period_ns;
			break;
		case HWC_DISPLAY_WIDTH:
			values[i] = (int32_t)hwc->width;
			break;
		case HWC_DISPLAY_HEIGHT:
			values[i] = (int32_t)hwc->height;
			break;
		case HWC_DISPLAY_DPI_X:
			values[i] = (int32_t)hwc->xdpi_1000;
			break;
		case HWC_DISPLAY_DPI_Y:
			values[i] = (int32_t)hwc->ydpi_1000;
			break;
		default:
			values[i] = 0;
			break;
		}
	}
	return 0;
}

static int fhwc_close(hw_device_t *dev)
{
	struct forge_hwc *hwc = (struct forge_hwc *)dev;
	struct disp_session_config cfg;

	pthread_mutex_lock(&hwc->lock);
	hwc->stop = 1;
	pthread_cond_signal(&hwc->cond);
	pthread_mutex_unlock(&hwc->lock);
	pthread_join(hwc->vsync_thread, NULL);

	if (hwc->session_ok) {
		memset(&cfg, 0, sizeof(cfg));
		cfg.type = DISP_SESSION_PRIMARY;
		cfg.session_id = hwc->session;
		ioctl(hwc->disp_fd, DISP_IOCTL_DESTROY_SESSION, &cfg);
	}
	if (hwc->fb_fd >= 0)
		close(hwc->fb_fd);
	if (hwc->disp_fd >= 0)
		close(hwc->disp_fd);
	if (hwc->ge_lib)
		dlclose(hwc->ge_lib);
	free(hwc);
	return 0;
}

static int fhwc_open(const struct hw_module_t *module, const char *name,
		     struct hw_device_t **device)
{
	struct forge_hwc *hwc;
	int err;

	if (strcmp(name, HWC_HARDWARE_COMPOSER))
		return -EINVAL;

	hwc = calloc(1, sizeof(*hwc));
	if (!hwc)
		return -ENOMEM;

	hwc->disp_fd = open(DISP_DEV_PATH, O_RDWR);
	if (hwc->disp_fd < 0) {
		err = -errno;
		FLOGE("cannot open %s: %s", DISP_DEV_PATH, strerror(errno));
		free(hwc);
		return err;
	}
	hwc->fb_fd = open(FB_DEV_PATH, O_RDWR);
	if (hwc->fb_fd < 0)
		FLOGW("cannot open %s: %s (blank() disabled)", FB_DEV_PATH,
		      strerror(errno));

	err = engine_open_session(hwc);
	if (err) {
		/* leave the system on the fbdev fallback rather than limp */
		if (hwc->fb_fd >= 0)
			close(hwc->fb_fd);
		close(hwc->disp_fd);
		free(hwc);
		return err;
	}

	hwc->ge_lib = dlopen("libgralloc_extra.so", RTLD_LAZY | RTLD_LOCAL);
	if (hwc->ge_lib)
		hwc->ge_query = (int (*)(buffer_handle_t, int, void *))
		    dlsym(hwc->ge_lib, "gralloc_extra_query");
	FLOGI("gralloc_extra: %s", hwc->ge_query ? "loaded" : "unavailable, using fallback");

	hwc->fmt_override = prop_int("debug.forgehwc.fmt", 0);

	pthread_mutex_init(&hwc->lock, NULL);
	pthread_cond_init(&hwc->cond, NULL);
	err = pthread_create(&hwc->vsync_thread, NULL, vsync_thread_fn, hwc);
	if (err) {
		FLOGE("vsync thread: %s", strerror(err));
		close(hwc->disp_fd);
		if (hwc->fb_fd >= 0)
			close(hwc->fb_fd);
		free(hwc);
		return -err;
	}

	hwc->base.common.tag = HARDWARE_DEVICE_TAG;
	hwc->base.common.version = HWC_DEVICE_API_VERSION_1_1;
	hwc->base.common.module = (struct hw_module_t *)module;
	hwc->base.common.close = fhwc_close;
	hwc->base.prepare = fhwc_prepare;
	hwc->base.set = fhwc_set;
	hwc->base.eventControl = fhwc_event_control;
	hwc->base.blank = fhwc_blank;
	hwc->base.query = fhwc_query;
	hwc->base.registerProcs = fhwc_register_procs;
	hwc->base.dump = fhwc_dump;
	hwc->base.getDisplayConfigs = fhwc_get_display_configs;
	hwc->base.getDisplayAttributes = fhwc_get_display_attributes;

	*device = &hwc->base.common;
	FLOGI("forge-hwc up (HWC1.1, native 4.9 disp ABI)");
	return 0;
}

static struct hw_module_methods_t fhwc_module_methods = {
	.open = fhwc_open,
};

hwc_module_t HAL_MODULE_INFO_SYM = {
	.common = {
		.tag = HARDWARE_MODULE_TAG,
		.module_api_version = HWC_MODULE_API_VERSION_0_1,
		.hal_api_version = HARDWARE_HAL_API_VERSION,
		.id = HWC_HARDWARE_MODULE_ID,
		.name = "forge hwcomposer for m5c (mt6737m, 4.9 kernel)",
		.author = "forge",
		.methods = &fhwc_module_methods,
	},
};
