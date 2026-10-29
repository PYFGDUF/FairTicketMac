#!/usr/bin/env bash
#
# Capture the app's window without taking over the screen you are using.
#
# Reviewing the interface used to cost whoever was at the machine their desktop: the app
# was launched into the foreground, the *system* appearance was flipped to dark and back,
# and the capture fell back to a screen region — which returns whatever happens to be on
# top, i.e. the user's own window.  This does none of that:
#
#   * the app is launched as a second, hidden, background instance
#     (`open -n -g -j -F`), so no window appears over the user's work, focus never moves,
#     and a copy of the app they are already using is left running and untouched;
#   * the window is captured by window id, which is z-order independent: it works with
#     the window completely covered, so the user can keep working on top of it;
#   * dark mode is this instance's own appearance (`FAIRTICKET_APPEARANCE=dark`), never
#     the system's;
#   * only the instance started here is stopped at the end.
#
# There is deliberately no region-capture fallback.  A region capture of a covered window
# silently returns the user's own window, which reads as "the app is broken" and is worse
# than a failed run; this exits non-zero with the reason instead.
#
#   ./script/preview.sh                             main window, current defaults
#   ./script/preview.sh --section advanced --expand
#   ./script/preview.sh --section cart,trip,log     one capture each, into --out-dir
#   ./script/preview.sh --outcome success           the panel after a successful grab
#   ./script/preview.sh --demo running              scripted running-state timeline
#   ./script/preview.sh --dark
#   ./script/preview.sh --dump-menu                 menu bar as text, no window shown
#   ./script/preview.sh --no-build                  reuse the current bundle
#   ./script/preview.sh --keep                      leave the instance running to poke at
#   ./script/preview.sh --out /tmp/x.png
#
# The state switches (`--section`, `--expand`, `--outcome`) come from `ReviewHooks`, which
# is compiled into debug builds only — the default here.  With CONFIG=release they are
# absent and a capture would silently show the default state, so a release bundle is
# rejected rather than used.
#
# Output: $FAIRTICKET_SHOT, or <out-dir>/<section>.png when several sections are asked for.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FairTicketMac"
BUNDLE="$ROOT/build/$APP_NAME.app"
LOG=/tmp/fairticket-preview.log
DEFAULT_OUT="${FAIRTICKET_SHOT:-/tmp/fairticket-preview.png}"

BUILD=1
SECTIONS=""
EXPAND=0
OUTCOME=""
DEMO=""
DARK=0
KEEP=0
DUMP_MENU=0
OUT=""
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --section)  SECTIONS="${2:-}"; shift 2 ;;
    --expand)   EXPAND=1; shift ;;
    --outcome)  OUTCOME="${2:-}"; shift 2 ;;
    --demo)     DEMO="${2:-}"; shift 2 ;;
    --dark)     DARK=1; shift ;;
    --dump-menu) DUMP_MENU=1; shift ;;
    --keep)     KEEP=1; shift ;;
    --out)      OUT="${2:-}"; shift 2 ;;
    --out-dir)  OUT_DIR="${2:-}"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "$BUILD" == "1" ]]; then
  echo "==> build + bundle"
  "$ROOT/script/build_and_run.sh" --no-launch >/dev/null
fi

if [[ ! -x "$BUNDLE/Contents/MacOS/$APP_NAME" ]]; then
  echo "error: 找不到 ${BUNDLE}，先运行 ./script/build_and_run.sh" >&2
  exit 1
fi

# The review switches are #if DEBUG.  A release binary ignores them, which would make a
# capture quietly show the wrong state rather than fail.
if ! strings -a "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null | grep -q FAIRTICKET_SECTION; then
  echo "error: 这个 bundle 是 release 构建，没有截图用的状态开关（--section/--expand/--outcome）" >&2
  echo "       用默认的 debug 构建重跑：./script/preview.sh" >&2
  exit 1
fi

# One capture per requested section; a plain run is one capture of the default state.
if [[ -n "$SECTIONS" ]]; then
  IFS=',' read -r -a SECTION_LIST <<< "$SECTIONS"
else
  SECTION_LIST=("")
fi

