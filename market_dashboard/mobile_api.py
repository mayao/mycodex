from __future__ import annotations

from typing import Any

try:
    from portfolio_analytics import (
        build_dashboard_ai_payload_from_snapshot,
        build_dashboard_payload,
        build_stock_detail_payload,
    )
except ModuleNotFoundError:
    from market_dashboard.portfolio_analytics import (
        build_dashboard_ai_payload_from_snapshot,
        build_dashboard_payload,
        build_stock_detail_payload,
    )


def _tone_for_ratio(value: float, warn: float, risk: float) -> str:
    if value >= risk:
        return "down"
    if value >= warn:
        return "warn"
    return "up"


def _format_hkd(value: float | None) -> str:
    if value is None:
        return "N/A"
    return f"HK${value:,.0f}"


def _format_signed_hkd(value: float | None) -> str:
    if value is None:
        return "N/A"
    sign = "+" if value > 0 else "-" if value < 0 else ""
    return f"{sign}HK${abs(value):,.0f}"


def _format_pct(value: float | None) -> str:
    if value is None:
        return "N/A"
    return f"{value:.2f}%"


def _extract_sparkline_points(holding: dict[str, Any]) -> list[float]:
    history = holding.get("normalized_history") or holding.get("history") or []
    points: list[float] = []
    for row in history:
        if not isinstance(row, dict):
            continue
        value = row.get("value")
        if value is None:
            for key in ("normalized", "close", "price", "current_price"):
                if row.get(key) is not None:
                    value = row[key]
                    break
        if value is None:
            continue
        try:
            points.append(round(float(value), 4))
        except (TypeError, ValueError):
            continue
    return points[-30:]


def _compact_position(holding: dict[str, Any], note_by_symbol: dict[str, dict[str, Any]]) -> dict[str, Any]:
    note = note_by_symbol.get(holding["symbol"], {})
    return {
        "symbol": holding["symbol"],
        "name": holding["name"],
        "name_en": holding.get("name_en"),
        "market": holding["market"],
        "currency": holding["currency"],
        "category_name": holding["category_name"],
        "style_label": holding["style_label"],
        "fundamental_label": holding["fundamental_label"],
        "weight_pct": holding["weight_pct"],
        "statement_value_hkd": holding["statement_value_hkd"],
        "statement_pnl_pct": holding.get("statement_pnl_pct"),
        "statement_pnl_hkd": holding.get("statement_pnl_hkd"),
        "current_price": holding.get("current_price"),
        "change_pct": holding.get("change_pct"),
        "change_pct_5d": holding.get("change_pct_5d"),
        "trade_date": holding.get("trade_date"),
        "signal_score": holding.get("signal_score"),
        "signal_zone": holding.get("signal_zone"),
        "trend_state": holding.get("trend_state"),
        "position_label": holding.get("position_label"),
        "macro_signal": holding.get("macro_signal"),
        "news_signal": holding.get("news_signal"),
        "account_count": holding.get("account_count"),
        "stance": note.get("stance") or "继续跟踪",
        "role": note.get("role") or holding["style_label"],
        "summary": note.get("thesis") or holding.get("business_note"),
        "action": note.get("action") or holding.get("fundamental_note"),
        "watch_items": note.get("watch_items") or holding.get("watch_items"),
        "sparkline_points": _extract_sparkline_points(holding),
    }


def _pulse_category_for_topic(topic: dict[str, Any]) -> str:
    text = " ".join(
        str(topic.get(key) or "")
        for key in ("name", "headline", "summary", "impact_labels", "source")
    )
    if any(keyword in text for keyword in ("出口管制", "关税", "贸易", "制裁", "地缘", "外交", "政府", "政策", "监管")):
        return "政治/政策"
    if any(keyword in text for keyword in ("非农", "通胀", "利率", "就业", "消费", "GDP", "PMI", "增长", "联储", "央行")):
        return "经济/宏观"
    return "行业/主题"


def _pulse_tone_for_topic(topic: dict[str, Any]) -> str:
    score = float(topic.get("score") or 0.0)
    severity = str(topic.get("severity") or "")
    if score <= -1:
        return "down"
    if score >= 2:
        return "up"
    if severity == "高":
        return "warn"
    return "neutral"


