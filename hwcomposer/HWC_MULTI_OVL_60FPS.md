# m2note HWC — true multi-OVL hardware composition (60 fps)

Design + RE record for moving the source HWC from a single GLES-into-FB_TARGET
path to **real MT6753 DDP multi-OVL hardware composition**. Author: Claude
(display/HWC lane). All non-trivial claims tagged FACT / INFERENCE / HYPOTHESIS
per `/srv/forge/android/CLAUDE.md §2`.

Paths are relative to the ROM tree
`/srv/forge/android/meizu_m6/rom-lineage-15.1-meizu_m6-experimental` unless they
start with `drivers/…`, which are in the kernel tree
`/srv/forge/android/m2note/kernel-m2note-3.18-adapt`.

---

## 1. The regression being fixed

**FACT** (orchestrator measurement, `dumpsys gfxinfo com.cyanogenmod.trebuchet`
during home swipes): 100% janky frames, p50 frame 61 ms (target ≤16.6 ms) ≈
16 fps; "Slow issue draw commands" 100%; Missed Vsync ≈50%.

**FACT** (`dumpsys SurfaceFlinger`): all 7 HW layers report `Comp Type =
Client` (GLES), zero `Device`/overlay; `debug.composition.type=gpu`.

**FACT** (source, `hwcomposer.cpp:583` `hwc_prepare`): every non-FB_TARGET layer
is forced to `HWC_FRAMEBUFFER`, so SurfaceFlinger GLES-composites the whole
screen into one `FRAMEBUFFER_TARGET` buffer, which the HWC presents on a single
OVL0 slot (`hwc_set`, slot 0; slots 1-3 sent disabled every frame).

**INFERENCE**: the GPU (Mali-T720, mostly 299 MHz) fills the entire 1080×1920
screen every frame → ~61 ms/frame. Stock firmware hit 60 fps by hardware
multi-OVL. This is a **port regression**, not a hardware limit.

---

## 2. Kernel ground truth (why multi-OVL is a userspace-only change)

The kernel DDP path already supports up to 4 hardware layers on the primary
OVL0 engine. The single-OVL HWC simply never populated more than one slot.

- **FACT F1 — 4 hardware layers.** `OVL_LAYER_NUM = 4`
  (`drivers/…/dispsys/mt6753/ddp_ovl.h:15`; the `= 6` alternative needs
  `OVL_CASCADE_SUPPORT`, which is **commented out** for mt6753 —
  `drivers/…/videox/mt6753/disp_drv_platform.h:119`). `ovl_config_l` runs
  `layer_min=0 … layer_max=4` (`ddp_ovl.c:1037-1040`); `ovl_layer_config`
  asserts `layer <= 3` (`ddp_ovl.c:514`). So the primary path has hardware
  layers `layer_id = 0..3`.

- **FACT F2 — layer_id IS the OVL slot / Z order.** `_config_ovl_input` indexes
  `ovl_cfg = &data_config->ovl_config[input_cfg->layer_id]`
  (`primary_display.c:6880-6886`). OVL blends slot 0 (bottom) → slot 3 (top).
  A higher `layer_id` composites over a lower one.

- **FACT F3 — `src_pitch` is a PIXEL stride.** `_convert_disp_input_to_ovl`
  sets `dst->src_pitch = src->src_pitch * Bpp` (`primary_display.c:3035`; same
  in the memory path `_sync_convert_fb_layer_to_disp_input`, `:1252`). This is
  the source-truth for the historical "skew" bug — the HWC must pass a pixel
  stride, never a byte pitch.

- **FACT F4 — every frame must send all 4 slots.** `CONFIG_ALL_IN_TRIGGER_STAGE`
  is defined (`disp_drv_platform.h:67`). `set_primary_buffer` therefore does
  NOT configure OVL at SET_INPUT time; it caches per layer_id:
  `captured_session_input[PRIMARY-1].config[layer_id] = input->config[i]`
  (`mtk_disp_mgr.c:1590-1593`). At TRIGGER,
  `primary_display_merge_session_cmd` copies the whole captured struct, forces
  `config_layer_num = OVL_LAYER_NUM (4)`, and applies all four slots
  (`primary_display.c:6329-6339,6359`). Consequence: a slot NOT present in the
  current SET_INPUT keeps its previous cached config and **keeps scanning**.
  The HWC must send all 4 slots every frame — used ones enabled, unused ones
  explicitly `layer_enable=0`. (The single-OVL path already does this; the v220
  comment in `hwcomposer.cpp` records the same finding.)

