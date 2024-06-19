source functions.sh

echo "
        Config /etc/resolv.conf
        Config /etc/hosts
        Start proxy server ...
 ================================="
echo nameserver $PRIVATE_LAN_DNS > /etc/resolv.conf
echo nameserver 1.1.1.1 >> /etc/resolv.conf
sh /append-etc-hosts.sh
privoxy /etc/privoxy/config

# template out all the config files using env vars
. /l2tp-ipsec.env
sed -i 's/right=.*/right='$VPN_SERVER_IP'/' /etc/ipsec.conf
echo ': PSK "'$VPN_IPSEC_PSK'"' > /etc/ipsec.secrets
sed -i 's/lns = .*/lns = '$VPN_SERVER_IP'/' /etc/xl2tpd/xl2tpd.conf
sed -i 's/name .*/name '$VPN_USER'/' /etc/ppp/options.l2tpd.client
sed -i 's/password .*/password '$VPN_PASSWORD'/' /etc/ppp/options.l2tpd.client

trap 'sigterm_handler' SIGTERM

while true
do
  if ping -c 1 -W 1 $PRIVATE_LAN_HEALTH_CHECK >/dev/null 2>&1; then
    snooze 3 &
    wait $!
  else
    if ! ping -c 1 -W 1 $PRIVATE_LAN_HEALTH_CHECK >/dev/null 2>&1 && ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
      echo "Internet access is available, but the VPN is not activated."
      break
    fi
  fi
done

vpn_connect # >/dev/null 2>&1
echo "VPN Connected:" $PPP_IF $PPP_IP

while true
do
  if vpn_healthy_check; then
    snooze 3 &
    wait $!
  else
    vpn_disconnect
    vpn_connect
  fi
done