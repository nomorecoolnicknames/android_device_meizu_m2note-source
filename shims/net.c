/* libmtkshim_net — ifc_ipv6_trigger_rs for the MTK RIL blobs.
 *
 * FACT (differential 2026-07-27, tools/blob-symdiff.py against the built ROM):
 * mtk-ril.so and mtk-rilmd2.so (both 32- and 64-bit) each have exactly ONE
 * unresolved symbol, ifc_ipv6_trigger_rs. It is an MTK addition to Nougat's
 * libnetutils; AOSP never had it, in any release.
 *
 * Semantics (INFERENCE from the name, the single `const char *ifname`
 * argument, and MTK's use of it on data-call bring-up): send an ICMPv6 Router
 * Solicitation on the named interface so SLAAC does not wait for the next
 * unsolicited Router Advertisement. Implemented for real rather than stubbed
 * to 0 — a no-op would link but silently slow or break IPv6 address
 * acquisition on mobile data, and that failure is much harder to diagnose
 * later than this function is to write.
 *
 * rild holds CAP_NET_RAW, so the raw ICMPv6 socket is permitted. The kernel
 * computes the ICMPv6 checksum itself for IPPROTO_ICMPV6 raw sockets
 * (required by RFC 3542 section 3.1), so the bare header below goes out valid.
 *
 * NOT VERIFIED on hardware: the ROM has never booted, so this has never sent a
 * packet. The signature is inferred, not read from an MTK header.
 *
 * Deliberately NOT included (the first draft of this file had them):
 *  - socket_loopback_client: only libviatelecom-withuim-ril.so wants it, a VIA
 *    CDMA modem lib irrelevant to this device's radio.
 *  - android_fork_execvp_ext: only libwo.so (China Unicom) wants it, and that
 *    blob is unloadable regardless — liblogwrap.so, one of its DT_NEEDED
 *    entries, does not exist on the image at all (see BLOB_SHIMS.md, "missing
 *    DT_NEEDED"). A forwarder that dlopen()s a library which is not there
 *    cannot work, so shipping one would be theatre.
 */
#include <arpa/inet.h>
#include <net/if.h>
#include <netinet/icmp6.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

int ifc_ipv6_trigger_rs(const char *ifname) {
    struct icmp6_hdr rs;
    struct sockaddr_in6 dst;
    int s, hops = 255, ret = -1;

    if (ifname == NULL)
        return -1;

    memset(&rs, 0, sizeof(rs));
    rs.icmp6_type = ND_ROUTER_SOLICIT;

    memset(&dst, 0, sizeof(dst));
    dst.sin6_family = AF_INET6;
    inet_pton(AF_INET6, "ff02::2", &dst.sin6_addr); /* all-routers */
    dst.sin6_scope_id = if_nametoindex(ifname);
    if (dst.sin6_scope_id == 0)
        return -1;

    s = socket(AF_INET6, SOCK_RAW | SOCK_CLOEXEC, IPPROTO_ICMPV6);
    if (s < 0)
        return -1;

    /* RFC 4861 section 4.1: an RS must be sent with hop limit 255, and the
     * receiver must discard it otherwise. */
    setsockopt(s, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, &hops, sizeof(hops));
    setsockopt(s, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &hops, sizeof(hops));

    if (sendto(s, &rs, sizeof(rs), 0, (struct sockaddr *)&dst,
               sizeof(dst)) == (ssize_t)sizeof(rs))
        ret = 0;

    close(s);
    return ret;
}