- **FACT F5 — OVL cannot scale.** `_convert_disp_input_to_ovl` clamps
  `dst_w = min(src_width, tgt_width)`, `dst_h = min(src_height, tgt_height)`
  (`primary_display.c:3041-3042`); there is no scaler in `ovl_layer_config`. An
  OVL layer is a crop + reposition only. **Overlay-eligible layers must be 1:1**
  (sourceCrop size == displayFrame size).

- **FACT F6 — per-layer alpha registers.** `ovl_layer_config`
  (`ddp_ovl.c:462-623`):
  - `aen` → `L_CON_FLD_AEN` (plane/const-alpha blend enable).
  - `alpha` → `L_CON_FLD_APHA` (8-bit plane alpha).
  - `sur_aen` → bit 15 of `L_PITCH` `SUR_ALFA` (per-pixel/surface alpha enable).
  - `src_alpha`/`dst_alpha` → 2-bit coefficient selectors, values from
    `DISP_ALPHA_TYPE` (`disp_session.h:105-110`): `ONE=0`, `SRC=1`,
    `SRC_INVERT=2`.

- **FACT F7 — X-channel alpha auto-forced opaque.** `DISP_DISABLE_X_CHANNEL_ALPHA`
  is defined (`mtk_disp_mgr.c:78`). In `_convert_disp_input_to_ovl`
  (`primary_display.c:3057-3066`) the kernel forces `aen=sur_aen=0` for
  non-alpha formats (RGBX/XRGB/XBGR/BGRX) but keeps them for
  RGBA/BGRA/ARGB/ABGR and dim layers. So an opaque RGBX wallpaper is treated
  opaque automatically, and an RGBA FB_TARGET keeps per-pixel alpha.

- **FACT F8 — per-layer buffer registration.** `PREPARE_INPUT_BUFFER`
  (`_ioctl_prepare_buffer`, type `PREPARE_INPUT_FENCE`) honors `info.layer_id`
  (only present/output fence types override it — `mtk_disp_mgr.c:809-814`).
  `set_primary_buffer` resolves each layer's MVA with
  `disp_sync_query_buf_info(session_id, layer_id, next_buff_idx, …)`
  (`mtk_disp_mgr.c:1542`). So **each overlay layer needs its own
  PREPARE_INPUT_BUFFER** carrying its `layer_id` + dmabuf fd; the returned
  `index` goes into `config[slot].next_buff_idx`, and the returned `fence_fd` is
  that layer's scanout release fence.

- **FACT F9 — TRIGGER `.type` must be PRIMARY.** Already understood and handled
  (`hwcomposer.cpp` v215 comment; `.type` indexes `captured_session_input[type-1]`).
  `.type=0` → OOB → OOPS. Unchanged by this work.

**INFERENCE**: multi-OVL composition is achievable entirely in the userspace HWC
by populating `config[0..k]` with real per-layer buffers. It is actually
*closer to stock behavior* than the single-FB_TARGET hack, because the stock
blob drove these same slots.

---

## 3. Target design

### 3.1 Z-band partition (bottom-band offload)

SurfaceFlinger hands layers bottom→top: `hwLayers[0..N-1]` are app layers,
`hwLayers[last]` is `FRAMEBUFFER_TARGET`. A single FB_TARGET can only represent
one contiguous Z band, so the offloaded overlays must be Z-contiguous.

We offload the **bottom contiguous run** of overlay-eligible layers and leave
the FB_TARGET holding the GLES composition of everything above it:

```
 OVL slot (layer_id)   content                         Z
 -------------------   -----------------------------   ------
 0                     bottom eligible app layer       bottom
 1                     next eligible app layer up       |
 …                     … (up to 3 overlay layers)       |
 k = #overlays         FB_TARGET (GLES of top layers)  top
```

Rationale (**INFERENCE**): the expensive part of a home-screen swipe is the
full-screen bottom layers (wallpaper + scrolling launcher workspace). Offloading
those to OVL frees the GPU from the big fills; the GPU then only composites the
small top chrome (status bar, nav bar) into FB_TARGET. The alternative
(top-band offload, FB_TARGET opaque at slot 0) is lower risk but offloads only
the small layers and barely helps the measured workload.

- Reserve 1 slot for FB_TARGET, so at most **3** app layers go to overlay
  (`MAX_OVL_LAYERS - 1`). If more than 3 bottom layers qualify, the surplus
  stays in FB_TARGET (they are the higher-Z members of the bottom run — the run
  is taken from slot 0 upward, capped at 3).
- If the **bottom-most** app layer is ineligible, no layer is offloaded and the
  path is byte-for-byte the current single-OVL behavior (safe no-op).

### 3.2 FB_TARGET alpha, two cases

