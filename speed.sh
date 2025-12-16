#!/bin/sh
ifs=${SQUID_IFNAME:-eth0 eth1}
rate_speed=${1:-10Mbit}
MARK_HEX=0x12321 # The mark set by Squid

set -x
for i in $ifs; do
    ifname=$i
    echo "BEFORE tc info: "
    tc -s -d qdisc show dev $ifname
    tc -s -d class show dev $ifname

    # Create the Hierarchical Token Bucket (CBQ) root qdisc
    tc qdisc del dev $ifname root 2>/dev/null
    tc qdisc add dev $ifname root handle 10: htb default 30

    # Add the Parent Class (10:1) with maximum rate
    tc class add dev $ifname parent 10: classid 10:1 htb \
        rate 100Mbit ceil 100Mbit

    # Add the Throttled Class (10:2) with the desired rate
    tc class add dev $ifname parent 10:1 classid 10:2 htb \
        rate $rate_speed
    # Add a Stochastic Fairness Queueing (SFQ) qdisc to the throttled class
    tc qdisc add dev $ifname parent 10:2 handle 2: sfq perturb 10

    # Add the 'fw' (Firewall Mark) Filter
    # It checks the Netfilter Mark (fwmark) on the packet.
    # It matches packets with $MARK_HEX
    tc filter add dev $ifname parent 10:0 protocol ip prio 1 \
        handle $MARK_HEX fw flowid 10:2

    echo "AFTER tc info: "
    tc -s -d qdisc show dev $ifname
    tc -s -d class show dev $ifname
done
