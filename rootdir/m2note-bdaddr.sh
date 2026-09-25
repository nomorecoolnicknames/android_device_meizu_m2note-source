#!/vendor/bin/sh
# Publish the factory Bluetooth address from MTK NVRAM as a system property.
# Port of device/meizu/m95/rootdir/m95-bdaddr.sh (rationale there and in
# forge-bluetooth.rc), via the m5c copy.  Source record:
# /data/nvram/APCFG/APRDEB/BT_Addr, ap_nvram_btradio_struct, addr[6] first —
# the layout proven on the m5c.  The m2note libnvram names the same record
# (FACT: strings vendor/lib/libnvram.so); its content on an m2note was never read.

set -u

NV=/data/nvram/APCFG/APRDEB/BT_Addr

[ -r "$NV" ] || exit 0

# Already published (persist properties survive reboots) - leave it alone.
case "$(getprop persist.service.bdroid.bdaddr)" in
    ??:??:??:??:??:??) exit 0 ;;
esac

addr=$(od -An -tx1 -N6 "$NV" 2>/dev/null | tr -d ' \n' | tr 'a-f' 'A-F')

case "$addr" in
    ????????????) ;;
    *) exit 0 ;;
esac
[ "$addr" = "000000000000" ] && exit 0
[ "$addr" = "FFFFFFFFFFFF" ] && exit 0

formatted=$(echo "$addr" | sed 's/../&:/g; s/:$//')
setprop persist.service.bdroid.bdaddr "$formatted"

exit 0
