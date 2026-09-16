#!/bin/sh
# check_prebuilt_kernel.sh — гейт свежести prebuilt-ядра m2note, вызывается из
# BoardConfig.mk.  Печатает НИЧЕГО при успехе; при несовпадении печатает
# указание в stderr и короткий маркер в stdout, по которому BoardConfig валит
# сборку через $(error).
#
# Зачем: ядро попадает в образ через TARGET_PREBUILT_KERNEL, кладётся в дерево
# РУКАМИ и молча устаревает.  На m5c это уже случилось: 2026-09-03 в дереве
# лежало ядро от 28 августа, и чистая сборка отгрузила бы ROM без единой
# правки того дня.  Ядро не входит ни в /system, ни в /vendor, поэтому никакой
# инвентарь образов этого не ловит.
#
# ГРАНИЦА ГЕЙТА, названная явно: он проверяет СООТВЕТСТВИЕ образа дереву, а НЕ
# актуальность дерева.  Зелёный ответ означает «образ совпадает с тем, что в
# дереве записано», а не «в дереве лежит нужное ядро».
#
#   $1 — путь к Image.gz-dtb
#   $2 — путь к файлу ожиданий (MD5 / VERSION)
set -u
IMG=$1
EXP=$2

[ -f "$IMG" ] || { echo "ЯДРО НЕ НАЙДЕНО: $IMG" >&2; echo "prebuilt-kernel: ЯДРА НЕТ, см. подробности выше"; exit 0; }
[ -f "$EXP" ] || { echo "НЕТ ФАЙЛА ОЖИДАНИЙ: $EXP" >&2; echo "prebuilt-kernel: НЕТ ФАЙЛА ОЖИДАНИЙ, см. подробности выше"; exit 0; }

want_md5=$(awk '$1=="MD5"{print $2}' "$EXP")
have_md5=$(md5sum "$IMG" | cut -d' ' -f1)
[ "$want_md5" = "$have_md5" ] && exit 0

want_ver=$(sed -n 's/^VERSION //p' "$EXP")
have_ver=$(python3 - "$IMG" <<'PY' 2>/dev/null
import sys, zlib, re
d = open(sys.argv[1], 'rb').read()
i = d.find(b'\x1f\x8b\x08')
raw = b''
if i >= 0:
    o = zlib.decompressobj(16 + zlib.MAX_WBITS)
    try:
        for off in range(i, len(d), 1 << 16):
            raw += o.decompress(d[off:off + (1 << 16)])
            if o.eof:
                break
    except Exception:
        pass
m = re.search(rb'Linux version [0-9][^\x00\n]{0,140}', raw)
print(m.group(0).decode('utf-8', 'replace') if m else 'версию извлечь не удалось')
PY
)

cat >&2 <<MSG
ЯДРО В prebuilt-lane m2note УСТАРЕЛО ИЛИ ПОДМЕНЕНО.
  файл:    $IMG
  ожидаем: $want_md5
           $want_ver
  найдено: $have_md5
           $have_ver
Что делать: НЕ пересобирать вслепую.  Прибилт здесь — не «текущая сборка», а
единственный артефакт 3.18, про который зафиксировано, что он довёл аппарат до
sys.boot_completed (цепочка sha256 в prebuilt-kernel/PROVENANCE.md).  Если он
не совпал, значит кто-то положил сюда другой файл.  Варианты:
  * вернуть исходный: вырезать ядро из
    export/m2note_flash_captures/runtime/v181_15.1_v178_regdump_20260618-121109/
    boot-after-v181-v178-readback-p9-16m.img (страница 2048, длина из заголовка);
  * если это ОСОЗНАННАЯ замена на 4.9 — обновить EXPECTED.txt, PROVENANCE.md и
    отчёт meizu-fleet/trees/M2NOTE_LOS20_TREE.md одним коммитом.
Напоминание: на 3.18 Android 13 не стартует вовсе (нет BPF_SYSCALL и нет
символа CGROUP_BPF) — см. PROVENANCE.md §3.

ГРАНИЦА ЭТОГО ГЕЙТА: он не проверяет, что prebuilt АКТУАЛЕН.  Совпадение md5
означает лишь «образ соответствует дереву».
MSG
echo "prebuilt-kernel: ядро не совпадает с ожидаемым ($have_md5 вместо $want_md5), см. подробности выше"
