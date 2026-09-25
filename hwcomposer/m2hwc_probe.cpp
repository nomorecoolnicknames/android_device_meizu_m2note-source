/* Standalone safe probe: dlopen the m2note HWC module and drive open()/init
 * queries WITHOUT touching the live composer service. Used to debug why the
 * module fails to load under composer@2.1 without risking a boot loop. */
#define LOG_TAG "m2hwc_probe"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <setjmp.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <linux/fb.h>
#include <hardware/hardware.h>
#include <hardware/hwcomposer.h>
#include <hardware/gralloc.h>

#ifndef FBIO_WAITFORVSYNC
#define FBIO_WAITFORVSYNC _IOW('F', 0x20, uint32_t)
#endif

static sigjmp_buf g_jb;
static volatile const char* g_stage = "";
static void on_alarm(int) {
    /* fb ioctl blocked: report and jump back instead of hanging forever */
    siglongjmp(g_jb, 1);
}

/* Directly exercise the present-path ioctls my hwc_set() uses, each guarded by
 * a 3 s alarm so a blocking MTK fbdev call is reported as HUNG, not a hang. */
static void test_fb_present() {
    printf("\n--- fb present-path test ---\n"); fflush(stdout);
    int fd = open("/dev/graphics/fb0", O_RDWR);
    if (fd < 0) fd = open("/dev/fb0", O_RDWR);
    printf("open fb0 = %d\n", fd); fflush(stdout);
    if (fd < 0) return;

    struct fb_var_screeninfo var; struct fb_fix_screeninfo fix;
    if (ioctl(fd, FBIOGET_VSCREENINFO, &var) || ioctl(fd, FBIOGET_FSCREENINFO, &fix)) {
        printf("FBIOGET_*SCREENINFO failed\n"); close(fd); return;
    }
    printf("var: %ux%u virt %ux%u bpp %u line_length %u\n",
           var.xres, var.yres, var.xres_virtual, var.yres_virtual,
           var.bits_per_pixel, fix.line_length);

    size_t total = (size_t)fix.line_length * var.yres_virtual;
    uint8_t* mem = (uint8_t*)mmap(0, total, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    printf("mmap(%zu) = %p\n", total, mem); fflush(stdout);
    if (mem == MAP_FAILED) { close(fd); return; }
    /* paint page 0 so a real pan would show something */
    memset(mem, 0x40, (size_t)fix.line_length * var.yres);

    signal(SIGALRM, on_alarm);

    /* THROUGHPUT: time 60 pans each way. If VBL blocks ~16 ms it's a healthy
     * 60 Hz vblank; if it blocks ~100-200 ms the panel vsync is slow and that
     * is exactly why my set() throttles SF to ~5 fps. FBIOPAN_DISPLAY also
     * needs a real FB_VSYNC wait via FBIO_WAITFORVSYNC on MTK sometimes. */
    {
        struct timespec a, b;
        const int N = 60;
        /* VBL */
        clock_gettime(CLOCK_MONOTONIC, &a);
        for (int k = 0; k < N; k++) {
            var.yoffset = (k & 1) ? var.yres : 0; var.activate = FB_ACTIVATE_VBL;
            ioctl(fd, FBIOPAN_DISPLAY, &var);
        }
        clock_gettime(CLOCK_MONOTONIC, &b);
        double ms = ((b.tv_sec-a.tv_sec)*1e3 + (b.tv_nsec-a.tv_nsec)/1e6)/N;
        printf("FBIOPAN(VBL)  avg %.2f ms/pan  => %.1f fps ceiling\n", ms, 1000.0/ms);
        fflush(stdout);
        /* NOW */
        clock_gettime(CLOCK_MONOTONIC, &a);
        for (int k = 0; k < N; k++) {
            var.yoffset = (k & 1) ? var.yres : 0; var.activate = FB_ACTIVATE_NOW;
            ioctl(fd, FBIOPAN_DISPLAY, &var);
        }
        clock_gettime(CLOCK_MONOTONIC, &b);
        ms = ((b.tv_sec-a.tv_sec)*1e3 + (b.tv_nsec-a.tv_nsec)/1e6)/N;
        printf("FBIOPAN(NOW)  avg %.2f ms/pan  => %.1f fps ceiling\n", ms, 1000.0/ms);
        fflush(stdout);
        /* explicit vsync wait cost, if the driver supports FBIO_WAITFORVSYNC */
        clock_gettime(CLOCK_MONOTONIC, &a);
        int okv = 0;
        for (int k = 0; k < N; k++) {
            uint32_t z = 0;
            if (ioctl(fd, FBIO_WAITFORVSYNC, &z) == 0) okv++;
        }
        clock_gettime(CLOCK_MONOTONIC, &b);
        ms = ((b.tv_sec-a.tv_sec)*1e3 + (b.tv_nsec-a.tv_nsec)/1e6)/N;
        printf("FBIO_WAITFORVSYNC ok=%d/%d avg %.2f ms => %.1f Hz panel vsync\n",
               okv, N, ms, 1000.0/ms);
        fflush(stdout);
    }

    munmap(mem, total);
    close(fd);
}

int main(int argc, char** argv) {
    const char* path = (argc > 1) ? argv[1]
                       : "/system/vendor/lib64/hw/hwcomposer.m2note.so";
    printf("probe: dlopen %s\n", path);
    void* h = dlopen(path, RTLD_NOW);
    printf("dlopen=%p err=%s\n", h, dlerror());
    if (!h) return 1;

    hw_module_t* m = (hw_module_t*)dlsym(h, "HMI");
    printf("HMI=%p err=%s\n", m, dlerror());
    if (!m) return 2;
    printf("  tag=%08x api=%x id=%s name=%s methods=%p\n",
           m->tag, m->module_api_version, m->id ? m->id : "?",
           m->name ? m->name : "?", m->methods);
    if (!m->methods || !m->methods->open) { printf("no open\n"); return 3; }

    printf("probe: calling open(\"composer\")...\n"); fflush(stdout);
    hw_device_t* dev = 0;
    int rc = m->methods->open(m, HWC_HARDWARE_COMPOSER, &dev);
    printf("open rc=%d dev=%p\n", rc, dev); fflush(stdout);
    if (rc || !dev) return 4;

    hwc_composer_device_1_t* hwc = (hwc_composer_device_1_t*)dev;
    printf("  version=%x prepare=%p set=%p\n",
           hwc->common.version, hwc->prepare, hwc->set);

    uint32_t cfgs[8]; size_t n = 8;
    int r2 = hwc->getDisplayConfigs(hwc, 0, cfgs, &n);
    printf("getDisplayConfigs rc=%d n=%zu cfg0=%u\n", r2, n, n ? cfgs[0] : 0u);
    fflush(stdout);

    uint32_t attrs[] = { HWC_DISPLAY_WIDTH, HWC_DISPLAY_HEIGHT,
                         HWC_DISPLAY_VSYNC_PERIOD, HWC_DISPLAY_DPI_X,
                         HWC_DISPLAY_NO_ATTRIBUTE };
    int32_t vals[5] = {0};
    int r3 = hwc->getDisplayAttributes(hwc, 0, 0, attrs, vals);
    printf("getDisplayAttributes rc=%d w=%d h=%d vsync=%d dpi=%d\n",
           r3, vals[0], vals[1], vals[2], vals[3]);
    fflush(stdout);

    printf("PROBE OK (open + init queries succeeded)\n");

    test_fb_present();

    /* exercise the real per-frame path: alloc a FB_TARGET, prepare(), set() */
    printf("\n--- hwc_set() test with a real FB_TARGET buffer ---\n"); fflush(stdout);
    const gralloc_module_t* gr = 0;
    if (hw_get_module(GRALLOC_HARDWARE_MODULE_ID, (const hw_module_t**)&gr) || !gr) {
        printf("no gralloc module\n"); return 0;
    }
    alloc_device_t* alloc = 0;
    if (gralloc_open((const hw_module_t*)gr, &alloc) || !alloc) {
        printf("gralloc_open failed\n"); return 0;
    }
    /* IMPORTANT: no GRALLOC_USAGE_HW_FB. On MTK the framebuffer is a singleton
     * owned by the composer; allocating HW_FB from a normal process faults in
     * gralloc. SurfaceFlinger's real FB_TARGET that my hwc_set() locks is a
     * normal HW_COMPOSER/SW buffer, so this matches the live path. */
    buffer_handle_t buf = 0; int bstride = 0;
    int ra = alloc->alloc(alloc, 1080, 1920, HAL_PIXEL_FORMAT_RGBA_8888,
                GRALLOC_USAGE_HW_COMPOSER |
                GRALLOC_USAGE_SW_READ_OFTEN | GRALLOC_USAGE_SW_WRITE_OFTEN,
                &buf, &bstride);
    printf("gralloc alloc rc=%d buf=%p stride=%d (fb line_length needs >=1088)\n",
           ra, buf, bstride); fflush(stdout);
    if (ra || !buf) return 0;

    /* fill with a visible test pattern so a successful present shows something,
     * and so my hwc_set's per-row 4352-byte memcpy reads initialised memory. */
    {
        void* vp = 0;
        if (gr->lock(gr, buf, GRALLOC_USAGE_SW_WRITE_OFTEN,
                     0, 0, 1080, 1920, &vp) == 0 && vp) {
            memset(vp, 0x80, (size_t)bstride * 4 * 1920);
            gr->unlock(gr, buf);
        }
    }

    size_t sz = sizeof(hwc_display_contents_1_t) + sizeof(hwc_layer_1_t);
    hwc_display_contents_1_t* c = (hwc_display_contents_1_t*)calloc(1, sz);
    c->retireFenceFd = -1; c->numHwLayers = 1;
    hwc_layer_1_t* L = &c->hwLayers[0];
    L->compositionType = HWC_FRAMEBUFFER_TARGET;
    L->handle = buf; L->acquireFenceFd = -1; L->releaseFenceFd = -1;
    hwc_display_contents_1_t* disp[1] = { c };

    int rp = hwc->prepare(hwc, 1, disp);
    printf("prepare rc=%d\n", rp); fflush(stdout);

    signal(SIGALRM, on_alarm);
    if (sigsetjmp(g_jb, 1) == 0) {
        alarm(4);
        int rs = hwc->set(hwc, 1, disp);
        alarm(0);
        printf("set rc=%d  -> OK (present completed)\n", rs);
    } else {
        printf("set() HUNG >4s  <<<< blocker is inside hwc_set (gralloc lock / pan)\n");
    }
    fflush(stdout);

    free(c);
    alloc->free(alloc, buf);
    gralloc_close(alloc);
    printf("hwc_set test done\n");
    return 0;
}
