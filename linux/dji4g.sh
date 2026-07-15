#!/usr/bin/env bash
set -Eeuo pipefail

# DJI Cellular Dongle 2 / Fibocom NL668T-GL PPP helper
# 默认拨号口：MI_03 -> /dev/ttyUSB3
# 默认不替换系统默认路由，避免远程 SSH 断线。

VID="2ca3"
PID="4009"
MODEM_PORT="${MODEM_PORT:-/dev/ttyUSB3}"
BAUD="${BAUD:-115200}"
PEER_NAME="dji4g"
CHAT_FILE="/etc/chatscripts/${PEER_NAME}"
PEER_FILE="/etc/ppp/peers/${PEER_NAME}"
PPP_IFACE="${PPP_IFACE:-ppp0}"

log() {
  printf '[dji4g] %s\n' "$*"
}

die() {
  printf '[dji4g] 错误：%s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 运行：sudo $0 $*"
}

install_dependencies() {
  if command -v pppd >/dev/null 2>&1 && command -v chat >/dev/null 2>&1; then
    return
  fi

  command -v apt-get >/dev/null 2>&1 || die "缺少 pppd/chat，且系统不是 apt 系发行版。"
  log "安装 PPP 依赖……"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ppp
}

bind_usb_serial() {
  modprobe option

  local new_id="/sys/bus/usb-serial/drivers/option1/new_id"
  [[ -w "$new_id" ]] || die "找不到可写的 option1/new_id：$new_id"

  # 已添加时内核可能返回 File exists，忽略即可。
  if ! printf '%s %s\n' "$VID" "$PID" >"$new_id" 2>/tmp/dji4g-new-id.err; then
    if ! grep -qiE 'exist|busy' /tmp/dji4g-new-id.err 2>/dev/null; then
      cat /tmp/dji4g-new-id.err >&2 || true
      die "添加 USB VID/PID 到 option 驱动失败。"
    fi
  fi
  rm -f /tmp/dji4g-new-id.err

  log "等待拨号口 ${MODEM_PORT}……"
  for _ in {1..20}; do
    [[ -c "$MODEM_PORT" ]] && return
    sleep 0.5
  done

  die "未找到 ${MODEM_PORT}。请检查模块是否插入，以及 dmesg | tail -n 50。"
}

write_config() {
  mkdir -p /etc/chatscripts /etc/ppp/peers

  cat >"$CHAT_FILE" <<'EOF'
ABORT 'BUSY'
ABORT 'NO CARRIER'
ABORT 'NO DIALTONE'
ABORT 'ERROR'
TIMEOUT 30
'' AT
OK ATE0
OK AT+CGDCONT=1,"IP",""
OK ATD*99***1#
CONNECT ''
EOF

  cat >"$PEER_FILE" <<EOF
${MODEM_PORT}
${BAUD}
connect "/usr/sbin/chat -v -f ${CHAT_FILE}"
noauth
usepeerdns
persist
holdoff 5
maxfail 0
lock
modem
crtscts
ipcp-accept-local
ipcp-accept-remote
noipdefault
debug
logfile /var/log/dji4g-ppp.log
EOF

  chmod 600 "$CHAT_FILE" "$PEER_FILE"
  log "已写入 ${CHAT_FILE}"
  log "已写入 ${PEER_FILE}"
}

setup() {
  require_root
  install_dependencies
  bind_usb_serial
  write_config
  log "初始化完成。执行：$0 start"
}

start_ppp() {
  require_root
  install_dependencies
  bind_usb_serial
  [[ -f "$CHAT_FILE" && -f "$PEER_FILE" ]] || write_config

  if ip link show "$PPP_IFACE" >/dev/null 2>&1; then
    log "${PPP_IFACE} 已存在。"
    status_ppp
    return
  fi

  log "开始通过 ${MODEM_PORT} 拨号……"
  # updetach：建立后返回；persist：掉线后由 pppd 自动重拨。
  pppd call "$PEER_NAME" updetach

  for _ in {1..30}; do
    if ip link show "$PPP_IFACE" >/dev/null 2>&1; then
      log "拨号成功。"
      status_ppp
      return
    fi
    sleep 1
  done

  log "暂未出现 ${PPP_IFACE}，最近日志如下："
  tail -n 50 /var/log/dji4g-ppp.log 2>/dev/null || true
  exit 1
}

stop_ppp() {
  require_root
  log "停止 PPP……"
  poff "$PEER_NAME" 2>/dev/null || true
  pkill -f "pppd call ${PEER_NAME}" 2>/dev/null || true

  for _ in {1..10}; do
    ip link show "$PPP_IFACE" >/dev/null 2>&1 || {
      log "已停止。"
      return
    }
    sleep 0.5
  done

  log "${PPP_IFACE} 仍存在，请检查：ps aux | grep '[p]ppd'"
}

status_ppp() {
  if ip link show "$PPP_IFACE" >/dev/null 2>&1; then
    log "${PPP_IFACE} 状态："
    ip -br address show "$PPP_IFACE"
    log "相关路由："
    ip route show dev "$PPP_IFACE" || true
  else
    log "${PPP_IFACE} 尚未建立。"
  fi

  if pgrep -a pppd >/dev/null 2>&1; then
    log "pppd 进程："
    pgrep -a pppd
  fi
}

test_ppp() {
  ip link show "$PPP_IFACE" >/dev/null 2>&1 || die "${PPP_IFACE} 不存在，请先执行 $0 start"

  log "测试 IPv4 连通性……"
  ping -I "$PPP_IFACE" -c 4 -W 3 223.5.5.5 || true

  if command -v curl >/dev/null 2>&1; then
    log "查询出口 IP："
    curl --interface "$PPP_IFACE" --max-time 15 -4 https://api.ipify.org || true
    printf '\n'
  else
    log "未安装 curl，跳过出口 IP 查询。"
  fi
}

show_log() {
  tail -n "${LINES:-100}" /var/log/dji4g-ppp.log 2>/dev/null \
    || die "日志尚不存在。"
}

usage() {
  cat <<EOF
用法：
  sudo $0 setup    安装依赖、绑定 USB 串口并生成配置
  sudo $0 start    启动 PPP 拨号
  sudo $0 stop     停止 PPP
  $0 status        查看状态
  $0 test          通过 ${PPP_IFACE} 测试联网
  $0 log           查看最近 PPP 日志

可选环境变量：
  MODEM_PORT=/dev/ttyUSB3
  BAUD=115200
  PPP_IFACE=ppp0

说明：
  脚本默认不添加 defaultroute，也不会替换服务器默认路由，
  因而通常不会影响现有 SSH 连接。
EOF
}

case "${1:-}" in
  setup)  setup ;;
  start)  start_ppp ;;
  stop)   stop_ppp ;;
  status) status_ppp ;;
  test)   test_ppp ;;
  log)    show_log ;;
  *)      usage ;;
esac
