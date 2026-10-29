"""Protocol tests for the headless JSON-Lines bridge.

These tests never log in to 12306 and never submit an order.  The subprocess
tests exercise the real ``python -m ticket_app.sidecar`` entry point with a
temporary data directory; the in-process tests drive the engine callback with a
stub runner so the safety-critical terminal frame can be asserted without any
network access.
"""

from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any, Dict, List, Optional

import pytest

from ticket_app.configuration import ResponseFormatError
from ticket_app.gui.settings import DEFAULT_VALUES, EDITABLE_SETTINGS_KEYS
from ticket_app.runtime import CancellationToken
from ticket_app import sidecar as sidecar_module


REPO_ROOT = Path(__file__).resolve().parents[1]
STARTUP_TIMEOUT = 60.0

#: One valid cart entry.  The version-5 form has no separate station or seat
#: fields: every journey choice lives inside the cart, and the engine derives
#: ``seat_types`` from it.
CART_ENTRY: Dict[str, str] = {
    "from_station": "北京西",
    "to_station": "郑州东",
    "train_scope": "all",
    "train_code": "",
    "seat_type": "二等座",
}


def runnable_settings() -> Dict[str, Any]:
    """A draft the validator accepts: one cart entry plus date and passengers."""

    settings = dict(DEFAULT_VALUES)
    settings.update(
        {
            "cart_items": [dict(CART_ENTRY)],
            "train_date": "2099-01-01",
            "passenger_names": ["张三"],
        }
    )
    return settings


class _CaptureWriter:
    """Stand-in for :class:`ProtocolWriter` that records frames instead."""

    def __init__(self) -> None:
        self.frames: List[Dict[str, Any]] = []

    def send(self, **frame: Any) -> None:
        self.frames.append(frame)

    def of_kind(self, kind: str) -> List[Dict[str, Any]]:
        return [frame for frame in self.frames if frame.get("kind") == kind or frame.get("type") == kind]