def _pulse_tone_for_position(position: dict[str, Any]) -> str:
    stance = str(position.get("stance") or "")
    signal_score = int(position.get("signal_score") or 0)
    change_pct = float(position.get("change_pct") or 0.0)
    if any(keyword in stance for keyword in ("减仓", "降风险", "清理", "暂停")) or signal_score <= 44:
        return "down"
    if signal_score >= 68 and change_pct >= 0:
        return "up"
    return "warn"


def _recent_trade_index(recent_trades: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    trade_index: dict[str, dict[str, Any]] = {}
    for rank, trade in enumerate(recent_trades[:8]):
        symbol = str(trade.get("symbol") or "").strip()
        if not symbol or symbol in trade_index:
            continue
        trade_index[symbol] = {
            "rank": rank,
            "side": str(trade.get("side") or "").strip(),
            "date": str(trade.get("date") or "").strip(),
        }
    return trade_index


def _position_has_unusual_move(position: dict[str, Any]) -> bool:
    change_pct = abs(float(position.get("change_pct") or 0.0))
    change_pct_5d = abs(float(position.get("change_pct_5d") or 0.0))
    signal_score = int(position.get("signal_score") or 0)
    return change_pct >= 2.0 or change_pct_5d >= 4.0 or signal_score >= 68 or signal_score <= 44


def _position_unusual_move_priority(position: dict[str, Any]) -> tuple[float, float, int, float]:
    signal_score = int(position.get("signal_score") or 0)
    signal_gap = max(signal_score - 68, 44 - signal_score, 0)
    return (
        abs(float(position.get("change_pct_5d") or 0.0)),
        abs(float(position.get("change_pct") or 0.0)),
        signal_gap,
        float(position.get("weight_pct") or 0.0),
    )


def _position_has_macro_news_attention(position: dict[str, Any]) -> bool:
    macro_signal = str(position.get("macro_signal") or "").strip()
    news_signal = str(position.get("news_signal") or "").strip()
    return macro_signal not in {"", "中性"} or news_signal not in {"", "中性"}


def _position_macro_news_priority(position: dict[str, Any]) -> tuple[int, float, float, int]:
    macro_signal = str(position.get("macro_signal") or "").strip()
    news_signal = str(position.get("news_signal") or "").strip()
    macro_rank = 2 if macro_signal == "逆风" else 1 if macro_signal == "顺风" else 0
    news_rank = 2 if "偏空" in news_signal else 1 if "偏多" in news_signal else 0
    signal_score = int(position.get("signal_score") or 0)
    signal_gap = max(signal_score - 68, 44 - signal_score, 0)
    return (
        max(macro_rank, news_rank),
        float(position.get("weight_pct") or 0.0),
        abs(float(position.get("change_pct_5d") or 0.0)),
        signal_gap,
    )


def _position_has_trend_attention(position: dict[str, Any]) -> bool:
    trend_state = str(position.get("trend_state") or "").strip()
    signal_zone = str(position.get("signal_zone") or "").strip()
    return trend_state in {"强势上行", "修复抬头", "弱势下行"} or signal_zone in {"偏强跟踪", "偏弱跟踪"}


def _position_trend_priority(position: dict[str, Any]) -> tuple[int, float, float, int]:
    trend_state = str(position.get("trend_state") or "").strip()
    signal_zone = str(position.get("signal_zone") or "").strip()
    trend_rank = 2 if trend_state in {"弱势下行", "强势上行"} else 1 if trend_state == "修复抬头" else 0
    zone_rank = 1 if signal_zone in {"偏强跟踪", "偏弱跟踪"} else 0
    signal_score = int(position.get("signal_score") or 0)
    signal_gap = max(signal_score - 68, 44 - signal_score, 0)
    return (
        max(trend_rank, zone_rank),
        abs(float(position.get("change_pct_5d") or 0.0)),
        float(position.get("weight_pct") or 0.0),
        signal_gap,
    )


def _position_has_fundamental_attention(position: dict[str, Any]) -> bool:
    label = str(position.get("fundamental_label") or "").strip()
    signal_score = int(position.get("signal_score") or 0)
    pnl_pct = abs(float(position.get("statement_pnl_pct") or 0.0))
    return label in {"强", "偏弱", "工具属性"} and (
        signal_score >= 64 or signal_score <= 46 or pnl_pct >= 20.0 or float(position.get("weight_pct") or 0.0) >= 3.0
    )


def _position_fundamental_priority(position: dict[str, Any]) -> tuple[int, float, float, int]:
    label = str(position.get("fundamental_label") or "").strip()
    label_rank = {"偏弱": 3, "工具属性": 2, "强": 1}.get(label, 0)
    signal_score = int(position.get("signal_score") or 0)
    signal_gap = max(signal_score - 68, 44 - signal_score, 0)
    return (
        label_rank,
        float(position.get("weight_pct") or 0.0),
        abs(float(position.get("statement_pnl_pct") or 0.0)),
        signal_gap,
    )


def _stock_candidate_reason_parts(
    position: dict[str, Any],
    *,
    top_weight_ranks: dict[str, int],
    trade_index: dict[str, dict[str, Any]],
) -> list[str]:
    symbol = str(position.get("symbol") or "").strip()
    reason_parts = [f"权重 {float(position.get('weight_pct') or 0.0):.2f}%"]
    if symbol in top_weight_ranks:
        reason_parts.append(f"当前第 {top_weight_ranks[symbol] + 1} 大持仓")
    trade_info = trade_index.get(symbol)
    if trade_info:
        trade_text = " ".join(part for part in (trade_info.get("side"), trade_info.get("date")) if part)
        reason_parts.append(f"最近交易 {trade_text}" if trade_text else "最近交易")
    macro_signal = str(position.get("macro_signal") or "").strip()
    if macro_signal and macro_signal != "中性":
        reason_parts.append(f"宏观 {macro_signal}")
    news_signal = str(position.get("news_signal") or "").strip()
    if news_signal and news_signal != "中性":
        reason_parts.append(f"新闻 {news_signal}")
    trend_state = str(position.get("trend_state") or "").strip()
    if trend_state:
        reason_parts.append(f"趋势 {trend_state}")
    if _position_has_unusual_move(position):
        reason_parts.append(
            f"日内 {_format_pct(position.get('change_pct'))} · 5日 {_format_pct(position.get('change_pct_5d'))}"
        )
        signal_score = int(position.get("signal_score") or 0)
        if signal_score >= 68:
            reason_parts.append("信号偏强")
        elif signal_score <= 44:
            reason_parts.append("信号偏弱")
    return reason_parts


def _build_market_pulse_stock_candidates(
    positions: list[dict[str, Any]],
    recent_trades: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    max_candidates = 6
    positions_by_symbol = {str(item.get("symbol") or "").strip(): item for item in positions if str(item.get("symbol") or "").strip()}
    sorted_by_weight = sorted(positions, key=lambda row: float(row.get("weight_pct") or 0.0), reverse=True)
    top_weight_ranks = {item["symbol"]: rank for rank, item in enumerate(sorted_by_weight[:10])}
    trade_index = {
        symbol: info
        for symbol, info in _recent_trade_index(recent_trades).items()
        if symbol in positions_by_symbol
    }
    recent_trade_symbols = list(trade_index.keys())
    unusual_move_symbols = [
        item["symbol"]
        for item in sorted(
            [
                position
                for position in (sorted_by_weight[:12] or sorted_by_weight)
                if _position_has_unusual_move(position)
            ],
            key=_position_unusual_move_priority,
            reverse=True,
        )
    ]
    if not unusual_move_symbols:
        unusual_move_symbols = [
            item["symbol"]
            for item in sorted(
                [position for position in positions if _position_has_unusual_move(position)],
                key=_position_unusual_move_priority,
                reverse=True,
            )
        ]

    macro_news_symbols = [
        item["symbol"]
        for item in sorted(
            [position for position in sorted_by_weight[:14] if _position_has_macro_news_attention(position)],
            key=_position_macro_news_priority,
            reverse=True,
        )
    ]
    trend_symbols = [
        item["symbol"]
        for item in sorted(
            [position for position in sorted_by_weight[:14] if _position_has_trend_attention(position)],
            key=_position_trend_priority,
            reverse=True,
        )
    ]
    fundamental_symbols = [
        item["symbol"]
        for item in sorted(
            [position for position in sorted_by_weight[:14] if _position_has_fundamental_attention(position)],
            key=_position_fundamental_priority,
            reverse=True,
        )
    ]

    candidates: list[dict[str, Any]] = []
    seen_symbols: set[str] = set()

    def append_candidate(symbol: str, selection_reason: str) -> None:
        if not symbol or symbol in seen_symbols or symbol not in positions_by_symbol:
            return
        position = positions_by_symbol[symbol]
        candidates.append(
            {
                "position": position,
                "selection_reason": selection_reason,
                "reason_parts": _stock_candidate_reason_parts(
                    position,
                    top_weight_ranks=top_weight_ranks,
                    trade_index=trade_index,
                ),
            }
        )
        seen_symbols.add(symbol)

    for item in sorted_by_weight[:3]:
        symbol = item["symbol"]
        append_candidate(symbol, f"头部持仓关注 · 当前第 {top_weight_ranks.get(symbol, 0) + 1} 大仓位")
        if len(candidates) >= 2:
            break

    for symbol in recent_trade_symbols:
        trade_info = trade_index.get(symbol, {})
        trade_text = " ".join(
            part for part in (f"第 {int(trade_info.get('rank') or 0) + 1} 个唯一成交标的", trade_info.get("side"), trade_info.get("date")) if part
        )
        append_candidate(symbol, f"近期交易关注 · {trade_text}" if trade_text else "近期交易关注")
        if len(candidates) >= 3:
            break

    for symbol in macro_news_symbols:
        position = positions_by_symbol.get(symbol)
        if not position:
            continue
        append_candidate(
            symbol,
            f"宏观/新闻关注 · 宏观 {position.get('macro_signal') or '中性'} / 新闻 {position.get('news_signal') or '中性'}",
        )
        if len(candidates) >= 4:
            break

    for symbol in trend_symbols:
        position = positions_by_symbol.get(symbol)
        if not position:
            continue
        append_candidate(
            symbol,
            f"趋势影响关注 · {position.get('trend_state') or '无数据'} / {position.get('signal_zone') or '中性跟踪'}",
        )
        if len(candidates) >= 5:
            break

    for symbol in fundamental_symbols:
        position = positions_by_symbol.get(symbol)
        if not position:
            continue
        append_candidate(
            symbol,
            f"基本面验证关注 · {position.get('fundamental_label') or '中性'} / {position.get('stance') or '继续跟踪'}",
        )
        if len(candidates) >= max_candidates - 1:
            break

    for symbol in unusual_move_symbols:
        position = positions_by_symbol.get(symbol)
        if not position:
            continue
        signal_score = int(position.get("signal_score") or 0)
        move_bits = [
            f"日内 {_format_pct(position.get('change_pct'))}",
            f"5日 {_format_pct(position.get('change_pct_5d'))}",
        ]
        if signal_score >= 68:
            move_bits.append("信号偏强")
        elif signal_score <= 44:
            move_bits.append("信号偏弱")
        append_candidate(symbol, f"异常波动关注 · {' / '.join(move_bits)}")
        if len(candidates) >= max_candidates:
            break

    fallback_symbols = [item["symbol"] for item in sorted_by_weight[:10]] + recent_trade_symbols + macro_news_symbols + trend_symbols + fundamental_symbols + unusual_move_symbols
    for symbol in fallback_symbols:
        append_candidate(symbol, "补位关注 · 优先补足今日未覆盖的重点持仓")
        if len(candidates) >= max_candidates:
            break

    return candidates


def _build_market_pulse(
    *,
    analysis_date_cn: str,
    macro_topics: list[dict[str, Any]],
    holdings: list[dict[str, Any]],
    positions: list[dict[str, Any]],
    recent_trades: list[dict[str, Any]],
    priority_actions: list[dict[str, Any]],
    holding_notes: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    catalysts: list[dict[str, Any]] = []

    for topic in macro_topics[:5]:
        impacted_holdings = [
            item
            for item in sorted(holdings, key=lambda row: row["weight_pct"], reverse=True)
            if item.get("category") in topic.get("impact_categories", [])
        ][:3]
        related_symbols = [item["symbol"] for item in impacted_holdings]
        top_note = holding_notes.get(related_symbols[0], {}) if related_symbols else {}
        focus_label = related_symbols[0] if related_symbols else topic["name"]
        category = _pulse_category_for_topic(topic)
        tone = _pulse_tone_for_topic(topic)
        if tone == "down":
            advice = (
                str(top_note.get("action") or "").strip()
                or f"优先检查 {focus_label} 等仓位，确认该变量是否继续恶化后再决定是否放大风险。"
            )
        elif tone == "up":
            advice = (
                f"顺风可以利用，但不要把它当成追高理由。先围绕 {focus_label} 做验证后再加码。"
            )
        else:
            advice = (
                f"把 {topic['name']} 作为今日跟踪变量，等待下一次数据或政策更新，再决定仓位动作。"
            )
        catalysts.append(
            {
                "id": topic.get("id"),
                "category": category,
                "title": topic["name"],
                "headline": topic.get("headline") or topic.get("summary") or topic["name"],
                "summary": topic.get("summary") or topic.get("headline") or "",
                "impact_note": (
                    f"关联持仓约 {float(topic.get('impact_weight_pct') or 0.0):.2f}%"
                    + (f" · {topic['impact_labels']}" if topic.get("impact_labels") else "")
                    + (f" · 重点 {', '.join(related_symbols)}" if related_symbols else "")
                ),
                "advice": advice[:360],
                "related_symbols": related_symbols,
                "source": topic.get("source"),
                "published_at": topic.get("published_at"),
                "tone": tone,
            }
        )

    stock_candidates = _build_market_pulse_stock_candidates(positions, recent_trades)
    for candidate in stock_candidates[:6]:
        position = candidate["position"]
        impact_chunks = [
            candidate["selection_reason"],
            *candidate["reason_parts"],
            f"{position.get('role') or '核心观察'} · {position.get('stance') or '继续跟踪'}",
            f"宏观 {position.get('macro_signal') or '中性'} / 新闻 {position.get('news_signal') or '中性'}",
        ]
        catalysts.append(
            {
                "id": f"stock-{position['symbol']}",
                "category": "个股",
                "title": f"{position['symbol']} · {position['name']}",
                "headline": (
                    str(position.get("summary") or "").strip()
                    or str(position.get("action") or "").strip()
                    or f"当前处于 {position.get('trend_state') or '无数据'} / {position.get('signal_zone') or '中性跟踪'}"
                )[:220],
                "summary": (
                    f"权重 {float(position.get('weight_pct') or 0.0):.2f}%"
                    f" · 日内 {_format_pct(position.get('change_pct'))}"
                    f" · 5日 {_format_pct(position.get('change_pct_5d'))}"
                    f" · {position.get('trend_state') or '无数据'} / {position.get('signal_zone') or '中性跟踪'}。"
                ),
                "selection_reason": candidate["selection_reason"],
                "impact_note": " · ".join(str(item).strip() for item in impact_chunks if str(item).strip()),
                "advice": (
                    str(position.get("action") or "").strip()
                    or str(position.get("watch_items") or "").strip()
                    or "围绕趋势、信号和权重三件事管理仓位。"
                )[:360],
                "related_symbols": [position["symbol"]],
                "source": None,
                "published_at": position.get("trade_date"),
                "tone": _pulse_tone_for_position(position),
            }
        )

    catalysts = catalysts[:10]
    macro_title = catalysts[0]["title"] if catalysts else "宏观变量"
    stock_focuses = [
        item["position"]["symbol"]
        for item in stock_candidates[:6]
    ]
    stock_focus_summary = "、".join(item for item in stock_focuses if item) or "暂无个股关注"
    summary = (
        f"{analysis_date_cn} 优先跟踪 {macro_title}。"
        f"今日重点标的：{stock_focus_summary}。"
    )
    suggestions = [
        str(item.get("title") or "").strip()
        for item in priority_actions[:3]
        if str(item.get("title") or "").strip()
    ]
    if not suggestions:
        suggestions = [item["advice"] for item in catalysts[:3] if item.get("advice")]

    return {
        "headline": "今日市场与持仓重点",
        "summary": summary,
        "selection_logic": None,
        "catalysts": catalysts,
        "suggestions": suggestions[:5],
    }


def _tone_for_action_text(text: str) -> str:
    lowered = text.strip()
    if any(keyword in lowered for keyword in ("减仓", "降权", "暂停", "防守", "止损", "回撤")):
        return "down"
    if any(keyword in lowered for keyword in ("增持", "进攻", "继续持有", "加码", "提高")):
        return "up"
    if any(keyword in lowered for keyword in ("观察", "跟踪", "等待", "验证")):
        return "neutral"
    return "warn"


def _build_action_detail(parts: list[str], limit: int = 360) -> str | None:
    cleaned = [str(part).strip().rstrip("。；; ") for part in parts if str(part).strip()]
    if not cleaned:
        return None
    detail = "；".join(cleaned)
    return detail[:limit]


def _build_mobile_action_blocks(
    priority_actions: list[dict[str, Any]],
    ai_insights: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    ai_position_actions = (ai_insights or {}).get("position_actions") or []
    blocks: list[dict[str, Any]] = []

    for item in ai_position_actions[:4]:
        label = str(item.get("symbol") or item.get("name") or "AI").strip()[:18]
        badge = str(item.get("stance") or "AI").strip()[:20]
        title = str(item.get("action") or item.get("thesis") or badge).strip()[:72]
        detail = _build_action_detail(
            [
                str(item.get("thesis") or "").strip(),
                f"触发点：{item.get('trigger')}" if item.get("trigger") else "",
                f"风险：{item.get('risk')}" if item.get("risk") else "",
            ]
        )
        if not title:
            continue
        blocks.append(
            {
                "label": label or "AI",
                "title": title,
                "detail": detail,
                "badge": badge or None,
                "tone": _tone_for_action_text(f"{badge} {title}"),
            }
        )

    if blocks:
        return blocks

    for item in priority_actions[:4]:
        title = str(item.get("title") or "").strip()[:72]
        detail = _build_action_detail([str(item.get("detail") or "").strip()])
        if not title:
            continue
        blocks.append(
            {
                "label": "组合",
                "title": title,
                "detail": detail,
                "badge": "待执行",
                "tone": _tone_for_action_text(title),
            }
        )

    return blocks


def build_mobile_dashboard_payload(
    force_refresh: bool = False,
    include_live: bool = True,
    allow_cached_fallback: bool = True,
    include_ai: bool = False,
    user_id: str | None = None,
) -> dict[str, Any]:
    payload = build_dashboard_payload(
        force_refresh=force_refresh,
        include_live=include_live,
        allow_cached_fallback=allow_cached_fallback,
        include_ai=include_ai,
        user_id=user_id,
    )
    summary = payload["summary"]
    notes_by_symbol = {item["symbol"]: item for item in payload["brief"]["holding_notes"]}
    statement_source_by_account = {item["account_id"]: item for item in payload["statement_sources"]}
    positions = [_compact_position(item, notes_by_symbol) for item in payload["holdings"]]
    positions_with_pnl = [item for item in payload["holdings"] if item.get("statement_pnl_hkd") is not None]
    total_statement_pnl_hkd = sum(float(item.get("statement_pnl_hkd") or 0.0) for item in positions_with_pnl)

    primary_theme = payload["breakdowns"]["themes"][0] if payload["breakdowns"]["themes"] else None
    primary_broker = payload["breakdowns"]["brokers"][0] if payload["breakdowns"]["brokers"] else None
    live = payload["live"]
    macro = payload["macro"]

    live_note = (
        f"{live.get('provider_summary') or '结单价格'} · 行情更新 {live.get('updated_at') or '未记录'}"
        if live.get("tracked_count")
        else "当前先显示最近一次已同步的价格。"
    )
    macro_note = (
        f"宏观更新 {macro.get('updated_at') or '未记录'}"
        if macro.get("topics")
        else "市场主题整理中。"
    )

    summary_cards = [
        {
            "label": "净资产",
            "value": _format_hkd(summary["total_nav_hkd"]),
            "detail": f"结单窗口 {summary['statement_start_date']} 至 {summary['statement_end_date']}",
            "tone": "up",
        },
        {
            "label": "股票市值",
            "value": _format_hkd(summary["total_statement_value_hkd"]),
            "detail": f"{summary['holding_count']} 个持仓，头部主题 {primary_theme['label'] if primary_theme else '未识别'}",
            "tone": "neutral",
        },
        {
            "label": "盈亏额",
            "value": _format_signed_hkd(total_statement_pnl_hkd),
            "detail": f"{len(positions_with_pnl)} 个持仓已计算浮盈亏",
            "tone": "up" if total_statement_pnl_hkd > 0 else "down" if total_statement_pnl_hkd < 0 else "neutral",
        },
        {
            "label": "融资占用",
            "value": _format_hkd(summary["total_financing_hkd"]),
            "detail": f"约占净资产 {_format_pct((summary['total_financing_hkd'] / summary['total_nav_hkd'] * 100) if summary['total_nav_hkd'] else 0.0)}",
            "tone": _tone_for_ratio(
                (summary["total_financing_hkd"] / summary["total_nav_hkd"] * 100) if summary["total_nav_hkd"] else 0.0,
                warn=12.0,
                risk=20.0,
            ),
        },
        {
            "label": "衍生品名义敞口",
            "value": _format_hkd(summary["total_derivative_notional_hkd"]),
            "detail": f"{summary['derivative_count']} 条衍生品 / 结构化头寸",
            "tone": _tone_for_ratio(
                (summary["total_derivative_notional_hkd"] / summary["total_nav_hkd"] * 100) if summary["total_nav_hkd"] else 0.0,
                warn=12.0,
                risk=18.0,
            ),
        },
        {
            "label": "前五集中度",
            "value": _format_pct(summary["top5_ratio"]),
            "detail": f"第一大仓位 {_format_pct(summary['top1_weight_pct'])}",
            "tone": _tone_for_ratio(summary["top5_ratio"], warn=42.0, risk=50.0),
        },
        {
            "label": "账户覆盖",
            "value": f"{summary['account_count']} 个",
            "detail": f"主券商 {primary_broker['label'] if primary_broker else '未识别'}",
            "tone": "neutral",
        },
    ]

    accounts = []
    for account in payload["accounts"]:
        source = statement_source_by_account.get(account["account_id"], {})
        accounts.append(
            {
                "account_id": account["account_id"],
                "broker": account["broker"],
                "statement_date": account["statement_date"],
                "base_currency": account["base_currency"],
                "nav_hkd": account["nav_hkd"],
                "holdings_value_hkd": account["holdings_value_hkd"],
                "financing_hkd": account["financing_hkd"],
                "holding_count": account["holding_count"],
                "trade_count": account["trade_count"],
                "derivative_count": account["derivative_count"],
                "risk_notes": account.get("risk_notes") or [],
                "top_names": account.get("top_names"),
                "source_mode": source.get("source_mode"),
                "uploaded_at": source.get("uploaded_at"),
                "load_status": source.get("load_status"),
                "issue": source.get("issue"),
                "file_name": source.get("file_name"),
                "file_exists": source.get("file_exists"),
                "statement_type": source.get("statement_type"),
            }
        )

    return {
        "generated_at": payload["generated_at"],
        "analysis_date_cn": payload["analysis_date_cn"],
        "snapshot_date": payload["snapshot_date"],
        "hero": {
            "title": "MyInvAI",
            "subtitle": payload["headline"],
            "overview": payload["overview"],
            "snapshot_window": f"{summary['statement_start_date']} 至 {summary['statement_end_date']}",
            "live_note": live_note,
            "macro_note": macro_note,
            "primary_theme": primary_theme["label"] if primary_theme else None,
            "primary_broker": primary_broker["label"] if primary_broker else None,
        },
        "summary_cards": summary_cards,
        "market_pulse": _build_market_pulse(
            analysis_date_cn=payload["analysis_date_cn"],
            macro_topics=payload["macro"]["topics"][:6],
            holdings=payload["holdings"],
            positions=positions,
            recent_trades=payload["trades"],
            priority_actions=payload["brief"]["priority_actions"],
            holding_notes=notes_by_symbol,
        ),
        "source_health": payload["source_health"],
        "key_drivers": payload["key_drivers"],
        "risk_flags": [{**item, "tone": "down"} for item in payload["risk_flags"]],
        "action_center": {
            "headline": payload["brief"]["headline"],
            "overview": payload["brief"]["overview"],
            "priority_actions": payload["brief"]["priority_actions"],
            "disclaimer": payload["brief"]["disclaimer"],
        },
        "action_blocks": _build_mobile_action_blocks(payload["brief"]["priority_actions"], payload.get("ai_insights")),
        "ai_updated_at": payload["generated_at"] if include_ai else None,
        "ai_engine_label": ((payload.get("ai_insights") or {}).get("engine") or {}).get("label"),
        "health_radar": payload["charts"]["health_radar"],
        "allocation_groups": {
            "themes": payload["breakdowns"]["themes"],
            "markets": payload["breakdowns"]["markets"],
            "brokers": payload["breakdowns"]["brokers"],
        },
        "macro_topics": payload["macro"]["topics"][:8],
        "strategy_views": payload["strategy_views"],
        "positions": positions,
        "spotlight_positions": positions[:10],
        "accounts": accounts,
        "recent_trades": payload["trades"],
        "derivatives": payload["derivatives"][:12],
        "statement_sources": payload["statement_sources"],
        "reference_sources": payload["reference_sources"],
        "update_guide": payload["update_guide"],
    }


def build_mobile_dashboard_ai_payload(
    force_refresh: bool = False,
    allow_cached_fallback: bool = True,
    user_id: str | None = None,
) -> dict[str, Any]:
    snapshot = build_dashboard_payload(
        force_refresh=force_refresh,
        include_live=False,
        allow_cached_fallback=allow_cached_fallback,
        include_ai=False,
        user_id=user_id,
    )
    ai_payload = build_dashboard_ai_payload_from_snapshot(snapshot)
    ai_insights = ai_payload.get("ai_insights") or {}
    return {
        "generated_at": ai_payload["generated_at"],
        "analysis_date_cn": ai_payload["analysis_date_cn"],
        "action_blocks": _build_mobile_action_blocks(snapshot["brief"]["priority_actions"], ai_insights),
        "ai_updated_at": ai_payload["generated_at"],
        "ai_engine_label": (ai_insights.get("engine") or {}).get("label"),
        "ai_status_message": (ai_payload.get("ai_status") or {}).get("message") or "AI 洞察已刷新。",
    }


def build_mobile_stock_detail_ai_payload(
    symbol: str,
    force_refresh: bool = False,
    allow_cached_fallback: bool = True,
    share_mode: bool = False,
    user_id: str | None = None,
) -> dict[str, Any]:
    payload = build_stock_detail_payload(
        symbol=symbol,
        force_refresh=force_refresh,
        include_live=False,
        allow_cached_fallback=allow_cached_fallback,
        share_mode=share_mode,
        user_id=user_id,
    )
    return {
        "generated_at": payload["generated_at"],
        "analysis_date_cn": payload["analysis_date_cn"],
        "executive_summary": payload["executive_summary"],
        "bull_case": payload["bull_case"],
        "bear_case": payload["bear_case"],
        "watchlist": payload["watchlist"],
        "action_plan": payload["action_plan"],
        "ai_status_message": "AI 洞察已刷新。",
    }


def build_mobile_ai_chat_context(
    context_type: str,
    *,
    symbol: str | None = None,
    force_refresh: bool = False,
    allow_cached_fallback: bool = True,
    user_id: str | None = None,
) -> dict[str, Any]:
    normalized_context = (context_type or "dashboard").strip().lower()
    if normalized_context == "holding":
        if not symbol:
            raise KeyError("missing symbol")
        payload = build_stock_detail_payload(
            symbol=symbol,
            force_refresh=force_refresh,
            include_live=False,
            allow_cached_fallback=allow_cached_fallback,
            share_mode=False,
            user_id=user_id,
        )
        return {
            "context_type": "holding",
            "context_title": f"{payload['hero']['name']} ({payload['hero']['symbol']})",
            "analysis_date_cn": payload["analysis_date_cn"],
            "hero": payload["hero"],
            "executive_summary": payload["executive_summary"][:4],
            "focus_cards": payload["focus_cards"][:6],
            "portfolio_context": payload["portfolio_context"][:6],
            "bull_case": payload["bull_case"][:3],
            "bear_case": payload["bear_case"][:3],
            "watchlist": payload["watchlist"][:4],
            "action_plan": payload["action_plan"][:4],
            "peers": [
                {
                    "symbol": item["symbol"],
                    "name": item["name"],
                    "signal_score": item.get("signal_score"),
                    "signal_zone": item.get("signal_zone"),
                    "trend_state": item.get("trend_state"),
                    "change_pct": item.get("change_pct"),
                }
                for item in payload["peers"][:4]
            ],
            "holding_note": payload["holding_note"],
        }

    payload = build_dashboard_payload(
        force_refresh=force_refresh,
        include_live=False,
        allow_cached_fallback=allow_cached_fallback,
        include_ai=False,
        user_id=user_id,
    )
    holding_notes = payload["brief"]["holding_notes"]
    return {
        "context_type": "dashboard",
        "context_title": "MyInvAI 总览",
        "analysis_date_cn": payload["analysis_date_cn"],
        "headline": payload["headline"],
        "overview": payload["overview"],
        "summary": payload["summary"],
        "macro_topics": payload["macro"]["topics"][:4],
        "key_drivers": payload["key_drivers"][:4],
        "risk_flags": payload["risk_flags"][:4],
        "priority_actions": payload["brief"]["priority_actions"][:4],
        "holding_notes": [
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "weight_pct": item["weight_pct"],
                "stance": item["stance"],
                "role": item["role"],
                "thesis": item["thesis"],
                "action": item["action"],
                "risk": item["risk"],
            }
            for item in sorted(holding_notes, key=lambda row: row["weight_pct"], reverse=True)[:8]
        ],
    }
