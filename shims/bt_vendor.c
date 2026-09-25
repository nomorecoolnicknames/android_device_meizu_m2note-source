/* libbt-vendor.so (64-bit) — the BT vendor interface Pie's HIDL HAL dlopen()s.
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * FACT (logcat, booted device, 2026-08-09 09:01:14.824, pid 364):
 *     E android.hardware.bluetooth@1.0-impl: Open unable to open
 *       libbt-vendor.so (dlopen failed: library "libbt-vendor.so" not found)
 * followed 0.4 ms later, in com.android.bluetooth, by
 *     F [0809/090114.824394:FATAL:hci_layer_android.cc(78)]
 *       Check failed: status == Status::SUCCESS.
 * That CHECK is the whole 1711-crash-per-boot loop: the HAL reports
 * INITIALIZATION_ERROR, the stack CHECK-fails in hci_thread, init restarts
 * com.android.bluetooth, repeat once a second forever.
 *
 * FACT (/proc/364/exe + /proc/364/maps on the booted device): the HIDL service
 * /system/vendor/bin/hw/android.hardware.bluetooth@1.0-service is ELF64 and
 * loads /system/vendor/lib64/hw/android.hardware.bluetooth@1.0-impl.so.
 * FACT (find on device; sha256 in stock/ and proprietary/): libbt-vendor.so
 * exists ONLY as /system/vendor/lib/libbt-vendor.so, ELF32 ARM
 * (sha256 1a02898dfdc99b62b5e3c86e6ecd9656bf184ed6cd7781383cf5daf209c5e904).
 * Flyme 8.0.5.0A never shipped a 64-bit one, because Nougat's MTK stack loaded
 * the vendor lib in-process from 32-bit bluetooth.default.so. Pie moved it into
 * a 64-bit HIDL service, so the blob can no longer be reached at all.
 *
 * FACT (readelf --dyn-syms): the 64-bit libbluetooth_mtk.so that Meizu DID ship
 * (system/vendor/lib64/libbluetooth_mtk.so, sha256
 * 7a99341a6bd843ccdcf40176fa160d30fdffe5d545da05c96f6aa48cb5550a33) exports the
 * exact same symbol set as the 32-bit one, including all ten symbols the 32-bit
 * libbt-vendor.so imports from it. Only the thin forwarding shim is missing —
 * so we rebuild the shim, 64-bit, instead of downgrading the HAL to 32-bit.
 *
 * THE SHIM IS NOT GUESSED, IT IS DECODED
 * --------------------------------------
 * Everything below reproduces the stock 32-bit libbt-vendor.so, read out of the
 * blob with capstone (CS_MODE_THUMB) and readelf, not from an MTK header:
 *
 *   BLUETOOTH_VENDOR_LIB_INTERFACE @0x3e0c, 16 bytes = {size, init, op,
 *   cleanup}; R_ARM_ABS32 relocs at +4/+8/+12 name mtk_bt_init (0xa55),
 *   mtk_bt_op (0xa89), mtk_bt_cleanup (0xc75).
 *
 *   mtk_bt_init(p_cb, bdaddr): logs, set_callbacks(p_cb), return 0.
 *                              local_bdaddr is IGNORED (r1 never read).
 *   mtk_bt_cleanup():          clean_resource(); tail-call clean_callbacks().
 *   mtk_bt_op(): `cmp r0,#0xd / bhi default / tbb [pc,r0]`, table at 0xa98 =
 *                07 0f 1d 2b 39 46 54 5d 68 76 68 68 84 95, i.e.
 *      0  POWER_CTRL            log *(int*)param, return 0   (no chip call)
 *      1  FW_CFG                return mtk_fw_cfg()
 *      2  SCO_CFG               return mtk_sco_cfg()
 *      3  USERIAL_OPEN          *(int*)param = init_uart(); return 1
 *      4  USERIAL_CLOSE         close_uart(); return 0
 *      5  GET_LPM_IDLE_TIMEOUT  *(uint32_t*)param = 5000 (0x1388); return 0
 *      6  LPM_SET_MODE          log *(uint8_t*)param, return 0
 *      7  LPM_WAKE_SET_STATE    log, return 0
 *      8  SET_AUDIO_STATE       falls into the default arm  -> return -1
 *      9  EPILOG                return mtk_prepare_off()
 *      10 A2DP_OFFLOAD_START    default arm                 -> return -1
 *      11 A2DP_OFFLOAD_STOP     default arm                 -> return -1
 *      12 (MTK) SET_FW_ASSERT   return mtk_set_fw_assert(*(uint32_t*)param)
 *      13 (MTK) SET_PSM_CONTRL  return mtk_set_psm_control(*(uint8_t*)param)
 *      default                  log "Unknown operation %d"; return -1
 *
 * Opcodes 0..11 line up one-for-one with bt_vendor_opcode_t in
 * hardware/interfaces/bluetooth/1.0/default/bt_vendor_lib.h, which is what makes
 * the table readable at all; 12 and 13 are MTK additions with no AOSP caller.
 *
 * CALLBACK-STRUCT ABI IS PROVEN, NOT ASSUMED
 * ------------------------------------------
 * set_callbacks() stores the pointer verbatim (0x1860: `str x0,[x8]; ret`), so
 * the 64-bit libbluetooth_mtk.so dereferences the caller's struct directly and
 * the layouts must agree. They do: mtk_prepare_off (0x2bbc) reaches the epilog
 * callback as `ldr x8,[x8,#64]`, and offset 64 is exactly epilog_cb in the
 * 64-bit bt_vendor_callbacks_t {size, fwcfg, scocfg, lpm, audio, alloc, dealloc,
 * xmit, epilog} = {0,8,16,24,32,40,48,56,64}. Pie only APPENDS a2dp_offload_cb
 * after epilog_cb, and the struct is size-prefixed, so P's struct is a superset
 * the N-era blob reads safely.
 *
 * WHY dlopen INSTEAD OF LINKING
 * -----------------------------
 * libbluetooth_mtk.so is installed by PRODUCT_COPY_FILES (m95-vendor.mk:735),
 * not as a build module, so there is nothing to put in LOCAL_SHARED_LIBRARIES.
 * Turning it into a prebuilt module would collide with that copy rule. Runtime
 * resolution costs one dlopen on the BT enable path and keeps the blob install
 * machinery untouched. FACT (/system/etc/ld.config.txt on the device): this is
 * a non-treble image, dir.legacy covers /vendor, and the default namespace is
 * non-isolated with search paths /system/${LIB}:/vendor/${LIB}:/odm/${LIB} —
 * so a bare soname resolves from /system/vendor/lib64.
 */
