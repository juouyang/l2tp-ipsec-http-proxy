#!/bin/bash

function connect_vpn {
  echo "restart ipsec"
  ipsec restart
  echo "restart l2tpd"
  service xl2tpd restart
  echo "connect ipsec"
  ipsec up myvpn

  # 定義一個變數來儲存您想要的字串
  target="1 up, 0 connecting"
  # 定義一個變數來儲存等待的秒數
  wait_time=3
  # 使用一個無限迴圈來重複檢查
  echo "wait for ipsec ESTABLISHED ..."
  while true; do
    # 執行 ipsec status 命令並使用 grep 命令來檢查背景程序的輸出是否包含目標字串
    ipsec status | grep -q "$target"
    match=$?
    # 如果退出狀態是 0，表示找到了目標字串，則跳出迴圈
    if [ $match -eq 0 ]; then
      echo "ipsec status matched"
      break
    fi
    # 如果沒有找到目標字串，則使用 sleep 命令來暫停一段時間，然後繼續迴圈
    snooze $wait_time &
    wait $!
  done

  echo "connect l2tp"
  echo "c myvpn" > /var/run/xl2tpd/l2tp-control

  echo "waiting for ppp0 ..."
  count=0 # 記錄檢查的次數
  while [ -z "$(ifconfig ppp0 2>/dev/null)" -a $count -lt 10 ] ; do # 如果 ppp0 不存在且檢查次數小於 10
      snooze 3 &
      wait $!
      count=$((count+1)) # 每次檢查後將次數加一
  done
  # 檢查 ppp0 介面是否存在
  if [ -z "$(ifconfig ppp0 2>/dev/null)" ]; then # 如果不存在，則輸出錯誤訊息並退出腳本，返回 1
    echo "ppp0 interface not found"
    exit 1
  fi
  echo "ppp0 is up! waiting for IP of ppp0 ..."
  snooze 10 &
  wait $!
  PPP_IP=$(ip -f inet addr show ppp0 | awk '/inet / {print $2}')
  echo $PPP_IP
  ip route add $PRIVATE_LAN_IP_SUBNET via $PPP_IP dev ppp0
}

function disconnect_vpn {
  echo "d myvpn" > /var/run/xl2tpd/l2tp-control
  ifconfig ppp0 down
  ipsec down myvpn
}

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

connect_vpn

while true
do
  if ping -c 1 -W 1 $PRIVATE_LAN_HEALTH_CHECK >/dev/null 2>&1; then
    snooze 3 &
    wait $!
  else
    echo "Ping $PRIVATE_LAN_HEALTH_CHECK failed, shutdown container..."
    disconnect_vpn
    exit 0
  fi
done
