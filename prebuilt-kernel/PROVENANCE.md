# prebuilt-kernel/Image.gz-dtb — Meizu M2 Note (m2note, M571)

## READ THIS FIRST

**Android 13 will not start on this kernel.** It is here so the device tree is
complete and buildable, and so the next agent has the exact artifact that last
ran on this handset. It is *not* the runtime this port will ship. See §3.

## 1. What it is (FACT)

Extracted from the boot partition image of the last recorded session in which
this handset reached `sys.boot_completed=1`.

| field | value |
|---|---|
| source boot.img | `/srv/forge/android/export/m2note_flash_captures/runtime/v181_15.1_v178_regdump_20260618-121109/boot-after-v181-v178-readback-p9-16m.img` |
| kernel blob offset | 2048 (page size), length 7 654 977 B |
| md5 | `c98b27fec7f9452420f15bab39973ea1` |
| sha256 | `87f5ec53f1bd49cee96a7cdf0cfab25fc0f6e663d56f2e0b9fa95361a07f4080` |
| version | `Linux version 3.18.19+ (n8n@n8nagent) (gcc version 4.9 20150123 (prerelease) (GCC) ) #108 SMP PREEMPT Thu Jun 18 11:02:00 CDT 2026` |
| appended DTB | offset 7 587 015, 67 962 B, md5 `8b477a6c3c16eb6ea20288de272cd10c`, sha256 `33a8779d0dd68e134b19ac4ff922c4b6d5e219e677087c5ad8885490653bc980` |
| DTB eMMC key | `mt6753-mmc` × 2, `mediatek,msdc\0` × 0 — correct compatible for this driver |

## 2. Why this image and not another (FACT)

The capture directory records a four-way sha256 identity for the source image:

```
9b25c1e09b635483616f8dfb525a85517ade02a2ed1fc3860593f1ccc1e27a3f
  /sdcard/m2note_rescue/m2note-boot-v178-pmic-rail-trace-15.1.img   (host-built)
  /dev/block/mmcblk0p9                                              (device, after flash)
  .../artifacts/v178_3.18_pmic_rail_trace_20260618-104508/m2note-boot-v178-pmic-rail-trace-15.1.img
  .../runtime/v181_.../boot-after-v181-v178-readback-p9-16m.img     (readback)
```

(`recovery-device-boot-p9-sha256.txt` + `host-v178-readback-sha256.txt` +
`SHA256SUMS`, all re-verified on 2026-09-16 with `sha256sum`.)

And the same directory's `android-identity-boot-completed.txt` records, from
that boot:

```
8.1.0
15.1-UNOFFICIAL-m2note
1                      <- sys.boot_completed
ok
Linux localhost 3.18.19+ #108 SMP PREEMPT Thu Jun 18 11:02:00 CDT 2026 aarch64
```

So: host artifact == flashed partition == readback, and that exact kernel
booted to `boot_completed`. That chain is the reason this image was chosen over
`/home/n8n/m2note_backups/boot_backup.img` (2026-07-01), whose gzip stream
fails to decompress past 64 KiB and which is therefore not trustworthy, and
over the later captures (v194 ran #109, v207–v214 contain no boot image at all).

## 3. Why Android 13 will not boot on it (FACT, then INFERENCE)

**FACT.** The config this kernel line is built from
(`/home/n8n/m5s_out/m2note_check/.config`, a regression build of
`m2note_defconfig` from the shared 3.18 tree) contains:

```
CONFIG_BPF=y
# CONFIG_BPF_SYSCALL is not set
# CONFIG_NET_CLS_BPF is not set
# CONFIG_NETFILTER_XT_MATCH_BPF is not set
```

**FACT.** `CONFIG_CGROUP_BPF` does not exist as a symbol in this kernel at all:
`grep -n 'CGROUP_BPF' /srv/forge/android/m2note/kernel-m2note-3.18-adapt/init/Kconfig`
returns nothing, while `config BPF_SYSCALL` is at `init/Kconfig:1529`.
(For contrast, the 4.9 tree used for the m5s has `config CGROUP_BPF` at
`init/Kconfig:1281`.) The cgroup-BPF attach point was added upstream in 4.10.

**INFERENCE (direct, not speculative).** Android 13's `netd` starts
`bpfloader`, which mounts `/sys/fs/bpf`, loads its programs with `bpf(2)` and
attaches them with `BPF_CGROUP_INET_*`. Without `BPF_SYSCALL` there is no
syscall; without `CGROUP_BPF` there is no attach point. `bpfloader` fails,
`netd` does not come up, and nothing past `post-fs-data` runs. This cannot be
worked around by a device tree.

**Therefore:** m2note on Android 13 is gated on the same 3.18 → 4.9 port the
m5s already has. That is the "Фронт C, после m5s" item — the C1 checklist
(stock DTB, SIP table, msdc naming, DRAM windows, expdb, mt_gpt, 8 cores,
PMIC) is already codified from the m5c and m5s work and is what has to be
replayed here with m2note's own addresses.

## 4. What this tree IS good for today

* It is a complete, parsing LineageOS 20 device tree, so the A13 side of the
  port can be worked on (blobs, fstab, VINTF, overlays, size) while the kernel
  lane runs separately.
* Every partition number, size and address in it is a live measurement of THIS
  handset, not a guess copied from a sibling.
* The moment a 4.9 kernel for m2note exists, only three things change:
  this file, `EXPECTED.txt`, and `prebuilt-kernel/Image.gz-dtb`.
