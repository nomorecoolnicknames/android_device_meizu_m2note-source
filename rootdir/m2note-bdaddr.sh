#!/system/bin/sh
# Publish the factory Bluetooth address from MTK NVRAM as a system property.
#
# WHY THIS IS NEEDED (ported from device/meizu/m95/rootdir/m95-bdaddr.sh,
# lesson of 2026-09-24, device/meizu/m95 15d2dc9)
#
# The Bluetooth HAL of this tree is the AOSP one (device.mk:
# android.hardware.bluetooth@1.1-service over @1.0-impl).  It gets the local
# address from BluetoothAddress::get_local_address(), which tries exactly
# three sources in order (hardware/interfaces/bluetooth/1.0/default/
# bluetooth_address.{h,cc}):
#
#   1. the file named by  ro.bt.bdaddr_path       - as ASCII "XX:XX:..."
#   2. the property       ro.boot.btmacaddr
#   3. the property       persist.service.bdroid.bdaddr
#
# and if all three fail VendorInterface::Open() does LOG_ALWAYS_FATAL("No
# Bluetooth Address!") (vendor_interface.cc:217; the 1.1 service reaches it
# through 1.1/default/bluetooth_hci.cc:70).  None of the three is set in this
# tree (FACT, grep over device/meizu/m2note and vendor/meizu/m2note/*.mk,
# 2026-09-24) - the Flyme stack read NVRAM directly, so it never needed them.
#
# The address is in NVRAM: /data/nvram/APCFG/APRDEB/BT_Addr (FACT, strings of
# vendor/meizu/m2note/proprietary/vendor/lib64/libcustom_nvram.so),
# the MTK ap_nvram_btradio_struct record whose first member is addr[6].  On
# m95 those six bytes are the factory address in natural byte order
# (<factory-address-redacted>, verified on the unit).  HYPOTHESIS for this device: same
# record layout and byte order.  Check on the first boot:
# `od -An -tx1 -N6 /data/nvram/APCFG/APRDEB/BT_Addr` against the address on
# the box / in stock Flyme settings.
#
# So the only thing missing is publishing it. Reading NVRAM and setting
# persist.service.bdroid.bdaddr is the least invasive of the three routes: it
# needs no new file in a fixed format and no change to the HAL.
#
# Ordering: started from init.m2note.nvram.rc on service.nvram_init=Ready,
# i.e. only after nvram_daemon has restored BT_Addr (on m95 an earlier trigger
# ran before NVRAM on a fresh /data, exited on the missing file, and the HAL
# aborted).

set -u

NV=/data/nvram/APCFG/APRDEB/BT_Addr

[ -r "$NV" ] || exit 0

# Already published (persist properties survive reboots) - leave it alone so a
# user-set or framework-set address is not overwritten on every boot.
case "$(getprop persist.service.bdroid.bdaddr)" in
    ??:??:??:??:??:??) exit 0 ;;
esac

addr=$(od -An -tx1 -N6 "$NV" 2>/dev/null | tr -d ' \n' | tr 'a-f' 'A-F')

# Six bytes, twelve hex digits, and not one of the two degenerate addresses
# NVRAM shows when it has never been provisioned.
case "$addr" in
    ????????????) ;;
    *) exit 0 ;;
esac
[ "$addr" = "000000000000" ] && exit 0
[ "$addr" = "FFFFFFFFFFFF" ] && exit 0

formatted=$(echo "$addr" | sed 's/../&:/g; s/:$//')
setprop persist.service.bdroid.bdaddr "$formatted"

exit 0
