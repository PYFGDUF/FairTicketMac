"""Headless JSON-Lines bridge that exposes the ticket engine to other frontends.

Why this exists
---------------
The engine is frontend-agnostic in ``runner``/``client``/``clock``/``runtime``,
and the GUI-facing layer wrapped around it is plain Python too: ``gui.settings``
(the version-5 cart configuration model, atomic JSON writes and the offline
station snapshot), ``gui.validation`` (field rules), ``gui.async_logging``
(batched redacting log transport) and ``gui.station_worker`` (explicit station
refresh) none of them import PySide6.

This bridge therefore *reuses those modules* instead of reimplementing them.  A
second frontend -- such as the macOS SwiftUI application -- inherits the same
defaults, the same validation messages, the same version-5 configuration
contract, the same log redaction and the same event payloads as the PySide6
window, because it is literally running the same code.

The configuration surface is the *cart*: one ordered list of
``{from_station, to_station, train_scope, train_code, seat_type}`` entries, tried
in order until one of them produces a ticket.  There is no separate seat list --
``seat_types`` is derived from the cart by the engine, so a frontend that renders
the cart cannot disagree with what gets attempted.

Protocol
--------
One JSON object per line over stdin/stdout.

``stdout`` carries protocol frames only.  ``sys.stdout`` is redirected to
``stderr`` at start-up so a stray ``print`` anywhere in the engine cannot corrupt
the stream, and every frame is written under a lock by a single writer.  ``stderr``
carries this bridge's own fatal errors.  Readers should skip any line that is not
decodable JSON.

Frames emitted by the bridge::

    {"type": "hello",  ...capabilities...}
    {"type": "reply",  "id": 7, "ok": true,  "result": {...}}
    {"type": "reply",  "id": 7, "ok": false, "error": "...", "error_type": "AppError"}
    {"type": "event",  "kind": "phase", "message": "...", "data": {...}, "timestamp": 1.0}
    {"type": "log",    "lines": [["15:00:12  INFO  ...", "INFO"], ...]}

Commands accepted on stdin; every one echoes its ``id``::

    capabilities      no payload                  -> the hello payload
    validate          {"settings": {...}}         -> {"valid": bool, "errors": {field: msg}}
    preview           {"settings": {...}}         -> {"cart_rows": [...], "scope_summary": str, ...}
    stations          none                        -> {"names": [...], "count": int}
    update_stations   none                        -> {"count": int}   (network; async reply)
    load_settings     {"path": "..."}             -> {"settings": {...}}
    save_settings     {"path": "...", "settings": {...}} -> {}
    start             {"settings": {...}}         -> {"started": bool, "errors": {...}}
    stop              none                        -> {"stopping": bool}
    refresh_qr        none                        -> {"refreshing": bool}  (new code, task keeps running)
    reset_session     none                        -> {}   (forget the login; next run rescans)
    shutdown          none                        -> {} then exit
"""

from __future__ import annotations

import base64
import json
import logging
import math
import os
import sys
import threading
import time
from pathlib import Path
from typing import Any, BinaryIO, Iterable, Mapping, Optional, Sequence

import requests

from ticket_app.cart import cart_seat_types, normalize_cart_items
from ticket_app.configuration import (
    SEAT_SPECS,
    AppError,
    ResponseFormatError,
    preference_capabilities,
)
from ticket_app.gui.async_logging import AsyncLogPipeline
from ticket_app.gui.settings import (
    DEFAULT_VALUES,
    EDITABLE_SETTINGS_KEYS,
    LOCAL_DATA_DIR,
    build_app_config,
    cached_station_names,
    canonical_mapping,
    editable_settings_payload,
    load_gui_settings,
    save_gui_settings,
)
from ticket_app.gui.field_specs import (
    COMPOSITE_KEYS,
    FIELD_SPECS,
    GROUP_ORDER,
    spec_to_mapping,
)
from ticket_app.gui.station_worker import refresh_station_cache
from ticket_app.gui.validation import (
    NUMERIC_FIELD_RULES,
    VALID_LOG_LEVELS,
    validate_gui_mapping,
)
from ticket_app.passengers import TICKET_TYPE_CODES
from ticket_app.preferences import CHOOSABLE_SEAT_TYPES, SEAT_LAYOUT_LETTERS
from ticket_app.runner import TicketRunner
from ticket_app.runtime import CancellationToken

