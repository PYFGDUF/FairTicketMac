"""Declarative descriptor for the editable settings surface.

Both frontends render the same form, so the labels, help text, control kind and
practical input ranges live here instead of being retyped per toolkit.  The
PySide6 window keeps its own bespoke layout code (it was written first), but the
*authoritative* bounds remain :data:`ticket_app.gui.validation.NUMERIC_FIELD_RULES`;
``tests/test_sidecar_protocol.py`` asserts the two agree, so a frontend that reads
this descriptor cannot offer a value the validator would reject.

The strings here are the ones the desktop form actually shows, preserved verbatim
so a replacement frontend keeps the product's voice.

The version-5 form is built around ``cart_items``: the ordered list of
``{from_station, to_station, train_scope, train_code, seat_type}`` entries that
the engine tries in order.  There is deliberately no ``seat_types`` spec -- the
engine derives the seat list from the cart, and a second control for it is exactly
how the two would drift apart.  ``priority_strategy`` and ``empty_train_scope``
are gone from the engine as well: the cart order *is* the priority rule.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Tuple

#: Render order for ``FieldSpec.group``.  Mirrors the desktop window's cards.
#: The names are deliberately *not* the frontends' page titles: a page and its only
#: card should not print the same heading twice.
GROUP_ORDER: Tuple[str, ...] = (
    "备选列表",
    "日期与时间",
    "乘车人与票种",
    "座位与铺位偏好",
    "任务模式",
    "查询与热身",
    "网络、登录与校时",
    "出票等待与诊断",
)

PAGE_BASIC = "basic"
PAGE_ADVANCED = "advanced"

#: Canonical keys handled by dedicated composite widgets rather than one control.
COMPOSITE_KEYS: Tuple[str, ...] = (
    "cart_items",
    "passenger_ticket_types",
    "seat_position_preferences",
    "berth_preference",
)


@dataclass(frozen=True)
class FieldSpec:
    """One editable field as the desktop form presents it."""

    key: str
    label: str
    page: str = PAGE_BASIC
    group: str = ""
    #: ``text`` | ``list`` | ``date`` | ``time`` | ``number`` | ``integer`` |
    #: ``toggle`` | ``choice`` | ``cart`` | ``ticket_types`` | ``seat_map`` |
    #: ``berths``
    kind: str = "text"
    help: str = ""
    placeholder: str = ""
    minimum: float | None = None
    maximum: float | None = None
    step: float | None = None
    decimals: int = 0
    suffix: str = ""
    #: ``(value, label)`` pairs for ``choice`` fields.
    options: Tuple[Tuple[str, str], ...] = ()
    #: For ``time`` fields: the label of the checkbox that switches this field
    #: off, which serialises to an empty string.
    optional_toggle: str = ""
    #: ``toggle`` fields carry their sentence here instead of a separate label.
    inline_label: str = ""
    #: Composite widgets that can be present but inactive, and must not be
    #: validated while their seat family is unselected.  The cart is the only
    #: source of seat capability now, so both preferences watch ``cart_items``.
    dormant_until: str = ""


FIELD_SPECS: Tuple[FieldSpec, ...] = (
    # ----------------------------- 备选列表 -----------------------------
    FieldSpec(
        key="cart_items",
        label="备选购物车",
        group="备选列表",
        kind="cart",
        help=(
            "按顺序尝试的备选路线；任意一项成功出票后，其余备选停止。"
            "每一项由出发站、到达站、车次范围和席别组成。"
        ),
    ),
    # ----------------------------- 日期与时间 -----------------------------
    FieldSpec(
        key="train_date",
        label="乘车日期",
        group="日期与时间",
        kind="date",
    ),
    FieldSpec(
        key="start_at",
        label="开始 / 开售时间",
        group="日期与时间",
        kind="time",
        help="按时、分、秒设置每日开始时间；勾选“立即开始”后不等待。",
        optional_toggle="立即开始",
    ),
    FieldSpec(
        key="stop_at",
        label="停止时间",
        group="日期与时间",
        kind="time",
        help="到达该时间后安全停止查询；勾选“不设停止时间”则由最大查询轮数控制。",
        optional_toggle="不设停止时间",
    ),
    # ------------------------------ 乘车人与票种 ------------------------------
    FieldSpec(
        key="passenger_names",
        label="乘车人",
        group="乘车人与票种",
        kind="list",
        placeholder="张三，李四（最多 5 人）",
        help=(
            "自动提交时填写 1–5 个已在当前 12306 账户中的姓名；仅监控可留空。"
            "多个姓名可用中英文逗号、顿号、中英文分号、换行或制表符分隔。"
        ),
    ),
    FieldSpec(
        key="passenger_ticket_types",
        label="购票类型",
        group="乘车人与票种",
        kind="ticket_types",
        help=(
            "按乘车人覆盖票种；留空即沿用该联系人在 12306 的记录。"
            "学生票需要联系人在 12306 已完成学生资质核验。"
        ),
    ),
    # --------------------------- 座位与铺位偏好 ---------------------------
    FieldSpec(
        key="seat_position_preferences",
        label="座位关系",
        group="座位与铺位偏好",
        kind="seat_map",
        help="偏好仅在对应席别和服务端支持时生效，不改变车次或席别；无法满足时接受系统分配。",
        dormant_until="cart_items",
    ),
    FieldSpec(
        key="berth_preference",
        label="铺位数量",
        group="座位与铺位偏好",
        kind="berths",
        dormant_until="cart_items",
    ),
    FieldSpec(
        key="quiet_carriage_preference",
        label="静音车厢",
        group="座位与铺位偏好",
        kind="toggle",
        inline_label="优先静音车厢",
        help="仅在列车提供静音服务且当前候选为二等座时提交偏好；不保证分配成功。",
    ),
    # ------------------------------ 任务模式 ------------------------------
    FieldSpec(
        key="auto_submit",
        label="提交方式",
        group="任务模式",
        kind="toggle",
        inline_label="发现符合条件的票后自动提交订单",
        help="关闭后仅查询并提示票源，不提交订单，也不要求填写乘车人。",
    ),
    # ------------------------------ 查询与热身 ------------------------------
    FieldSpec(
        key="query_interval_seconds",
        label="常规查询间隔",
        page=PAGE_ADVANCED,
        group="查询与热身",
        kind="number",
        minimum=0.05,
        maximum=60.0,
        step=0.05,
        decimals=2,
        suffix=" 秒",
        help="默认 0.60 秒，范围 0.05–60 秒。过低可能触发限流。",
    ),
    FieldSpec(
        key="max_retries",
        label="最大查询轮数",
        page=PAGE_ADVANCED,
        group="查询与热身",
        kind="integer",
        minimum=1,
        maximum=100000,
        step=1,
        help="默认 1000 轮，范围 1–100000。数值越大，任务可能运行越久。",
    ),
    FieldSpec(
        key="pre_query_seconds",
        label="提前热身",
        page=PAGE_ADVANCED,
        group="查询与热身",
        kind="number",
        minimum=0.0,
        maximum=60.0,
        step=0.1,
        decimals=2,
        suffix=" 秒",
        help="默认 1.50 秒，范围 0–60 秒。在开始时间前进入热身。",
    ),
    FieldSpec(
        key="hot_query_interval_seconds",
        label="热身查询间隔",
        page=PAGE_ADVANCED,
        group="查询与热身",
        kind="number",
        minimum=0.05,
        maximum=10.0,
        step=0.05,
        decimals=2,
        suffix=" 秒",
        help="默认 0.25 秒，范围 0.05–10 秒。过低可能触发限流。",
    ),
    FieldSpec(
        key="hot_window_seconds",
        label="开售后热身窗口",
        page=PAGE_ADVANCED,
        group="查询与热身",
        kind="number",
        minimum=0.0,
        maximum=120.0,
        step=0.5,
        decimals=2,
        suffix=" 秒",
        help="默认 5 秒，范围 0–120 秒。窗口后恢复常规查询间隔。",
    ),
    # --------------------------- 网络、登录与校时 ---------------------------
    FieldSpec(
        key="request_timeout_seconds",
        label="请求超时",
        page=PAGE_ADVANCED,
        group="网络、登录与校时",
        kind="number",
        minimum=1.0,
        maximum=120.0,
        step=1.0,
        decimals=2,
        suffix=" 秒",
        help="默认 10 秒，范围 1–120 秒。过短会把慢响应误判为失败。",
    ),
    FieldSpec(
        key="login_qr_timeout_seconds",
        label="扫码超时",
        page=PAGE_ADVANCED,
        group="网络、登录与校时",
        kind="number",
        minimum=30.0,
        maximum=900.0,
        step=10.0,
        decimals=2,
        suffix=" 秒",
        help="默认 180 秒，范围 30–900 秒。过期后会自动换一张码，任务不中断。",
    ),
    FieldSpec(
        key="login_qr_poll_seconds",
        label="扫码状态间隔",
        page=PAGE_ADVANCED,
        group="网络、登录与校时",
        kind="number",
        minimum=0.2,
        maximum=10.0,
        step=0.1,
        decimals=2,
        suffix=" 秒",
        help="默认 1 秒，范围 0.2–10 秒。过低会增加登录接口请求。",
    ),
    FieldSpec(
        key="time_sync_samples",
        label="校时采样数",
        page=PAGE_ADVANCED,
        group="网络、登录与校时",
        kind="integer",
        minimum=1,
        maximum=30,
        step=1,
        help="默认 7 次，范围 1–30。更多采样会延长准备阶段。",
    ),
    FieldSpec(
        key="time_sync_max_rtt_seconds",
        label="校时最大 RTT",
        page=PAGE_ADVANCED,
        group="网络、登录与校时",
        kind="number",
        minimum=0.05,
        maximum=10.0,
        step=0.05,
        decimals=2,
        suffix=" 秒",
        help="默认 1 秒，范围 0.05–10 秒。高延迟样本将被丢弃。",
    ),
    # --------------------------- 出票等待与诊断 ---------------------------
    FieldSpec(
        key="order_wait_attempts",
        label="出票查询次数",
        page=PAGE_ADVANCED,
        group="出票等待与诊断",
        kind="integer",
        minimum=1,
        maximum=1000,
        step=1,
        help="默认 300 次，范围 1–1000。用于提交后的排队结果查询。",
    ),
    FieldSpec(
        key="order_wait_interval_seconds",
        label="出票查询间隔",
        page=PAGE_ADVANCED,
        group="出票等待与诊断",
        kind="number",
        minimum=0.1,
        maximum=60.0,
        step=0.1,
        decimals=2,
        suffix=" 秒",
        help="默认 2 秒，范围 0.1–60 秒。过低会增加排队接口请求。",
    ),
    FieldSpec(
        key="station_cache_days",
        label="站点缓存天数",
        page=PAGE_ADVANCED,
        group="出票等待与诊断",
        kind="integer",
        minimum=1,
        maximum=365,
        step=1,
        help="默认 7 天，范围 1–365。仅影响购票任务对缓存新鲜度的判断。",
    ),
    FieldSpec(
        key="log_level",
        label="日志级别",
        page=PAGE_ADVANCED,
        group="出票等待与诊断",
        kind="choice",
        options=(
            ("DEBUG", "DEBUG"),
            ("INFO", "INFO"),
            ("WARNING", "WARNING"),
            ("ERROR", "ERROR"),
        ),
        help="默认 INFO。DEBUG 信息最多，ERROR 只显示错误。",
    ),
    FieldSpec(
        key="perf_log",
        label="性能日志",
        page=PAGE_ADVANCED,
        group="出票等待与诊断",
        kind="toggle",
        inline_label="显示关键阶段耗时",
        help="默认开启；记录校时、查询、提交等阶段耗时，不改变请求节奏。",
    ),
)

FIELD_SPEC_BY_KEY = {spec.key: spec for spec in FIELD_SPECS}


def specs_for_page(page: str) -> Tuple[FieldSpec, ...]:
    return tuple(spec for spec in FIELD_SPECS if spec.page == page)


def spec_to_mapping(spec: FieldSpec) -> dict:
    """Serialise one spec for the wire protocol."""

    return {
        "key": spec.key,
        "label": spec.label,
        "page": spec.page,
        "group": spec.group,
        "kind": spec.kind,
        "help": spec.help,
        "placeholder": spec.placeholder,
        "minimum": spec.minimum,
        "maximum": spec.maximum,
        "step": spec.step,
        "decimals": spec.decimals,
        "suffix": spec.suffix,
        "options": [{"value": value, "label": label} for value, label in spec.options],
        "optional_toggle": spec.optional_toggle,
        "inline_label": spec.inline_label,
        "dormant_until": spec.dormant_until,
    }