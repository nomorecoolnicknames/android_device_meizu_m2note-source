/*
 * MTK video-codec blob shim, LineageOS 16.0 (m5c source, used for the m2note).
 *
 * libvcodecdrv.so ships from Flyme (Android 7.1) and imports
 * __pthread_gettid, which bionic dropped in Pie. Without it the whole
 * dlopen chain of the 32-bit Mali driver fails and the 32-bit zygote
 * aborts with couldn't find an OpenGL ES implementation, taking the
 * boot with it. Pie exposes the same value as pthread_gettid_np.
 */
#include <pthread.h>
#include <sys/types.h>

pid_t __pthread_gettid(pthread_t t);

pid_t __pthread_gettid(pthread_t t)
{
    return pthread_gettid_np(t);
}
