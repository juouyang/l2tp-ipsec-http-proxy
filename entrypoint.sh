#!/bin/bash

function check_pppoe_connection {
  if ping -c 1 -W 1 $PPP_IP >/dev/null 2>&1; then
    # "PPP interface $PPP_IF is up and reachable."
    if ping -c 10 -W 10 $PRIVATE_LAN_HEALTH_CHECK >/dev/null 2>&1; then
      return 0
    else
      return 1
    fi
  else
    echo "PPP interface $PPP_IF is down or unreachable."
    return 1
  fi
}

function snooze {
  sleep $1
}

function disconnect_vpn {
  echo "
        disconnect vpn
  ================================="
  echo "d myvpn" > /var/run/xl2tpd/l2tp-control
  ipsec down myvpn
  rm -rf /var/run/ppp*
  rm -rf /var/run/*charon*
  rm -rf /var/run/xl2tpd/l2tp-control
}

function connect_ipsec {
  echo "
        connect ipsec
  ================================="
  ipsec up myvpn
}

function connect_l2tp {
  echo "
        connect l2tp
  ================================="
  ipsec status
  echo "c myvpn" > /var/run/xl2tpd/l2tp-control
}

function wait_for_pppoe {
  echo "
        wait for PPPoE
  ================================="
  echo "waiting for ppp interface ..."
  count=0 # 記錄檢查的次數
  while [ -z "$(ifconfig |grep -E '^ppp*' 2>/dev/null)" -a $count -lt 10 ] ; do # 如果 ppp 不存在且檢查次數小於 10
      snooze 3 &
      wait $!
      count=$((count+1)) # 每次檢查後將次數加一
  done

  # 檢查 ppp 介面是否存在
  if [ -z "$(ifconfig |grep -E '^ppp*' 2>/dev/null)" ]; then # 如果不存在，則輸出錯誤訊息並退出腳本，返回 1
    echo "ppp interface not found"

    export -f disconnect_vpn
    timeout 10s bash -c disconnect_vpn
    exit 1
  fi
  ip route del $PRIVATE_LAN_IP_SUBNET via $PPP_IP dev $PPP_IF
  PPP_IF=$(ip addr show | awk '/inet.*ppp/ {print $NF}')
  echo "ppp interface" $PPP_IF "is up! waiting for IP of" $PPP_IF
  snooze 3 &
  wait $!
  PPP_IP=$(ip addr show | awk '/inet.*ppp/ {print $2}')
  ip route add $PRIVATE_LAN_IP_SUBNET via $PPP_IP dev $PPP_IF
}

function connect_vpn {
  echo "
        connect vpn
 ================================="
  rm -rf /var/run/ppp*
  rm -rf /var/run/*charon*
  rm -rf /var/run/xl2tpd/l2tp-control
  ipsec restart
  service xl2tpd restart

  export -f connect_ipsec
  timeout 10s bash -c connect_ipsec

  # 定義一個變數來儲存您想要的字串
  target="1 up, 0 connecting"
  # 定義一個變數來儲存等待的秒數
  wait_time=3
  # 使用一個無限迴圈來重複檢查
  echo "wait for ipsec ESTABLISHED ..."
  count=0 # 記錄檢查的次數
  while true; do
    # 執行 ipsec status 命令並使用 grep 命令來檢查背景程序的輸出是否包含目標字串
    ipsec status | grep connect
    ipsec status | grep -q "$target"
    match=$?
    # 如果退出狀態是 0，表示找到了目標字串，則跳出迴圈
    if [ $match -eq 0 ]; then
      echo "ipsec status matched"
      break
    fi
    if [ $count -gt 10 ]; then
      echo "ipsec status mis-matched"

      export -f disconnect_vpn
      timeout 10s bash -c disconnect_vpn
      exit 1
    fi
    # 如果沒有找到目標字串，則使用 sleep 命令來暫停一段時間，然後繼續迴圈
    snooze $wait_time &
    wait $!
    count=$((count+1)) # 每次檢查後將次數加一
  done

  export -f connect_l2tp
  timeout 10s bash -c connect_l2tp
  wait_for_pppoe
}

# 設置信號處理函數
sigterm_handler() {
  # 在這裡執行接收到 SIGTERM 信號時要執行的操作
  echo "Received SIGTERM. Cleaning up..."
  # 清理任務
  # ...
  export -f disconnect_vpn
  timeout 6s bash -c disconnect_vpn
  # 結束腳本
  exit 0
}

# 設置 SIGTERM 信號處理器
trap 'sigterm_handler' SIGTERM

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

connect_vpn # >/dev/null 2>&1
echo "VPN Connected:" $PPP_IF $PPP_IP

while true
do
  status=$(ipsec status | grep "myvpn" | grep "INSTALLED")
  if [ -z "$status" ]; then
    echo "ipsec connection down"
    export -f disconnect_vpn
    timeout 10s bash -c disconnect_vpn
    exit 1
  else
    if check_pppoe_connection; then
      snooze 3 &
      wait $!
    else
      echo "PPPoE connection is down, reconnecting..."
      export -f connect_l2tp
      timeout 10s bash -c connect_l2tp
      wait_for_pppoe
    fi
  fi
done