#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>

#include <android/log.h>

#define LOG_TAG "bt-vendor-m95"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* bt_vendor_lib.h subset. Only the interface struct matters here: the callback
 * struct is forwarded as an opaque pointer, exactly as the stock shim does. */
typedef struct {
    size_t size;
    int (*init)(const void *p_cb, unsigned char *local_bdaddr);
    int (*op)(int opcode, void *param);
    void (*cleanup)(void);
} bt_vendor_interface_t;

/* bt_vendor_opcode_t, hardware/interfaces/bluetooth/1.0/default/bt_vendor_lib.h.
 * 12/13 are MTK-private and are not in that header. */
enum {
    BT_VND_OP_POWER_CTRL = 0,
    BT_VND_OP_FW_CFG = 1,
    BT_VND_OP_SCO_CFG = 2,
    BT_VND_OP_USERIAL_OPEN = 3,
    BT_VND_OP_USERIAL_CLOSE = 4,
    BT_VND_OP_GET_LPM_IDLE_TIMEOUT = 5,
    BT_VND_OP_LPM_SET_MODE = 6,
    BT_VND_OP_LPM_WAKE_SET_STATE = 7,
    BT_VND_OP_SET_AUDIO_STATE = 8,
    BT_VND_OP_EPILOG = 9,
    BT_VND_OP_A2DP_OFFLOAD_START = 10,
    BT_VND_OP_A2DP_OFFLOAD_STOP = 11,
    BT_VND_OP_MTK_SET_FW_ASSERT = 12,
    BT_VND_OP_MTK_SET_PSM_CONTRL = 13,
};