PROTOCOL_VERSION = 2
LOG_FILE = LOCAL_DATA_DIR / "logs" / "app.log"

#: Where the desktop window's "打开 12306 订单" button points.
ORDER_URL = "https://kyfw.12306.cn/otn/view/train_order.html"

#: ``(value, label)`` pairs for one cart entry's 车次范围.  Passed to the frontend
#: rather than hard-coded there, so the labels stay with the validation rule that
#: rejects an unknown scope.
TRAIN_SCOPES: tuple[tuple[str, str], ...] = (
    ("specific", "指定车次"),
    ("all", "不限车次"),
)

#: The empty value means "follow whatever the 12306 contact record says", which is
#: why it carries a label instead of being omitted.
TICKET_TYPES: tuple[tuple[str, str], ...] = (
    ("", "12306 默认"),
    ("adult", "成人票"),
    ("student", "学生票"),
)


def _initial_form_state() -> dict:
    """The form state the desktop window opens with.

    ``MainWindow._load_initial_values`` applies ``DEFAULT_VALUES`` wholesale and
    only prefills the two station editors, so the packaged defaults *are* the
    initial state -- an empty cart is a valid draft.  Rebuilding the mapping here
    by hand is what would let the two frontends drift apart.
    """

    return editable_settings_payload(DEFAULT_VALUES)


def _cart_row_text(item: Any, index: int) -> str:
    """One cart entry as the desktop window words it.

    ``gui.cart_flow.cart_row_text`` is the original; keeping the exact wording here
    means the two frontends describe the same cart the same way, and a user moving
    between them does not have to re-read the list.
    """

    scope = "不限车次" if item.train_scope == "all" else (item.train_code or "未填写车次")
    return f"{index}. {item.from_station} → {item.to_station} · {scope} · {item.seat_type}"


#: Stock columns shared by distinct berth products.  ``SEAT_SPECS`` keeps the
#: order used by the desktop form, so filtering on these keys reproduces the
#: exact 坐席/卧铺 grouping without keeping a second copy of the label lists.
_BERTH_STOCK_KEYS = frozenset({"gr", "rw", "yw"})

_MAX_PASSENGERS = 5


def _json_safe(value: Any) -> Any:
    """Convert engine payloads into strictly serialisable JSON values.

    ``bytes`` becomes an explicitly tagged base64 object rather than a raw
    string so a reader can never mistake a QR image for ordinary text.
    Non-finite floats become ``null`` because ``NaN``/``Infinity`` are not valid
    JSON and would desynchronise a strict parser.
    """

    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, (bytes, bytearray)):
        return {
            "encoding": "base64",
            "data": base64.b64encode(bytes(value)).decode("ascii"),
        }
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, Mapping):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set, frozenset)):
        return [_json_safe(item) for item in value]
    return str(value)


