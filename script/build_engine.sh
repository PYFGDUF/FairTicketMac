#!/usr/bin/env bash
#
# Freeze the Python engine into one executable the app bundle can carry.
#
# A shipped .app must not depend on a checkout, a virtualenv or whatever `python3`
# happens to be on PATH.  This produces `build/engine/run-sidecar`, which
# `build_and_run.sh` copies to `Contents/Resources/engine/`, the second path
# EngineLocator tries after FAIRTICKET_ENGINE.
#
# The engine is only *read*: its requirements are installed into a private
# virtualenv under FairTicketMac/build, so the third-party checkout keeps its own
# environment and nothing is added to it.
#
#   ./script/build_engine.sh
#   FAIRTICKET_REPO=~/src/12306FairTicket ./script/build_engine.sh
#   FAIRTICKET_PYPI=https://pypi.org/simple ./script/build_engine.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${FAIRTICKET_REPO:-$(cd "$ROOT/.." && pwd)/12306FairTicket}"
OUT="$ROOT/build/engine"
VENV="$ROOT/build/engine-venv"
PYPI="${FAIRTICKET_PYPI:-https://pypi.tuna.tsinghua.edu.cn/simple}"
ENTRY="$ROOT/script/engine_entry.py"

if [[ ! -f "$REPO/ticket_app/sidecar.py" ]]; then
  echo "error: 未找到引擎检出：$REPO/ticket_app/sidecar.py 不存在" >&2
  echo "       用 FAIRTICKET_REPO 指定引擎仓库路径。" >&2
  exit 1
fi

# v2.1.0 split the single requirements.txt into requirements/, and the runtime set
# is the one the frozen sidecar must carry.  PySide6 deliberately stays out: the
# frozen engine is headless, and the Qt wheels would triple the binary.
REQUIREMENTS="$REPO/requirements/base.txt"
if [[ ! -f "$REQUIREMENTS" ]]; then
  echo "error: 未找到引擎依赖清单：$REQUIREMENTS 不存在" >&2
  exit 1
fi

# --- interpreter -----------------------------------------------------------------
#
# The engine needs >= 3.12 (it uses modern union syntax at class scope), and a
# frozen binary keeps whatever interpreter built it, so pick deliberately instead
# of inheriting the shell's default `python3`.
BASE_PY="${FAIRTICKET_PYTHON:-}"
if [[ -z "$BASE_PY" ]]; then
  for candidate in \
    "$REPO/.venv/bin/python" \
    "$REPO/venv/bin/python" \
    "$(command -v python3.12 || true)" \
    "$(command -v python3.13 || true)" \
    "$(command -v python3 || true)"
  do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      BASE_PY="$candidate"
      break
    fi
  done
fi
if [[ -z "$BASE_PY" || ! -x "$BASE_PY" ]]; then
  echo "error: 找不到可用的 Python 解释器，用 FAIRTICKET_PYTHON 指定。" >&2
  exit 1
fi

VERSION="$("$BASE_PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
echo "==> 解释器 $BASE_PY (Python $VERSION)"
if [[ "${VERSION%%.*}" -lt 3 || "$(echo "$VERSION" | cut -d. -f2)" -lt 12 ]]; then
  echo "error: 引擎需要 Python >= 3.12，当前为 $VERSION" >&2
  exit 1
fi

# --- build environment -----------------------------------------------------------

PY="$VENV/bin/python"
if [[ ! -x "$PY" ]]; then
  echo "==> 创建冻结专用虚拟环境 ${VENV}（仅首次）"
  "$BASE_PY" -m venv "$VENV"
  "$PY" -m pip install --quiet --upgrade pip
fi
if ! "$PY" -c 'import PyInstaller' >/dev/null 2>&1; then
  echo "==> 安装冻结依赖（镜像 ${PYPI}）"
  "$PY" -m pip install --quiet -i "$PYPI" -r "$REQUIREMENTS" pyinstaller
fi

# --- freeze ---------------------------------------------------------------------

echo "==> PyInstaller 冻结 sidecar"
rm -rf "$OUT"
# --console is required, not cosmetic: the protocol *is* stdio, and a windowed
# build has no usable stdin/stdout.
"$PY" -m PyInstaller \
  --noconfirm \
  --clean \
  --onefile \
  --console \
  --name run-sidecar \
  --paths "$REPO" \
  --distpath "$OUT" \
  --workpath "$ROOT/build/engine-work" \
  --specpath "$ROOT/build/engine-spec" \
  "$ENTRY" > "$ROOT/build/engine-build.log" 2>&1 \
  || { echo "error: PyInstaller 失败，日志见 build/engine-build.log" >&2; tail -20 "$ROOT/build/engine-build.log" >&2; exit 1; }

chmod +x "$OUT/run-sidecar"

# --- smoke test -----------------------------------------------------------------
#
# A frozen binary fails in ways a source run cannot (missing hidden import, no
# stdout).  Speaking one frame pair to it is the cheapest possible proof, and it
# must pass before the engine is allowed into a bundle.
echo "==> 自检：握手 + 关机"
printf '%s\n%s\n' '{"id": 1, "cmd": "capabilities"}' '{"id": 2, "cmd": "shutdown"}' \
  | "$OUT/run-sidecar" > "$OUT/smoke.jsonl" 2> "$OUT/smoke.err" || {
    echo "error: 冻结引擎自检失败" >&2
    tail -20 "$OUT/smoke.err" >&2
    exit 1
  }
if ! grep -q '"type": "hello"' "$OUT/smoke.jsonl"; then
  echo "error: 冻结引擎没有发出 hello 帧" >&2
  head -5 "$OUT/smoke.jsonl" >&2
  exit 1
fi

SIZE="$(du -h "$OUT/run-sidecar" | cut -f1)"
echo "==> 完成：${OUT}/run-sidecar（${SIZE}）"
echo "    内置到窗口：./script/build_and_run.sh"