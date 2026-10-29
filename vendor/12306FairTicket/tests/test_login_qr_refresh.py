"""Offline regression: an expired QR code must not end the task.

The desktop window could only reach a fresh code by restarting the run, and the engine
used to raise on expiry to match — so missing the code in time cost the user the clock
correction, the station load and their place in the queue.  These tests pin the new
rule: the code is replaced, the run continues, and a frontend can ask for a new code
without stopping the task.
"""

from datetime import date, timedelta

import pytest
import requests

from ticket_app import client as client_module
from ticket_app.client import LOGIN_QR_MAX_CODES, RailwayClient
from ticket_app.configuration import AppConfig, AppError


@pytest.fixture(autouse=True)
def reject_network(monkeypatch):
    """The login loop must be exercised entirely through stubs."""

    def reject(*args, **kwargs):
        raise AssertionError("QR regression must not access the network")

    monkeypatch.setattr(requests.Session, "request", reject)


def make_config(**updates):
    values = {
        "cart_items": [
            {
                "from_station": "北京西",
                "to_station": "郑州东",
                "train_scope": "all",
                "train_code": "",
                "seat_type": "二等座",
            }
        ],
        "train_date": (date.today() + timedelta(days=2)).isoformat(),
        "passenger_names": ["测试甲"],
        "auto_submit": True,
        "persist_session": False,
        # Short enough that the whole suite stays instant; the real loop uses 180s.
        "login_qr_timeout_seconds": 0.3,
        "login_qr_poll_seconds": 0.01,
    }
    values.update(updates)
    return AppConfig.from_mapping(values)


class Harness:
    """A client whose QR lifecycle is scripted, plus the events it emitted."""

    def __init__(self, statuses, monkeypatch, **config_updates):
        self.events = []
        self.codes = 0
        self.statuses = list(statuses)
        self.client = RailwayClient(
            make_config(**config_updates),
            event_sink=self.events.append,
        )
        monkeypatch.setattr(self.client, "check_session", lambda: False)
        monkeypatch.setattr(self.client, "_prefetch_login_cookies", lambda: None)
        monkeypatch.setattr(self.client, "save_cookies", lambda: None)
        monkeypatch.setattr(self.client, "_complete_login", lambda: (True, "ok"))
        monkeypatch.setattr(self.client, "_create_qr_code", self._create_qr_code)
        monkeypatch.setattr(self.client, "_check_qr_status", self._check_qr_status)

    def _create_qr_code(self):
        self.codes += 1
        return b"png-bytes", f"uuid-{self.codes}"

    def _check_qr_status(self, uuid):
        # Exhausted scripts keep waiting, which is what an unscanned code looks like.
        return self.statuses.pop(0) if self.statuses else ("0", "")

    @property
    def qr_ready(self):
        return [event for event in self.events if event.kind == "qr_ready"]

    @property
    def qr_statuses(self):
        return [event.data.get("status") for event in self.events if event.kind == "qr_status"]

    @property
    def uuids(self):
        return [event.data.get("uuid") for event in self.qr_ready]


def test_expired_code_is_replaced_without_ending_the_task(monkeypatch):
    """The reported bug: expiry used to raise, so the task died and had to be restarted."""

    harness = Harness([("3", "expired"), ("2", "ok")], monkeypatch)

    harness.client.ensure_login()  # must not raise

    assert harness.codes == 2, "过期后应当自动生成第二张码"
    assert harness.uuids == ["uuid-1", "uuid-2"]
    assert harness.qr_statuses == ["waiting", "expired", "waiting", "confirmed"]


def test_expiry_message_says_a_new_code_is_coming(monkeypatch):
    """The interface shows this text, so it must not tell the user to restart."""

    harness = Harness([("3", "expired"), ("2", "ok")], monkeypatch)

    harness.client.ensure_login()

    expired = [event for event in harness.events if event.data.get("status") == "expired"]
    assert len(expired) == 1
    assert "正在生成新的二维码" in expired[0].message
    assert "重新开始" not in expired[0].message


def test_each_code_gets_its_own_expiry_deadline(monkeypatch):
    harness = Harness([("3", "expired"), ("2", "ok")], monkeypatch)

    harness.client.ensure_login()

    deadlines = [event.data["expires_at"] for event in harness.qr_ready]
    assert deadlines[1] > deadlines[0], "第二张码必须有新的有效期"


def test_refresh_request_reissues_the_code_without_stopping(monkeypatch):
    """「重新扫码」while the task runs: a new code, same run."""

    harness = Harness([("0", ""), ("2", "ok")], monkeypatch)
    harness.client.request_new_qr()

    harness.client.ensure_login()

    assert harness.codes == 2
    assert harness.uuids == ["uuid-1", "uuid-2"]
    assert "expired" in harness.qr_statuses, "换码时也要告诉前端旧码作废了"


def test_refresh_request_is_consumed_once(monkeypatch):
    """One request, one new code — otherwise the button would spin forever."""

    harness = Harness([("0", ""), ("2", "ok")], monkeypatch)
    harness.client.request_new_qr()

    harness.client.ensure_login()

    assert harness.codes == 2


def test_scanning_normally_still_uses_a_single_code(monkeypatch):
    harness = Harness([("1", "scanned"), ("2", "ok")], monkeypatch)

    harness.client.ensure_login()

    assert harness.codes == 1
    assert harness.qr_statuses == ["waiting", "scanned", "confirmed"]


def test_giving_up_after_the_cap_reports_how_many_codes_were_tried(monkeypatch):
    """The cap only exists so an unattended task cannot wait for a phone forever."""

    monkeypatch.setattr(client_module, "LOGIN_QR_MAX_CODES", 3)
    harness = Harness([("3", "expired")], monkeypatch)

    with pytest.raises(AppError) as failure:
        harness.client.ensure_login()

    assert harness.codes == 3
    assert str(3) in str(failure.value)


def test_an_existing_session_still_skips_the_code_entirely(monkeypatch):
    harness = Harness([], monkeypatch)
    monkeypatch.setattr(harness.client, "check_session", lambda: True)

    harness.client.ensure_login()

    assert harness.codes == 0
    assert harness.qr_statuses == ["logged_in"]


def test_the_cap_is_high_enough_to_be_worth_waiting_for():
    """A regression guard on the constant itself: 20 codes ≈ an hour by default."""

    assert LOGIN_QR_MAX_CODES >= 10