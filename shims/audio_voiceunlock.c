/*
 * audio_voiceunlock.c — no-op stubs for the eleven MediaTek "voice unlock"
 * statics that audio.primary.mt6737m.so (Flyme, Android M era) imports from
 * android::AudioSystem.  AOSP libmedia never exported them, so on Pie the HAL
 * cannot be dlopen'ed at all:
 *
 *   dlopen failed: cannot locate symbol "_ZN7android11AudioSystem18startVoiceUnlockDLEv"
 *   referenced by "/vendor/lib/hw/audio.primary.mt6737m.so"
 *
 * Measured, not guessed (blobsym.py differential against the LOS 16 out tree,
 * 2026-09-03, both ABIs): these eleven are the ONLY unresolved symbols of the
 * primary audio HAL once libtinyxml.so and libtinycompress.so are installed.
 * They belong to MTK's voice-unlock feature (wake-on-voice), which nothing in
 * this ROM ever calls, so every stub returns 0 / NULL.
 *
 * Wired through TARGET_LD_SHIM_LIBS (BoardConfig.mk) as a shim for
 * /vendor/lib{,64}/hw/audio.primary.mt6737m.so.  Return types are not part
 * of the Itanium mangling for non-template functions, so the asm labels below
 * reproduce the blob's imports exactly whatever the originals returned; the
 * pointer-returning one is declared as such so x0/r0 is a clean NULL.
 */

#include <stddef.h>
#include <stdint.h>

#define VU_STUB(ret, name, mangled, params, retval) \
    ret name params __asm__(mangled);               \
    ret name params { return retval; }

/* int AudioSystem::ReadRefFromRing(void*, uint32_t, void*) */
VU_STUB(int, m5c_vu_ReadRefFromRing,
        "_ZN7android11AudioSystem15ReadRefFromRingEPvjS1_",
        (void *a __attribute__((unused)), uint32_t b __attribute__((unused)),
         void *c __attribute__((unused))), 0)

/* int AudioSystem::SetVoiceUnlockSRC(uint32_t, uint32_t) */
VU_STUB(int, m5c_vu_SetVoiceUnlockSRC,
        "_ZN7android11AudioSystem17SetVoiceUnlockSRCEjj",
        (uint32_t a __attribute__((unused)), uint32_t b __attribute__((unused))), 0)

/* bool AudioSystem::stopVoiceUnlockDL() */
VU_STUB(int, m5c_vu_stopVoiceUnlockDL,
        "_ZN7android11AudioSystem17stopVoiceUnlockDLEv", (void), 0)

/* bool AudioSystem::startVoiceUnlockDL() */
VU_STUB(int, m5c_vu_startVoiceUnlockDL,
        "_ZN7android11AudioSystem18startVoiceUnlockDLEv", (void), 0)

/* bool AudioSystem::GetVoiceUnlockULTime(void*) */
VU_STUB(int, m5c_vu_GetVoiceUnlockULTime,
        "_ZN7android11AudioSystem20GetVoiceUnlockULTimeEPv",
        (void *a __attribute__((unused))), 0)

/* int AudioSystem::GetVoiceUnlockDLLatency() */
VU_STUB(int, m5c_vu_GetVoiceUnlockDLLatency,
        "_ZN7android11AudioSystem23GetVoiceUnlockDLLatencyEv", (void), 0)

/* void* AudioSystem::getVoiceUnlockDLInstance() */
VU_STUB(void *, m5c_vu_getVoiceUnlockDLInstance,
        "_ZN7android11AudioSystem24getVoiceUnlockDLInstanceEv", (void), NULL)

/* void AudioSystem::freeVoiceUnlockDLInstance() — declared int for uniformity;
 * a discarded 0 in r0/w0 is harmless for a void caller. */
VU_STUB(int, m5c_vu_freeVoiceUnlockDLInstance,
        "_ZN7android11AudioSystem25freeVoiceUnlockDLInstanceEv", (void), 0)
