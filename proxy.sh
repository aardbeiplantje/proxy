#!/bin/sh
cfg_file=${SQUID_CONFIG_FILE:-/etc/squid/squid.conf}
daemon_opts=${SQUID_DAEMON_OPTS:-}
sh /speed.sh "${TC_HTB_RATE:-10Mbit}"
gw_ip=$(ip r|awk '/default via / {print $3}')
echo "default gw: $gw_ip"
sed -i "s/\[OUT\]/$gw_ip/g" $cfg_file
sudo -u squid bash -c "
 squid -f $cfg_file -k parse     || exit \$?
 squid -z -N -F -S -f $cfg_file  || exit \$?
"
exec /usr/sbin/squid --foreground -f $cfg_file $daemon_opts