/* Idle timeout the stock shim hands back for BT_VND_OP_GET_LPM_IDLE_TIMEOUT
 * (movw r0,#0x1388 at 0xb36). */
#define MTK_LPM_IDLE_TIMEOUT_MS 5000

#define MTK_BT_LIBRARY "libbluetooth_mtk.so"

/* Signatures recovered from the 64-bit libbluetooth_mtk.so with
 * aarch64-linux-gnu-objdump; argument widths match how the stock 32-bit shim
 * loads them out of `param` (ldr vs ldrb). */
static void *g_mtk_handle;
static void (*p_set_callbacks)(const void *p_cb);   /* 0x1860 str x0,[x8]; ret */
static void (*p_clean_callbacks)(void);             /* 0x1870 str xzr,[x8]     */
static int (*p_init_uart)(void);                    /* 0x1880 open("/dev/stpbt")*/
static void (*p_close_uart)(void);                  /* 0x191c close(fd)        */
static int (*p_mtk_fw_cfg)(void);                   /* 0x194c                  */
static int (*p_mtk_sco_cfg)(void);                  /* 0x2ba0 BT_InitSCO       */
static int (*p_mtk_prepare_off)(void);              /* 0x2bbc epilog_cb        */
static int (*p_mtk_set_fw_assert)(uint32_t reason); /* 0x2bec                  */
static int (*p_mtk_set_psm_control)(int on);        /* 0x2c94 w0 & 1 -> ioctl  */
static void (*p_clean_resource)(void);              /* 0x2d44 b BT_Cleanup     */

struct mtk_sym {
    const char *name;
    void **slot;
};

static const struct mtk_sym kMtkSyms[] = {
    {"set_callbacks", (void **)&p_set_callbacks},
    {"clean_callbacks", (void **)&p_clean_callbacks},
    {"init_uart", (void **)&p_init_uart},
    {"close_uart", (void **)&p_close_uart},
    {"mtk_fw_cfg", (void **)&p_mtk_fw_cfg},
    {"mtk_sco_cfg", (void **)&p_mtk_sco_cfg},
    {"mtk_prepare_off", (void **)&p_mtk_prepare_off},
    {"mtk_set_fw_assert", (void **)&p_mtk_set_fw_assert},
    {"mtk_set_psm_control", (void **)&p_mtk_set_psm_control},
    {"clean_resource", (void **)&p_clean_resource},
};

/* Resolve every symbol or none. A partially-bound shim would fail later, deep
 * inside an op(), where the log says nothing useful. */
static int mtk_bind(void) {
    size_t i;

    if (g_mtk_handle != NULL)
        return 0;

    g_mtk_handle = dlopen(MTK_BT_LIBRARY, RTLD_NOW);
    if (g_mtk_handle == NULL) {
        ALOGE("dlopen %s failed: %s", MTK_BT_LIBRARY, dlerror());
        return -1;
    }

    for (i = 0; i < sizeof(kMtkSyms) / sizeof(kMtkSyms[0]); i++) {
        void *sym = dlsym(g_mtk_handle, kMtkSyms[i].name);
        if (sym == NULL) {
            ALOGE("%s has no symbol %s: %s", MTK_BT_LIBRARY, kMtkSyms[i].name,
                  dlerror());
            dlclose(g_mtk_handle);
            g_mtk_handle = NULL;
            return -1;
        }
        *kMtkSyms[i].slot = sym;
    }
    return 0;
}

