#!/bin/sh
# Verify the prebuilt against the supplied MD5/VERSION expectations.
# Success is silent; stdout on mismatch makes BoardConfig reject the input.
# Usage: check_prebuilt_kernel.sh IMAGE EXPECTATIONS

set -u
IMG=$1
EXP=$2

# Подробности идут в stderr — make их не схлопывает, они видны в логе как
# есть, с переносами.  В stdout уходит короткий маркер, по которому
# BoardConfig валит сборку через $(error).
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
    try:
        raw = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(d[i:])
    except Exception:
        pass
m = re.search(rb'Linux version [0-9][^\x00]{0,120}', raw)
print(m.group(0).decode('utf-8', 'replace') if m else 'версию извлечь не удалось')
PY
)

cat >&2 <<MSG
ЯДРО В prebuilt-lane УСТАРЕЛО ИЛИ ПОДМЕНЕНО.
  файл:    $IMG
  ожидаем: $want_md5
           $want_ver
  найдено: $have_md5
           $have_ver
Что делать (m2note): ядро собирается из /srv/forge/android/m2note/kernel-m2note-3.18-adapt
(m2note_defconfig) в Image.gz-dtb со стоковым DTB m2note (md5 8b477a6c…);
положить сюда и обновить $EXP.  Приклеенный DTB проверяет
tools/check_appended_dtb.sh.

ГРАНИЦА ЭТОГО ГЕЙТА: он не проверяет, что prebuilt АКТУАЛЕН.  Совпадение
md5 означает лишь «образ соответствует дереву»; отстало ли само дерево от
рабочего ядра — вопрос отдельный, и зелёный ответ на него не отвечает.
MSG
echo "prebuilt-kernel: ядро не совпадает с ожидаемым ($have_md5 вместо $want_md5), см. подробности выше"
