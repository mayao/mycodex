from __future__ import annotations

import html
import json
import threading
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote_plus
from urllib.request import Request, urlopen


CN_TZ = timezone(timedelta(hours=8))
BASE_DIR = Path(__file__).resolve().parent
ANALYSIS_CACHE_PATH = BASE_DIR / "daily_analysis_cache.json"
HISTORY_POINTS = 60
LIVE_HOLDING_LIMIT = 10
LIVE_CACHE_TTL_SECONDS = 600
MACRO_CACHE_TTL_SECONDS = 900
REQUEST_TIMEOUT_SECONDS = 3.0
NASDAQ_HISTORY_URL = (
    "https://api.nasdaq.com/api/quote/{symbol}/historical"
    "?assetclass={assetclass}&fromdate={fromdate}&todate={todate}&limit=120"
)
TENCENT_KLINE_URL = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param={code},day,,,60,qfq"
GOOGLE_NEWS_URL = "https://news.google.com/rss/search?q={query}&hl=en-US&gl=US&ceid=US:en"
POSITIVE_KEYWORDS = {
    "beat",
    "beats",
    "expand",
    "growth",
    "improve",
    "rebound",
    "rally",
    "soft landing",
    "stimulus",
    "surge",
    "upgrade",
}
NEGATIVE_KEYWORDS = {
    "cut",
    "cuts",
    "down",
    "downgrade",
    "export control",
    "inflation",
    "probe",
    "risk",
    "slump",
    "tariff",
    "warning",
}
MACRO_TOPICS = [
    {
        "id": "fed",
        "name": "美联储与美国增长",
        "query": "Federal Reserve inflation jobs rate cuts when:7d",
        "impact_categories": ["ai_compute", "growth_platform", "crypto_beta", "ev_beta"],
    },
    {
        "id": "trade",
        "name": "贸易与出口管制",
        "query": "US China tariffs semiconductor export controls when:7d",
        "impact_categories": ["ai_compute", "hk_internet", "ev_beta"],
    },
    {
        "id": "china_policy",
        "name": "中国政策与内需",
        "query": "China stimulus consumption platform economy when:7d",
        "impact_categories": ["hk_internet", "ev_beta", "healthcare_special"],
    },
    {
        "id": "ai_capex",
        "name": "AI 资本开支",
        "query": "AI capex hyperscaler nvidia hbm cloud when:7d",
        "impact_categories": ["ai_compute", "growth_platform"],
    },
    {
        "id": "crypto",
        "name": "Crypto 与监管",
        "query": "Bitcoin stablecoin regulation crypto when:7d",
        "impact_categories": ["crypto_beta", "growth_platform"],
    },
]
LIVE_CACHE: dict[str, Any] = {"timestamp": 0.0, "key": "", "payload": None}
MACRO_CACHE: dict[str, Any] = {"timestamp": 0.0, "key": "", "payload": None}
LIVE_LOCK = threading.Lock()
MACRO_LOCK = threading.Lock()
CACHE_SYMBOL_ALIASES = {
    "06606.HK": "45769.HK",
    "45769.HK": "06606.HK",
}
MACRO_FALLBACK_TOPICS = [
    {
        "id": "fed",
        "name": "美联储与美国增长",
        "impact_categories": ["ai_compute", "growth_platform", "crypto_beta", "ev_beta"],
        "headlines": [
            {
                "title": "美国 2 月非农减少 9.2 万、失业率 4.4%，同时纽约联储 1 年通胀预期回落至 3.1%。",
                "source": "BLS / NY Fed / BEA",
                "published_at": "2026-03-06T13:30:00+00:00",
                "source_url": "https://www.bls.gov/news.release/archives/empsit_03062026.htm",
            }
        ],
        "score": -1,
        "severity": "高",
        "summary": (
            "美国增长边际放缓，2025 年四季度 GDP 年化增速为 1.4%，"
            "利率敏感成长股面对的是“增长降温 + 降息预期摇摆”的混合环境。"
        ),
    },
    {
        "id": "trade",
        "name": "贸易与出口管制",
        "impact_categories": ["ai_compute", "hk_internet", "ev_beta"],
        "headlines": [
            {
                "title": "美国商务部 1 月起对 H200、MI325X 等对华出口改为逐案审批，3 月仍在酝酿更严格的全球 AI 芯片准入条件。",
                "source": "BIS / Financial Times",
                "published_at": "2026-03-06T00:00:00+00:00",
                "source_url": "https://media.bis.gov/sites/default/files/documents/DoC%20Revises%20License%20Review%20Policy%20for%20Semiconductors%20Exports.pdf",
            }
        ],
        "score": -3,
        "severity": "高",
        "summary": "算力链的核心不确定性不再只是需求，而是许可、地域分配和供应链合规。",
    },
    {
        "id": "china_policy",
        "name": "中国政策与内需",
        "impact_categories": ["hk_internet", "ev_beta", "healthcare_special"],
        "headlines": [
            {
                "title": "2026 年政府工作报告延续更积极财政政策，赤字率目标约 4%，继续把促消费和科技投入放在前列。",
                "source": "中国政府网",
                "published_at": "2026-03-05T02:44:00+00:00",
                "source_url": "https://english.www.gov.cn/2026special/2026npcandcpcc/202603/05/content_WS69a8ee1ac6d00ca5f9a09881.html",
            }
        ],
        "score": 2,
        "severity": "中",
        "summary": "港股互联网与中国消费链的方向性修复仍依赖内需政策持续落地和企业盈利兑现。",
    },
    {
        "id": "ai_capex",
        "name": "AI 资本开支",
        "impact_categories": ["ai_compute", "growth_platform"],
        "headlines": [
            {
                "title": "谷歌计划在 2026 年将资本开支提升至约 1850 亿美元，英伟达也在光模块与 Meta 基建上继续扩产绑定。",
                "source": "Financial Times / NVIDIA IR",
                "published_at": "2026-03-02T00:00:00+00:00",
                "source_url": "https://www.ft.com/content/22d97d8e-1101-4b1b-8a28-66054dfa363a",
            }
        ],
        "score": 3,
        "severity": "中",
        "summary": "算力主线的核心顺风仍在，真正的分化点在兑现节奏、产能获取和估值承受力。",
    },
    {
        "id": "crypto",
        "name": "Crypto 与监管",
        "impact_categories": ["crypto_beta", "growth_platform"],
        "headlines": [
            {
                "title": "美国稳定币法案框架仍在推进，FATF 3 月报告同时强调稳定币与非托管钱包的反洗钱风险。",
                "source": "Congress.gov / FATF",
                "published_at": "2026-03-03T00:00:00+00:00",
                "source_url": "https://www.fatf-gafi.org/en/publications/Virtualassets/targeted-report-stablecoins-unhosted-wallets.html",
            }
        ],
        "score": 1,
        "severity": "中",
        "summary": "对合规交易所与稳定币龙头偏中性偏多，但监管边界越清晰，经营与合规能力差异也会被放大。",
    },
]


