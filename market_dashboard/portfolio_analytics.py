from __future__ import annotations

import re
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

try:
    from market_context import fetch_live_bundle, fetch_macro_bundle, load_local_analysis_cache
    from statement_parser import USD_HKD_RATE, load_real_portfolio
    from statement_sources import REFERENCE_ANALYSIS_SOURCES, STATEMENT_SOURCES
    from universe import ASSETS, CATEGORIES
except ModuleNotFoundError:
    from market_dashboard.market_context import fetch_live_bundle, fetch_macro_bundle, load_local_analysis_cache
    from market_dashboard.statement_parser import USD_HKD_RATE, load_real_portfolio
    from market_dashboard.statement_sources import REFERENCE_ANALYSIS_SOURCES, STATEMENT_SOURCES
    from market_dashboard.universe import ASSETS, CATEGORIES


CN_TZ = timezone(timedelta(hours=8))
ASSET_BY_SYMBOL = {asset["symbol"]: asset for asset in ASSETS}
CATEGORY_BY_ID = {category["id"]: category for category in CATEGORIES}
HOLDING_META_OVERRIDES: dict[str, dict[str, Any]] = {
    "06606.HK": {
        "symbol": "06606.HK",
        "quote_code": "6606.hk",
        "market": "HK",
        "currency": "HKD",
        "name": "New Horizon Health",
        "name_zh": "诺辉健康",
        "category": "healthcare_special",
        "fundamental_score": 2,
        "risk_level": "高",
        "style": "speculative",
        "business_note": "偏单品与监管主题的医疗成长资产，波动高于主流平台股。",
        "fundamental_note": "需要更严格关注产品兑现和现金流，不适合无纪律重仓。",
        "watch_items": "核心产品销售、监管、现金流、融资",
    },
    "07709.HK": {
        "category": "ai_compute",
        "business_note": "这是海力士方向的两倍杠杆工具，本质属于半导体主题交易仓。",
        "fundamental_note": "工具属性强于公司基本面，重点不在长期价值，而在持有期限与波动控制。",
        "watch_items": "HBM 价格、海力士景气、持有期限、止损纪律",
    },
}
SYMBOL_META_ALIASES = {
    "45769.HK": "06606.HK",
}
REVERSE_SYMBOL_META_ALIASES = {value: key for key, value in SYMBOL_META_ALIASES.items()}
STYLE_LABELS = {
    "quality": "核心资产",
    "platform": "平台型资产",
    "turnaround": "修复仓",
    "leveraged": "杠杆工具",
    "speculative": "高波动卫星",
    "stablecoin": "支付/稳定币",
    "cyclical": "周期成长",
    "high_growth": "高成长",
    "defensive_growth": "防守成长",
    "crypto_beta": "Crypto Beta",
    "unclassified": "其他",
}
FUNDAMENTAL_LABELS = {
    1: "工具属性",
    2: "偏弱",
    3: "中性",
    4: "稳健",
    5: "强",
}
STYLE_FAMILY_BY_STYLE = {
    "quality": "quality_core",
    "defensive_growth": "quality_core",
    "platform": "platform_repair",
    "turnaround": "platform_repair",
    "cyclical": "cyclical_growth",
    "high_growth": "cyclical_growth",
    "stablecoin": "cyclical_growth",
    "crypto_beta": "event_beta",
    "speculative": "event_beta",
    "leveraged": "tactical_tools",
    "unclassified": "other",
}
STYLE_FAMILY_LABELS = {
    "quality_core": "质量复利",
    "platform_repair": "平台/修复",
    "cyclical_growth": "周期成长",
    "event_beta": "事件高波动",
    "tactical_tools": "杠杆交易",
    "other": "其他",
}
ACTION_PLAYBOOK: dict[str, dict[str, str]] = {
    "00700.HK": {
        "role": "核心底仓",
        "stance": "持有但控上限",
        "risk": "它是好资产，但不是用来对冲其他大亏仓位的万能保险。",
        "action": "保留为港股底仓，但单一资产权重不宜长期维持在 20% 附近以上。",
    },
    "03690.HK": {
        "role": "问题仓",
        "stance": "反弹减仓",
        "risk": "大仓位叠加深度浮亏，正在主导组合波动和情绪。",
        "action": "把目标改成降权而不是回本；优先利用反弹或波段窗口把风险权重降下来。",
    },
    "09988.HK": {
        "role": "修复仓",
        "stance": "保留修复弹性",
        "risk": "估值修复需要业务兑现，不宜被动抬到核心仓级别。",
        "action": "维持修复仓定位，和腾讯分开看待；若云与回购兑现，可保留中等权重。",
    },
    "MSTR": {
        "role": "高 Beta 卫星",
        "stance": "反弹降杠杆",
        "risk": "既有正股，又有卖 Put，等于把 Crypto 波动和杠杆叠在一起。",
        "action": "把它当卫星仓，不再让其兼任方向仓和衍生品收租仓；优先压缩总暴露。",
    },
    "BMNR": {
        "role": "投机仓",
        "stance": "缩到极小仓",
        "risk": "小市值加密题材弹性大，但流动性和估值回撤更快。",
        "action": "不建议继续承接主要风险预算，除非你明确只保留非常小的事件仓位。",
    },
    "NVDA": {
        "role": "核心成长",
        "stance": "核心观察持有",
        "risk": "高位时波动会放大，但它依然是 AI 主线里确定性最高的资产之一。",
        "action": "适合作为美股核心成长仓，重点看仓位纪律，而不是频繁做 T。",
    },
    "AMD": {
        "role": "次核心成长",
        "stance": "观察持有",
        "risk": "AI 兑现度不如 NVDA，容易在景气与估值切换里波动放大。",
        "action": "保留观察仓，等兑现度进一步明确后再决定是否提升权重。",
    },
    "ORCL": {
        "role": "AI 基建仓",
        "stance": "小仓等待修复",
        "risk": "当前成本较高，若继续弱于预期，会拖累组合效率。",
        "action": "先把它当等待验证的 AI 基建仓，不急于补仓摊薄。",
    },
    "CRCL": {
        "role": "主题成长仓",
        "stance": "保留弹性但控仓",
        "risk": "好处是叙事顺，坏处是同样受风险偏好驱动明显。",
        "action": "保留但不宜过度加码，避免和 MSTR/BMNR 一起堆出单边加密贝塔。",
    },
    "META": {
        "role": "现金流成长仓",
        "stance": "继续持有",
        "risk": "权重不大，但如果只是小仓试错，别指望它单独对冲其他亏损。",
        "action": "这类资产更适合稳态复利，可以作为组合质量锚的一部分。",
    },
    "HIMS": {
        "role": "主题仓",
        "stance": "缩仓观察",
        "risk": "医疗成长叠加单品与监管风险，波动不适合做大仓。",
        "action": "更适合事件驱动或轻仓跟踪，不建议再和结构性产品一起叠加暴露。",
    },
    "HOOD": {
        "role": "平台成长仓",
        "stance": "持有观察",
        "risk": "交易活跃度与风险偏好波动会传导到业绩。",
        "action": "保持中等以下权重，和 IBKR 分成成长弹性与稳健券商两类仓看待。",
    },
    "IBKR": {
        "role": "稳健券商仓",
        "stance": "可保留",
        "risk": "弹性不高，但胜在经营质量和波动收敛。",
        "action": "如果想提高组合质量，可以把这类仓位当作券商板块里的稳定器。",
    },
    "07709.HK": {
        "role": "杠杆工具",
        "stance": "只做交易仓",
        "risk": "两倍杠杆产品持有时间越长，路径损耗越明显。",
        "action": "限定持有周期和止损规则，不纳入中长期收益预期。",
    },
    "TSLL": {
        "role": "杠杆工具",
        "stance": "只做交易仓",
        "risk": "这是波动放大器，不是企业基本面仓。",
        "action": "若继续保留，必须把它和长期仓完全分账管理。",
    },
    "XPEV": {
        "role": "高波动成长",
        "stance": "观察或缩仓",
        "risk": "行业竞争和盈利兑现都不稳定，赔率不够时不要恋战。",
        "action": "除非你有很强的行业观点，否则更适合作为轻仓交易仓。",
    },
    "NIO": {
        "role": "弱修复仓",
        "stance": "优先清理尾部",
        "risk": "在高亏损状态下继续占用资金，会拖慢组合重建速度。",
        "action": "把它当需要处理的不良资产，而不是等待奇迹的仓位。",
    },
    "06606.HK": {
        "role": "高风险主题仓",
        "stance": "极小仓跟踪",
        "risk": "流动性、监管和商业兑现都偏弱，承受不了大仓位。",
        "action": "如果继续保留，只适合极小仓位观察，不宜占用过多注意力。",
    },
}
REFERENCE_FRAMEWORK = [
    "先做组合诊断，再看个股：集中度、融资、衍生品是上层约束，选股逻辑是下层执行。",
    "同时保留五种视角：自上而下宏观、自下而上基本面、趋势动量、估值修复、事件驱动。",
    "把建议写成四段式：核心逻辑、验证指标、失效条件、执行动作，避免只有方向没有处置。",
    "负 Gamma 工具不能当主建仓手段。卖 Put、FCN、杠杆 ETF 只能放在受限额度里。",
    "核心-卫星结构比单纯选股更重要：核心仓追求复利，卫星仓追求赔率，二者不能混账。",
    "关键因子必须被显式高亮：宏观政策、监管、价格位置、基本面质量和仓位纪律缺一不可。",
]


