# device/meizu/m2note — LineageOS 16.0 (Android 9), ветка `lineage-16.0`

Meizu M2 Note (M571, MT6753, 8×A53). Продукт `lineage_m2note` (`-userdebug`, `-eng`).
Метки — `/srv/forge/android/CLAUDE.md §2`. **Дерево не собиралось и не запускалось.**
Единственный из трёх A9-аппаратов с живой историей: LOS 15.1 доходил до `sys.boot_completed`.

## 1. Происхождение

| Что | Откуда (FACT) |
|---|---|
| Pie-обвязка (zygote в vendor-rc, RIL-рецепт, modem-rc, шимы, периферия) | `device/meizu/m5c` @`77e62e0` (первый коммит — снимок `git archive`), MT6753-решения — как в `a9-trees/m5s` |
| Разделы, геометрия, cmdline, экран | живые захваты 15.1 (`export/m2note_flash_captures/`), заголовок доказанного boot-образа (sha256 `9b25c1e0…3a3f`) |
| HWC, USB-rc, конфиги, keylayout | дерево и набор блобов LOS 15.1 m2note |
| Блобы | набор 15.1 (1110 файлов) → `a9-trees/m2note/vendor/meizu/m2note` (912 правил, генератор) |
| Ядро | prebuilt 3.18.19+ #108 (§3) |
| Платформа | состояние ганвеста `m6rom16` — `designs/a9-trees/gunwest-m6rom16-heads-20260925.txt` |

## 2. Чем m2note отличается от донора и от m5s

- **Ядро 3.18, не 4.9.** Поэтому HWC — **собственный source-HWC 1.1 из 15.1**, а не `forge_hwc`: UAPI
  `forge_hwc` (4.9) расходится с ядром m2note на 626 строк; `hwcomposer/disp_session.h` побайтно равен
  `kernel-m2note-3.18-adapt` `drivers/misc/mediatek/video/include/disp_session.h` (FACT, cmp).
- **USB — legacy-гаджет.** `m2note_defconfig`: `CONFIG_USB_G_ANDROID=y`, configfs нет (FACT). Взят
  собственный `init.mt6735.usb.rc` из набора 15.1 (FunctionFS для adb: `mount functionfs adb` +
  `f_ffs/aliases adb`); configfs-обвязка донора убрана.
- **Разделы m2note:** boot p9, recovery p10 (**20 МиБ**), para p8, expdb p12, custom p19 → `/vendor`, system
  p23 1536 МиБ, userdata p25. Номера в fstab не пишутся.
- **cmdline:** из доказанного образа, но **без `m2note.disable_md1=1`** — это cmdline-изоляция модема
  (коммит ядра `44275ddc`, `ccci_util_lib_fo.c:297-308`): доказанная загрузка шла **с выключенным MD1**.
  `firmware_class.path` → `/vendor/firmware` (реальный раздел).
- **vendor/mediatek включает для m2note всё** (`Android.mk` @`6dd7c54b`): дерево ничего оттуда не включает
  повторно и не определяет `lib_driver_cmd_mt66xx`. `m3_meizu_m6-common` для m2note пуст (все подкаталоги
  под `ifneq m2note`) — отсюда свой `libbt-vendor/` (исходник оттуда).
- **BT:** `libbluetoothdrv.so` есть в обеих ABI (FACT) → `libbt-vendor` в обеих ABI → штатный 64-битный
  сервис AOSP.
- **Шимы по readelf блобов m2note:** `__pthread_gettid` (5 потребителей), ICU `*_53` (mtk_agpsd + 3 медиа-
  библиотеки; Pie — ICU 60), камерные gui/ui. VoiceUnlock-аудио и `libfs_mgr.so` m2note не нужны.
- **RIL:** `librilmtk.so` m2note не экспортирует `IMS_isRilRequestFromIms`/`RIL_UpdateToVT` — безвредно,
  MTK libril определяет первую сам (`ril/libril/ril.cpp:1102-1110`), вторую не использует (FACT).
