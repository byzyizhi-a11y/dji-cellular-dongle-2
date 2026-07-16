#!/bin/zsh
set -u

BRIDGE_LINK="/tmp/DJICellular2"
CHAT_FILE="/etc/ppp/dji4g.chat"
PPP_LOG="/tmp/dji4g-ppp.log"
PID_FILE="/tmp/dji4g-ppp.pid"
PPPD="/usr/sbin/pppd"
CHAT="/usr/sbin/chat"

die() {
  print -u2 "错误：$*"
  exit 1
}

info() {
  print "[DJI4G] $*"
}

[[ -x "$PPPD" ]] || die "找不到 $PPPD"
[[ -x "$CHAT" ]] || die "找不到 $CHAT"
[[ -L "$BRIDGE_LINK" || -e "$BRIDGE_LINK" ]] || \
  die "没有发现 $BRIDGE_LINK，请先运行 DJICellular2Bridge。"
[[ -f "$CHAT_FILE" ]] || die "找不到拨号脚本 $CHAT_FILE"

DEVICE="$(readlink "$BRIDGE_LINK" 2>/dev/null || true)"
[[ -n "$DEVICE" ]] || DEVICE="$BRIDGE_LINK"
[[ -e "$DEVICE" ]] || die "PTY 设备不存在：$DEVICE"

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    die "PPP 已经在运行，PID：$OLD_PID"
  fi
  rm -f "$PID_FILE"
fi

BUSY="$(/usr/sbin/lsof "$DEVICE" 2>/dev/null | tail -n +2 || true)"
if [[ -n "$BUSY" ]]; then
  print -u2 "设备当前被占用："
  print -u2 "$BUSY"
  die "请先退出 screen、cat、旧 pppd 等占用程序。"
fi

rm -f "$PPP_LOG"

info "Bridge PTY：$DEVICE"
info "PPP 日志：$PPP_LOG"
info "开始拨号……"

PPP_OPTIONS=(
  "$DEVICE"
  115200
  connect "$CHAT -v -f $CHAT_FILE"
  noauth
  noipdefault
  ipcp-accept-local
  ipcp-accept-remote
  usepeerdns
  local
  debug
  dump
  nodetach
  logfile "$PPP_LOG"
)

if [[ "${DJI4G_DEFAULT_ROUTE:-0}" == "1" ]]; then
  PPP_OPTIONS+=(defaultroute)
  info "将请求添加 PPP 默认路由。"
else
  info "不会修改当前默认路由。"
fi

sudo "$PPPD" "${PPP_OPTIONS[@]}" &
PPP_PID=$!
print "$PPP_PID" > "$PID_FILE"

cleanup() {
  rm -f "$PID_FILE"
}
trap cleanup EXIT INT TERM

for _ in {1..40}; do
  if ! kill -0 "$PPP_PID" 2>/dev/null; then
    wait "$PPP_PID"
    STATUS=$?
    print -u2
    print -u2 "拨号进程已退出，状态码：$STATUS"
    [[ -f "$PPP_LOG" ]] && tail -n 60 "$PPP_LOG"
    exit "$STATUS"
  fi

  PPP_IF="$(/sbin/ifconfig -l 2>/dev/null | tr ' ' '\n' | grep '^ppp[0-9][0-9]*$' | head -n 1 || true)"
  if [[ -n "$PPP_IF" ]]; then
    info "连接成功：$PPP_IF"
    /sbin/ifconfig "$PPP_IF" | sed -n '1,8p'
    info "脚本保持运行以维持 PPP；按 Control+C 断开。"
    wait "$PPP_PID"
    exit $?
  fi

  sleep 0.5
done

info "仍在等待 PPP 协商，可在另一终端查看："
print "sudo tail -f $PPP_LOG"
wait "$PPP_PID"
