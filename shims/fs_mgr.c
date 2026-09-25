/* libfs_mgr (shim) — minimal N-ABI fstab reader for m95's libnvram.so.
 *
 * FACTS (differential + readelf, 2026-07-27):
 *  - libnvram.so (32/64) has DT_NEEDED [libfs_mgr.so] and imports exactly
 *    three symbols: fs_mgr_read_fstab, fs_mgr_get_entry_for_mount_point,
 *    fs_mgr_free_fstab.
 *  - P builds libfs_mgr as cc_library_static ONLY — no libfs_mgr.so exists
 *    on the image, so libnvram (and with it MTK NVRAM: WiFi/BT MAC, IMEI
 *    calibration data) cannot load at all.
 *  - Disassembly of libnvram's NVM_Init: snprintf a path, call
 *    fs_mgr_read_fstab(path), NULL-check, keep struct fstab* in a global,
 *    look entries up and read the leading fields of the returned record.
 *
 * Rather than dragging in P's static libfs_mgr (whose struct fstab_rec grew
 * new fields — returned-record field offsets would still match, but we would
 * inherit its heavy deps and its parsing side effects), this is a
 * self-contained implementation using the *N* (7.1) struct layout the blob
 * was compiled against. We allocate the records, we index them, the blob only
 * dereferences pointers we return — so layout agreement with the consumer is
 * total and there is no ABI hazard by construction.
 *
 * Only the fields libnvram can meaningfully read are populated:
 * blk_device / mount_point / fs_type / fs_options; everything else is zero.
 * fs_mgr flag PARSING is deliberately absent — nvram only needs the
 * mount-point -> block-device mapping.
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* struct layout from N (7.1) system/core/fs_mgr/fs_mgr_priv.h — the layout
 * the consumer blob was compiled against. Field order/type must not change. */
struct fstab_rec {
    char *blk_device;
    char *mount_point;
    char *fs_type;
    unsigned long flags;
    char *fs_options;
    int fs_mgr_flags;
    char *key_loc;
    char *verity_loc;
    long long length;
    char *label;
    int partnum;
    int swap_prio;
    int max_comp_streams;
    unsigned int zram_size;
    unsigned long long reserved_size;
    unsigned int file_contents_mode;
    unsigned int file_names_mode;
};

struct fstab {
    int num_entries;
    struct fstab_rec *recs;
    char *fstab_filename;
};

void fs_mgr_free_fstab(struct fstab *fstab) {
    int i;
    if (fstab == NULL)
        return;
    for (i = 0; i < fstab->num_entries; i++) {
        free(fstab->recs[i].blk_device);
        free(fstab->recs[i].mount_point);
        free(fstab->recs[i].fs_type);
        free(fstab->recs[i].fs_options);
    }
    free(fstab->recs);
    free(fstab->fstab_filename);
    free(fstab);
}

struct fstab *fs_mgr_read_fstab(const char *fstab_path) {
    FILE *f;
    char line[1024];
    struct fstab *fstab;

    if (fstab_path == NULL)
        return NULL;
    f = fopen(fstab_path, "re");
    if (f == NULL)
        return NULL;

    fstab = calloc(1, sizeof(*fstab));
    if (fstab == NULL) {
        fclose(f);
        return NULL;
    }
    fstab->fstab_filename = strdup(fstab_path);

    while (fgets(line, sizeof(line), f) != NULL) {
        char *p = line, *save = NULL;
        char *dev, *mnt, *type, *opts;
        struct fstab_rec *nrecs;

        while (isspace(*p))
            p++;
        if (*p == '\0' || *p == '#')
            continue;

        dev = strtok_r(p, " \t\r\n", &save);
        mnt = strtok_r(NULL, " \t\r\n", &save);
        type = strtok_r(NULL, " \t\r\n", &save);
        opts = strtok_r(NULL, " \t\r\n", &save);
        if (dev == NULL || mnt == NULL || type == NULL)
            continue;

        nrecs = realloc(fstab->recs,
                        (fstab->num_entries + 1) * sizeof(struct fstab_rec));
        if (nrecs == NULL)
            break;
        fstab->recs = nrecs;
        memset(&fstab->recs[fstab->num_entries], 0, sizeof(struct fstab_rec));
        fstab->recs[fstab->num_entries].blk_device = strdup(dev);
        fstab->recs[fstab->num_entries].mount_point = strdup(mnt);
        fstab->recs[fstab->num_entries].fs_type = strdup(type);
        fstab->recs[fstab->num_entries].fs_options =
            strdup(opts != NULL ? opts : "");
        fstab->num_entries++;
    }
    fclose(f);

    if (fstab->num_entries == 0) {
        fs_mgr_free_fstab(fstab);
        return NULL;
    }
    return fstab;
}

struct fstab_rec *fs_mgr_get_entry_for_mount_point(struct fstab *fstab,
                                                   const char *path) {
    int i;
    if (fstab == NULL || path == NULL)
        return NULL;
    for (i = 0; i < fstab->num_entries; i++) {
        if (fstab->recs[i].mount_point != NULL &&
            strcmp(fstab->recs[i].mount_point, path) == 0)
            return &fstab->recs[i];
    }
    return NULL;
}
