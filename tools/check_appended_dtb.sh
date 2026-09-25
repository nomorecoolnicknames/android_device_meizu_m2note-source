# check_appended_dtb.sh — проверка приклеенного DTB в Image.gz-dtb m2note.
#
# Ключ различения для MT6753: узел eMMC обязан называться
# compatible = "mediatek,mt6753-mmc".  Имя "mediatek,msdc" означает, что DTB
# собран деревом, у которого этот узел не переименован — на таком образе
# аппарат не найдёт корневую ФС.
#
# ВАЖНОЕ ОТЛИЧИЕ ОТ m5c, чтобы правило не переносили вслепую.  На m5c действует
# жёсткое правило «только СТОКОВЫЙ DTB байт-в-байт», потому что DTS в его
# дереве пишет "mediatek,msdc", а драйвер ждёт "mediatek,mt6735m-mmc".
# На m2note такого расхождения НЕТ: FACT —
#   /srv/forge/android/m2note/kernel-m2note-3.18-adapt/arch/arm64/boot/dts/
#   mt6753.dtsi:37,45  ->  compatible = "mediatek,mt6753-mmc"
# то есть DTB, собранный этим деревом, уже несёт правильное имя, и именно
# такой DTB приклеен к образу, который довёл аппарат до boot_completed.
# Поэтому эталон здесь — DTB ИЗ ДОКАЗАННОГО ОБРАЗА, а не «стоковый».
#
# ВАЖНО: гейт осмыслен только на СЖАТОМ Image.gz-dtb.  На сыром
# arch/arm64/boot/Image строки msdc читаются из самого драйвера и вывод был бы
# ложным; поэтому не-gzip вход отвергается отдельным кодом 2.
#
#   ./check_appended_dtb.sh <Image.gz-dtb> [ожидаемый-md5-dtb]
#
# Без второго аргумента сверяет с DTB из образа v178
# (67 962 Б, md5 8b477a6c3c16eb6ea20288de272cd10c,
#  sha256 33a8779d0dd68e134b19ac4ff922c4b6d5e219e677087c5ad8885490653bc980).
set -u

STOCK_MD5=8b477a6c3c16eb6ea20288de272cd10c

IMG=${1:-}
WANT=${2:-$STOCK_MD5}

if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "usage: $0 <Image.gz-dtb> [expected-dtb-md5]" >&2
    exit 2
fi

python3 - "$IMG" "$WANT" <<'PY'
import hashlib, sys

img, want = sys.argv[1], sys.argv[2]
data = open(img, 'rb').read()
MAGIC = bytes.fromhex('d00dfeed')

if data[:2] != b'\x1f\x8b':
    print("НЕ ТОТ ВХОД: %s не начинается с gzip-сигнатуры 1f 8b." % img)
    print("Гейт применяется к Image.gz-dtb, а не к сырому Image и не к boot.img.")
    print("Для boot.img сначала достаньте ядро, потом проверяйте его.")
    sys.exit(2)

found = []
i = data.find(MAGIC)
while i != -1:
    total = int.from_bytes(data[i + 4:i + 8], 'big')
    version = int.from_bytes(data[i + 20:i + 24], 'big')
    if 1000 < total <= len(data) - i and 1 <= version <= 17:
        found.append((i, total))
    i = data.find(MAGIC, i + 1)

if not found:
    print("ОШИБКА: в %s нет приклеенного DTB (магии d00dfeed не найдено)" % img)
    sys.exit(1)

if len(found) > 1:
    print("ВНИМАНИЕ: найдено %d кандидатов DTB, проверяю первый" % len(found))

off, total = found[0]
blob = data[off:off + total]
got = hashlib.md5(blob).hexdigest()
print("образ  : %s (%d байт)" % (img, len(data)))
print("dtb    : off=%d size=%d" % (off, total))
print("md5    : %s" % got)
print("sha256 : %s" % hashlib.sha256(blob).hexdigest())
print("ожидаю : %s" % want)

stock_key = blob.count(b"mt6753-mmc")
built_key = blob.count(b"mediatek,msdc\x00")
print("ключ   : mt6753-mmc=%d  mediatek,msdc=%d" % (stock_key, built_key))
structural_ok = stock_key > 0 and built_key == 0

if got == want and structural_ok:
    print("OK — приклеен ожидаемый DTB m2note (из доказанного образа v178)")
    sys.exit(0)
if got == want and not structural_ok:
    print("ОТКАЗ — md5 совпал, но в DTB нет имени eMMC, которое ищет драйвер.")
    sys.exit(1)
if got != want and structural_ok:
    print("ВНИМАНИЕ — md5 не совпал, но структурно DTB стоковый.")
    print("Сверяйте вручную; сток мог законно смениться.")
    sys.exit(1)
print("ОТКАЗ — приклеен НЕ тот DTB, использовать НЕЛЬЗЯ")
print()
print("Починить, не пересобирая ядро:")
print("  cat <дерево>/arch/arm64/boot/Image.gz \\")
print("      <the DTB that shipped in the proven boot image> \\")
print("      > %s.STOCKDTB" % img)
sys.exit(1)
PY