def symbol_variants(symbol: str) -> list[str]:
    variants = [symbol]
    canonical = SYMBOL_META_ALIASES.get(symbol, symbol)
    if canonical not in variants:
        variants.append(canonical)
    reverse_alias = REVERSE_SYMBOL_META_ALIASES.get(symbol)
    if reverse_alias and reverse_alias not in variants:
        variants.append(reverse_alias)
    return variants


def lookup_symbol_value(mapping: dict[str, Any], symbol: str, default: Any = None) -> Any:
    for candidate in symbol_variants(symbol):
        if candidate in mapping:
            return mapping[candidate]
    return default


def fundamental_label(score: int | None) -> str:
    if score is None:
        return "未知"
    return FUNDAMENTAL_LABELS.get(int(score), "中性")


def news_signal_label(score: int) -> str:
    if score >= 4:
        return "显著偏多"
    if score >= 2:
        return "偏多"
    if score <= -4:
        return "显著偏空"
    if score <= -2:
        return "偏空"
    return "中性"


def infer_trend_state(
    current_price: float | None,
    ma20: float | None,
    ma60: float | None,
    reasons: list[str] | None = None,
) -> str:
    if current_price is not None and ma20 is not None and ma60 is not None:
        if current_price >= ma20 >= ma60:
            return "强势上行"
        if current_price >= ma20 and current_price < ma60:
            return "修复抬头"
        if current_price < ma20 < ma60:
            return "弱势下行"
        if current_price < ma20 and current_price >= ma60:
            return "高位震荡"
        return "震荡待确认"

    reason_blob = "；".join(reasons or [])
    if "站上 20 日均线" in reason_blob and "站上 60 日均线" in reason_blob:
        return "强势上行"
    if "站上 20 日均线" in reason_blob:
        return "修复抬头"
    if "仍在 20 日均线下方" in reason_blob and "仍在 60 日均线下方" in reason_blob:
        return "弱势下行"
    if "仍在 20 日均线下方" in reason_blob and "站上 60 日均线" in reason_blob:
        return "高位震荡"
    if reason_blob:
        return "震荡待确认"
    return "无数据"


def factor_score_bucket(value: int) -> int:
    return max(-2, min(2, int(value)))


def trend_factor_score(trend_state: str) -> int:
    return {
        "强势上行": 2,
        "修复抬头": 1,
        "震荡待确认": 0,
        "高位震荡": -1,
        "弱势下行": -2,
        "无数据": 0,
    }.get(trend_state, 0)


def risk_factor_score(holding: dict[str, Any]) -> int:
    level_map = {"低": 2, "中": 1, "中高": 0, "高": -1, "很高": -2}
    score = level_map.get(holding.get("risk_level"), 0)
    if holding.get("style") in {"leveraged", "speculative", "crypto_beta"}:
        score -= 1
    if (holding.get("weight_pct") or 0.0) >= 10:
        score -= 1
    if (holding.get("statement_pnl_pct") or 0.0) <= -40:
        score -= 1
    return factor_score_bucket(score)


def composite_signal_score(
    fundamental_score_factor: int,
    trend_score_factor: int,
    news_score_factor: int,
    macro_score_factor: int,
    risk_score_factor: int,
) -> int:
    score = 50
    score += fundamental_score_factor * 12
    score += trend_score_factor * 8
    score += news_score_factor * 6
    score += macro_score_factor * 6
    score += risk_score_factor * 8
    return max(0, min(100, int(round(score))))


def signal_zone(score: int) -> str:
    if score >= 68:
        return "进攻观察"
    if score >= 52:
        return "中性跟踪"
    return "防守处理"


def now_cn_date() -> str:
    return datetime.now(CN_TZ).date().isoformat()


def hkd_value(amount: float | None, currency: str | None) -> float:
    if amount is None:
        return 0.0
    return amount if currency == "HKD" else amount * USD_HKD_RATE


def safe_pct(numerator: float, denominator: float) -> float | None:
    if denominator == 0:
        return None
    return numerator / denominator * 100.0


def asset_meta(symbol: str, fallback_name: str, market: str, currency: str) -> dict[str, Any]:
    canonical = SYMBOL_META_ALIASES.get(symbol, symbol)
    base = {
        "symbol": canonical,
        "quote_code": "",
        "market": market,
        "currency": currency,
        "name": fallback_name,
        "name_zh": fallback_name,
        "category": "other",
        "fundamental_score": 3,
        "risk_level": "中",
        "style": "unclassified",
        "business_note": "暂无预设逻辑，请结合结单和后续研究补充。",
        "fundamental_note": "暂无预设基本面备注。",
        "watch_items": "仓位变化、资金占用、后续催化",
    }
    meta = {**base, **ASSET_BY_SYMBOL.get(canonical, {}), **HOLDING_META_OVERRIDES.get(canonical, {})}
    return meta