- **Гироскоп объявлен:** на живой 15.1 sensorservice его показывал (`M2NOTE_SUBSYSTEM_STATUS_2026-07-06.md:62`),
  стоковый `etc/permissions` тоже его объявлял. Отпечатка нет.
- **`libgralloc_extra.so` — блоб** (доказанно на 15.1, `device_m2note.mk:497-510`); HWC использует только
  `gralloc_extra_query`, блоб её экспортирует (FACT). На сборке ожидается одно «overriding commands».

## 3. Ядро

- `prebuilt-kernel/Image.gz-dtb`: `3.18.19+ #108 SMP PREEMPT Thu Jun 18 11:02:00 CDT 2026`, sha256
  `87f5ec53f1bd49cee96a7cdf0cfab25fc0f6e663d56f2e0b9fa95361a07f4080` = страницы `[2048, 2048+7654977)`
  доказанного образа (пересчитано 2026-09-25). Гейты `check_prebuilt_kernel.sh` и `check_appended_dtb.sh`
  (DTB md5 `8b477a6c…`, `mt6753-mmc=2`, `msdc=0`) — зелёные.
- Это отладочная сборка v178 («pmic rail trace»), последняя, что грузилась, — не релизное ядро.

## 4. Модем: пара образ/DSP (главная находка этого прохода)

- **FACT (strings):** `modem_1_lwg_n.img` = `MOLY.LR9.W1444.MD.LWTG.CMCC.MP.V9.P44`.
  Набор 15.1 несёт **два разных** `dsp_1_lwg_n.bin`: `etc/firmware/` = `DSPMOLY…CMCC.MP.V9.P44`
  (сток, 2018-03-05) и `firmware/` = `DSPMOLY…MP.V79.P26` (mtime 2026-05-17). То же — с
  `catcher_filter_1_lwg_n.bin` и `S_ANDRO_SFL.ini`.
- **INFERENCE:** на 15.1 ядро с `firmware_class.path=/system/vendor/firmware` брало `/vendor/firmware/` —
  то есть DSP V79.P26 к модему V9.P44.
- **HYPOTHESIS H-DSP:** «SIM ABSENT при живом модеме» на 15.1 (`M2NOTE_SUBSYSTEM_STATUS:60`) — следствие
  несовпадения DSP и модема. Опровержение: на A9 (здесь взята пара V9.P44) `gsm.sim.state` всё равно
  ABSENT при `mtk.md1.status=ready`. Дешёвая проверка без сборки: на 15.1 из recovery заменить
  `/vendor/firmware/dsp_1_lwg_n.bin` на V9.P44 (решение владельца — это запись в раздел).
- Раскладка `RIL_InitialAttachApn` у m2note — как у m5c (llvm-objdump, FACT) → нужен патч
  `meizu-fleet/patches/a9-los16/0001-…` (иначе SIGSEGV m5c после регистрации).

## 5. Статическая проверка (без сборки)

`meizu-fleet/tools/a9-static-check.py m2note`: 976 правил `PRODUCT_COPY_FILES` — все источники есть
(912 блобов, 37 в дереве, 27 в платформе на коммитах ганвеста); двойных назначений — 0 (два найденных —
seccomp-политика и `wpa_supplicant.conf` — сняты исключением блобов); 53/53 имён `PRODUCT_PACKAGES`
определены; строки fstab — по 5 полей; `.bp`-модулей в дереве нет. Не `m nothing`.

**Исправлено по ревью 2026-09-25** (независимый проход code-reviewer):
- fstab: при замене шапки осталась незакомментированная строка `…/by-name/<partition>` — fs_mgr счёл бы
  весь fstab пустым (`fs_mgr_fstab.cpp:582-584` @e7f32da), `mount_all` без /system. Удалена; в проверку
  добавлен разбор fstab.
