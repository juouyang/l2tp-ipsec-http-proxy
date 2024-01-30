#!/bin/bash

# 設置信號處理函數
sigterm_handler() {
  # 在這裡執行接收到 SIGTERM 信號時要執行的操作
  echo "Received SIGTERM. Cleaning up..."
  # 清理任務
  # ...
  echo "d myvpn" > /var/run/xl2tpd/l2tp-control
  ifconfig ppp0 down
  ipsec down myvpn

  # 結束腳本
  exit 0
}

# 設置 SIGTERM 信號處理器
trap 'sigterm_handler' SIGTERM

function snooze {
    sleep $1
}

. /l2tp-ipsec.env

# template out all the config files using env vars
sed -i 's/right=.*/right='$VPN_SERVER_IP'/' /etc/ipsec.conf
echo ': PSK "'$VPN_IPSEC_PSK'"' > /etc/ipsec.secrets
sed -i 's/lns = .*/lns = '$VPN_SERVER_IP'/' /etc/xl2tpd/xl2tpd.conf
sed -i 's/name .*/name '$VPN_USER'/' /etc/ppp/options.l2tpd.client
sed -i 's/password .*/password '$VPN_PASSWORD'/' /etc/ppp/options.l2tpd.client

echo "Start proxy server ..."
privoxy /etc/privoxy/config

echo "Config /etc/resolv.conf"
echo nameserver $PRIVATE_LAN_DNS > /etc/resolv.conf
echo nameserver 1.1.1.1 >> /etc/resolv.conf

echo "Config /etc/hosts"
sh /append-etc-hosts.sh

while true
do
  if ping -c 1 -W 1 $PRIVATE_LAN_DNS >/dev/null 2>&1; then
    snooze 3 &
    wait $!
  else
    if ping -c 10 -W 10 1.1.1.1 >/dev/null 2>&1; then
      break
    fi
  fi
done

function connect_vpn {
  ipsec restart
  service xl2tpd restart
  ipsec up myvpn
  echo "c myvpn" > /var/run/xl2tpd/l2tp-control

  echo "waiting for ppp0 ..."
  while [ -z "$(ifconfig ppp0 2>/dev/null)" ] ; do
      snooze 3 &
      wait $!
  done
  echo "ppp0 is up! waiting for IP of ppp0 ..."
  snooze 10 &
  wait $!
  PPP_IP=$(ip -f inet addr show ppp0 | awk '/inet / {print $2}')
  echo $PPP_IP
  ip route add $PRIVATE_LAN_IP_SUBNET via $PPP_IP dev ppp0
}

connect_vpn

while true
do
  if ping -c 1 -W 1 $PRIVATE_LAN_DNS >/dev/null 2>&1; then
    snooze 3 &
    wait $!
  else
    echo "Ping $PRIVATE_LAN_DNS failed, shutdown container..."

    echo "d myvpn" > /var/run/xl2tpd/l2tp-control
    ifconfig ppp0 down
    ipsec down myvpn
    exit 0
  fi
done