def normalize_holding(row: dict[str, Any], total_value_hkd: float) -> dict[str, Any]:
    meta = asset_meta(row["symbol"], row["name"], row["market"], row["currency"])
    statement_value_hkd = hkd_value(row.get("statement_value"), row.get("currency"))
    statement_pnl_hkd = hkd_value(row.get("statement_pnl"), row.get("currency"))
    avg_cost = row.get("avg_cost")
    price = row.get("statement_price")
    pnl_pct = safe_pct(row.get("statement_pnl") or 0.0, row.get("cost_value") or 0.0)
    weight_pct = safe_pct(statement_value_hkd, total_value_hkd) or 0.0
    category = CATEGORY_BY_ID.get(meta["category"], {"name": "其他持仓"})

    return {
        "symbol": meta["symbol"],
        "name": meta.get("name_zh") or row["name"],
        "name_en": meta.get("name") or row["name"],
        "quote_code": meta.get("quote_code"),
        "assetclass": meta.get("assetclass", "stocks"),
        "market": row["market"],
        "currency": row["currency"],
        "quantity": row["quantity"],
        "avg_cost": avg_cost,
        "statement_price": price,
        "statement_value": row.get("statement_value"),
        "statement_value_hkd": round(statement_value_hkd, 2),
        "statement_pnl": row.get("statement_pnl"),
        "statement_pnl_hkd": round(statement_pnl_hkd, 2),
        "statement_pnl_pct": round(pnl_pct, 2) if pnl_pct is not None else None,
        "weight_pct": round(weight_pct, 2),
        "account_count": row["account_count"],
        "accounts": row["accounts"],
        "category": meta["category"],
        "category_name": category["name"],
        "fundamental_score": meta["fundamental_score"],
        "fundamental_label": fundamental_label(meta["fundamental_score"]),
        "risk_level": meta["risk_level"],
        "style": meta["style"],
        "style_label": STYLE_LABELS.get(meta["style"], "其他"),
        "business_note": meta["business_note"],
        "fundamental_note": meta["fundamental_note"],
        "watch_items": meta["watch_items"],
    }


def derivative_underlyings(description: str) -> list[str]:
    matches = set()
    text = description.upper()
    for symbol in list(ASSET_BY_SYMBOL) + list(HOLDING_META_OVERRIDES):
        token = symbol.replace(".HK", "").replace(".US", "")
        if token and token in text:
            matches.add(symbol)
    return sorted(matches)


def derivative_notional(item: dict[str, Any]) -> float:
    if item.get("notional") is not None:
        return abs(float(item["notional"]))
    desc = item.get("description", "")
    strike_match = re.search(r"PUT\s+([\d.]+)", desc.upper())
    quantity = abs(float(item.get("quantity") or 0.0))
    if strike_match and quantity:
        return quantity * 100.0 * float(strike_match.group(1))
    return abs(float(item.get("market_value") or 0.0))


def normalize_trade(item: dict[str, Any]) -> dict[str, Any]:
    side = item.get("side") or ""
    clean_side = "卖出" if "卖" in side else "买入"
    meta = asset_meta(item["symbol"], item["name"], "US" if item["currency"] == "USD" else "HK", item["currency"])
    return {
        "date": item["date"],
        "symbol": meta["symbol"],
        "name": meta.get("name_zh") or item["name"],
        "side": clean_side,
        "quantity": item["quantity"],
        "price": item["price"],
        "currency": item["currency"],
        "broker": item["broker"],
        "account_id": item["account_id"],
    }


def normalize_derivative(item: dict[str, Any]) -> dict[str, Any]:
    estimated_notional = derivative_notional(item)
    underlyings = derivative_underlyings(item.get("description", ""))
    return {
        "symbol": item["symbol"],
        "description": item.get("description", ""),
        "currency": item.get("currency", "USD"),
        "quantity": item.get("quantity"),
        "market_value": item.get("market_value"),
        "unrealized_pnl": item.get("unrealized_pnl"),
        "estimated_notional": round(estimated_notional, 2),
        "estimated_notional_hkd": round(hkd_value(estimated_notional, item.get("currency")), 2),
        "underlyings": underlyings,
        "broker": item["broker"],
        "account_id": item["account_id"],
    }


