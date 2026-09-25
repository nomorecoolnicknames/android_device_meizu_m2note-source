/*
 * pthread_mutex_destroy interposer for /vendor/bin/mnld (ported from
 * device/meizu/m95/shims/pthread.c, same Nougat-era MTK GPS stack).
 *
 * Flyme's Nougat-era libmnl.so destroys its session mutex twice on every MNL
 * stop. Pie's bionic FORTIFY-aborts on destroying an already-destroyed mutex,
 * so every GPS session teardown kills mnld with SIGABRT:
 *
 *   FORTIFY: pthread_mutex_destroy called on a destroyed mutex
 *
 * init restarts mnld in about 0.3 s and the mnld_reboot handshake re-inits the
 * HAL, so it mostly self-heals - but each location toggle costs a crash and a
 * tombstone, and a start that lands inside the restart window is lost.
 *
 * A no-op is strictly safer here than what Nougat did: bionic's destroy only
 * writes a tombstone value into the state word and frees no kernel resource,
 * and a later pthread_mutex_init() reinitialises that word regardless.
 *
 * m5c status (2026-09-03): the double destroy is a FACT on m95 (libmnl.so
 * +0xef7b <- +0x1e8a1); on m5c the import is confirmed (readelf: libmnl.so
 * UND pthread_mutex_destroy) and the crash itself is still to be observed.
 */
#include <pthread.h>

int pthread_mutex_destroy(pthread_mutex_t* mutex __attribute__((unused))) {
    return 0;
}
