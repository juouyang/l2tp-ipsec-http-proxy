function snooze {
  sleep $1
}

function vpn_disconnect {
  echo "
        disconnect vpn
  ================================="
  echo "d myvpn" > /var/run/xl2tpd/l2tp-control
  ipsec down myvpn
}

function _connect_ipsec {
  ipsec up myvpn
}

function _wait_ipsec {
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

      export -f vpn_disconnect
      timeout 10s bash -c vpn_disconnect
      exit 1
    fi
    # 如果沒有找到目標字串，則使用 sleep 命令來暫停一段時間，然後繼續迴圈
    snooze $wait_time &
    wait $!
    count=$((count+1)) # 每次檢查後將次數加一
  done
}

function _connect_l2tp {
  ipsec status
  echo "c myvpn" > /var/run/xl2tpd/l2tp-control
}

function _wait_l2tp {
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

    export -f vpn_disconnect
    timeout 10s bash -c vpn_disconnect
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

function vpn_connect {
  echo "
        connect vpn
 ================================="
  rm -rf /var/run/ppp*.pid
  rm -rf /var/run/*charon*
  rm -rf /var/run/xl2tpd/l2tp-control
  ipsec restart
  service xl2tpd restart

  echo "
        connect ipsec
 ================================="
  export -f _connect_ipsec
  timeout 10s bash -c _connect_ipsec
  _wait_ipsec

  echo "
        connect l2tp
 ================================="
  export -f _connect_l2tp
  timeout 10s bash -c _connect_l2tp
  _wait_l2tp
}

# 設置信號處理函數
sigterm_handler() {
  # 在這裡執行接收到 SIGTERM 信號時要執行的操作
  echo "Received SIGTERM. Cleaning up..."
  # 清理任務
  # ...
  export -f vpn_disconnect
  timeout 6s bash -c vpn_disconnect
  # 結束腳本
  exit 0
}

function vpn_healthy_check {
  if ping -c 1 -W 1 $PPP_IP >/dev/null 2>&1; then
    # "PPP interface $PPP_IF is up and reachable."
    if ping -c 10 -W 10 $PRIVATE_LAN_HEALTH_CHECK >/dev/null 2>&1; then
      return 0
    fi
  fi
  echo "PPP interface $PPP_IF is down or unreachable."
  return 1
}

function vpn_healthy_check {
  if ping -c 1 -W 1 $PPP_IP >/dev/null 2>&1 &&
     ping -c 10 -W 10 $PRIVATE_LAN_HEALTH_CHECK >/dev/null 2>&1; then
    return 0
  else
    echo "VPN is down or unhealthy."
    return 1
  fi
}