def build_account_cards(accounts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    cards = []
    for account in accounts:
        holdings_value_hkd = round(
            sum(hkd_value(item.get("statement_value"), item.get("currency")) for item in account.get("holdings", [])),
            2,
        )
        financing_hkd = round(
            sum(abs(hkd_value(cash.get("amount"), cash.get("currency"))) for cash in account.get("cash_balances", []) if (cash.get("amount") or 0.0) < 0),
            2,
        )
        nav_hkd = round(hkd_value(account.get("nav"), account.get("base_currency")), 2)
        top_names = []
        sorted_holdings = sorted(
            account.get("holdings", []),
            key=lambda item: hkd_value(item.get("statement_value"), item.get("currency")),
            reverse=True,
        )
        for item in sorted_holdings[:3]:
            top_names.append(item["name"])
        cards.append(
            {
                "account_id": account["account_id"],
                "broker": account["broker"],
                "statement_date": account["statement_date"],
                "base_currency": account["base_currency"],
                "nav_hkd": nav_hkd,
                "holdings_value_hkd": holdings_value_hkd,
                "financing_hkd": financing_hkd,
                "holding_count": len(account.get("holdings", [])),
                "trade_count": len(account.get("recent_trades", [])),
                "derivative_count": len(account.get("derivatives", [])),
                "risk_notes": account.get("risk_notes", []),
                "top_names": "、".join(top_names),
            }
        )
    cards.sort(key=lambda item: item["nav_hkd"], reverse=True)
    return cards


def build_breakdown(rows: list[dict[str, Any]], key: str, label_key: str) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    total = sum(item["statement_value_hkd"] for item in rows)
    for row in rows:
        group_id = row[key]
        entry = grouped.setdefault(
            group_id,
            {
                "id": group_id,
                "label": row[label_key],
                "value_hkd": 0.0,
                "count": 0,
            },
        )
        entry["value_hkd"] += row["statement_value_hkd"]
        entry["count"] += 1
    result = []
    for item in grouped.values():
        result.append(
            {
                **item,
                "value_hkd": round(item["value_hkd"], 2),
                "weight_pct": round(safe_pct(item["value_hkd"], total) or 0.0, 2),
            }
        )
    result.sort(key=lambda item: item["value_hkd"], reverse=True)
    return result


def build_broker_breakdown(account_cards: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    total_nav = sum(item["nav_hkd"] for item in account_cards)
    for card in account_cards:
        entry = grouped.setdefault(card["broker"], {"label": card["broker"], "value_hkd": 0.0, "count": 0})
        entry["value_hkd"] += card["nav_hkd"]
        entry["count"] += 1
    rows = []
    for item in grouped.values():
        rows.append(
            {
                **item,
                "value_hkd": round(item["value_hkd"], 2),
                "weight_pct": round(safe_pct(item["value_hkd"], total_nav) or 0.0, 2),
            }
        )
    rows.sort(key=lambda item: item["value_hkd"], reverse=True)
    return rows


def enrich_holdings_with_live_and_macro(
    holdings: list[dict[str, Any]],
    live_rows: dict[str, dict[str, Any]],
    macro_scores: dict[str, int],
    research_cache: dict[str, Any],
) -> list[dict[str, Any]]:
    recommendation_rows = research_cache.get("recommendations", {}).get("rows", [])
    recommendation_by_symbol = {row["symbol"]: row for row in recommendation_rows if row.get("symbol")}
    news_by_symbol = research_cache.get("news", {}).get("by_symbol", {})
    news_stats_by_symbol = research_cache.get("news", {}).get("stats_by_symbol", {})
    analysis_date_cn = research_cache.get("analysis_date_cn")
    enriched = []
    for item in holdings:
        live_row = live_rows.get(item["symbol"], {})
        cached_reco = lookup_symbol_value(recommendation_by_symbol, item["symbol"], {}) or {}
        cached_news = lookup_symbol_value(news_by_symbol, item["symbol"], []) or []
        cached_stats = lookup_symbol_value(news_stats_by_symbol, item["symbol"], {}) or {}
        macro_score = macro_scores.get(item["category"], 0)
        macro_signal = "中性"
        if macro_score >= 2:
            macro_signal = "顺风"
        elif macro_score <= -2:
            macro_signal = "逆风"
        current_price = live_row.get("current_price")
        if current_price is None:
            current_price = cached_reco.get("price")
        price_source = "statement"
        if live_row.get("history"):
            price_source = "network"
        elif cached_reco.get("price") is not None:
            price_source = "cache"
        elif current_price is None:
            current_price = item.get("statement_price")

        position_label = live_row.get("position_label") or cached_reco.get("position_label") or "无数据"
        trend_state = infer_trend_state(
            current_price,
            live_row.get("ma20"),
            live_row.get("ma60"),
            cached_reco.get("reasons") or [],
        )
        news_score = int(cached_stats.get("total_score") or 0)
        news_score_factor = 2 if news_score >= 4 else 1 if news_score >= 2 else -2 if news_score <= -4 else -1 if news_score <= -2 else 0
        macro_score_factor = 2 if macro_score >= 4 else 1 if macro_score >= 2 else -2 if macro_score <= -4 else -1 if macro_score <= -2 else 0
        fundamental_score_factor = factor_score_bucket(item["fundamental_score"] - 3)
        trend_score_factor = trend_factor_score(trend_state)

        enriched_item = {
            **item,
            "live_available": bool(live_row),
            "current_price": current_price,
            "trade_date": live_row.get("trade_date") or analysis_date_cn,
            "change_pct": live_row.get("change_pct", cached_reco.get("change_pct")),
            "change_pct_5d": live_row.get("change_pct_5d", cached_reco.get("change_pct_5d")),
            "ma20": live_row.get("ma20"),
            "ma60": live_row.get("ma60"),
            "range_position_60d": live_row.get("range_position_60d"),
            "position_label": position_label,
            "trend_state": trend_state,
            "history": live_row.get("history", []),
            "normalized_history": live_row.get("normalized_history", []),
            "macro_score": macro_score,
            "macro_signal": macro_signal,
            "news_score": news_score,
            "news_signal": news_signal_label(news_score),
            "news_headline": cached_news[0]["title"] if cached_news else "",
            "news_count": int(cached_stats.get("count") or len(cached_news)),
            "cached_action": cached_reco.get("action"),
            "cached_summary": cached_reco.get("summary"),
            "cached_reasons": cached_reco.get("reasons") or [],
            "price_source": price_source,
        }
        risk_score_factor = risk_factor_score(enriched_item)
        total_signal = composite_signal_score(
            fundamental_score_factor,
            trend_score_factor,
            news_score_factor,
            macro_score_factor,
            risk_score_factor,
        )
        enriched_item.update(
            {
                "factor_scores": {
                    "fundamental": fundamental_score_factor,
                    "trend": trend_score_factor,
                    "news": news_score_factor,
                    "macro": macro_score_factor,
                    "risk": risk_score_factor,
                },
                "signal_score": total_signal,
                "signal_zone": signal_zone(total_signal),
            }
        )
        enriched.append(enriched_item)
    return enriched


def build_broker_risk_chart(account_cards: list[dict[str, Any]], derivatives: list[dict[str, Any]]) -> list[dict[str, Any]]:
    derivative_by_account: dict[str, float] = defaultdict(float)
    for item in derivatives:
        derivative_by_account[item["account_id"]] += item["estimated_notional_hkd"]
    rows = []
    for card in account_cards:
        rows.append(
            {
                "label": card["broker"],
                "account_id": card["account_id"],
                "nav_hkd": card["nav_hkd"],
                "financing_hkd": card["financing_hkd"],
                "derivative_hkd": round(derivative_by_account.get(card["account_id"], 0.0), 2),
            }
        )
    return rows


def build_scatter_points(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    points = []
    for item in holdings[:14]:
        points.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "x": item["weight_pct"],
                "y": item["statement_pnl_pct"] if item["statement_pnl_pct"] is not None else 0.0,
                "size": item["statement_value_hkd"],
                "category_name": item["category_name"],
                "macro_signal": item["macro_signal"],
            }
        )
    return points


def build_performance_chart(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for item in holdings:
        if item.get("normalized_history"):
            rows.append(
                {
                    "symbol": item["symbol"],
                    "name": item["name"],
                    "points": item["normalized_history"],
                }
            )
        if len(rows) >= 6:
            break
    return rows


def build_style_mix_chart(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    for item in holdings:
        family_id = STYLE_FAMILY_BY_STYLE.get(item["style"], "other")
        entry = grouped.setdefault(
            family_id,
            {
                "id": family_id,
                "label": STYLE_FAMILY_LABELS.get(family_id, "其他"),
                "weight_pct": 0.0,
                "weighted_fundamental": 0.0,
                "weighted_pnl": 0.0,
                "count": 0,
            },
        )
        entry["weight_pct"] += item["weight_pct"]
        entry["weighted_fundamental"] += item["weight_pct"] * item["fundamental_score"]
        entry["weighted_pnl"] += item["weight_pct"] * (item.get("statement_pnl_pct") or 0.0)
        entry["count"] += 1
    rows = []
    for entry in grouped.values():
        weight = entry["weight_pct"] or 1.0
        rows.append(
            {
                "id": entry["id"],
                "label": entry["label"],
                "weight_pct": round(entry["weight_pct"], 2),
                "avg_fundamental": round(entry["weighted_fundamental"] / weight, 2),
                "avg_pnl_pct": round(entry["weighted_pnl"] / weight, 2),
                "count": entry["count"],
            }
        )
    rows.sort(key=lambda item: item["weight_pct"], reverse=True)
    return rows


def build_price_regime_chart(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    order = ["强势上行", "修复抬头", "震荡待确认", "高位震荡", "弱势下行", "无数据"]
    grouped = {
        label: {"label": label, "weight_pct": 0.0, "count": 0, "avg_signal": 0.0}
        for label in order
    }
    for item in holdings:
        label = item.get("trend_state", "无数据")
        entry = grouped.setdefault(label, {"label": label, "weight_pct": 0.0, "count": 0, "avg_signal": 0.0})
        entry["weight_pct"] += item["weight_pct"]
        entry["count"] += 1
        entry["avg_signal"] += item.get("signal_score", 0)
    rows = []
    for label in order:
        entry = grouped[label]
        avg_signal = entry["avg_signal"] / entry["count"] if entry["count"] else 0.0
        rows.append(
            {
                "label": label,
                "weight_pct": round(entry["weight_pct"], 2),
                "count": entry["count"],
                "avg_signal": round(avg_signal, 2),
            }
        )
    return rows


def build_signal_heatmap(holdings: list[dict[str, Any]]) -> dict[str, Any]:
    columns = [
        {"key": "fundamental", "label": "基本面"},
        {"key": "trend", "label": "趋势"},
        {"key": "news", "label": "新闻"},
        {"key": "macro", "label": "宏观"},
        {"key": "risk", "label": "风控"},
    ]
    rows = []
    for item in holdings[:8]:
        rows.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "weight_pct": item["weight_pct"],
                "score": item.get("signal_score", 50),
                "zone": item.get("signal_zone", "中性跟踪"),
                "cells": [
                    {"label": column["label"], "score": item.get("factor_scores", {}).get(column["key"], 0)}
                    for column in columns
                ],
            }
        )
    return {"columns": columns, "rows": rows}


def build_health_radar(
    holdings: list[dict[str, Any]],
    total_nav_hkd: float,
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    top5_ratio: float,
) -> list[dict[str, Any]]:
    total_weight = sum(item["weight_pct"] for item in holdings) or 1.0
    quality_score = sum(item["weight_pct"] * item["fundamental_score"] for item in holdings) / total_weight / 5.0 * 100.0
    positive_trend_weight = sum(item["weight_pct"] for item in holdings if item.get("trend_state") in {"强势上行", "修复抬头"})
    negative_trend_weight = sum(item["weight_pct"] for item in holdings if item.get("trend_state") == "弱势下行")
    trend_score = max(0.0, min(100.0, 50.0 + positive_trend_weight * 1.2 - negative_trend_weight * 0.9))
    macro_alignment = sum(item["weight_pct"] * item.get("factor_scores", {}).get("macro", 0) for item in holdings) / total_weight
    macro_score = max(0.0, min(100.0, 50.0 + macro_alignment * 18.0))
    diversification_score = max(10.0, min(100.0, 100.0 - max(0.0, top5_ratio - 35.0) * 1.9))
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0
    leverage_score = max(0.0, min(100.0, 100.0 - financing_ratio * 2.2 - derivative_ratio * 1.1))
    tactical_weight = sum(item["weight_pct"] for item in holdings if item["style"] in {"leveraged", "speculative", "crypto_beta"})
    drawdown_weight = sum(item["weight_pct"] for item in holdings if (item.get("statement_pnl_pct") or 0.0) <= -30)
    discipline_score = max(0.0, min(100.0, 100.0 - tactical_weight * 1.4 - drawdown_weight * 0.9))
    return [
        {"label": "质量", "value": round(quality_score, 1)},
        {"label": "趋势", "value": round(trend_score, 1)},
        {"label": "宏观", "value": round(macro_score, 1)},
        {"label": "分散", "value": round(diversification_score, 1)},
        {"label": "杠杆", "value": round(leverage_score, 1)},
        {"label": "纪律", "value": round(discipline_score, 1)},
    ]


def build_macro_flash_topics(macro_bundle: dict[str, Any], holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for item in macro_bundle.get("topics", []):
        impact_labels = "、".join(CATEGORY_BY_ID.get(category, {"name": category})["name"] for category in item["impact_categories"])
        top_headline = item["headlines"][0]["title"] if item.get("headlines") else "暂无标题"
        top_source = item["headlines"][0].get("source") if item.get("headlines") else None
        top_published_at = item["headlines"][0].get("published_at") if item.get("headlines") else None
        impact_weight_pct = round(
            sum(holding["weight_pct"] for holding in holdings if holding["category"] in item.get("impact_categories", [])),
            2,
        )
        rows.append(
            {
                "id": item.get("id"),
                "name": item["name"],
                "severity": item["severity"],
                "summary": item["summary"],
                "headline": top_headline,
                "impact_labels": impact_labels,
                "score": item["score"],
                "source": top_source,
                "published_at": top_published_at,
                "impact_weight_pct": impact_weight_pct,
            }
        )
    return rows


def build_key_drivers(
    holdings: list[dict[str, Any]],
    risk_flags: list[dict[str, str]],
    macro_topics: list[dict[str, Any]],
) -> list[dict[str, str]]:
    drivers: list[dict[str, str]] = []
    if macro_topics:
        top_macro = max(
            macro_topics,
            key=lambda item: (
                {"高": 3, "中": 2, "低": 1}.get(item["severity"], 0),
                abs(item.get("score", 0)),
                item.get("impact_weight_pct", 0.0),
            ),
        )
        macro_tone = "warn" if top_macro["severity"] == "高" and top_macro.get("score", 0) >= 0 else "down" if top_macro.get("score", 0) < 0 else "up"
        drivers.append(
            {
                "title": top_macro["name"],
                "detail": f"{top_macro['headline']} 关联持仓约 {top_macro.get('impact_weight_pct', 0.0):.2f}%。",
                "tone": macro_tone,
            }
        )
    if risk_flags:
        drivers.append(
            {
                "title": risk_flags[0]["title"],
                "detail": risk_flags[0]["detail"],
                "tone": "down",
            }
        )
    opportunity = next(
        (
            item
            for item in sorted(holdings, key=lambda row: (row.get("signal_score", 0), row["weight_pct"]), reverse=True)
            if item["fundamental_score"] >= 4
        ),
        None,
    )
    if opportunity:
        drivers.append(
            {
                "title": f"{opportunity['name']} 可作为高质量观察窗口",
                "detail": (
                    f"当前信号分数 {opportunity.get('signal_score', 0)}，价格来源 {opportunity.get('price_source', 'statement')}，"
                    f"处于 {opportunity.get('trend_state', '无数据')} / {opportunity.get('position_label', '无数据')}。"
                ),
                "tone": "up",
            }
        )
    weak_spot = next(
        (
            item
            for item in sorted(holdings, key=lambda row: (row["weight_pct"], -(row.get("signal_score", 50))), reverse=True)
            if item["style"] in {"leveraged", "speculative", "crypto_beta"} or item.get("signal_score", 50) < 48
        ),
        None,
    )
    if weak_spot:
        drivers.append(
            {
                "title": f"{weak_spot['name']} 需要更强风控",
                "detail": (
                    f"当前信号分数 {weak_spot.get('signal_score', 0)}，"
                    f"{weak_spot.get('news_signal', '中性')}新闻叠加 {weak_spot.get('macro_signal', '中性')} 宏观环境。"
                ),
                "tone": "down",
            }
        )
    return drivers[:4]


def build_strategy_views(
    holdings: list[dict[str, Any]],
    macro_bundle: dict[str, Any],
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    total_nav_hkd: float,
) -> list[dict[str, str]]:
    quality_weight = sum(item["weight_pct"] for item in holdings if item["fundamental_score"] >= 4)
    repair_weight = sum(item["weight_pct"] for item in holdings if item["style"] in {"turnaround", "platform"})
    tactical_weight = sum(item["weight_pct"] for item in holdings if item["style"] in {"leveraged", "speculative", "crypto_beta"})
    trend_up = sum(item["weight_pct"] for item in holdings if item.get("trend_state") in {"强势上行", "修复抬头"})
    trend_down = sum(item["weight_pct"] for item in holdings if item.get("trend_state") == "弱势下行")
    strongest_macro = macro_bundle.get("topics", [])[:1]
    macro_text = (strongest_macro[0].get("headlines") or [{}])[0].get("title", "暂无宏观快照") if strongest_macro else "暂无宏观快照"
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0
    best_quality = next((item for item in holdings if item["fundamental_score"] >= 4), None)
    repair_names = "、".join([item["name"] for item in holdings if item["style"] in {"turnaround", "platform"}][:3]) or "暂无"
    tactical_names = "、".join([item["name"] for item in holdings if item["style"] in {"leveraged", "speculative", "crypto_beta"}][:3]) or "暂无"
    return [
        {
            "title": "自上而下宏观",
            "tag": "Top-down",
            "tone": "warn" if macro_bundle.get("topics") else "neutral",
            "summary": (
                "先判断利率、贸易、政策与 AI 资本开支，再决定哪些主题值得放大。"
                f"当前一级变量是：{macro_text}"
            ),
        },
        {
            "title": "质量复利",
            "tag": f"权重 {quality_weight:.2f}%",
            "tone": "up" if quality_weight >= 28 else "warn",
            "summary": (
                f"当前强基本面仓位约占 {quality_weight:.2f}%，"
                f"{best_quality['name']} 等资产更适合承担底仓，而不是用交易仓扛净值。"
                if best_quality
                else f"当前强基本面仓位约占 {quality_weight:.2f}%。"
            ),
        },
        {
            "title": "估值修复",
            "tag": f"修复仓 {repair_weight:.2f}%",
            "tone": "warn",
            "summary": f"平台与修复类仓位约 {repair_weight:.2f}%，代表标的包括 {repair_names}；关键不在摊平，而在等盈利与政策共振。",
        },
        {
            "title": "趋势动量",
            "tag": f"顺势 {trend_up:.2f}% / 弱势 {trend_down:.2f}%",
            "tone": "up" if trend_up >= trend_down else "warn",
            "summary": "趋势强弱决定执行节奏。顺势阶段可以用加减仓管理，弱势阶段不要只看成本线。 ",
        },
        {
            "title": "事件/主题",
            "tag": f"高波动 {tactical_weight:.2f}%",
            "tone": "down" if tactical_weight >= 18 else "warn",
            "summary": f"高波动与杠杆主题仓约 {tactical_weight:.2f}%，目前主要集中在 {tactical_names}，应当只拿交易预算，不拿底仓预算。",
        },
        {
            "title": "风险预算",
            "tag": f"融资 {financing_ratio:.2f}%",
            "tone": "down" if financing_ratio >= 15 or derivative_ratio >= 15 else "up",
            "summary": (
                f"融资约占净资产 {financing_ratio:.2f}% ，衍生品估算名义本金约占 {derivative_ratio:.2f}% ，"
                "需要独立于选股观点单独管理。"
            ),
        },
    ]


def build_risk_flags(
    holdings: list[dict[str, Any]],
    total_nav_hkd: float,
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    top5_ratio: float,
) -> list[dict[str, str]]:
    flags: list[dict[str, str]] = []
    largest = holdings[0] if holdings else None
    biggest_loser = min(holdings, key=lambda item: item["statement_pnl_hkd"], default=None)
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0

    if top5_ratio >= 50:
        flags.append(
            {
                "title": "集中度偏高",
                "detail": f"前五大仓位已占股票市值 {top5_ratio:.2f}%，组合波动基本由头部少数资产决定。",
            }
        )
    if largest and largest["weight_pct"] >= 15:
        flags.append(
            {
                "title": "单一仓位偏大",
                "detail": f"{largest['name']} 当前权重 {largest['weight_pct']:.2f}%，单一仓位已经足以改变组合日波动轨迹。",
            }
        )
    if financing_ratio >= 20:
        flags.append(
            {
                "title": "融资占用仍然偏重",
                "detail": f"结单显示融资相关负现金约 HK${total_financing_hkd:,.0f}，约占净资产 {financing_ratio:.2f}%。",
            }
        )
    if derivative_ratio >= 15:
        flags.append(
            {
                "title": "衍生品敞口不可忽视",
                "detail": f"卖 Put 与 FCN 估算名义本金约 HK${total_derivative_notional_hkd:,.0f}，约占净资产 {derivative_ratio:.2f}%。",
            }
        )
    if biggest_loser and biggest_loser["statement_pnl_hkd"] < -500000:
        flags.append(
            {
                "title": "最大亏损仓仍未出清",
                "detail": (
                    f"{biggest_loser['name']} 当前浮亏约 HK${abs(biggest_loser['statement_pnl_hkd']):,.0f}，"
                    "继续重仓会拖累整个账户的再配置能力。"
                ),
            }
        )
    return flags


def diagnose_holding(holding: dict[str, Any]) -> dict[str, Any]:
    playbook = ACTION_PLAYBOOK.get(holding["symbol"], {})
    role = playbook.get("role") or holding["style_label"]
    stance = playbook.get("stance")
    if not stance:
        if holding["style"] == "leveraged":
            stance = "只做交易仓"
        elif holding["weight_pct"] >= 8 and (holding["statement_pnl_pct"] or 0.0) < -20:
            stance = "减仓降风险"
        elif holding["fundamental_score"] >= 4 and holding["weight_pct"] <= 8:
            stance = "观察持有"
        else:
            stance = "继续跟踪"
    if holding.get("cached_action") == "分批关注" and stance in {"继续跟踪", "观察持有", "谨慎观察"}:
        stance = "分批关注"
    elif holding.get("cached_action") == "持有观察" and stance == "继续跟踪":
        stance = "观察持有"
    elif holding.get("cached_action") == "减仓控制" and stance not in {"反弹减仓", "减仓降风险", "优先清理尾部"}:
        stance = "减仓降风险"
    if holding.get("macro_score", 0) <= -2 and stance in {"继续跟踪", "观察持有"}:
        stance = "谨慎观察"
    if (
        holding.get("current_price") is not None
        and holding.get("ma20") is not None
        and holding.get("ma60") is not None
        and holding["current_price"] < holding["ma20"] < holding["ma60"]
        and holding["style"] in {"leveraged", "speculative", "crypto_beta"}
        and stance not in {"反弹减仓", "减仓降风险", "只做交易仓", "优先清理尾部"}
    ):
        stance = "减仓降风险"
    risk = playbook.get("risk") or holding["fundamental_note"]
    if holding["statement_pnl_pct"] is not None and holding["statement_pnl_pct"] <= -40:
        risk = f"当前浮亏 {holding['statement_pnl_pct']:.2f}%，继续加仓需要极高把握。"
    if holding.get("macro_score", 0) <= -2:
        risk = f"{risk} 当前宏观新闻面对该主题偏逆风。"
    elif holding.get("macro_score", 0) >= 2:
        risk = f"{risk} 当前宏观新闻面对该主题偏顺风。"
    if holding.get("news_signal") in {"偏空", "显著偏空"}:
        risk = f"{risk} 个股新闻流也偏谨慎。"
    action = playbook.get("action")
    if not action:
        if stance in {"减仓降风险", "反弹减仓"}:
            action = "优先处理仓位结构，不再用摊平去解决结构性问题。"
        elif stance == "只做交易仓":
            action = "把它从中长期仓位账本里剥离，单独管理止损与持有期限。"
        else:
            action = "维持当前仓位级别，围绕验证指标和风险预算动态调整。"
    if holding.get("cached_summary") and holding.get("cached_action") in {"分批关注", "持有观察"} and "当前盘面信号" not in action:
        action = f"{action} 当前盘面信号提示：{holding['cached_summary']}"
    if (
        holding.get("current_price") is not None
        and holding.get("ma20") is not None
        and holding.get("ma60") is not None
        and holding["current_price"] >= holding["ma20"] >= holding["ma60"]
    ):
        action = f"{action} 当前价格位于 20/60 日均线上方，可把加减仓节奏建立在趋势未破坏的前提下。"
    elif (
        holding.get("current_price") is not None
        and holding.get("ma20") is not None
        and holding.get("ma60") is not None
        and holding["current_price"] < holding["ma20"] < holding["ma60"]
    ):
        action = f"{action} 当前价格仍在 20/60 日均线下方，弱趋势里不建议只凭成本线做决策。"
    thesis = holding["business_note"]
    if holding.get("cached_summary"):
        thesis = f"{holding['business_note']} 当前信号：{holding['cached_summary']}"
    return {
        "symbol": holding["symbol"],
        "name": holding["name"],
        "weight_pct": holding["weight_pct"],
        "role": role,
        "stance": stance,
        "thesis": thesis,
        "watch_items": holding["watch_items"],
        "risk": risk,
        "action": action,
        "current_price": holding.get("current_price"),
        "change_pct": holding.get("change_pct"),
        "position_label": holding.get("position_label"),
        "trend_state": holding.get("trend_state"),
        "macro_signal": holding.get("macro_signal"),
        "news_signal": holding.get("news_signal"),
        "fundamental_label": holding.get("fundamental_label"),
        "signal_score": holding.get("signal_score"),
        "signal_zone": holding.get("signal_zone"),
        "statement_pnl_pct": holding["statement_pnl_pct"],
        "statement_value_hkd": holding["statement_value_hkd"],
        "category_name": holding["category_name"],
    }


def build_priority_actions(
    holdings: list[dict[str, Any]],
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    total_nav_hkd: float,
    macro_topics: list[dict[str, Any]],
) -> list[dict[str, str]]:
    actions: list[dict[str, str]] = []
    by_symbol = {item["symbol"]: item for item in holdings}
    if macro_topics:
        top_macro = max(
            macro_topics,
            key=lambda item: (
                {"高": 3, "中": 2, "低": 1}.get(item["severity"], 0),
                item.get("impact_weight_pct", 0.0),
            ),
        )
        if top_macro.get("impact_weight_pct", 0.0) >= 20:
            actions.append(
                {
                    "title": f"把 {top_macro['name']} 当作本周一级变量",
                    "detail": (
                        f"{top_macro['headline']} "
                        f"该主题关联持仓约 {top_macro.get('impact_weight_pct', 0.0):.2f}% ，"
                        "本周的加减仓应先服从这个外部变量。"
                    ),
                }
            )
    if "03690.HK" in by_symbol:
        item = by_symbol["03690.HK"]
        actions.append(
            {
                "title": "先处理美团的大仓位拖累",
                "detail": (
                    f"美团当前约占股票市值 {item['weight_pct']:.2f}%，浮亏 {item['statement_pnl_pct']:.2f}% 。"
                    "后续策略应围绕降权与释放风险预算，而不是等待被动回本。"
                ),
            }
        )
    crypto_names = [symbol for symbol in ("MSTR", "BMNR", "COIN", "CRCL", "IREN") if symbol in by_symbol]
    if crypto_names:
        crypto_weight = sum(by_symbol[symbol]["weight_pct"] for symbol in crypto_names)
        actions.append(
            {
                "title": "把 Crypto Beta 与衍生品分开看待",
                "detail": (
                    f"MSTR/BMNR/COIN/CRCL/IREN 合计约 {crypto_weight:.2f}% 权重，"
                    "再叠加卖 Put 和 FCN，会让同一风险因子被重复放大。"
                ),
            }
        )
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0
    if financing_ratio >= 15 or derivative_ratio >= 15:
        actions.append(
            {
                "title": "把融资和结构性票据都降到可控区",
                "detail": (
                    f"当前融资约占净资产 {financing_ratio:.2f}%，衍生品估算名义本金约占 {derivative_ratio:.2f}% 。"
                    "先恢复调仓主动权，再谈提高赔率。"
                ),
            }
        )
    core_names = [symbol for symbol in ("00700.HK", "NVDA", "META") if symbol in by_symbol]
    if core_names:
        actions.append(
            {
                "title": "让核心资产重新定义底仓",
                "detail": (
                    "腾讯、NVDA、META 这类更接近质量型资产，应承担底仓功能；"
                    "交易仓和高波动仓不应继续主导净值曲线。"
                ),
            }
        )
    tactical_names = [symbol for symbol in ("07709.HK", "TSLL") if symbol in by_symbol]
    if tactical_names:
        actions.append(
            {
                "title": "杠杆工具必须从中长期仓里剥离",
                "detail": (
                    "07709.HK、TSLL 这类产品更像交易指令，不是长期投资标的。"
                    "保留的话要有明确持有期限、止损和退出条件。"
                ),
            }
        )
    weakest_core = next(
        (
            item
            for item in sorted(holdings, key=lambda row: (row["weight_pct"], -(row.get("signal_score", 50))), reverse=True)
            if item["weight_pct"] >= 5 and item.get("signal_score", 50) < 45
        ),
        None,
    )
    if weakest_core:
        actions.append(
            {
                "title": f"{weakest_core['name']} 先解决信号与仓位不匹配",
                "detail": (
                    f"它当前权重 {weakest_core['weight_pct']:.2f}% ，综合信号仅 {weakest_core.get('signal_score', 0)}。"
                    "这类仓位更适合先降风险，再等待更清晰的基本面或趋势确认。"
                ),
            }
        )
    return actions[:5]


def monitored_statements(accounts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    date_by_account = {account["account_id"]: account["statement_date"] for account in accounts}
    rows = []
    for item in STATEMENT_SOURCES:
        rows.append(
            {
                "broker": item["broker"],
                "account_id": item["account_id"],
                "statement_type": item["type"],
                "statement_date": date_by_account.get(item["account_id"]),
                "file_name": Path(item["path"]).name,
            }
        )
    return rows


def build_dashboard_payload(force_refresh: bool = False, include_live: bool = True) -> dict[str, Any]:
    portfolio = load_real_portfolio(force_refresh=force_refresh)
    research_cache = load_local_analysis_cache()
    accounts = portfolio["accounts"]
    total_value_hkd = portfolio["total_statement_value_hkd"]
    holdings = [normalize_holding(item, total_value_hkd) for item in portfolio["aggregate_holdings"]]
    holdings.sort(key=lambda item: item["statement_value_hkd"], reverse=True)
    account_cards = build_account_cards(accounts)
    derivatives = [normalize_derivative(item) for item in portfolio["derivatives"]]
    trades = [normalize_trade(item) for item in portfolio["recent_trades"]]
    total_derivative_notional_hkd = round(sum(item["estimated_notional_hkd"] for item in derivatives), 2)
    live_bundle = {"updated_at": None, "rows_by_symbol": {}, "errors": [], "source_mode": "empty", "fallback_symbols": []}
    macro_bundle = {"updated_at": None, "topics": [], "category_scores": {}, "errors": [], "source_mode": "empty"}
    if include_live:
        with ThreadPoolExecutor(max_workers=2) as executor:
            live_future = executor.submit(fetch_live_bundle, holdings, force_refresh, True)
            macro_future = executor.submit(fetch_macro_bundle, force_refresh, True)
            live_bundle = live_future.result()
            macro_bundle = macro_future.result()
    else:
        live_bundle = fetch_live_bundle(holdings, force_refresh=force_refresh, allow_network=False)
        macro_bundle = fetch_macro_bundle(force_refresh=force_refresh, allow_network=False)
    holdings = enrich_holdings_with_live_and_macro(
        holdings,
        live_bundle.get("rows_by_symbol", {}),
        macro_bundle.get("category_scores", {}),
        research_cache,
    )
    risk_flags = build_risk_flags(
        holdings,
        portfolio["total_nav_hkd"],
        portfolio["total_financing_hkd"],
        total_derivative_notional_hkd,
        portfolio["top5_ratio"],
    )

    snapshot_dates = sorted(account["statement_date"] for account in accounts)
    theme_breakdown = build_breakdown(holdings, "category", "category_name")
    market_breakdown = build_breakdown(holdings, "market", "market")
    broker_breakdown = build_broker_breakdown(account_cards)
    holding_notes = [diagnose_holding(item) for item in holdings]
    macro_topics = build_macro_flash_topics(macro_bundle, holdings)
    strategy_views = build_strategy_views(
        holdings,
        macro_bundle,
        portfolio["total_financing_hkd"],
        total_derivative_notional_hkd,
        portfolio["total_nav_hkd"],
    )
    key_drivers = build_key_drivers(holdings, risk_flags, macro_topics)

    main_theme_names = "、".join(item["label"] for item in theme_breakdown[:3])
    top_names = "、".join(item["name"] for item in holdings[:5])
    live_mode_map = {
        "network": "在线行情",
        "mixed": "在线行情 + 本地日更快照",
        "cache": "本地日更快照",
        "empty": "结单价格",
    }
    macro_mode_map = {
        "network": "在线宏观新闻",
        "mixed": "在线宏观新闻 + 本地研究快照",
        "cache": "本地研究快照",
        "empty": "静态框架",
    }
    headline = (
        f"截至 {snapshot_dates[-1]} 的真实结单快照显示，这是一组以 {main_theme_names} 为主轴、"
        f"头部仓位集中在 {top_names} 的高波动组合。"
    )
    overview = (
        f"股票市值约 HK${portfolio['total_statement_value_hkd']:,.0f}，净资产约 HK${portfolio['total_nav_hkd']:,.0f}，"
        f"融资相关负现金约 HK${portfolio['total_financing_hkd']:,.0f}。"
        f"当前价格层使用 {live_mode_map.get(live_bundle.get('source_mode'), '离线快照')}，"
        f"宏观层使用 {macro_mode_map.get(macro_bundle.get('source_mode'), '静态框架')}。"
        "建议阅读顺序是：先看关键驱动与风险旗标，再看优先动作，最后逐只检查个股定位。"
    )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "analysis_date_cn": now_cn_date(),
        "snapshot_date": snapshot_dates[-1],
        "summary": {
            "account_count": len(accounts),
            "holding_count": len(holdings),
            "trade_count": len(trades),
            "derivative_count": len(derivatives),
            "total_nav_hkd": portfolio["total_nav_hkd"],
            "total_statement_value_hkd": portfolio["total_statement_value_hkd"],
            "total_financing_hkd": portfolio["total_financing_hkd"],
            "total_derivative_notional_hkd": total_derivative_notional_hkd,
            "top5_ratio": portfolio["top5_ratio"],
            "top1_weight_pct": holdings[0]["weight_pct"] if holdings else 0.0,
            "statement_start_date": snapshot_dates[0],
            "statement_end_date": snapshot_dates[-1],
        },
        "headline": headline,
        "overview": overview,
        "live": {
            "updated_at": live_bundle.get("updated_at"),
            "tracked_count": len(live_bundle.get("rows_by_symbol", {})),
            "errors": live_bundle.get("errors", []),
            "source_mode": live_bundle.get("source_mode", "empty"),
            "fallback_symbols": live_bundle.get("fallback_symbols", []),
        },
        "macro": {
            "updated_at": macro_bundle.get("updated_at"),
            "topics": macro_topics,
            "errors": macro_bundle.get("errors", []),
            "source_mode": macro_bundle.get("source_mode", "empty"),
        },
        "key_drivers": key_drivers,
        "risk_flags": risk_flags,
        "accounts": account_cards,
        "breakdowns": {
            "themes": theme_breakdown,
            "markets": market_breakdown,
            "brokers": broker_breakdown,
        },
        "charts": {
            "theme_donut": theme_breakdown,
            "broker_risk": build_broker_risk_chart(account_cards, derivatives),
            "holding_scatter": build_scatter_points(holdings),
            "performance": build_performance_chart(holdings),
            "health_radar": build_health_radar(
                holdings,
                portfolio["total_nav_hkd"],
                portfolio["total_financing_hkd"],
                total_derivative_notional_hkd,
                portfolio["top5_ratio"],
            ),
            "style_mix": build_style_mix_chart(holdings),
            "signal_heatmap": build_signal_heatmap(holdings),
            "price_regime": build_price_regime_chart(holdings),
            "macro_topics": macro_topics,
        },
        "holdings": holdings,
        "top_holdings": holdings[:10],
        "trades": trades[:12],
        "derivatives": derivatives,
        "strategy_views": strategy_views,
        "brief": {
            "headline": headline,
            "overview": overview,
            "priority_actions": build_priority_actions(
                holdings,
                portfolio["total_financing_hkd"],
                total_derivative_notional_hkd,
                portfolio["total_nav_hkd"],
                macro_topics,
            ),
            "framework": REFERENCE_FRAMEWORK,
            "holding_notes": holding_notes,
            "disclaimer": (
                "本页结论基于你提供的真实结单与本地参考分析框架自动生成，"
                "属于研究辅助与执行清单，不构成个性化投顾承诺。"
            ),
        },
        "update_guide": [
            "保持 `statement_sources.py` 指向最新结单文件；文件时间戳变更后，点击页面右上角“强制刷新”即可重建缓存。",
            "网页展示以结单快照为准，适合做真实仓位复盘、集中度监控和账户风险管理。",
            "如果后续新增券商或想补基金/现金类细项，只需要扩充解析器，不必重做前端。",
        ],
        "statement_sources": monitored_statements(accounts),
        "reference_sources": [
            {
                "label": item["label"],
                "type": item["type"],
                "file_name": Path(item["path"]).name,
            }
            for item in REFERENCE_ANALYSIS_SOURCES
        ],
    }


def validate_payload(payload: dict[str, Any]) -> list[str]:
    errors = []
    summary = payload["summary"]
    if summary["account_count"] != len(STATEMENT_SOURCES):
        errors.append("account count mismatch")
    if summary["holding_count"] < 20:
        errors.append("too few holdings")
    if summary["trade_count"] < 5:
        errors.append("too few trades")
    if summary["derivative_count"] < 8:
        errors.append("too few derivatives")
    if not payload["brief"]["priority_actions"]:
        errors.append("missing priority actions")
    if len(payload["brief"]["holding_notes"]) != summary["holding_count"]:
        errors.append("holding notes mismatch")
    if "charts" not in payload:
        errors.append("missing charts")
    return errors