- `vendor/mediatek`, включённый для m2note целиком, ссылается по имени модуля на блобы `libged`,
  `libion_mtk`, `libdpframework`; `core/main.mk:804-815` проверяет зависимости всех объявленных модулей →
  `m nothing` упал бы. Теперь это BUILD_PREBUILT-модули в `vendor/meizu/m2note` + PRODUCT_PACKAGES.
- шимы `libshim_vcodec_m2note`, `libshim_icu53_m2note` были спарены, но не ставились — добавлены в
  PRODUCT_PACKAGES (иначе потребитель шима не грузится: linker.cpp:1368-1371).
- возвращён `sys.usb.ffs.aio_compat=1` (adbd Pie использует AIO на FunctionFS; на 15.1 был Oreo-adbd без AIO).
- Оставлено как у донора: `forge-modem.rc` без `override` для nvram/ccci/muxreport/terservice (действуют
  рамдисковые определения); `vendor/mediatek/nfc` кладёт висячие симлинки в system — шум, не сбой.

## 6. HYPOTHESIS первого бута

| # | HYPOTHESIS | Проверка |
|---|---|---|
| H-USB | legacy-гаджет + FunctionFS из 15.1 поднимает adb на Pie | `adb devices`; иначе — `cat /sys/class/android_usb/android0/functions` из recovery-логов |
| H-ZYG | forge-zygote.rc m5c запускает zygote без first-stage mount и на 3.18 | `getprop init.svc.zygote`, `logcat -b all \| grep -i zygote` |
| H-HWC | source-HWC 15.1 работает под composer@2.1 Pie | SF «Boot is finished», нет tombstone в `hwcomposer.mt6753` |
| H-DSP | §4 | `getprop gsm.sim.state`, `gsm.version.baseband` |
| H-MUX | ожидание `mtk.md1.status=ready` вместо printk 4.9 не пропускает HS2 | `CMUX READY` в logcat, нет `ASSERT ERROR_CODE=8` |
| H-ICU | шим ICU 53 закрывает `mtk_agpsd` | `logcat \| grep -i "cannot locate symbol.*_53"` пуст, `init.svc.agpsd=running` |
| H-GPT | GPT m2note не менялся после 07-03 (`SUBSYSTEM_STATUS:69` говорит о переразметке под GSI) | `cat /proc/partitions`, `sgdisk -p /dev/block/mmcblk0` из recovery — ДО прошивки |

## 7. Проверки перед и после первой загрузки

```sh
# ДО прошивки (из recovery, только чтение): разметка и бэкап NV (IMEI!)
adb shell 'cat /proc/partitions; ls -l /dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/'
# бэкап nvram/nvdata/proinfo/protect1/protect2 + boot/recovery — процедура m95 (BS:863-867)
# ПОСЛЕ
adb shell 'getprop ro.build.display.id; uname -a; cat /proc/uptime; getprop sys.boot_completed'
adb shell 'mount | grep -E " /(system|vendor|data) "; getprop init.svc.zygote'
adb logcat -b crash -d | head -50
adb logcat -d | grep -E "cannot locate symbol|library .* not found|dlopen failed" | sort | uniq -c | sort -rn | head
adb shell 'getprop mtk.md1.status; getprop gsm.sim.state; getprop gsm.version.baseband'
# посмертно: expdb = p12 на m2note (НЕ p10), skill mtklogs
```

## 8. Сознательно не сделано

- Острова 15.1 `light/`, `power/` (power.mt6753), `usb/`, `gatekeeper/`, `camera_compat/`, `mtk/` (камерный
  D1) не перенесены — только HWC. Возвращать по одному, с уликой.
- rc 15.1 из `vendor/etc/init/*.rc` не ставятся — сервисы определяет rc дерева.
- sepolicy — как у донора (permissive, `SELINUX_IGNORE_NEVERALLOWS`).
- Символьное замыкание против Pie не мерилось (нужен out-каталог).