if [[ ${#SECTION_LIST[@]} -gt 1 && -z "$OUT_DIR" ]]; then
  OUT_DIR="/tmp/fairticket-shots"
fi
# One --out path cannot hold several pages; failing is better than silently keeping the
# last one and leaving the caller believing they have all of them.
if [[ ${#SECTION_LIST[@]} -gt 1 && -n "$OUT" ]]; then
  echo "error: --out 只能配单个 --section，多页请用 --out-dir" >&2
  exit 2
fi
if [[ -n "$OUT_DIR" ]]; then
  mkdir -p "$OUT_DIR"
fi

STARTED_PIDS=()
READY_SECONDS=""

stop_started() {
  for pid in "${STARTED_PIDS[@]:-}"; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done
  STARTED_PIDS=()
}

cleanup() {
  rm -f /tmp/fairticket-review-ready-* /tmp/fairticket-menu-*
  if [[ "$KEEP" != "1" ]]; then
    stop_started
  else
    echo "==> keeping the instance(s) running: ${STARTED_PIDS[*]:-}"
  fi
}
trap cleanup EXIT

# Launches one hidden instance and prints its pid.
#
# The pid is found by difference rather than by name: `pgrep` matches every instance,
# including the one the user may be working in, and killing or capturing the wrong one is
# exactly the kind of interference this script exists to avoid.
launch_instance() {
  local section="$1"
  local before new_pid pid
  before="$(pgrep -x "$APP_NAME" 2>/dev/null | tr '\n' ' ')"

  # Left behind by an instance that was killed before it was ready.  Cleared before the
  # launch so the marker this instance writes can only be its own.
  rm -f /tmp/fairticket-review-ready-*

  local env_args=()
  if [[ -n "$DEMO" ]]; then env_args+=(--env "FAIRTICKET_DEMO=$DEMO"); fi
  if [[ -n "$section" ]]; then env_args+=(--env "FAIRTICKET_SECTION=$section"); fi
  if [[ "$EXPAND" == "1" ]]; then env_args+=(--env "FAIRTICKET_EXPAND=1"); fi
  if [[ -n "$OUTCOME" ]]; then env_args+=(--env "FAIRTICKET_OUTCOME=$OUTCOME"); fi
  if [[ "$DARK" == "1" ]]; then env_args+=(--env "FAIRTICKET_APPEARANCE=dark"); fi
  if [[ "$DUMP_MENU" == "1" ]]; then env_args+=(--env "FAIRTICKET_DUMP_MENU=1"); fi

  # -n a second instance, -g never brings it forward, -j never shows its windows,
  # -F starts fresh instead of restoring the last session's window state (which is what
  # the old script deleted the saved-state directory for).
  open -n -g -j -F "${env_args[@]+"${env_args[@]}"}" \
    --stdout "$LOG" --stderr "$LOG" "$BUNDLE"

  new_pid=""
  for _ in $(seq 1 60); do
    sleep 0.25
    for pid in $(pgrep -x "$APP_NAME" 2>/dev/null); do
      case " $before " in
        *" $pid "*) ;;
        *) new_pid="$pid" ;;
      esac
    done
    [[ -n "$new_pid" ]] && break
  done

  if [[ -z "$new_pid" ]]; then
    echo "error: 新实例没有启动，见 $LOG" >&2
    return 1
  fi
  echo "$new_pid"
}

# "A window exists" is not "the window is worth looking at": the first frames of a
# fresh instance are an empty form, because the engine handshake has not answered yet.
# The app touches a pid-named file once the handshake is done and the requested state is
# applied, so the screenshot path and the menu dump wait on the same signal.
wait_ready() {
  local pid="$1" marker="/tmp/fairticket-review-ready-$pid" started elapsed
  started=$SECONDS
  for _ in $(seq 1 120); do
    [[ -f "$marker" ]] && break
    sleep 0.5
  done
  if [[ ! -f "$marker" ]]; then
    echo "error: 60 秒内引擎没有就绪（pid ${pid}），见 $LOG" >&2
    return 1
  fi
  elapsed=$((SECONDS - started))
  READY_SECONDS="$elapsed"
  # The state was applied on the last runloop turn; give the frame that redraws it a
  # moment to land, so what is captured or dumped is the state that was asked for.
  sleep 0.6
}

capture_window() {
  local pid="$1" path="$2" window_id attempt
  wait_ready "$pid" || return 1

  window_id=""
  # Hidden windows are reported as off-screen but still capturable, so the probe filters
  # by size instead — the window server also lists a few thin strips per window.
  for _ in $(seq 1 20); do
    window_id="$(python3 "$ROOT/script/window_id.py" --pid "$pid" --min-width 600 2>/dev/null || true)"
    [[ -n "$window_id" ]] && break
    sleep 0.5
  done

  if [[ -z "$window_id" ]]; then
    echo "error: 10 秒内没有找到窗口（pid ${pid}），见 $LOG" >&2
    return 1
  fi

  # The very first frames of a fresh instance can be un-capturable while the window is
  # still being composited; that is a race, not a permission problem, so it is retried.
  for attempt in 1 2 3 4 5; do
    if screencapture -x -o -l "$window_id" "$path" 2>/dev/null && [[ -s "$path" ]]; then
      return 0
    fi
    sleep 0.7
  done

  echo "error: 按窗口 ID 截图失败（id ${window_id}）。" >&2
  echo "       通常是「屏幕录制」权限没给到运行这个脚本的程序（系统设置 → 隐私与安全性 → 屏幕录制）。" >&2
  return 1
}

for section in "${SECTION_LIST[@]}"; do
  if [[ -n "$OUT" ]]; then
    target="$OUT"
  elif [[ -n "$OUT_DIR" ]]; then
    target="$OUT_DIR/${section:-main}.png"
  else
    target="$DEFAULT_OUT"
  fi

  mkdir -p "$(dirname "$target")"

  pid="$(launch_instance "$section")" || exit 1
  STARTED_PIDS+=("$pid")

  # Built from explicit comparisons: `${DARK:+...}` expands for "0" too, which made the
  # log claim a dark capture for every run.
  state=""
  [[ -n "$section" ]] && state+=" · $section"
  [[ "$DARK" == "1" ]] && state+=" · dark"
  [[ "$EXPAND" == "1" ]] && state+=" · expanded"
  [[ -n "$OUTCOME" ]] && state+=" · $OUTCOME"
  [[ -n "$DEMO" ]] && state+=" · demo:$DEMO"
  echo "==> pid $pid$state"

  if [[ "$DUMP_MENU" == "1" ]]; then
    wait_ready "$pid" || exit 1
    menu="/tmp/fairticket-menu-$pid.txt"
    if [[ -f "$menu" ]]; then
      echo "menu bar (ready in ${READY_SECONDS:-?}s):"
      cat "$menu"
    else
      echo "error: 菜单没有 dump 出来" >&2
      exit 1
    fi
  else
    capture_window "$pid" "$target" || exit 1
    echo "screenshot: $target (ready in ${READY_SECONDS:-?}s)"
  fi

  # One instance per capture: the state switches are read once at launch.
  if [[ "$KEEP" != "1" ]]; then
    kill "$pid" 2>/dev/null || true
    STARTED_PIDS=("${STARTED_PIDS[@]/$pid/}")
  fi
done
