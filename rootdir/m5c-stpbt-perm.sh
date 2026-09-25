#!/vendor/bin/sh
# forge m5c (bt-stp, 2026-09-03): hand /dev/stpbt to the Bluetooth HAL user.
#
# The node does not exist when `on post-fs-data` runs: it is created only when
# wmt_loader initialises the connectivity drivers, and wmtLoader is `class core`
# (init.rc:677, inside `on boot`) while post-fs-data is init.rc:389.  The ramdisk
# ueventd rule asks for group `net_bt_stack`, an AID that does not exist on Pie,
# so ueventd leaves the node root:root 0600 and the HAL (user bluetooth) cannot
# open it -> BT crash-loops.  Waiting here is deliberate: `on property:
# init.svc.wmtLoader=stopped` can still race ueventd's asynchronous node
# creation, and `sys.boot_completed` is NOT reliable on this build (observed
# empty on the 14:10 boot with the framework up).  The permanent fix is the
# tree's ueventd.mt6735.rc (`bluetooth bluetooth`), which needs a new boot.img.
i=0
while [ "$i" -lt 60 ]; do
    if [ -c /dev/stpbt ]; then
        chown bluetooth:bluetooth /dev/stpbt
        chmod 0660 /dev/stpbt
        echo "forge-stpbt-perm: /dev/stpbt -> bluetooth:bluetooth 0660 after ${i}s" > /dev/kmsg
        exit 0
    fi
    sleep 1
    i=$((i + 1))
done
echo "forge-stpbt-perm: /dev/stpbt never appeared after ${i}s" > /dev/kmsg
exit 1