class SidecarProcess:
    """Drives one sidecar subprocess and decodes its frame stream."""

    def __init__(self, data_dir: Path) -> None:
        env = dict(os.environ)
        env["FAIRTICKET_DATA_DIR"] = str(data_dir)
        env["PYTHONUNBUFFERED"] = "1"
        self.process = subprocess.Popen(
            [sys.executable, "-m", "ticket_app.sidecar"],
            cwd=str(REPO_ROOT),
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self._inbox: "queue.Queue[Optional[bytes]]" = queue.Queue()
        self._stderr_lines: List[str] = []
        self._next_id = 0
        self._observed_stream: List[bytes] = []
        threading.Thread(target=self._pump_stdout, daemon=True).start()
        threading.Thread(target=self._pump_stderr, daemon=True).start()

    # ------------------------------------------------------------------ pumps

    def _pump_stdout(self) -> None:
        assert self.process.stdout is not None
        for raw in self.process.stdout:
            self._inbox.put(raw)
        self._inbox.put(None)

    def _pump_stderr(self) -> None:
        assert self.process.stderr is not None
        for raw in self.process.stderr:
            self._stderr_lines.append(raw.decode("utf-8", "replace").rstrip("\n"))

    # ------------------------------------------------------------------- read

    def next_frame(self, timeout: float = STARTUP_TIMEOUT) -> Dict[str, Any]:
        raw = self._inbox.get(timeout=timeout)
        assert raw is not None, f"sidecar 提前结束; stderr={self.stderr_text()}"
        self._observed_stream.append(raw)
        text = raw.decode("utf-8")
        # Every stdout line must be a protocol frame; anything else means the
        # engine corrupted the stream with a stray print.
        frame = json.loads(text)
        assert isinstance(frame, dict)
        return frame

    def request(self, command: str, timeout: float = STARTUP_TIMEOUT, **payload: Any) -> Dict[str, Any]:
        self._next_id += 1
        request_id = self._next_id
        body = {"id": request_id, "cmd": command}
        body.update(payload)
        assert self.process.stdin is not None
        self.process.stdin.write((json.dumps(body, ensure_ascii=False) + "\n").encode("utf-8"))
        self.process.stdin.flush()

        pending: List[Dict[str, Any]] = []
        while True:
            frame = self.next_frame(timeout=timeout)
            if frame.get("type") == "reply" and frame.get("id") == request_id:
                frame["_pending"] = pending
                return frame
            pending.append(frame)

    # ---------------------------------------------------------------- shutdown

    def stderr_text(self) -> str:
        return "\n".join(self._stderr_lines[-40:])

    def close(self) -> int:
        if self.process.poll() is None:
            try:
                self.process.stdin and self.process.stdin.close()
            except OSError:
                pass
            try:
                self.process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    self.process.kill()
        return int(self.process.returncode or 0)


@pytest.fixture()
def sidecar(tmp_path: Path):
    client = SidecarProcess(tmp_path / "data")
    try:
        yield client
    finally:
        client.close()


# --------------------------------------------------------------------- frames


def test_handshake_announces_protocol_and_full_editable_surface(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()

    assert hello["type"] == "hello"
    assert hello["protocol"] == sidecar_module.PROTOCOL_VERSION
    # The bridge must publish exactly the settings the engine accepts, so a
    # reader that renders every key it is told about cannot miss a field.
    assert set(hello["editable_keys"]) == set(EDITABLE_SETTINGS_KEYS)
    assert set(hello["defaults"]) == set(EDITABLE_SETTINGS_KEYS)
    assert hello["max_passengers"] == 5
    assert hello["log_levels"] == ["CRITICAL", "DEBUG", "ERROR", "INFO", "WARNING"]


def test_handshake_describes_the_cart_vocabulary(sidecar: SidecarProcess) -> None:
    """The cart's own words travel with the protocol, not hard-coded in the UI."""

    hello = sidecar.next_frame()

    assert hello["train_scopes"] == [
        {"value": "specific", "label": "指定车次"},
        {"value": "all", "label": "不限车次"},
    ]
    assert [item["value"] for item in hello["ticket_types"]] == ["", "adult", "student"]
    assert hello["ticket_type_codes"] == {"adult": "1", "student": "3"}


def test_handshake_describes_seat_groups_and_layouts(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()

    groups = hello["seat_groups"]
    assert groups["seated"] == ["商务座", "特等座", "一等座", "二等座", "软座", "硬座", "无座"]
    assert groups["berth"] == ["高级软卧", "软卧", "硬卧", "一等卧", "二等卧"]

    layouts = hello["seat_layouts"]
    assert layouts["rows"] == [1, 2]
    assert layouts["letters_by_code"]["O"] == ["A", "B", "C", "D", "F"]
    assert layouts["letters_by_code"]["P"] == ["A", "C", "F"]
    assert layouts["business_code"] == "9"


def test_numeric_rules_cover_every_bounded_field(sidecar: SidecarProcess) -> None:
    rules = {rule["key"]: rule for rule in sidecar.next_frame()["numeric_rules"]}

    # A representative bound from each advanced-parameter group; the point is
    # that limits travel with the protocol instead of being re-typed in the UI.
    assert rules["max_retries"]["maximum"] == 100000
    assert rules["max_retries"]["integer"] is True
    assert rules["station_cache_days"]["minimum"] == 1
    assert rules["hot_query_interval_seconds"]["maximum"] == 10
    assert rules["query_interval_seconds"]["inclusive"] is False
    assert len(rules) == 13


def test_field_specs_cover_every_editable_key(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()
    covered = {spec["key"] for spec in hello["field_specs"]}

    # Version 5 dropped the compatibility keys, so every editable setting now has
    # a control.  Anything missing here would be a field the form cannot reach.
    assert covered == set(EDITABLE_SETTINGS_KEYS)
    assert len(hello["field_specs"]) == len(covered)
    # The cart replaces both of the removed single-route controls.
    for gone in ("from_station", "to_station", "preferred_trains", "only_preferred_trains"):
        assert gone not in covered


def test_field_spec_bounds_are_never_looser_than_the_validator(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()
    rules = {rule["key"]: rule for rule in hello["numeric_rules"]}
    specs = {spec["key"]: spec for spec in hello["field_specs"]}

    for key, rule in rules.items():
        spec = specs[key]
        assert spec["kind"] in ("number", "integer"), key
        # A control must never let the user pick a value the validator rejects.
        assert spec["minimum"] >= rule["minimum"], key
        assert spec["maximum"] <= rule["maximum"], key

    for key in ("max_retries", "time_sync_samples", "order_wait_attempts", "station_cache_days"):
        assert specs[key]["kind"] == "integer"
        assert specs[key]["step"] == 1


def test_packaged_defaults_fit_inside_their_controls(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()
    specs = {spec["key"]: spec for spec in hello["field_specs"]}

    for key, spec in specs.items():
        if spec["kind"] not in ("number", "integer"):
            continue
        value = float(hello["defaults"][key])
        assert spec["minimum"] <= value <= spec["maximum"], key


def test_groups_are_declared_and_presented_in_order(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()
    order = hello["group_order"]
    used = [spec["group"] for spec in hello["field_specs"]]

    assert set(used) <= set(order)
    # Presented in the configured order, so a form can render the list directly.
    assert used == sorted(used, key=order.index)


def test_composite_fields_are_declared_as_such(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()
    kinds = {spec["key"]: spec["kind"] for spec in hello["field_specs"]}

    assert hello["composite_keys"] == [
        "cart_items",
        "passenger_ticket_types",
        "seat_position_preferences",
        "berth_preference",
    ]
    assert kinds["cart_items"] == "cart"
    assert kinds["passenger_ticket_types"] == "ticket_types"
    assert kinds["seat_position_preferences"] == "seat_map"
    assert kinds["berth_preference"] == "berths"
    # Starting and stopping are optional daily times that serialise to "".
    assert kinds["start_at"] == "time"
    assert kinds["stop_at"] == "time"


def test_seat_preferences_wait_for_the_cart(sidecar: SidecarProcess) -> None:
    """Seat capability is derived from the cart, so that is what they watch."""

    hello = sidecar.next_frame()
    specs = {spec["key"]: spec for spec in hello["field_specs"]}

    assert specs["seat_position_preferences"]["dormant_until"] == "cart_items"
    assert specs["berth_preference"]["dormant_until"] == "cart_items"


def test_initial_state_is_the_packaged_defaults_with_an_empty_cart(sidecar: SidecarProcess) -> None:
    """The window opens on the defaults; an empty cart is a valid draft."""

    hello = sidecar.next_frame()
    initial = hello["initial_state"]

    assert set(initial) == set(EDITABLE_SETTINGS_KEYS)
    assert initial["cart_items"] == []
    assert initial["berth_preference"] == {"lower": 0, "middle": 0, "upper": 0}


def test_initial_state_becomes_valid_once_a_cart_entry_is_added(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()
    settings = dict(hello["initial_state"])
    settings.update({"train_date": "2099-01-01", "passenger_names": ["张三"]})

    empty_cart = sidecar.request("validate", settings=settings)["result"]
    assert empty_cart["errors"]["cart_items"] == "请至少加入一个购物车备选"

    settings["cart_items"] = [dict(CART_ENTRY)]
    result = sidecar.request("validate", settings=settings)["result"]
    assert result["valid"] is True, result["errors"]


def test_order_page_url_travels_with_the_capabilities(sidecar: SidecarProcess) -> None:
    assert sidecar.next_frame()["order_url"] == "https://kyfw.12306.cn/otn/view/train_order.html"


def test_reset_session_succeeds_when_idle(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()
    assert sidecar.request("reset_session")["ok"] is True


def test_refresh_qr_reports_no_run_when_idle(sidecar: SidecarProcess) -> None:
    """The frontend falls back to forgetting the login when nothing is running."""

    sidecar.next_frame()
    reply = sidecar.request("refresh_qr")

    assert reply["ok"] is True
    assert reply["result"] == {"refreshing": False}


def test_refresh_qr_reaches_the_running_task() -> None:
    """A live run gets a new code; the session is untouched, unlike reset_session."""

    writer = _CaptureWriter()
    bridge = sidecar_module.Sidecar(writer)
    asked: list[str] = []

    class FakeRunner:
        def request_new_qr(self) -> None:
            asked.append("qr")

    bridge._runner = FakeRunner()
    try:
        bridge.handle({"id": 1, "cmd": "refresh_qr"})
    finally:
        bridge._runner = None
        bridge.close()

    reply = writer.frames[-1]
    assert reply["ok"] is True
    assert reply["result"] == {"refreshing": True}
    assert asked == ["qr"]


def test_reset_session_is_refused_while_a_task_is_running() -> None:
    writer = _CaptureWriter()
    bridge = sidecar_module.Sidecar(writer)
    bridge._thread = object()  # pretend a run is in flight
    try:
        bridge.handle({"id": 1, "cmd": "reset_session"})
    finally:
        bridge._thread = None
        bridge.close()

    reply = writer.frames[-1]
    assert reply["ok"] is False
    assert reply["error_type"] == "BusyError"


# ------------------------------------------------------------------- commands


def test_capabilities_command_mirrors_handshake(sidecar: SidecarProcess) -> None:
    hello = sidecar.next_frame()
    reply = sidecar.request("capabilities")

    assert reply["ok"] is True
    assert reply["result"]["editable_keys"] == hello["editable_keys"]


def test_validate_reports_backend_messages_for_bad_input(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()
    settings = dict(DEFAULT_VALUES)
    settings.update(
        {
            "cart_items": [dict(CART_ENTRY, from_station="不存在的车站")],
            "train_date": "1999-01-01",
            "passenger_names": [],
            "auto_submit": True,
        }
    )

    result = sidecar.request("validate", settings=settings)["result"]

    assert result["valid"] is False
    errors = result["errors"]
    assert "购物车第 1 项" in errors["cart_items"]
    assert "出发站不在当前站点列表中" in errors["cart_items"]
    assert errors["train_date"] == "乘车日期不能早于今天"
    assert errors["passenger_names"] == "自动提交时请填写 1 到 5 位乘车人"


def test_validate_accepts_a_consistent_draft(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()

    result = sidecar.request("validate", settings=runnable_settings())["result"]

    assert result["valid"] is True, result["errors"]
    assert result["errors"] == {}


def test_packaged_defaults_are_a_draft_not_a_runnable_config(sidecar: SidecarProcess) -> None:
    """Guards the UI against offering "start" on untouched defaults."""

    sidecar.next_frame()
    settings = dict(DEFAULT_VALUES)
    settings.update({"train_date": "2099-01-01", "passenger_names": ["张三"]})

    result = sidecar.request("validate", settings=settings)["result"]

    assert result["valid"] is False
    assert "cart_items" in result["errors"]


def test_preview_words_the_cart_the_way_the_desktop_window_does(sidecar: SidecarProcess) -> None:
    """The confirmation dialog must not promise an order the engine will not try."""

    sidecar.next_frame()
    settings = runnable_settings()
    settings["cart_items"] = [
        dict(CART_ENTRY),
        dict(CART_ENTRY, train_scope="specific", train_code="G79", seat_type="一等座"),
    ]

    result = sidecar.request("preview", settings=settings)["result"]

    assert result["cart_rows"] == [
        "1. 北京西 → 郑州东 · 不限车次 · 二等座",
        "2. 北京西 → 郑州东 · G79 · 一等座",
    ]
    assert result["cart_count"] == 2
    assert result["seat_types"] == ["二等座", "一等座"]
    assert result["train_codes"] == ["G79"]
    assert result["unlimited_scope_count"] == 1
    assert result["station_pairs"] == [["北京西", "郑州东"]]
    assert result["has_seated"] is True
    assert result["has_berth"] is False
    assert "按购物车顺序" in result["priority_preview"]


def test_preview_of_an_empty_cart_says_so_instead_of_promising_work(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()

    result = sidecar.request("preview", settings=dict(DEFAULT_VALUES))["result"]

    assert result["cart_rows"] == []
    assert result["cart_count"] == 0
    assert "购物车为空" in result["scope_summary"]


def test_stations_are_available_offline(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()
    result = sidecar.request("stations")["result"]

    names = result["names"]
    assert result["count"] == len(names)
    assert "北京西" in names and "上海虹桥" in names
    assert names == sorted(names)


def test_start_is_gated_by_validation_and_never_launches_a_runner(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()
    settings = dict(DEFAULT_VALUES)
    settings.update({"cart_items": [], "train_date": "", "passenger_names": []})

    reply = sidecar.request("start", settings=settings)

    assert reply["ok"] is True
    assert reply["result"]["started"] is False
    assert reply["result"]["errors"]
    # No engine frames may appear: the run must not have been dispatched.
    assert reply["_pending"] == []


def test_unknown_command_is_reported_without_killing_the_stream(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()
    reply = sidecar.request("definitely-not-a-command")

    assert reply["ok"] is False
    assert reply["error_type"] == "ProtocolError"
    # The stream must survive a bad command.
    assert sidecar.request("stations")["ok"] is True


def test_settings_roundtrip_writes_version_five(sidecar: SidecarProcess, tmp_path: Path) -> None:
    sidecar.next_frame()
    target = tmp_path / "profile.json"
    settings = runnable_settings()
    settings["cart_items"] = [
        dict(CART_ENTRY, from_station="开封北"),
        dict(CART_ENTRY, train_scope="specific", train_code="g1561", seat_type="一等座"),
    ]

    assert sidecar.request("save_settings", path=str(target), settings=settings)["ok"] is True

    document = json.loads(target.read_text(encoding="utf-8"))
    assert document["version"] == 5
    assert set(document["settings"]) == set(EDITABLE_SETTINGS_KEYS)

    loaded = sidecar.request("load_settings", path=str(target))["result"]["settings"]
    assert loaded["cart_items"][0]["from_station"] == "开封北"
    # Cart train codes are normalised to upper case by the engine.
    assert loaded["cart_items"][1]["train_code"] == "G1561"


def test_legacy_version_three_documents_are_rejected(sidecar: SidecarProcess, tmp_path: Path) -> None:
    """A v3 file describes a single-route world the engine no longer accepts."""

    sidecar.next_frame()
    target = tmp_path / "legacy.json"
    target.write_text(
        json.dumps({"version": 3, "settings": {"from_station": "北京西"}}),
        encoding="utf-8",
    )

    reply = sidecar.request("load_settings", path=str(target))

    assert reply["ok"] is False
    assert "version 5" in reply["error"]


def test_shutdown_replies_then_exits_cleanly(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()
    reply = sidecar.request("shutdown")

    assert reply["ok"] is True
    assert sidecar.close() == 0


def test_stdout_carries_protocol_frames_only(sidecar: SidecarProcess) -> None:
    sidecar.next_frame()
    sidecar.request("stations")
    sidecar.request("validate", settings=dict(DEFAULT_VALUES))
    sidecar.close()

    assert sidecar._observed_stream, "没有观察到任何输出"
    for raw in sidecar._observed_stream:
        decoded = json.loads(raw.decode("utf-8"))
        assert isinstance(decoded, dict)
        assert "type" in decoded


# ------------------------------------------------------------------ payloads


def test_json_safe_tags_binary_payloads_for_the_reader() -> None:
    tagged = sidecar_module._json_safe(b"\x89PNG\r\n")

    assert tagged == {"encoding": "base64", "data": "iVBORw0K"}


def test_json_safe_flattens_non_finite_numbers_and_paths(tmp_path: Path) -> None:
    converted = sidecar_module._json_safe(
        {"rtt": float("nan"), "offset": float("inf"), "path": tmp_path, "nested": [1, {"deep": b"ab"}]}
    )

    # NaN/Infinity are not valid JSON and would desynchronise a strict parser.
    assert converted["rtt"] is None
    assert converted["offset"] is None
    assert converted["path"] == str(tmp_path)
    assert converted["nested"][1]["deep"] == {"encoding": "base64", "data": "YWI="}


def test_engine_terminal_frame_reports_exit_code(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    writer = _CaptureWriter()
    bridge = sidecar_module.Sidecar(writer)
    monkeypatch.setattr(sidecar_module, "LOG_FILE", tmp_path / "app.log")

    class _StubRunner:
        def __init__(self, cfg, **kwargs) -> None:
            self.kwargs = kwargs

        def run(self) -> int:
            self.kwargs["event_sink"](_StubEvent("phase", "查票", {"phase": "querying"}))
            return 0

    monkeypatch.setattr(sidecar_module, "TicketRunner", _StubRunner)
    monkeypatch.setattr(
        sidecar_module,
        "build_app_config",
        lambda settings: _StubConfig(),
    )
    bridge._token = CancellationToken()

    try:
        bridge._engine_thread({"train_date": "2099-01-01"})
    finally:
        bridge.close()

    assert [frame["kind"] for frame in writer.of_kind("event")] == ["phase", "exit"]
    terminal = writer.of_kind("exit")[0]
    assert terminal["data"]["exit_code"] == 0
    assert terminal["data"]["safe_stop"] is False
    assert terminal["type"] == "event"


def test_response_format_error_is_flagged_as_a_safe_stop(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """The engine stops because the server may already hold the reservation.

    That state must reach the UI as a distinct signal rather than an ordinary
    failure, so the window can block and point at the official order page.
    """

    writer = _CaptureWriter()
    bridge = sidecar_module.Sidecar(writer)
    monkeypatch.setattr(sidecar_module, "LOG_FILE", tmp_path / "app.log")

    class _ExplodingRunner:
        def __init__(self, cfg, **kwargs) -> None:
            pass

        def run(self) -> int:
            raise ResponseFormatError("initDc 返回缺少 REPEAT_SUBMIT_TOKEN；尚未进入确认排队，本次任务已安全停止")

    monkeypatch.setattr(sidecar_module, "TicketRunner", _ExplodingRunner)
    monkeypatch.setattr(sidecar_module, "build_app_config", lambda settings: _StubConfig())
    bridge._token = CancellationToken()

    try:
        bridge._engine_thread({"train_date": "2099-01-01"})
    finally:
        bridge.close()

    terminal = writer.of_kind("exit")[0]
    assert terminal["data"]["exit_code"] == 2
    assert terminal["data"]["safe_stop"] is True
    assert terminal["data"]["exception_type"] == "ResponseFormatError"
    assert "安全停止" in terminal["message"]


class _StubEvent:
    def __init__(self, kind: str, message: str, data: Dict[str, Any]) -> None:
        self.kind = kind
        self.message = message
        self.data = data
        self.timestamp = 0.0


class _StubConfig:
    log_level = "INFO"
    passenger_names: List[str] = []