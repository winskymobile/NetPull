#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PID_FILE="$ROOT/.file_server.pid"
LOG_FILE="$ROOT/.file_server.log"
PORT_FILE="$ROOT/.file_server.port"
RUNTIME_PORT_FILE="$ROOT/.file_server.runtime_port"
SHARE_FILE="$ROOT/.file_server.share_dir"
RUNTIME_SHARE_FILE="$ROOT/.file_server.runtime_share"
BIND="${BIND:-0.0.0.0}"
DEFAULT_PORT=8765
DEFAULT_SHARE_DIR="$ROOT/down"
if [[ -n "${PORT:-}" ]]; then
  PORT_FROM_ENV="$PORT"
else
  PORT_FROM_ENV=""
fi
if [[ -n "${SHARE_DIR:-}" ]]; then
  SHARE_DIR_FROM_ENV="$SHARE_DIR"
else
  SHARE_DIR_FROM_ENV=""
fi
PORT="$DEFAULT_PORT"
SHARE_DIR="$DEFAULT_SHARE_DIR"
PY="${PYTHON:-python3}"
SERVER="$ROOT/file_server.py"
VERBOSE="${VERBOSE:-1}"

is_verbose() {
  [[ "${VERBOSE}" == 1 ]]
}

valid_port() {
  local p="${1:-}"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  ((10#$p >= 1 && 10#$p <= 65535))
}

read_saved_port() {
  local p=""
  if [[ -f "$PORT_FILE" ]]; then
    p="$(tr -d '[:space:]' < "$PORT_FILE" || true)"
  fi
  if valid_port "$p"; then
    echo "$((10#$p))"
    return 0
  fi
  return 1
}

read_runtime_port() {
  local p=""
  if [[ -f "$RUNTIME_PORT_FILE" ]]; then
    p="$(tr -d '[:space:]' < "$RUNTIME_PORT_FILE" || true)"
  fi
  if valid_port "$p"; then
    echo "$((10#$p))"
    return 0
  fi
  return 1
}

port_source_label() {
  if [[ -n "$PORT_FROM_ENV" ]]; then
    echo "本次环境变量"
  elif [[ -f "$PORT_FILE" ]]; then
    echo "已保存"
  else
    echo "默认"
  fi
}

load_port() {
  local saved=""
  saved="$(read_saved_port || true)"
  if [[ -n "$PORT_FROM_ENV" ]]; then
    if valid_port "$PORT_FROM_ENV"; then
      PORT="$((10#$PORT_FROM_ENV))"
    else
      say red "环境变量 PORT 无效: $PORT_FROM_ENV，改用已保存或默认端口"
      PORT="${saved:-$DEFAULT_PORT}"
    fi
  elif [[ -n "$saved" ]]; then
    PORT="$saved"
  else
    PORT="$DEFAULT_PORT"
  fi
}

save_port() {
  local p="$1"
  PORT="$p"
  if [[ "$p" == "$DEFAULT_PORT" ]]; then
    rm -f "$PORT_FILE"
  else
    printf '%s\n' "$p" > "$PORT_FILE"
  fi
}

active_port() {
  local live=""
  if running_pid >/dev/null 2>&1; then
    live="$(read_runtime_port || true)"
  fi
  echo "${live:-$PORT}"
}

trim_text() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

resolve_share_dir() {
  local raw
  raw="$(trim_text "${1:-}")"
  [[ -n "$raw" ]] || return 1
  case "$raw" in
    "~") raw="$HOME" ;;
    "~/"*) raw="$HOME/${raw:2}" ;;
  esac
  if [[ "$raw" != /* ]]; then
    raw="$ROOT/$raw"
  fi
  local parent base
  parent="$(dirname -- "$raw")"
  base="$(basename -- "$raw")"
  if [[ -d "$parent" ]]; then
    parent="$(cd "$parent" && pwd)"
    printf '%s\n' "$parent/$base"
  else
    printf '%s\n' "$raw"
  fi
}

valid_share_dir() {
  local d="${1:-}"
  [[ -n "$d" ]] || return 1
  if [[ -e "$d" && ! -d "$d" ]]; then
    return 1
  fi
  return 0
}

read_saved_share() {
  local p=""
  if [[ -f "$SHARE_FILE" ]]; then
    p="$(trim_text "$(tr -d '\r' < "$SHARE_FILE" || true)")"
  fi
  if [[ -n "$p" ]] && p="$(resolve_share_dir "$p")" && valid_share_dir "$p"; then
    printf '%s\n' "$p"
    return 0
  fi
  return 1
}

read_runtime_share() {
  local p=""
  if [[ -f "$RUNTIME_SHARE_FILE" ]]; then
    p="$(trim_text "$(tr -d '\r' < "$RUNTIME_SHARE_FILE" || true)")"
  fi
  if [[ -n "$p" ]]; then
    printf '%s\n' "$p"
    return 0
  fi
  return 1
}

share_source_label() {
  if [[ -n "$SHARE_DIR_FROM_ENV" ]]; then
    echo "本次环境变量"
  elif [[ -f "$SHARE_FILE" ]]; then
    echo "已保存"
  else
    echo "默认"
  fi
}

load_share() {
  local saved="" resolved=""
  saved="$(read_saved_share || true)"
  if [[ -n "$SHARE_DIR_FROM_ENV" ]]; then
    if resolved="$(resolve_share_dir "$SHARE_DIR_FROM_ENV")" && valid_share_dir "$resolved"; then
      SHARE_DIR="$resolved"
    else
      say red "环境变量 SHARE_DIR 无效: $SHARE_DIR_FROM_ENV，改用已保存或默认目录"
      SHARE_DIR="${saved:-$DEFAULT_SHARE_DIR}"
    fi
  elif [[ -n "$saved" ]]; then
    SHARE_DIR="$saved"
  else
    SHARE_DIR="$DEFAULT_SHARE_DIR"
  fi
}

save_share() {
  local d="$1"
  SHARE_DIR="$d"
  if [[ "$d" == "$DEFAULT_SHARE_DIR" ]]; then
    rm -f "$SHARE_FILE"
  else
    printf '%s\n' "$d" > "$SHARE_FILE"
  fi
}

active_share() {
  local live=""
  if running_pid >/dev/null 2>&1; then
    live="$(read_runtime_share || true)"
  fi
  echo "${live:-$SHARE_DIR}"
}

if [[ -z "${NO_COLOR:-}" && -t 1 && "${TERM:-}" != "dumb" ]]; then
  ENABLE_COLOR=1
else
  ENABLE_COLOR=0
fi

use_color() {
  [[ "${ENABLE_COLOR}" == 1 ]]
}

paint() {
  local color="$1"
  shift
  local text="$*"
  if use_color; then
    case "$color" in
      green) printf '\033[1;32m%s\033[0m' "$text" ;;
      yellow) printf '\033[1;38;5;226m%s\033[0m' "$text" ;;
      red) printf '\033[1;38;5;196m%s\033[0m' "$text" ;;
      cyan) printf '\033[1;36m%s\033[0m' "$text" ;;
      bold) printf '\033[1m%s\033[0m' "$text" ;;
      dim) printf '\033[2m%s\033[0m' "$text" ;;
      *) printf '%s' "$text" ;;
    esac
  else
    printf '%s' "$text"
  fi
}

say() {
  local color="$1"
  shift
  printf '%s\n' "$(paint "$color" "$*")"
}

usage() {
  cat <<EOF
用法: $(basename "$0") [start|stop|restart|status|dir|port]

  start           启动服务
  stop            停止服务
  restart         重启服务
  status          查看状态
  dir [路径]      修改分享目录；dir default 恢复 down
  port [端口]     修改端口；port default 恢复 8765

不带参数时进入菜单；执行完一项后会回到菜单，选 0 才退出。
服务运行中退出时会询问是否同时停止。
分享目录保存到 .file_server.share_dir，菜单第 5 项也可改。
端口会保存到 .file_server.port，菜单第 6 项也可改。

示例:
  ./server.sh start
  ./server.sh stop
  ./server.sh dir ~/Downloads
  ./server.sh dir default
  ./server.sh port 9000
  ./server.sh port default
  PORT=9000 ./server.sh start
  SHARE_DIR=/other/path ./server.sh start
EOF
}

is_alive() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

is_this_server() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 1
  ps -p "$pid" -ww -o args= 2>/dev/null | grep -F "$SERVER" >/dev/null
}

port_listener() {
  local p="${1:-$PORT}"
  lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $2}' | sort -u
}

print_urls() {
  local p="${1:-$PORT}"
  say bold "访问地址:"
  say cyan "  http://127.0.0.1:${p}/"
  local ip
  for iface in en0 en1 en2 bridge0; do
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      say cyan "  http://${ip}:${p}/"
    fi
  done
}

running_pid() {
  local pid=""
  if [[ -f "$PID_FILE" ]]; then
    pid="$(tr -d '[:space:]' < "$PID_FILE" || true)"
    if is_alive "$pid" && is_this_server "$pid"; then
      echo "$pid"
      return 0
    fi
  fi
  local p
  local listen_port
  for listen_port in "$PORT" "$(read_runtime_port || true)"; do
    [[ -n "$listen_port" ]] || continue
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if is_this_server "$p"; then
        echo "$p"
        return 0
      fi
    done < <(port_listener "$listen_port" || true)
  done
  return 1
}

collect_pids() {
  local pids=()
  local pid

  if [[ -f "$PID_FILE" ]]; then
    pid="$(tr -d '[:space:]' < "$PID_FILE" || true)"
    if is_alive "$pid" && is_this_server "$pid"; then
      pids+=("$pid")
    fi
  fi

  local listen_port
  for listen_port in "$PORT" "$(read_runtime_port || true)"; do
    [[ -n "$listen_port" ]] || continue
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      if is_this_server "$pid"; then
        pids+=("$pid")
      fi
    done < <(port_listener "$listen_port" || true)
  done

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if is_this_server "$pid"; then
      pids+=("$pid")
    fi
  done < <(pgrep -f "$SERVER" 2>/dev/null || true)

  if ((${#pids[@]})); then
    printf '%s\n' "${pids[@]}" | awk 'NF && !seen[$0]++'
  fi
}

wait_exit() {
  local pid="$1"
  local i
  for i in $(seq 1 30); do
    if ! is_alive "$pid"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

cmd_status() {
  local pid
  if pid="$(running_pid)"; then
    printf '状态: %s\n' "$(paint green "运行中 (PID ${pid})")"
    if is_verbose; then
      echo "目录: $SHARE_DIR ($(share_source_label))"
      echo "端口: $PORT ($(port_source_label))"
      print_urls "$(active_port)"
      echo "日志: $LOG_FILE"
    fi
    return 0
  fi
  printf '状态: %s\n' "$(paint yellow "未运行")"
  if is_verbose; then
    echo "目录: $SHARE_DIR ($(share_source_label))"
    echo "端口: $PORT ($(port_source_label))"
  fi
  return 0
}

cmd_start() {
  if [[ ! -f "$SERVER" ]]; then
    say red "找不到 $SERVER"
    return 1
  fi

  mkdir -p "$SHARE_DIR"

  if ! command -v "$PY" >/dev/null 2>&1; then
    say red "找不到 Python 解释器: $PY"
    return 1
  fi

  local pid
  if pid="$(running_pid)"; then
    say yellow "服务已在运行 (PID ${pid})"
    if is_verbose; then
      echo "目录: $SHARE_DIR ($(share_source_label))"
      print_urls
      echo "日志: $LOG_FILE"
    fi
    return 0
  fi
  rm -f "$PID_FILE"

  local existing_pids
  existing_pids="$(port_listener || true)"
  if [[ -n "$existing_pids" ]]; then
    say red "端口 ${PORT} 已被占用: ${existing_pids}"
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN || true
    echo "可先执行 ./server.sh stop，或换端口: PORT=9000 ./server.sh start"
    return 1
  fi

  : > "$LOG_FILE"
  nohup "$PY" "$SERVER" --bind "$BIND" --port "$PORT" --directory "$SHARE_DIR" >>"$LOG_FILE" 2>&1 &
  pid="$!"
  disown "$pid" 2>/dev/null || true
  echo "$pid" > "$PID_FILE"

  local ok=0
  local _
  for _ in $(seq 1 30); do
    if is_alive "$pid" && [[ -n "$(port_listener || true)" ]]; then
      ok=1
      break
    fi
    if ! is_alive "$pid"; then
      break
    fi
    sleep 0.1
  done

  if [[ "$ok" -ne 1 ]]; then
    say red "启动失败，最近日志:"
    tail -n 40 "$LOG_FILE" || true
    rm -f "$PID_FILE" "$RUNTIME_PORT_FILE" "$RUNTIME_SHARE_FILE"
    return 1
  fi

  printf '%s\n' "$PORT" > "$RUNTIME_PORT_FILE"
  printf '%s\n' "$SHARE_DIR" > "$RUNTIME_SHARE_FILE"
  say green "已启动内网文件服务 (PID ${pid})"
  if is_verbose; then
    echo "目录: $SHARE_DIR ($(share_source_label))"
    print_urls
    echo "日志: $LOG_FILE"
    echo "停止: ./server.sh stop"
  fi
}

cmd_stop() {
  local pids pid
  pids="$(collect_pids || true)"
  if [[ -z "$pids" ]]; then
    rm -f "$PID_FILE" "$RUNTIME_PORT_FILE" "$RUNTIME_SHARE_FILE"
    say yellow "服务未运行"
    return 0
  fi

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done <<< "$pids"

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if ! wait_exit "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
      wait_exit "$pid" || true
    fi
  done <<< "$pids"

  local still
  still="$(collect_pids || true)"
  if [[ -n "$still" ]]; then
    say red "停止失败，仍在运行: $still"
    return 1
  fi

  rm -f "$PID_FILE" "$RUNTIME_PORT_FILE" "$RUNTIME_SHARE_FILE"
  say yellow "已停止内网文件服务"
  if is_verbose && [[ -f "$LOG_FILE" ]]; then
    echo "日志: $LOG_FILE"
  fi
}

cmd_restart() {
  cmd_stop
  cmd_start
}

confirm_exit() {
  local pid answer
  if ! pid="$(running_pid)"; then
    say dim "已退出"
    return 0
  fi
  printf '%s' "$(paint yellow "退出后是否停止服务？ [y/N] ")"
  read -r answer
  case "${answer:-}" in
    y|Y|yes|YES|是|停|停止)
      cmd_stop || true
      say dim "已退出"
      ;;
    *)
      say cyan "服务继续在后台运行。"
      say dim "已退出"
      ;;
  esac
}

apply_port_value() {
  local raw new live answer
  raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr -d '[:space:]')"
  if [[ -z "$raw" ]]; then
    say dim "已取消"
    return 0
  fi
  case "$raw" in
    default|DEFAULT|默认|reset|restore|d)
      new="$DEFAULT_PORT"
      ;;
    *)
      if ! valid_port "$raw"; then
        say red "端口无效: ${raw} (需要 1-65535)"
        return 1
      fi
      new="$((10#$raw))"
      ;;
  esac

  if [[ "$new" == "$PORT" ]]; then
    if [[ "$new" == "$DEFAULT_PORT" && -f "$PORT_FILE" ]]; then
      save_port "$new"
      say green "已恢复默认端口 $DEFAULT_PORT"
    else
      say yellow "已经是端口 $new"
      return 0
    fi
  else
    save_port "$new"
    if [[ "$new" == "$DEFAULT_PORT" ]]; then
      say green "已恢复默认端口 $DEFAULT_PORT"
    else
      say green "端口已保存为 $PORT"
    fi
  fi

  if running_pid >/dev/null 2>&1; then
    live="$(read_runtime_port || true)"
    live="${live:-$PORT}"
    if [[ "$live" != "$PORT" ]]; then
      if [[ -t 0 ]]; then
        printf '%s' "$(paint yellow "服务仍在 $live 运行，是否立即按新端口重启？ [Y/n] ")"
        read -r answer
        case "${answer:-Y}" in
          n|N|no|NO|否) say cyan "下次启动或重启后生效。" ;;
          *) cmd_restart || true ;;
        esac
      else
        say cyan "服务仍在 $live 运行，下次启动或重启后生效。"
      fi
    fi
  fi
}

cmd_set_port() {
  local input
  echo "当前端口: $PORT ($(port_source_label))"
  if running_pid >/dev/null 2>&1; then
    echo "服务正在 $(active_port) 运行"
  fi
  echo "输入新端口 (1-65535)。输入 default / 默认 恢复 ${DEFAULT_PORT}，回车取消。"
  if [[ -t 0 ]]; then
    read -r -p "> " input
  else
    say red "非交互环境请使用: ./server.sh port 9000  或  ./server.sh port default"
    return 1
  fi
  apply_port_value "$input"
}

apply_share_value() {
  local raw new live answer
  raw="$(trim_text "${1:-}")"
  if [[ -z "$raw" ]]; then
    say dim "已取消"
    return 0
  fi
  case "$raw" in
    default|DEFAULT|默认|reset|restore|d)
      new="$DEFAULT_SHARE_DIR"
      ;;
    *)
      if ! new="$(resolve_share_dir "$raw")"; then
        say red "路径无效: ${raw}"
        return 1
      fi
      if [[ -e "$new" && ! -d "$new" ]]; then
        say red "不是目录: ${new}"
        return 1
      fi
      ;;
  esac

  if ! mkdir -p "$new" 2>/dev/null; then
    say red "无法创建目录: $new"
    return 1
  fi
  new="$(resolve_share_dir "$new")"

  if [[ "$new" == "$SHARE_DIR" ]]; then
    if [[ "$new" == "$DEFAULT_SHARE_DIR" && -f "$SHARE_FILE" ]]; then
      save_share "$new"
      say green "已恢复默认目录 $DEFAULT_SHARE_DIR"
    else
      say yellow "已经是目录 $new"
      return 0
    fi
  else
    save_share "$new"
    if [[ "$new" == "$DEFAULT_SHARE_DIR" ]]; then
      say green "已恢复默认目录 $DEFAULT_SHARE_DIR"
    else
      say green "分享目录已保存为 $SHARE_DIR"
    fi
  fi

  if running_pid >/dev/null 2>&1; then
    live="$(read_runtime_share || true)"
    if [[ -z "$live" || "$live" != "$SHARE_DIR" ]]; then
      if [[ -t 0 ]]; then
        printf '%s' "$(paint yellow "服务仍在使用 $live，是否立即按新目录重启？ [Y/n] ")"
        read -r answer
        case "${answer:-Y}" in
          n|N|no|NO|否) say cyan "下次启动或重启后生效。" ;;
          *) cmd_restart || true ;;
        esac
      else
        say cyan "服务仍在使用 $live，下次启动或重启后生效。"
      fi
    fi
  fi
}

cmd_set_share() {
  local input
  echo "当前目录: $SHARE_DIR ($(share_source_label))"
  if running_pid >/dev/null 2>&1; then
    echo "服务正在使用 $(active_share)"
  fi
  echo "输入新路径。相对路径相对于本程序目录。输入 default / 默认 恢复 down，回车取消。"
  if [[ -t 0 ]]; then
    read -r -p "> " input
  else
    say red "非交互环境请使用: ./server.sh dir /path  或  ./server.sh dir default"
    return 1
  fi
  apply_share_value "$input"
}

print_menu() {
  local pid
  echo
  say bold "内网文件服务"
  if pid="$(running_pid)"; then
    printf '状态: %s\n' "$(paint green "运行中 (PID ${pid})")"
  else
    printf '状态: %s\n' "$(paint yellow "未运行")"
  fi
  echo "目录: $SHARE_DIR ($(share_source_label))"
  printf '端口: %s (%s)\n' "$PORT" "$(port_source_label)"
  if [[ -n "${pid:-}" ]]; then
    local live live_dir
    live="$(read_runtime_port || true)"
    live_dir="$(read_runtime_share || true)"
    if [[ -n "$live" && "$live" != "$PORT" ]]; then
      say yellow "服务仍在端口 $live，重启后才会改到 $PORT"
    fi
    if [[ -n "$live_dir" && "$live_dir" != "$SHARE_DIR" ]]; then
      say yellow "服务仍在目录 $live_dir，重启后才会改到 $SHARE_DIR"
    fi
    if [[ -n "$live" && "$live" != "$PORT" ]]; then
      print_urls "$live"
    else
      print_urls "$PORT"
    fi
  fi
  cat <<EOF

  1) 启动
  2) 停止
  3) 重启
  4) 状态
  5) 修改分享目录
  6) 修改端口
  0) 退出

EOF
}

menu() {
  local choice redraw=1
  local saved="${VERBOSE}"
  VERBOSE=0
  while true; do
    if [[ "$redraw" == 1 ]]; then
      print_menu
    fi
    redraw=1
    read -r -p "请选择 [0-6]: " choice
    case "${choice:-}" in
      1|start|on|up|启动)
        cmd_start || true
        ;;
      2|stop|off|停止)
        cmd_stop || true
        ;;
      3|restart|reboot|重启)
        cmd_restart || true
        ;;
      4|status|state|状态)
        ;;
      5|dir|share|directory|目录)
        cmd_set_share || true
        ;;
      6|port|端口)
        cmd_set_port || true
        ;;
      0|q|quit|exit|退出)
        confirm_exit || true
        break
        ;;
      "")
        redraw=0
        ;;
      *)
        say yellow "未知选项: $choice"
        redraw=0
        ;;
    esac
  done
  VERBOSE="$saved"
}

run_and_maybe_menu() {
  local fn="$1"
  local rc=0
  if [[ -t 0 ]]; then
    VERBOSE=0
    "$fn" || rc=$?
    menu
    return 0
  fi
  VERBOSE=1
  "$fn" || rc=$?
  return "$rc"
}

load_port
load_share

action="${1:-}"
case "$action" in
  start|on|up|启动) run_and_maybe_menu cmd_start ;;
  stop|off|停止) run_and_maybe_menu cmd_stop ;;
  restart|reboot|重启) run_and_maybe_menu cmd_restart ;;
  status|state|状态) run_and_maybe_menu cmd_status ;;
  dir|share|directory|目录)
    if [[ -n "${2:-}" ]]; then
      apply_share_value "$2"
      if [[ -t 0 ]]; then
        menu
      fi
    else
      cmd_set_share || true
      if [[ -t 0 ]]; then
        menu
      fi
    fi
    ;;
  port|端口)
    if [[ -n "${2:-}" ]]; then
      apply_port_value "$2"
      if [[ -t 0 ]]; then
        menu
      fi
    else
      cmd_set_port || true
      if [[ -t 0 ]]; then
        menu
      fi
    fi
    ;;
  -h|--help|help|帮助) usage ;;
  "")
    if [[ -t 0 ]]; then
      menu
    else
      usage
      echo
      cmd_status
      exit 1
    fi
    ;;
  *)
    say red "未知命令: $action"
    usage
    exit 1
    ;;
esac