class ProtocolWriter:
    """Single, locked writer for the stdout frame stream."""

    def __init__(self, handle: BinaryIO) -> None:
        self._handle = handle
        self._lock = threading.Lock()

    def send(self, **frame: Any) -> None:
        payload = _json_safe(frame)
        try:
            data = (json.dumps(payload, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")
        except (TypeError, ValueError) as exc:  # pragma: no cover - guarded by _json_safe
            data = (
                json.dumps(
                    {"type": "error", "error": f"帧序列化失败: {exc}", "error_type": "ProtocolError"},
                    ensure_ascii=False,
                )
                + "\n"
            ).encode("utf-8")
        with self._lock:
            self._handle.write(data)
            self._handle.flush()


def _engine_version() -> str:
    try:
        from ticket_app import __version__ as version

        return str(version)
    except Exception:
        return "unknown"


class Sidecar:
    """Owns the engine lifecycle for one frontend process."""

    def __init__(self, writer: ProtocolWriter) -> None:
        self._writer = writer
        #: One session for the whole process.  ``build_app_config`` forces
        #: ``persist_session=False``, so the login cookies exist only in memory --
        #: reusing this object is what lets a second run in the same app session
        #: report "已登录，无需重新扫码" instead of demanding a new scan.
        self._session = requests.Session()
        self._pipeline = AsyncLogPipeline(gui_batch_sink=self._on_log_batch)
        self._token: Optional[CancellationToken] = None
        self._thread: Optional[threading.Thread] = None
        #: The live run, so a frontend can reach into it — currently only to ask for a
        #: fresh QR code without stopping the task.
        self._runner: Optional[TicketRunner] = None
        self._station_cache: Optional[list[str]] = None
        self._station_lock = threading.Lock()
        self._closed = False

    # ------------------------------------------------------------------ setup

    def prepare_logging(self) -> None:
        root = logging.getLogger()
        for handler in list(root.handlers):
            root.removeHandler(handler)
        root.addHandler(self._pipeline.handler)
        root.setLevel(logging.DEBUG)

    # ------------------------------------------------------------ capabilities

    def capabilities(self) -> dict:
        seats = [
            {"label": label, "stock_key": spec.stock_key, "submit_code": spec.submit_code}
            for label, spec in SEAT_SPECS.items()
        ]
        return {
            "protocol": PROTOCOL_VERSION,
            "engine_version": _engine_version(),
            "data_dir": str(LOCAL_DATA_DIR),
            "log_file": str(LOG_FILE),
            # The authoritative list of settings a frontend may edit.  A reader
            # that renders only these keys cannot silently miss a field the
            # engine accepts, nor offer one it will discard.
            "editable_keys": sorted(EDITABLE_SETTINGS_KEYS),
            "defaults": editable_settings_payload(DEFAULT_VALUES),
            "initial_state": _initial_form_state(),
            # The whole form, described declaratively, so a frontend cannot drop a
            # field or invent its own input bounds.
            "field_specs": [spec_to_mapping(spec) for spec in FIELD_SPECS],
            "group_order": list(GROUP_ORDER),
            "composite_keys": list(COMPOSITE_KEYS),
            "order_url": ORDER_URL,
            "seats": seats,
            "seat_groups": {
                "seated": [item["label"] for item in seats if item["stock_key"] not in _BERTH_STOCK_KEYS],
                "berth": [item["label"] for item in seats if item["stock_key"] in _BERTH_STOCK_KEYS],
            },
            "seat_layouts": {
                "rows": [1, 2],
                "letters_by_code": {code: list(letters) for code, letters in SEAT_LAYOUT_LETTERS.items()},
                "choosable_codes": sorted(CHOOSABLE_SEAT_TYPES),
                "business_code": "9",
            },
            # The cart's own vocabulary: the scope of one entry, and the optional
            # per-passenger ticket type.  Both are engine rules, so the frontend
            # renders these labels instead of inventing its own.
            "train_scopes": [
                {"value": value, "label": label} for value, label in TRAIN_SCOPES
            ],
            "ticket_types": [
                {"value": value, "label": label} for value, label in TICKET_TYPES
            ],
            "ticket_type_codes": dict(TICKET_TYPE_CODES),
            "log_levels": sorted(VALID_LOG_LEVELS),
            "numeric_rules": [
                {
                    "key": key,
                    "label": label,
                    "minimum": minimum,
                    "maximum": maximum,
                    "inclusive": inclusive,
                    "integer": integer,
                }
                for key, label, minimum, maximum, inclusive, integer in NUMERIC_FIELD_RULES
            ],
            "max_passengers": _MAX_PASSENGERS,
        }

    # ----------------------------------------------------------- station names

    def station_names(self) -> list[str]:
        with self._station_lock:
            if self._station_cache is None:
                self._station_cache = cached_station_names()
            return list(self._station_cache)

    def _invalidate_stations(self) -> None:
        with self._station_lock:
            self._station_cache = None

    # ------------------------------------------------------------- frame sinks

    def _on_log_batch(self, lines: Sequence[Any]) -> None:
        """Receive already-redacted ``(line, level)`` pairs from the pipeline."""

        payload = []
        for item in lines:
            if isinstance(item, (tuple, list)) and len(item) == 2:
                payload.append([str(item[0]), str(item[1])])
        if payload:
            self._writer.send(type="log", lines=payload)

    def _relay(self, event: Any) -> None:
        """Callable ``EventSink`` handed to :class:`TicketRunner`."""

        data = dict(getattr(event, "data", {}) or {})
        timestamp = getattr(event, "timestamp", None)
        self._writer.send(
            type="event",
            kind=str(getattr(event, "kind", "status") or "status"),
            message=str(getattr(event, "message", "") or ""),
            data=data,
            timestamp=float(timestamp) if timestamp is not None else time.time(),
        )

    # --------------------------------------------------------------- replies

    def _ok(self, request_id: Any, result: Optional[Mapping[str, Any]] = None) -> None:
        self._writer.send(type="reply", id=request_id, ok=True, result=dict(result or {}))

    def _fail(self, request_id: Any, message: str, error_type: str = "AppError") -> None:
        self._writer.send(type="reply", id=request_id, ok=False, error=str(message), error_type=error_type)

    # ------------------------------------------------------------------- loop

    def serve(self) -> int:
        self.prepare_logging()
        self._writer.send(type="hello", **self.capabilities())
        stream = sys.stdin.buffer
        try:
            for raw in stream:
                line = raw.strip()
                if not line:
                    continue
                try:
                    frame = json.loads(line.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    self._fail(None, f"无法解析指令: {exc}", "ProtocolError")
                    continue
                if not isinstance(frame, Mapping):
                    self._fail(None, "指令必须是 JSON 对象", "ProtocolError")
                    continue
                if not self.handle(frame):
                    break
        except (KeyboardInterrupt, BrokenPipeError):
            pass
        finally:
            self.close()
        return 0

    def handle(self, frame: Mapping[str, Any]) -> bool:
        """Dispatch one command.  Returns ``False`` to stop serving."""

        request_id = frame.get("id")
        command = str(frame.get("cmd") or frame.get("command") or "").strip()
        settings = frame.get("settings")

        if command in ("capabilities", "hello"):
            self._ok(request_id, self.capabilities())

        elif command == "validate":
            if not isinstance(settings, Mapping):
                self._fail(request_id, "settings 必须是对象", "ProtocolError")
            else:
                try:
                    errors = validate_gui_mapping(settings, self.station_names())
                except Exception as exc:
                    self._fail(request_id, str(exc), type(exc).__name__)
                else:
                    self._ok(request_id, {"valid": not errors, "errors": errors})

        elif command == "preview":
            self._cmd_preview(request_id, settings)

        elif command == "stations":
            names = self.station_names()
            self._ok(request_id, {"names": names, "count": len(names)})

        elif command == "update_stations":
            self._cmd_update_stations(request_id)

        elif command == "load_settings":
            self._cmd_load_settings(request_id, frame.get("path"))

        elif command == "save_settings":
            self._cmd_save_settings(request_id, frame.get("path"), settings)

        elif command == "start":
            self._cmd_start(request_id, settings)

        elif command == "stop":
            running = self._thread is not None
            self.stop()
            self._ok(request_id, {"stopping": running})

        elif command == "refresh_qr":
            self._cmd_refresh_qr(request_id)

        elif command == "reset_session":
            self._cmd_reset_session(request_id)

        elif command == "shutdown":
            self._ok(request_id, {})
            return False

        else:
            self._fail(request_id, f"未知指令: {command or '(空)'}", "ProtocolError")

        return True

    # -------------------------------------------------------------- commands

    def _cmd_preview(self, request_id: Any, settings: Any) -> None:
        """Describe what the current draft would actually attempt.

        The attempt order *is* the cart order, and one success ends the run.  Those
        are real decision rules, so a frontend must not re-derive them: at best the
        copy drifts, at worst the confirmation dialog promises an order the engine
        will not perform.
        """

        if not isinstance(settings, Mapping):
            self._fail(request_id, "settings 必须是对象", "ProtocolError")
            return
        try:
            canonical = canonical_mapping(settings)
            items = normalize_cart_items(canonical.get("cart_items"))
        except Exception as exc:
            self._fail(request_id, str(exc), type(exc).__name__)
            return

        seat_types = cart_seat_types(items)
        pairs = list(dict.fromkeys((item.from_station, item.to_station) for item in items))
        trains = list(
            dict.fromkeys(
                item.train_code
                for item in items
                if item.train_scope == "specific" and item.train_code
            )
        )
        unlimited = sum(1 for item in items if item.train_scope == "all")
        has_seats, has_berths = preference_capabilities(seat_types)

        if not items:
            scope_summary = "购物车为空，还没有可以尝试的备选。"
        else:
            scope_summary = (
                f"共 {len(items)} 个备选 · {len(pairs)} 组站对 · {len(seat_types)} 种席别"
            )
            if unlimited:
                scope_summary += f" · 其中 {unlimited} 项不限车次"

        self._ok(
            request_id,
            {
                "cart_rows": [_cart_row_text(item, index) for index, item in enumerate(items, 1)],
                "cart_count": len(items),
                "scope_summary": scope_summary,
                "priority_preview": "按购物车顺序依次尝试；任意一项成功出票后，其余备选停止。",
                "seat_types": seat_types,
                "station_pairs": [[from_station, to_station] for from_station, to_station in pairs],
                "train_codes": trains,
                "unlimited_scope_count": unlimited,
                "has_seated": has_seats,
                "has_berth": has_berths,
                "passenger_count": len(canonical.get("passenger_names") or []),
            },
        )

    def _cmd_update_stations(self, request_id: Any) -> None:
        # The desktop form also refuses this while a task is running: the ticket
        # thread holds the session that owns the station cache.
        if self._thread is not None:
            self._fail(request_id, "任务运行期间不能更新站点", "BusyError")
            return

        def worker() -> None:
            try:
                stations = refresh_station_cache(timeout_seconds=10.0)
            except Exception as exc:
                self._fail(request_id, str(exc), type(exc).__name__)
                return
            self._invalidate_stations()
            self._ok(request_id, {"count": len(stations)})

        threading.Thread(target=worker, name="fairticket-stations", daemon=True).start()

    def _cmd_load_settings(self, request_id: Any, raw_path: Any) -> None:
        if not raw_path:
            self._fail(request_id, "缺少 path", "ProtocolError")
            return
        try:
            values = load_gui_settings(Path(str(raw_path)).expanduser())
        except Exception as exc:
            self._fail(request_id, str(exc), type(exc).__name__)
        else:
            self._ok(request_id, {"settings": values})

    def _cmd_save_settings(self, request_id: Any, raw_path: Any, settings: Any) -> None:
        if not raw_path:
            self._fail(request_id, "缺少 path", "ProtocolError")
            return
        if not isinstance(settings, Mapping):
            self._fail(request_id, "settings 必须是对象", "ProtocolError")
            return
        try:
            save_gui_settings(Path(str(raw_path)).expanduser(), settings)
        except Exception as exc:
            self._fail(request_id, str(exc), type(exc).__name__)
        else:
            self._ok(request_id, {})

    def _cmd_start(self, request_id: Any, settings: Any) -> None:
        if self._thread is not None:
            self._fail(request_id, "已有任务在运行", "BusyError")
            return
        if not isinstance(settings, Mapping):
            self._fail(request_id, "settings 必须是对象", "ProtocolError")
            return
        # Mirror the desktop form: starting checks every field and reports all
        # problems at once, so the UI can move focus to the first one.
        try:
            errors = validate_gui_mapping(settings, self.station_names())
        except Exception as exc:
            self._fail(request_id, str(exc), type(exc).__name__)
            return
        if errors:
            self._ok(request_id, {"started": False, "errors": errors})
            return

        self._token = CancellationToken()
        self._thread = threading.Thread(
            target=self._engine_thread,
            args=(settings,),
            name="fairticket-engine",
            daemon=True,
        )
        self._thread.start()
        self._ok(request_id, {"started": True})

    def _cmd_refresh_qr(self, request_id: Any) -> None:
        """Hand the running task a new QR code without stopping it.

        Distinct from ``reset_session``: that one forgets the login and refuses to run
        while a task is live, because the desktop window can only reach a fresh code by
        restarting.  A frontend that keeps the task alive needs this instead — the user
        who missed the code keeps the clock correction and the queue position they
        already waited for.
        """

        runner = self._runner
        if runner is None:
            self._ok(request_id, {"refreshing": False})
            return
        try:
            runner.request_new_qr()
        except Exception as exc:
            self._fail(request_id, str(exc), type(exc).__name__)
        else:
            self._ok(request_id, {"refreshing": True})

    def _cmd_reset_session(self, request_id: Any) -> None:
        """Drop the in-memory login so the next run must scan a fresh QR code.

        The desktop window reaches the same state only indirectly, by restarting
        the task and letting the stale session fail its login check.  An explicit
        command makes a "重新扫码" button deterministic instead of relying on that
        timing.
        """

        if self._thread is not None:
            self._fail(request_id, "请先停止任务再重新扫码", "BusyError")
            return
        try:
            self._session.cookies.clear()
        except Exception as exc:
            self._fail(request_id, str(exc), type(exc).__name__)
        else:
            self._ok(request_id, {})

    def stop(self) -> None:
        token = self._token
        if token is not None:
            token.cancel()

    # ---------------------------------------------------------------- engine

    def _engine_thread(self, settings: Mapping[str, Any]) -> None:
        token = self._token
        exit_code = 1
        exit_message = "任务已结束"
        error_type = ""
        safe_stop = False

        try:
            cfg = build_app_config(settings)
            level = getattr(logging, str(cfg.log_level).upper(), logging.INFO)
            try:
                self._pipeline.configure_task(level, cfg.passenger_names, LOG_FILE)
            except RuntimeError as exc:
                logging.warning("无法配置异步日志: %s", exc)
            runner = TicketRunner(
                cfg,
                event_sink=self._relay,
                cancel_token=token,
                session=self._session,
            )
            self._runner = runner
            exit_code = int(runner.run())
            exit_message = {
                0: "任务已完成",
                130: "任务已停止",
            }.get(exit_code, "任务已结束")

        except ResponseFormatError as exc:
            # The server may already hold a reservation for this order.  The
            # engine deliberately refuses to try the next candidate, so report it
            # as a first-class signal instead of an ordinary failure: the UI must
            # block and send the user to the official order page.
            exit_code = 2
            error_type = "ResponseFormatError"
            safe_stop = True
            exit_message = str(exc)
        except AppError as exc:
            exit_code = 2
            error_type = type(exc).__name__
            exit_message = str(exc)
        except KeyboardInterrupt:
            exit_code = 130
            error_type = "KeyboardInterrupt"
            exit_message = "用户中断任务"
        except Exception as exc:
            exit_code = 1
            error_type = type(exc).__name__
            exit_message = str(exc)

        finally:
            try:
                self._pipeline.flush()
            except Exception:
                pass
            cancelled = bool(token is not None and token.is_cancelled)
            self._token = None
            self._thread = None
            self._runner = None
            self._writer.send(
                type="event",
                kind="exit",
                message=exit_message,
                data={
                    "exit_code": exit_code,
                    "safe_stop": safe_stop,
                    "exception_type": error_type,
                    "cancelled": cancelled,
                },
                timestamp=time.time(),
            )

    # ---------------------------------------------------------------- closing

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self.stop()
        thread = self._thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=15.0)
        try:
            logging.getLogger().removeHandler(self._pipeline.handler)
        except Exception:
            pass
        try:
            self._pipeline.close(timeout=5.0)
        except Exception:
            pass
        # Match the desktop window: drop in-memory credentials on exit.
        try:
            self._session.cookies.clear()
            self._session.close()
        except Exception:
            pass


def _reserve_stdout() -> BinaryIO:
    """Take a private handle for the protocol and point ``sys.stdout`` at stderr.

    Any incidental ``print`` from the engine or a third-party library would
    otherwise interleave with the frame stream and desynchronise the reader.
    """

    handle = os.fdopen(os.dup(sys.stdout.fileno()), "wb")
    sys.stdout = sys.stderr
    return handle


def main(argv: Optional[Iterable[str]] = None) -> int:
    writer = ProtocolWriter(_reserve_stdout())
    sidecar = Sidecar(writer)
    return sidecar.serve()


if __name__ == "__main__":
    raise SystemExit(main())