def fetch_text(url: str, timeout: float = REQUEST_TIMEOUT_SECONDS) -> str:
    request = Request(
        url,
        headers={
            "Accept": "*/*",
            "User-Agent": "personal-workbench/2.0",
        },
    )
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def fetch_json(url: str, timeout: float = REQUEST_TIMEOUT_SECONDS) -> Any:
    return json.loads(fetch_text(url, timeout=timeout))


def load_local_analysis_cache() -> dict[str, Any]:
    try:
        return json.loads(ANALYSIS_CACHE_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def cache_symbol_candidates(symbol: str) -> list[str]:
    candidates = [symbol]
    alias = CACHE_SYMBOL_ALIASES.get(symbol)
    if alias and alias not in candidates:
        candidates.append(alias)
    return candidates


def cached_recommendation_row(analysis_cache: dict[str, Any], symbol: str) -> dict[str, Any] | None:
    rows = analysis_cache.get("recommendations", {}).get("rows", [])
    if not rows:
        return None
    by_symbol = {row.get("symbol"): row for row in rows if row.get("symbol")}
    for candidate in cache_symbol_candidates(symbol):
        row = by_symbol.get(candidate)
        if row:
            return row
    return None


def fallback_quote_from_cache(analysis_cache: dict[str, Any], symbol: str) -> dict[str, Any] | None:
    row = cached_recommendation_row(analysis_cache, symbol)
    if not row:
        return None
    return {
        "symbol": symbol,
        "current_price": row.get("price"),
        "trade_date": analysis_cache.get("analysis_date_cn"),
        "change_pct": row.get("change_pct"),
        "change_pct_5d": row.get("change_pct_5d"),
        "history": [],
        "normalized_history": [],
        "ma20": None,
        "ma60": None,
        "range_position_60d": None,
        "position_label": row.get("position_label", "无数据"),
    }


def build_cached_live_payload(holdings: list[dict[str, Any]]) -> dict[str, Any]:
    analysis_cache = load_local_analysis_cache()
    by_symbol: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    fallback_symbols: list[str] = []
    for row in holdings[:LIVE_HOLDING_LIMIT]:
        cached_item = fallback_quote_from_cache(analysis_cache, row["symbol"])
        if cached_item:
            by_symbol[row["symbol"]] = cached_item
            fallback_symbols.append(row["symbol"])
        else:
            errors.append(f"{row['symbol']}: no cached quote")
    return {
        "updated_at": analysis_cache.get("analysis_generated_at") or datetime.now(timezone.utc).isoformat(),
        "rows_by_symbol": by_symbol,
        "errors": errors,
        "fallback_symbols": fallback_symbols,
        "source_mode": "cache" if by_symbol else "empty",
    }


def build_macro_category_scores(topics: list[dict[str, Any]]) -> dict[str, int]:
    category_scores: dict[str, int] = {}
    for item in topics:
        for category in item.get("impact_categories", []):
            category_scores[category] = category_scores.get(category, 0) + int(item.get("score", 0))
    return category_scores


def build_fallback_macro_payload(errors: list[str] | None = None, source_mode: str = "cache") -> dict[str, Any]:
    topics = deepcopy(MACRO_FALLBACK_TOPICS)
    topics.sort(key=lambda item: {"高": 0, "中": 1, "低": 2}.get(item["severity"], 3))
    latest_published = max(
        (headline.get("published_at") for topic in topics for headline in topic.get("headlines", []) if headline.get("published_at")),
        default=None,
    )
    return {
        "updated_at": latest_published or datetime.now(timezone.utc).isoformat(),
        "topics": topics,
        "category_scores": build_macro_category_scores(topics),
        "errors": errors or [],
        "source_mode": source_mode,
    }


def to_float(value: str | None) -> float | None:
    if value in (None, "", "N/A", "--"):
        return None
    cleaned = str(value).replace("$", "").replace(",", "").strip()
    try:
        return float(cleaned)
    except ValueError:
        return None


def rolling_average(values: list[float], window: int) -> float | None:
    if len(values) < window:
        return None
    subset = values[-window:]
    return round(sum(subset) / len(subset), 2)


def calc_price_position(history: list[dict[str, Any]]) -> dict[str, Any]:
    prices = [point["price"] for point in history if point.get("price") is not None]
    if not prices:
        return {
            "ma20": None,
            "ma60": None,
            "range_position_60d": None,
            "position_label": "无数据",
        }
    latest = prices[-1]
    low = min(prices[-60:])
    high = max(prices[-60:])
    range_position = ((latest - low) / (high - low) * 100.0) if high != low else 50.0
    if range_position <= 20:
        label = "区间低位"
    elif range_position <= 40:
        label = "偏低位"
    elif range_position <= 60:
        label = "区间中位"
    elif range_position <= 80:
        label = "偏高位"
    else:
        label = "区间高位"
    return {
        "ma20": rolling_average(prices, 20),
        "ma60": rolling_average(prices, 60),
        "range_position_60d": round(range_position, 2),
        "position_label": label,
    }


def normalize_series(points: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not points:
        return []
    first = points[0]["price"]
    if first in (None, 0):
        return []
    return [
        {"date": point["date"], "price": round(point["price"] / first * 100.0, 2)}
        for point in points
        if point.get("price") is not None
    ]


def tencent_symbol(row: dict[str, Any]) -> str:
    quote_code = row.get("quote_code")
    if quote_code:
        return quote_code
    if row["market"] == "US":
        return f"us{row['symbol']}"
    return f"hk{row['symbol'].split('.')[0].lstrip('0') or row['symbol'].split('.')[0]}"


def clean_numeric_text(value: str | None) -> float | None:
    if value in (None, "", "N/A", "--"):
        return None
    cleaned = str(value).replace("$", "").replace(",", "").strip()
    try:
        return float(cleaned)
    except ValueError:
        return None


def fetch_one_quote(row: dict[str, Any]) -> dict[str, Any]:
    if row["market"] == "US":
        today = datetime.now(CN_TZ).date()
        fromdate = (today - timedelta(days=190)).isoformat()
        url = NASDAQ_HISTORY_URL.format(
            symbol=row["symbol"],
            assetclass=row.get("assetclass", "stocks"),
            fromdate=fromdate,
            todate=today.isoformat(),
        )
        request = Request(
            url,
            headers={
                "User-Agent": "Mozilla/5.0",
                "Accept": "application/json",
                "Origin": "https://www.nasdaq.com",
                "Referer": "https://www.nasdaq.com/",
            },
        )
        with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read().decode("utf-8"))
        rows = payload.get("data", {}).get("tradesTable", {}).get("rows", [])
        valid_rows = list(reversed(rows))
        if not valid_rows:
            raise ValueError("no quote data")
        latest = valid_rows[-1]
        previous = valid_rows[-2] if len(valid_rows) > 1 else None
        close_price = clean_numeric_text(latest.get("close"))
        prev_close = clean_numeric_text(previous.get("close")) if previous else None
        history = [
            {
                "date": datetime.strptime(item["date"], "%m/%d/%Y").date().isoformat(),
                "price": round(clean_numeric_text(item.get("close")) or 0.0, 2),
            }
            for item in valid_rows[-HISTORY_POINTS:]
        ]
        trade_date = datetime.strptime(latest["date"], "%m/%d/%Y").date().isoformat()
    else:
        code = tencent_symbol(row)
        payload = fetch_json(TENCENT_KLINE_URL.format(code=code), timeout=REQUEST_TIMEOUT_SECONDS)
        node = payload.get("data", {}).get(code, {})
        day_rows = node.get("qfqday") or node.get("day") or []
        valid_rows = [item for item in day_rows if isinstance(item, list) and len(item) >= 6]
        if not valid_rows:
            raise ValueError("no quote data")
        latest = valid_rows[-1]
        previous = valid_rows[-2] if len(valid_rows) > 1 else None
        close_price = to_float(latest[2])
        prev_close = to_float(previous[2]) if previous else None
        history = [
            {"date": item[0], "price": round(to_float(item[2]) or 0.0, 2)}
            for item in valid_rows[-HISTORY_POINTS:]
        ]
        trade_date = latest[0]

    change = (close_price - prev_close) if close_price is not None and prev_close not in (None, 0.0) else None
    change_pct = (change / prev_close * 100.0) if change is not None and prev_close not in (None, 0.0) else None
    close_5d = history[-6]["price"] if len(history) > 5 else None
    change_pct_5d = (
        ((close_price - close_5d) / close_5d * 100.0)
        if close_price is not None and close_5d not in (None, 0.0)
        else None
    )
    position = calc_price_position(history)
    return {
        "symbol": row["symbol"],
        "current_price": close_price,
        "trade_date": trade_date,
        "change_pct": round(change_pct, 2) if change_pct is not None else None,
        "change_pct_5d": round(change_pct_5d, 2) if change_pct_5d is not None else None,
        "history": history,
        "normalized_history": normalize_series(history),
        **position,
    }


def fetch_live_bundle(
    holdings: list[dict[str, Any]],
    force_refresh: bool = False,
    allow_network: bool = True,
) -> dict[str, Any]:
    key = f"{'network' if allow_network else 'cache'}:" + ",".join(sorted(row["symbol"] for row in holdings[:LIVE_HOLDING_LIMIT]))
    with LIVE_LOCK:
        cached = LIVE_CACHE.get("payload")
        cached_at = LIVE_CACHE.get("timestamp", 0.0)
        cached_key = LIVE_CACHE.get("key")
        if not force_refresh and cached and cached_key == key and (time.time() - cached_at) < LIVE_CACHE_TTL_SECONDS:
            return cached

    if not allow_network:
        payload = build_cached_live_payload(holdings)
        with LIVE_LOCK:
            LIVE_CACHE["timestamp"] = time.time()
            LIVE_CACHE["key"] = key
            LIVE_CACHE["payload"] = payload
        return payload

    selected = holdings[:LIVE_HOLDING_LIMIT]
    analysis_cache = load_local_analysis_cache()
    by_symbol: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    fallback_symbols: list[str] = []
    network_symbols: list[str] = []
    with ThreadPoolExecutor(max_workers=4) as executor:
        future_map = {executor.submit(fetch_one_quote, row): row for row in selected}
        for future in as_completed(future_map):
            row = future_map[future]
            try:
                item = future.result()
                by_symbol[item["symbol"]] = item
                network_symbols.append(item["symbol"])
            except Exception as exc:  # noqa: BLE001
                cached_item = fallback_quote_from_cache(analysis_cache, row["symbol"])
                if cached_item:
                    by_symbol[row["symbol"]] = cached_item
                    fallback_symbols.append(row["symbol"])
                else:
                    errors.append(f"{row['symbol']}: {exc}")
    source_mode = "empty"
    if network_symbols and fallback_symbols:
        source_mode = "mixed"
    elif network_symbols:
        source_mode = "network"
    elif fallback_symbols:
        source_mode = "cache"
    payload = {
        "updated_at": analysis_cache.get("analysis_generated_at") if source_mode == "cache" else datetime.now(timezone.utc).isoformat(),
        "rows_by_symbol": by_symbol,
        "errors": errors,
        "fallback_symbols": fallback_symbols,
        "source_mode": source_mode,
    }
    with LIVE_LOCK:
        LIVE_CACHE["timestamp"] = time.time()
        LIVE_CACHE["key"] = key
        LIVE_CACHE["payload"] = payload
    return payload


def parse_rss_datetime(value: str | None) -> str | None:
    if not value:
        return None
    try:
        return parsedate_to_datetime(value).astimezone(timezone.utc).isoformat()
    except (TypeError, ValueError, IndexError):
        return None


def headline_score(title: str) -> int:
    text = title.lower()
    positive = sum(1 for item in POSITIVE_KEYWORDS if item in text)
    negative = sum(1 for item in NEGATIVE_KEYWORDS if item in text)
    return positive - negative


def severity_label(score: int, title_blob: str) -> str:
    critical_terms = ("tariff", "export control", "rate", "inflation", "sanction", "probe")
    if any(term in title_blob.lower() for term in critical_terms):
        return "高"
    if abs(score) >= 2:
        return "中"
    return "低"


def headline_digest_cn(topic: dict[str, Any], title: str) -> str:
    lower = title.lower()
    topic_id = topic.get("id")
    if topic_id == "fed":
        if "payroll" in lower or "jobs" in lower or "employment" in lower:
            return "美国就业数据重新成为降息节奏判断的核心变量。"
        if "inflation" in lower or "cpi" in lower or "pce" in lower:
            return "美国通胀信号继续左右成长股估值与降息预期。"
        if "fed" in lower or "powell" in lower or "rate cut" in lower:
            return "美联储表态仍在主导利率敏感资产的风险偏好。"
        return "美国增长与利率预期仍在反复拉扯市场定价。"
    if topic_id == "trade":
        if "tariff" in lower:
            return "关税议题升温，出口链与全球风险偏好同步承压。"
        if "export control" in lower or "license" in lower or "chip" in lower or "semiconductor" in lower:
            return "芯片出口限制仍在收紧，算力链地域分配的不确定性上升。"
        return "贸易与合规约束仍是科技链估值的重要折价因子。"
    if topic_id == "china_policy":
        if "stimulus" in lower or "consumption" in lower:
            return "中国政策重点仍在稳增长、促消费与平台经济修复。"
        if "property" in lower:
            return "地产与内需政策进展继续影响港股互联网和消费链风险偏好。"
        return "内需政策与平台环境改善，决定港股修复的持续性。"
    if topic_id == "ai_capex":
        if "capex" in lower or "datacenter" in lower or "data center" in lower:
            return "云厂商资本开支仍是算力链最关键的需求验证指标。"
        if "hbm" in lower or "nvidia" in lower or "gpu" in lower:
            return "算力产业链继续围绕 GPU、HBM 与网络扩容定价。"
        return "AI 资本开支主线未改，但分化转向兑现节奏。"
    if topic_id == "crypto":
        if "stablecoin" in lower:
            return "稳定币立法推进，合规平台与支付基础设施更受关注。"
        if "bitcoin" in lower or "etf" in lower:
            return "比特币资金流与监管口径继续决定高 Beta 资产方向。"
        if "regulation" in lower or "sec" in lower:
            return "监管边界越清晰，行业内部质量分化会越明显。"
        return "Crypto 仍由监管进展与风险偏好共同驱动。"
    return "相关新闻已纳入中文摘要。"


def topic_summary_cn_core(topic: dict[str, Any], headlines: list[dict[str, Any]]) -> str:
    if not headlines:
        return "暂无可用新闻。"
    title_blob = " ".join(item["title"].lower() for item in headlines)
    if topic["id"] == "fed":
        detail = "重点看就业、通胀和联储表态是否把降息窗口继续往后推。"
        impact = "这会直接影响 AI、高估值成长股和高 Beta 仓位的估值承受力。"
    elif topic["id"] == "trade":
        detail = "核心不确定性在于出口许可、关税与全球供应链合规要求。"
        impact = "算力链与中概/港股科技链的风险溢价容易因此再抬升。"
    elif topic["id"] == "china_policy":
        detail = "政策重点仍在促消费、稳增长与平台经济常态化。"
        impact = "港股互联网和中国需求链的修复更依赖政策持续性与盈利兑现。"
    elif topic["id"] == "ai_capex":
        detail = "大厂 Capex、HBM 供需和数据中心订单仍是最硬的验证指标。"
        impact = "龙头受益仍然明确，但二三线标的会更看兑现速度。"
    elif topic["id"] == "crypto":
        detail = "监管框架、稳定币立法和 BTC 资金流仍是三条主线。"
        impact = "合规平台受益更明显，但高杠杆高 Beta 标的波动仍会放大。"
    else:
        detail = "近期新闻正在改变该主题的预期路径。"
        impact = "需要结合持仓敞口和交易节奏持续跟踪。"
    if "tariff" in title_blob or "export control" in title_blob or "sanction" in title_blob:
        impact = f"{impact} 同时要额外留意政策冲击引发的估值折价。"
    if "stimulus" in title_blob or "rate cut" in title_blob or "stablecoin" in title_blob:
        impact = f"{impact} 一旦政策兑现，相关主题的顺风可能会更快传导到股价。"
    return f"{detail}{impact}"


def topic_summary(topic: dict[str, Any], headlines: list[dict[str, Any]]) -> str:
    if not headlines:
        return "暂无可用新闻。"
    titles = "；".join(headline_digest_cn(topic, item["title"]) for item in headlines[:2])
    return f"{topic_summary_cn_core(topic, headlines)} 近期焦点：{titles}"


def fetch_macro_topic(topic: dict[str, Any]) -> dict[str, Any]:
    url = GOOGLE_NEWS_URL.format(query=quote_plus(topic["query"]))
    xml_text = fetch_text(url, timeout=REQUEST_TIMEOUT_SECONDS)
    root = ET.fromstring(xml_text)
    channel = root.find("channel")
    items = channel.findall("item") if channel is not None else []
    headlines = []
    total_score = 0
    for item in items[:4]:
        title = html.unescape(item.findtext("title", default="")).strip()
        source = html.unescape(item.findtext("source", default="")).strip() or "Google News"
        score = headline_score(title)
        total_score += score
        headlines.append(
            {
                "title": title,
                "source": source,
                "published_at": parse_rss_datetime(item.findtext("pubDate")),
                "score": score,
            }
        )
    return {
        "id": topic["id"],
        "name": topic["name"],
        "impact_categories": topic["impact_categories"],
        "headlines": headlines,
        "headline_cn": headline_digest_cn(topic, headlines[0]["title"]) if headlines else "暂无可用新闻。",
        "score": total_score,
        "severity": severity_label(total_score, " ".join(item["title"] for item in headlines)),
        "summary": topic_summary(topic, headlines),
    }


def fetch_macro_bundle(force_refresh: bool = False, allow_network: bool = True) -> dict[str, Any]:
    cache_key = "network" if allow_network else "cache"
    with MACRO_LOCK:
        cached = MACRO_CACHE.get("payload")
        cached_at = MACRO_CACHE.get("timestamp", 0.0)
        cached_key = MACRO_CACHE.get("key")
        if not force_refresh and cached and cached_key == cache_key and (time.time() - cached_at) < MACRO_CACHE_TTL_SECONDS:
            return cached

    if not allow_network:
        payload = build_fallback_macro_payload(source_mode="cache")
        with MACRO_LOCK:
            MACRO_CACHE["timestamp"] = time.time()
            MACRO_CACHE["key"] = cache_key
            MACRO_CACHE["payload"] = payload
        return payload

    topics: list[dict[str, Any]] = []
    errors: list[str] = []
    fallback_used = False
    with ThreadPoolExecutor(max_workers=5) as executor:
        future_map = {executor.submit(fetch_macro_topic, topic): topic for topic in MACRO_TOPICS}
        for future in as_completed(future_map):
            topic = future_map[future]
            try:
                item = future.result()
                topics.append(item)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{topic['name']}: {exc}")

    existing_ids = {item["id"] for item in topics}
    for item in MACRO_FALLBACK_TOPICS:
        if item["id"] not in existing_ids:
            topics.append(deepcopy(item))
            fallback_used = True
    topics.sort(key=lambda item: {"高": 0, "中": 1, "低": 2}.get(item["severity"], 3))
    category_scores = build_macro_category_scores(topics)
    source_mode = "mixed" if fallback_used and existing_ids else "cache" if fallback_used else "network"
    payload = {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "topics": topics,
        "category_scores": category_scores,
        "errors": errors,
        "source_mode": source_mode,
    }
    with MACRO_LOCK:
        MACRO_CACHE["timestamp"] = time.time()
        MACRO_CACHE["key"] = cache_key
        MACRO_CACHE["payload"] = payload
    return payload