static int mtk_bt_init(const void *p_cb, unsigned char *local_bdaddr) {
    (void)local_bdaddr; /* stock ignores it; the BD address comes from NVRAM
                         * inside libbluetooth_mtk (bt_read_nvram /
                         * ap_nvram_btradio_struct, see its .rodata). */
    ALOGI("mtk_bt_init");

    if (mtk_bind() != 0)
        return -1; /* stock cannot fail here; we can, and must say so. */

    p_set_callbacks(p_cb);
    return 0;
}

static int mtk_bt_op(int opcode, void *param) {
    if (mtk_bind() != 0)
        return -1;

    switch (opcode) {
    case BT_VND_OP_POWER_CTRL:
        /* No chip call in stock: the WMT driver powers the combo chip up when
         * /dev/stpbt is opened, so USERIAL_OPEN is the real power-on. */
        ALOGD("BT_VND_OP_POWER_CTRL %d", param ? *(int *)param : -1);
        return 0;

    case BT_VND_OP_FW_CFG:
        ALOGD("BT_VND_OP_FW_CFG");
        return p_mtk_fw_cfg();

    case BT_VND_OP_SCO_CFG:
        ALOGD("BT_VND_OP_SCO_CFG");
        return p_mtk_sco_cfg();

    case BT_VND_OP_USERIAL_OPEN:
        ALOGD("BT_VND_OP_USERIAL_OPEN");
        /* One H4 fd. VendorInterface::Open() reads fd_list[0] and takes the
         * fd_count == 1 branch (H4Protocol). */
        *(int *)param = p_init_uart();
        return 1;

    case BT_VND_OP_USERIAL_CLOSE:
        ALOGD("BT_VND_OP_USERIAL_CLOSE");
        p_close_uart();
        return 0;

    case BT_VND_OP_GET_LPM_IDLE_TIMEOUT:
        ALOGD("BT_VND_OP_GET_LPM_IDLE_TIMEOUT");
        *(uint32_t *)param = MTK_LPM_IDLE_TIMEOUT_MS;
        return 0;

    case BT_VND_OP_LPM_SET_MODE:
        ALOGD("BT_VND_OP_LPM_SET_MODE %d", *(uint8_t *)param);
        return 0;

    case BT_VND_OP_LPM_WAKE_SET_STATE:
        ALOGD("BT_VND_OP_LPM_WAKE_SET_STATE");
        return 0;

    case BT_VND_OP_EPILOG:
        ALOGD("BT_VND_OP_EPILOG");
        return p_mtk_prepare_off();

    case BT_VND_OP_MTK_SET_FW_ASSERT:
        ALOGD("BT_VND_OP_SET_FW_ASSERT 0x%08x", *(uint32_t *)param);
        return p_mtk_set_fw_assert(*(uint32_t *)param);

    case BT_VND_OP_MTK_SET_PSM_CONTRL:
        ALOGD("BT_VND_OP_SET_PSM_CONTRL, setting: %d", *(uint8_t *)param);
        return p_mtk_set_psm_control(*(uint8_t *)param);

    default:
        /* BT_VND_OP_SET_AUDIO_STATE and both A2DP_OFFLOAD opcodes land here in
         * stock too — MTK offloads neither on this chip. */
        ALOGD("Unknown operation %d", opcode);
        return -1;
    }
}

static void mtk_bt_cleanup(void) {
    ALOGI("mtk_bt_cleanup");
    if (g_mtk_handle == NULL)
        return;
    p_clean_resource();
    p_clean_callbacks();
}

__attribute__((visibility("default")))
const bt_vendor_interface_t BLUETOOTH_VENDOR_LIB_INTERFACE = {
    sizeof(bt_vendor_interface_t),
    mtk_bt_init,
    mtk_bt_op,
    mtk_bt_cleanup,
};