- `k == 0` (no overlays — every app layer GLES'd): FB_TARGET on slot 0, **opaque**
  (`aen=1, alpha=0xFF, sur_aen=0, src_alpha=dst_alpha=ONE`). **Identical to the
  current shipping path** — zero behavior change when multi-OVL is off or finds
  nothing to offload.
- `k > 0` (FB_TARGET on top of overlays): FB_TARGET must blend per-pixel so its
  transparent holes reveal the overlays below. SF clears the FB to (0,0,0,0)
  and renders the top layers premultiplied. So set source-over premultiplied:
  `aen=1, alpha=0xFF, sur_aen=1, src_alpha=ONE, dst_alpha=SRC_INVERT`.

**FACT (was U1, now confirmed by ghidra of the stock blob — see §6).** The blend
mapping above is exactly what the stock HWC does. `DispDevice::updateOverlayInputs`
@ `0x28b78` builds `disp_input_config` (stride `0x84`) and, for the alpha fields,
does literally: `if (blending == 0x105 /*PREMULT*/) { sur_aen=1; src_alpha=0/*ONE*/;
dst_alpha=2/*SRC_INVERT*/; } else { sur_aen=0; }`. So premultiplied source-over
for PREMULT and per-pixel alpha OFF otherwise. `NONE` stays an opaque overwrite
(`aen=0`). **COVERAGE is deliberately NOT hardware-composed** (stock leaves
`sur_aen=0`, which would show it opaque) → it is excluded from eligibility (§3.4).

### 3.3 Per-overlay-layer config (from `hwc_layer_1_t`)

For each offloaded layer, fill `disp_input_config`:

| field | source | note |
|-------|--------|------|
| `layer_id` | slot index (0..k-1) | = Z position, FACT F2 |
| `layer_enable` | 1 | |
| `buffer_source` | `DISP_BUFFER_ION` | |
| `src_base_addr` | `(void*)(intptr_t)dup(handle->data[0])` | dmabuf fd, per the v215 fix (never gralloc GET_ION_FD) |
| `src_fmt` | `gralloc_extra_query(GET_FORMAT)` → `hal_to_disp_format` | |
| `src_pitch` | `gralloc_extra_query(GET_STRIDE)` (pixels) | FACT F3 |
| `src_offset_x/y`, `src_width/height` | `sourceCrop` | integer crop |
| `tgt_offset_x/y`, `tgt_width/height` | `displayFrame` | FACT F5: must equal src size |
| `layer_rotation` | `hwc_transform_to_disp_orientation(transform)` | live-proven for axis-preserving 0/180 |
| alpha fields | from `blending` + `planeAlpha` | §3.2 mapping |
| `next_buff_idx` | index from that layer's PREPARE_INPUT_BUFFER | FACT F8 |
| `security` | `DISP_NORMAL_BUFFER` | secure layers are ineligible (first cut) |

### 3.4 Eligibility rules (`layer_overlay_eligible`)

A layer qualifies for HWC_OVERLAY only if ALL hold (else it stays GLES):

1. `compositionType == HWC_FRAMEBUFFER` (not TARGET / SIDEBAND / CURSOR_OVERLAY).
2. `handle != NULL` and `handle->numFds >= 1` (has a dmabuf fd).
3. `flags & HWC_SKIP_LAYER == 0`.
4. `transform` is axis-preserving: `0` or `HWC_TRANSFORM_ROT_180`. The live
   m2note build uses `ro.sf.hwrotation=180`, so every normal layer arrives as
   `ROT_180`; v849-v855 proved that programming the OVL layer rotation handles
   this case. Axis-swapping 90/270 and flips still stay GLES until their geometry
   path is proven separately.
5. **1:1** — `sourceCrop` width/height == `displayFrame` width/height (FACT F5,
   OVL has no scaler).
6. Format is a plain packed RGB(A) understood by both `hal_to_disp_format` and
   the kernel (RGBA/RGBX/RGB565/RGB888/BGRA). YUV/compressed → GLES.
7. `blending` ∈ {NONE, PREMULT}. COVERAGE is excluded — the stock blob does not
   give it per-pixel alpha (§3.2 FACT), so it stays GLES.
8. displayFrame within panel bounds; width/height ≤ `OVL_MAX_WIDTH/HEIGHT`
   (4095, `ddp_ovl.h:9-10`).

### 3.5 Runtime flag + fallback (safety)

- Prop **`persist.forge.m2note.multi_ovl`** (also
  `debug.forge.m2note.multi_ovl`), default **`1`** after v853-v855 live proof.
  Set it to `0` to force the old single-OVL path for recovery/debug.
- Latched fallback `d->multi_ovl_failed`: any failure in the multi path
  (PREPARE / SET_INPUT / TRIGGER, or unusable metadata for a promised overlay
  layer) sets this flag; from then on `hwc_prepare` marks everything
  HWC_FRAMEBUFFER → the proven single-OVL FB_TARGET path resumes for the rest
  of the session. At most one transient frame is affected.
- The existing per-frame fb0 memcpy fallback and the `overlay_fail >= 60 &&
  overlay_present == 0` latch to fb0 remain untouched underneath.

### 3.6 Freeze watchdog — self-recovery without a reboot (v462b)

The ioctl-error fallback (§3.5) does NOT catch a **silent present freeze**:
frames stop scanning out but no ioctl returns an error (the classic DDP
pipeline stall behind project memory `m2note-overlay-hardreset-consys-bootloop`).
This device **cannot be recovered by the user with a cold power cycle** (hard
constraint), so the module must self-detect a freeze and revert **without any
external reboot**. Two independent layers, both keyed on the per-frame scanout
(frame-done) fence that `PREPARE_INPUT_BUFFER` returns:

1. **Canary (first `MULTI_OVL_CANARY_FRAMES = 3` frames).** After TRIGGER, the
   module block-waits that frame's scanout fence with a short budget
   (`MULTI_OVL_CANARY_TIMEOUT_MS = 300`). If it does not signal, the multi
   config never scanned out → latch `multi_ovl_failed` immediately. This catches
   a fundamentally broken multi config on frame 1 — while SurfaceFlinger is
   still healthy — instead of letting repeated bad frames wedge CONSYS. Cost is
   a one-time ≤300 ms hitch on at most the first three frames.

2. **Watchdog thread (`hwc_watchdog_thread`).** A dedicated thread (NOT the
   vsync thread, whose `WAIT_FOR_VSYNC` can itself block if the panel TE stalls)
   polls the most recent frame's scanout fence non-blockingly every
   `MULTI_OVL_WATCHDOG_POLL_MS = 100`. If a presented frame's fence stays
   unsignalled for `MULTI_OVL_FREEZE_TIMEOUT_NS = 1 s`, the pipeline has stalled
   → latch `multi_ovl_failed`. Because it runs independently of SF, it fires
   even if SF has blocked on the retire fence. No false-positive on an idle
   screen: an idle frame's fence signals within one refresh, clearing the
   outstanding-frame state.

**Hard invariant:** multi-OVL only ever runs with the watchdog armed. If the
watchdog thread fails to start, `hwc_device_open` disables `use_multi_ovl`
outright — there is no self-recovery guarantee without it, so it is not risked.

Residual limitation (honest): if the very first frame hard-wedges the DSI such
that SF blocks on an unsignalled retire fence AND the kernel never times that
fence out, the module still latches to single-OVL (whose fresh full-slot config
re-kicks OVL0), but it cannot *force-signal* a kernel fence. The canary shrinks
this exposure to ≤300 ms on frame 1. The orchestrator's host-side armed
watchdog (auto `setprop multi_ovl 0` + umount + warm reboot) remains the outer
backstop. `hwc_dump` exposes `freeze_latch` so a self-revert is observable.

### 3.7 Stock partition strategy + OVL bandwidth (v462d, ghidra cross-check)

Ghidra of the stock blob confirms two things about *how* it partitions layers,
cross-checking the bottom-band choice (§3.1):

- **No fixed FB_TARGET slot.** `DispDevice::updateOverlayInputs @0x28b78` sets
  each config's `layer_id` to the SurfaceFlinger Z index and packs the accepted
  layers into `config[0..n-1]`; the kernel then places each by `layer_id`
  (FACT F2). So the FB_TARGET may sit at any Z — our FB_TARGET-on-top
  (slot = #overlays) is legal, not a special case. **FACT.**
- **Stock uses a full per-layer dispatcher, not a simple band.**
  `HWCMediator::prepare @0x238e0` drives `HWCDispatcher` + `DispatcherJob` +
  MM/UI `ComposeThread`s (MDP fallback, per-layer). Our single-FB_TARGET
  bottom-band offload is a correct, simpler **subset** of that — it never
  produces an incorrect image, it just offloads fewer layers in complex scenes.
  So there is no field-level gap; the difference is scope, not correctness.

- **OVL has a bandwidth / overlap ceiling (watch-item).** The stock enforces a
  limit — `DevicePlatform::getBandwidthLimit`, `debug.hwc.ovl_overlap_limit`,
  and the log `"Exceed Overlap Limit1/2(%d), cur(%d)"` — and drops overlay
  layers to GLES/MDP when exceeded. The exact formula lives in an external
  platform lib (`getBandwidthLimit` is a thunk here), so it is **not** hardcoded
  in this module (no guessed threshold). Consequence for our path: offloading
  several large **overlapping** layers (e.g. two full-screen RGBA layers) can
  exceed OVL read bandwidth → **underflow = tearing/flicker, NOT a freeze** — so
  the §3.6 freeze watchdog will NOT catch it; it is a *visual* check in the A/B.
  Mitigations:
  - The target workload (home-screen swipe = wallpaper + workspace + two bars)
    is proven within budget because the **stock ran exactly this at 60 fps**.
  - Runtime knob **`persist.forge.m2note.multi_ovl_max`** (also
    `debug.…`), default `2`, clamps how many app layers we offload (1..3). If
    the first A/B shows underflow/tearing, the orchestrator lowers it live
    (`setprop … 2` or `1`, then `stop;start`) — no rebuild — trading some GPU
    offload for bandwidth headroom. Surfaced in `hwc_dump` as `max=`.

---

## 4. Risks & mitigations

| # | Risk | FACT/HYP | Mitigation |
|---|------|----------|------------|
| R1 | Stale slot keeps scanning if not all 4 sent | FACT F4 | Always `config_layer_num=4`; unused slots `layer_enable=0` every frame |
| R2 | `src_pitch` skew (byte vs pixel) | FACT F3 | Pass gralloc GET_STRIDE (pixels); kernel ×Bpp |
| R3 | Wrong blend coeffs → halos/black boxes | ~~INFERENCE~~ **FACT** | RESOLVED: stock blob ghidra (`DispDevice::updateOverlayInputs @0x28b78`) confirms PREMULT→sur_aen=1/src=ONE/dst=SRC_INVERT, else sur_aen=0; COVERAGE excluded. See §3.2 / §6 U1 |
| R4 | Z inversion from non-contiguous GLES band | design | Only the bottom contiguous run is offloaded; FB_TARGET sits above it |
| R5 | **Silent** overlay freeze → hard reset → CONSYS wedge bootloop (no ioctl error; user CANNOT cold-cycle) | project memory `m2note-overlay-hardreset-consys-bootloop` | §3.6 in-module freeze watchdog: canary (≤300ms, frame 1) + independent watchdog thread (1s) latch `multi_ovl_failed` → revert to single-OVL **without any reboot**; multi-OVL refuses to run unless the watchdog is armed; present_fence stays disabled; blank stays a no-op; orchestrator host-side watchdog as outer backstop |
| R6 | 0x118 OOPS from TRIGGER `.type` | FACT F9 | `.type=DISP_SESSION_PRIMARY` unchanged |
| R7 | `gralloc_extra_query` hot-path instability | source v273 comment | Queried only for the ≤3 offloaded layers; failure → layer ineligible (not fatal). If it proves unstable, fall back to reading MTK private-handle ints (open task) |
| R8 | Secure/protected layer mis-handled | design | Secure layers ineligible in first cut |
| R9 | OVL read-bandwidth/overlap underflow from many large overlapping overlays → tearing (NOT a freeze; watchdog won't catch) | FACT (stock `getBandwidthLimit` / `ovl_overlap_limit` / "Exceed Overlap Limit") §3.7 | Target scene proven within budget by stock 60fps; runtime `multi_ovl_max` knob (default 2) to lower offload count live in A/B; visual tearing check added to §5 |

---

## 5. Bind-mount test plan (for the orchestrator)

Host build only in this phase; the orchestrator runs the device steps when the
tree/device free. This is the bootloop-SAFE harness (project memory
`m2note-hwc-bindmount-test-harness`), NOT a flash.

1. **Build the module** (ROM tree, JDK8 env per `m2note-rom-build-env`):
   ```
   mka hwcomposer.mt6753
   ```
   Output: `out/target/product/m2note/vendor/lib64/hw/hwcomposer.mt6753.so`.

2. **Stage + bind-mount** the candidate over the installed one and restart SF:
   ```
   adb -H 127.0.0.1 -P 15039 push <built>.so /data/local/tmp/hwc_multiovl.so
   adb ... shell 'su 0 mount -o bind /data/local/tmp/hwc_multiovl.so \
        /vendor/lib64/hw/hwcomposer.mt6753.so'
   adb ... shell 'su 0 setprop persist.forge.m2note.multi_ovl 1'
   adb ... shell 'su 0 stop && su 0 start'
   ```
   (If the device has no `su`, do the bind-mount + setprop via the same
   root path the harness already uses.)

3. **Confirm overlay composition** — the pass/fail signal:
   ```
   adb ... shell dumpsys SurfaceFlinger | grep -A2 -iE 'Comp Type|HWC layers'
   ```
   PASS (a): the bottom app layers now show `Comp Type = Device` (overlay),
   FB_TARGET shows `Device` too; not everything `Client`.
   ```
   adb ... shell dumpsys gfxinfo com.cyanogenmod.trebuchet
   ```
   PASS (b): janky% and p50 frame time drop materially (target p50 ≤ ~16.6 ms,
   or at least a large improvement from 61 ms); Missed Vsync down.
   ```
   adb ... shell 'su 0 cat /d/dispsys/... ' (ovl analysis) OR the HWC dump:
   adb ... shell dumpsys SurfaceFlinger --hwc   # module hwc_dump: overlay_present rising, overlay_fail flat
   ```
   PASS (b2) — VISUAL, bandwidth check (R9): eyeball the screen during a swipe.
   No tearing / horizontal glitch / flicker on the wallpaper or workspace. OVL
   underflow shows as tearing, NOT a freeze, so gfxinfo alone won't flag it, and
   kernel log may show OVL underflow / `"Exceed Overlap Limit"`. If tearing
   appears, lower the offload count live and re-check:
   `setprop persist.forge.m2note.multi_ovl_max 2` (or `1`) `&& stop && start`
   (hwc_dump shows `max=`). Report which `max=` value is clean.

4. **Confirm no kernel fault** (bootloop safety):
   ```
   adb ... shell 'su 0 cat /sys/fs/pstore/console-ramoops-0' 2>/dev/null
   adb ... logcat -b kernel -d | grep -iE 'OVL|DISP|OOPS|Unable to handle|BUG|mtk_disp'
   ```
   PASS (c): no OVL/DISP OOPS, no `Unable to handle kernel`, no watchdog reset,
   screen not frozen after a sleep/wake cycle (`input keyevent 26` twice).
   Also check the module self-heal path did NOT trip (a trip means the pipeline
   stalled and the module reverted on its own — safe, but means multi-OVL did
   not hold): `dumpsys SurfaceFlinger --hwc` → the `multi_ovl:` line should show
   `freeze_latch=0` and `failed=0` on a healthy run. If `freeze_latch>0` the
   watchdog caught a stall and reverted to single-OVL **without a reboot** —
   capture the kernel log around that moment for the iteration.

5. **A/B toggle**: `setprop persist.forge.m2note.multi_ovl 0` + `stop;start`
   returns to the single-OVL baseline without unmounting — confirms the flag
   gates cleanly and the fallback path is intact.

6. **Un-stage**: `umount /vendor/lib64/hw/hwcomposer.mt6753.so`; `stop;start`.

Report back: SurfaceFlinger `Comp Type` per layer, gfxinfo before/after, the
HWC `multi_ovl: present/fail/last_layers/freeze_latch` + `overlay: failed`
counters, and any kernel-log OVL lines.

---

## 6. Open RE unknowns

- **U1 (blend coefficients) — RESOLVED (FACT).** Confirmed by ghidra of the
  stock blob `vendor/meizu/m2note/proprietary/lib/hw/hwcomposer.mt6753.so`
  (32-bit, 173480 B, sha1 `9fd73d0a90e336f1ed1fa0d55df9ba053ffcc0c4`).
  `DispDevice::updateOverlayInputs` @ `0x28b78` builds `disp_input_config`
  (stride `0x84`; field offset = store offset − `0x18`). The alpha block:
  `if (blending==0x105) { config.sur_aen=1; config.src_alpha=0; config.dst_alpha=2; }
  else { config.sur_aen=0; }` — i.e. PREMULT → per-pixel source-over
  (`src_alpha=ONE`, `dst_alpha=SRC_INVERT`); everything else per-pixel OFF. This
  matches the §3.2 mapping exactly; `fill_layer_alpha` now cites it as FACT and
  COVERAGE is excluded from eligibility (stock does not per-pixel-blend it). The
  same decompile also confirmed src/dst rects (`right-left`), `src_pitch` as a
  pixel stride, the ION/MVA/dim `buffer_source` selection, and the
  secure/protect `security` mapping — all consistent with this module.
- **U2 (per-layer stride source).** Using `gralloc_extra_query(GET_STRIDE)`. If
  R7 bites, the fallback is the MTK private-handle int layout — not yet mapped.

---

## 7. Change log

- v462 (ROM tree branch `arm64-treble`, commit subject "m2note HWC v462: draft
  true DDP multi-OVL hardware composition (60fps)"): first multi-OVL
  implementation, bottom-band offload, behind `persist.forge.m2note.multi_ovl`
  (default off), latched fallback to the single-OVL path. See the `MULTI-OVL`
  blocks in `hwcomposer.cpp`.
- v462b (same file, follow-up commit): freeze watchdog (§3.6) — canary-validate
  the first frames + independent watchdog thread that reverts to single-OVL on a
  silent present freeze **with no reboot required**; multi-OVL refuses to arm
  without the watchdog. Added at the orchestrator's request because the user
  cannot cold power-cycle. `freeze_latch` counter added to `hwc_dump`. Verified
  host-side (`clang++ -std=gnu++14 -Wall -Werror -fsyntax-only` against the real
  ROM headers, 0 warnings); not yet built or device-tested — awaiting the
  orchestrator's bind-mount run (§5).
- v462d (partition cross-check + bandwidth knob): ghidra confirmed no fixed
  FB_TARGET slot and that stock uses a per-layer dispatcher (our bottom-band is
  a correct subset). Discovered the OVL bandwidth/overlap ceiling
  (`getBandwidthLimit`, `ovl_overlap_limit`) → added the runtime
  `persist.forge.m2note.multi_ovl_max` cap (default 3) so underflow can be tuned
  live in the A/B without a rebuild. See §3.7 / risk R9.
- v462c (blend coeffs confirmed): ghidra of the stock 32-bit blob resolved U1 —
  the PREMULT source-over selectors (`sur_aen=1, src_alpha=ONE,
  dst_alpha=SRC_INVERT`) match; COVERAGE dropped from eligibility to mirror
  stock. `fill_layer_alpha` + §3.2/§3.4/§6 updated to FACT. No behavioural
  change for the common (PREMULT/NONE) home-screen layers.
- v849-v855 (live device proof): allowed axis-preserving `ROT_180`, normalized
  the Oreo HWC2On1Adapter `planeAlpha==0` bridge quirk for visible NONE/PREMULT
  layers, skipped the unsafe fb0 memcpy fallback after a transient bad overlay
  frame, switched multi-layer retire to the primary present fence
  (`GET_PRESENT_FENCE` + `present_fence_idx`), and made multi-OVL default-on
  with `multi_ovl_max=2`. v854/v855 proved two app Overlay layers plus
  FB_TARGET on 810BBMM22D7S without `fail` or `freeze_latch`.

---

## LIVE RESULT (2026-07-02/03, v849-v855 on 810BBMM22D7S) — ENGAGES, STABLE, NOT YET TRUE 60 FPS

The earlier A/B below is superseded for the root cause: multi-OVL is no longer
blocked by `ro.sf.hwrotation=180`. The source HWC now accepts axis-preserving
`ROT_180` and programs `layer_rotation` per offloaded app layer.

Accepted live build sequence:

- v849 first enabled `ROT_180`, but exposed an old fallback bug during composer
  restart: bad/stale FB_TARGET fd could fall through to CPU `fb0_present()`,
  crashing composer in `memcpy`. v850 skips that unsafe fb0 memcpy fallback for
  a single bad overlay frame while the overlay session is alive.
- v852 proved the first real Overlay layer after normalizing the adapter's
  `planeAlpha==0` quirk, but using the FB_TARGET release fence as display retire
  tripped the canary (`multi_present=1 fail=1 freeze_latch=1`).
- v853 fixed retire fencing by requesting the primary present fence and passing
  its index to `TRIGGER_SESSION`; cap=1 then held stable (`present=599 fail=0`).
- v854 widened the alpha normalization to PREMULT and used cap=2. SurfaceFlinger
  reported two app layers as `Overlay`, one layer in `Framebuffer`, and
  `FramebufferTarget`; HWC dump showed `multi_ovl: present=511 fail=0
  last_layers=2 max=2 freeze_latch=0`.
- v855 made the accepted settings the default and live-pushed
  `/vendor/lib64/hw/hwcomposer.mt6753.so` SHA
  `e0a69aa7c0ea3d589023998dfb1d58bfb91af2abbf35b81d99dc472317c60c1a`.
  With default props only, HWC dump showed `multi_ovl=1`, `max=2`,
  `present=135 fail=0 last_layers=2 freeze_latch=0`.

Important live-push caveat:
- Several composer tombstones from the v849-v855 window are attributed to
  overwriting `/vendor/lib64/hw/hwcomposer.mt6753.so` while the old
  `android.hardware.graphics.composer@2.1-service` process still mmap'ed it.
  The last one (`tombstone_13`) dies in `hwc_vsync_thread` with `pc=0xca0`,
  matching the shared object's PLT resolver offset, not a source line in the
  multi-OVL present path. Treat these as unsafe module replacement artifacts.
  For future HWC live tests, stop `hwcomposer-2-1` before replacing the target
  `.so`, or install through a fresh image/atomic staging; do not infer a
  multi-OVL runtime crash from those tombstones alone.

Performance is improved architecturally but not finished: Trebuchet swipes at
cap=2 still measured about 90% janky frames with p50 18 ms / p90 24 ms. The
next display work is therefore tuning the remaining GPU/HWC split, bandwidth
cap, animation workload, and any clock/composition policy issues, not reviving
the already-superseded "multi-OVL cannot engage because of ROT_180" theory.

## SUPERSEDED FIRST A/B (2026-07-02, orchestrator on 810BBMM22D7S) — SAFE but DID NOT ENGAGE

This section is retained as provenance for the original failure. Its root-cause
conclusion was correct for that source revision, but v849-v855 above fixed it by
allowing and programming axis-preserving `ROT_180` in the OVL path.

Built `mka hwcomposer.mt6753` (source, 23832B, strings confirm multi_ovl/v462),
bind-mounted, `persist.forge.m2note.multi_ovl=1`, `stop;start`, measured on a real
unlocked launcher (SearchLauncher, 233 frames driven by swipes). Ran twice.

**SAFETY = PROVEN.** No wedge either run: SF returned ~3–6s after every stop;start,
the host deadman never fired, `freeze_latch=0`, `failed=0`, no kernel OOPS/OVL
errors, byte-clean revert to the prebuilt. The guarded design works.

**BUT multi-OVL never engaged:** `multi_ovl: present=0 fail=0 last_layers=0` on
every frame; all 3 HWC layers stayed `Comp Type = Client`; jank unchanged
(p50 61ms, 100% janky).

**ROOT CAUSE (FACT):** `ro.sf.hwrotation=180` makes SurfaceFlinger set
`mCurrentTransform=0x3` (HAL_TRANSFORM_ROT_180) on **every** layer (confirmed in
dumpsys SurfaceFlinger: ImageWallpaper/SearchLauncher/StatusBar all
mCurrentTransform=0x3; SF matrix `[[-1,0,1080][0,-1,1920]]`). The eligibility gate
`layer_reject_reason()` line 690 `if (l->transform != 0) return "transform!=0"`
therefore rejects ALL layers → bottom-band selects nothing (band stops at the
first ineligible bottom layer, which is always the wallpaper) → 0 offload.

This is why the GLES/single-OVL path "works": GLES bakes the 180° into the FBT.
Hardware multi-OVL must rotate each offloaded layer itself.

**FIX for next round (hwc agent):** teach the OVL path the 180° rotation, one of:
  (a) allow OVL-supported pure rotations (0/90/180/270) in eligibility + program
      the OVL `DISP_REG_OVL_Ln_CON[8:9]` rotation field from l->transform +
      transform the src/dst geometry for the rotation (delicate — flipped coords);
  or (b) set a SESSION/output-level 180° rotation on the DDP so app layers can be
      offloaded unrotated and the display rotates the composited output (cleaner
      if mtk_disp_mgr exposes an output rotation; needs RE of the session mode).
Since every layer carries the identical ROT_180, option (b) is likely simplest.
Until then multi-OVL is inert on this device (safe, but no 60fps win).

## SUPERSEDED USER INSIGHT (2026-07-02) — kernel-panel 180° rotation alternative

The root cause above (every layer gets transform=ROT_180 from ro.sf.hwrotation=180,
which the OVL eligibility rejects) has a cleaner fix than teaching the OVL to rotate:
**do the 180° in the kernel LCM/DSI panel driver instead of at the SF/hwrotation
level.** Then SurfaceFlinger composites in native orientation → every layer
transform=0 → all layers become OVL-eligible → multi-OVL engages → 60fps, with the
panel driver handling the physical 180° flip. The user reports two other Meizu
devices did exactly this. This is a KERNEL change (panel init / MADCTL / DDP output
rotation) + REMOVING ro.sf.hwrotation=180 from system.prop; boot-critical (verify
orientation + touch mapping on a bind-mount/careful test). Preferred over the
in-HWC OVL-rotation path. Owner: kernel side (panel driver) + this HWC path becomes
trivially engaged once layers are transform=0.

Superseded by v849-v855: the HWC path now handles `ROT_180` directly and proved
real overlay on the live device. Do not move panel rotation into the kernel as a
lag fix unless a new visual/perf investigation proves the HWC rotation path is
itself the bottleneck.
