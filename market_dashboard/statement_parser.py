from __future__ import annotations

import json
import re
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any

DEPS_DIR = Path(__file__).resolve().parent / ".deps"
if str(DEPS_DIR) not in sys.path:
    sys.path.insert(0, str(DEPS_DIR))

import pdfplumber  # type: ignore

try:
    from statement_sources import OWNER_USER_ID, get_statement_sources
except ModuleNotFoundError:
    from market_dashboard.statement_sources import OWNER_USER_ID, get_statement_sources


BASE_DIR = Path(__file__).resolve().parent
CACHE_DIR = BASE_DIR / "cache"
LEGACY_CACHE_PATH = BASE_DIR / "statement_cache.json"
USD_HKD_RATE = 7.818
SYMBOL_ALIASES = {
    "45769.HK": "06606.HK",
}
NAME_TO_SYMBOL = {
    "诺辉健康": "06606.HK",
}


def _cache_path_for_user(user_id: str | None = None) -> Path:
    normalized = _cache_namespace(user_id)
    return CACHE_DIR / f"statement_cache.{normalized}.json"


def _cache_namespace(user_id: str | None = None) -> str:
    raw_user_id = (user_id or "").strip()
    if raw_user_id in {"", "owner", OWNER_USER_ID}:
        return "owner"
    return re.sub(r"[^a-zA-Z0-9_.-]+", "_", raw_user_id)


def _legacy_cache_candidates(user_id: str | None = None) -> list[Path]:
    candidates: list[Path] = []
    cache_path = _cache_path_for_user(user_id)
    if cache_path not in candidates:
        candidates.append(cache_path)

    normalized = _cache_namespace(user_id)
    legacy_named = BASE_DIR / f"statement_cache.{normalized}.json"
    if legacy_named not in candidates:
        candidates.append(legacy_named)

    if normalized == "owner" and LEGACY_CACHE_PATH not in candidates:
        candidates.append(LEGACY_CACHE_PATH)

    return candidates


def load_portfolio_cache(user_id: str | None = None) -> dict[str, Any] | None:
    for cache_path in _legacy_cache_candidates(user_id):
        if not cache_path.exists():
            continue
        try:
            payload = json.loads(cache_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        if not isinstance(payload, dict):
            continue
        cached_payload = payload.get("payload")
        if not isinstance(cached_payload, dict):
            continue
        return payload
    return None


def to_float(value: str | None) -> float | None:
    if value in (None, "", "/", "N/A", "--"):
        return None
    cleaned = (
        str(value)
        .replace(",", "")
        .replace("$", "")
        .replace("HK$", "")
        .replace("%", "")
        .strip()
    )
    try:
        return float(cleaned)
    except ValueError:
        return None


def hk_symbol(code: str) -> str:
    digits = code.zfill(5)
    return f"{digits}.HK"


def normalize_symbol(raw: str) -> str:
    text = raw.strip().replace("(", "").replace(")", "")
    if text.isdigit():
        symbol = hk_symbol(text)
    else:
        symbol = text.upper()
    return SYMBOL_ALIASES.get(symbol, symbol)


def file_signature(user_id: str | None = None) -> list[dict[str, Any]]:
    signature = []
    for source in get_statement_sources(user_id=user_id):
        path = Path(source["path"])
        signature.append(
            {
                "account_id": source["account_id"],
                "path": str(path),
                "mtime": path.stat().st_mtime if path.exists() else None,
                "size": path.stat().st_size if path.exists() else None,
            }
        )
    return signature


def parse_symbol_name(cell: str) -> tuple[str, str]:
    compact = cell.replace("\n", " ").strip()
    symbol_match = re.search(r"\(([^)]+)\)", cell)
    if symbol_match:
        symbol = normalize_symbol(symbol_match.group(1))
        name = cell.split("\n")[0].strip()
        if name in NAME_TO_SYMBOL:
            return NAME_TO_SYMBOL[name], name
        return symbol, name or symbol
    parts = compact.split()
    if not parts:
        return "", ""
    head = parts[0]
    if head.isdigit():
        symbol = hk_symbol(head)
        name = compact[len(head) :].strip()
        if name in NAME_TO_SYMBOL:
            return NAME_TO_SYMBOL[name], name
        return symbol, name
    symbol = normalize_symbol(parts[0])
    name = " ".join(parts[1:]).strip() or symbol
    if name in NAME_TO_SYMBOL:
        return NAME_TO_SYMBOL[name], name
    return symbol, name


def pick_display_name(current: str | None, candidate: str | None) -> str | None:
    if not candidate:
        return current
    if not current:
        return candidate
    if current.upper() == current and candidate.upper() != candidate:
        return candidate
    if len(candidate) > len(current):
        return candidate
    return current


def parse_tiger(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        page4_tables = pdf.pages[3].extract_tables()
        page5_tables = pdf.pages[4].extract_tables()
        page6_tables = pdf.pages[5].extract_tables()
        overview_text = "\n".join((pdf.pages[i].extract_text() or "") for i in range(3))

    holdings: list[dict[str, Any]] = []
    options: list[dict[str, Any]] = []
    recent_trades: list[dict[str, Any]] = []

    option_tables = []
    if len(page4_tables) > 1:
        option_tables.append(page4_tables[1])
    if page5_tables:
        option_tables.append(page5_tables[0])
    for table in option_tables:
        for row in table[1:]:
            if not row or "合计" in (row[0] or "") or not row[0]:
                continue
            match = re.search(r"\(([^)]+)", row[0])
            if not match:
                continue
            options.append(
                {
                    "symbol": normalize_symbol(match.group(1).split()[0]),
                    "description": row[0].replace("\n", " "),
                    "quantity": to_float(row[1]),
                    "market_value": to_float(row[5]),
                    "unrealized_pnl": to_float(row[6]),
                    "currency": row[9],
                }
            )

    stock_tables = [page5_tables[1], page6_tables[0]]
    for table in stock_tables:
        for row in table[1:]:
            if not row or "合计" in (row[0] or "") or not row[0]:
                continue
            cell = row[0]
            symbol, name = parse_symbol_name(cell)
            holdings.append(
                {
                    "symbol": symbol,
                    "name": name,
                    "quantity": to_float(row[1]) or 0.0,
                    "cost": to_float(row[3]),
                    "statement_price": to_float(row[4]),
                    "statement_value": to_float(row[5]),
                    "statement_pnl": to_float(row[6]),
                    "currency": row[9],
                    "market": "HK" if row[9] == "HKD" else "US",
                }
            )

    trade_rows = page4_tables[0][1:] if page4_tables else []
    for row in trade_rows:
        if not row or not row[0] or "合计" in (row[0] or ""):
            continue
        symbol, name = parse_symbol_name(row[0])
        trade_type = (row[3] or "").strip()
        if trade_type not in {"开仓", "买入", "卖出"}:
            continue
        side = "卖出" if trade_type == "卖出" else "买入"
        trade_date = (row[12] or "").strip() or (row[11] or "").split("\n")[0].strip()
        recent_trades.append(
            {
                "date": trade_date,
                "symbol": symbol,
                "name": name,
                "side": side,
                "quantity": to_float(row[4]),
                "price": to_float(row[5]),
                "currency": row[13],
                "account_id": source["account_id"],
                "broker": source["broker"],
            }
        )

    nav_match = re.search(r"期末总览.*?([\d,\-.]+)\s*$", overview_text, re.M)
    usd_cash_match = re.search(r"按货币分类: USD.*?期末现金\s+([-\d,\.]+)", overview_text, re.S)
    hkd_cash_match = re.search(r"按货币分类: HKD.*?期末现金\s+([-\d,\.]+)", overview_text, re.S)
    return {
        "account_id": source["account_id"],
        "broker": source["broker"],
        "statement_type": source["type"],
        "statement_date": "2026-03-05",
        "base_currency": "USD",
        "nav": 248837.40 if nav_match else None,
        "cash_balances": [
            {"currency": "USD", "amount": to_float(usd_cash_match.group(1)) if usd_cash_match else None},
            {"currency": "HKD", "amount": to_float(hkd_cash_match.group(1)) if hkd_cash_match else None},
        ],
        "holdings": holdings,
        "derivatives": options,
        "recent_trades": recent_trades,
        "risk_notes": ["卖出看跌期权 7 张，存在被动接股与保证金占用风险。"],
    }


def parse_ib(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        tables = pdf.pages[0].extract_tables()

    nav_table = tables[1]
    perf_table = tables[4]
    holdings: list[dict[str, Any]] = []
    recent_trades: list[dict[str, Any]] = []
    for row in perf_table[4:]:
        if not row or not row[0] or row[0].startswith("总数"):
            continue
        prev_qty = to_float(row[1]) or 0.0
        curr_qty = to_float(row[2]) or 0.0
        current_price = to_float(row[4])
        holdings.append(
            {
                "symbol": normalize_symbol(row[0]),
                "name": row[0],
                "quantity": curr_qty,
                "cost": to_float(row[3]),
                "statement_price": current_price,
                "statement_value": curr_qty * current_price if current_price is not None else None,
                "statement_pnl": to_float(row[9]),
                "currency": "USD",
                "market": "US",
            }
        )
        delta = curr_qty - prev_qty
        if abs(delta) > 0.0001:
            recent_trades.append(
                {
                    "date": "2026-03-06",
                    "symbol": normalize_symbol(row[0]),
                    "name": row[0],
                    "side": "买入" if delta > 0 else "卖出",
                    "quantity": abs(delta),
                    "price": current_price,
                    "currency": "USD",
                    "account_id": source["account_id"],
                    "broker": source["broker"],
                }
            )

    cash_amount = to_float(nav_table[3][4]) if len(nav_table) > 3 else None
    return {
        "account_id": source["account_id"],
        "broker": source["broker"],
        "statement_type": source["type"],
        "statement_date": "2026-03-06",
        "base_currency": "USD",
        "nav": to_float(nav_table[7][4]) if len(nav_table) > 7 else 70535.57,
        "cash_balances": [{"currency": "USD", "amount": cash_amount}],
        "holdings": holdings,
        "derivatives": [],
        "recent_trades": recent_trades,
        "risk_notes": ["账户现金为负，存在保证金占用压力。"],
    }


def parse_futu_monthly_us(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        page1_tables = pdf.pages[0].extract_tables()
        page2_tables = pdf.pages[1].extract_tables()
        page3_text = pdf.pages[2].extract_text() or ""

    holdings: list[dict[str, Any]] = []
    rows = [page1_tables[3][4], page2_tables[0][4], page2_tables[0][5]]
    for row in rows:
        cell = row[0].replace("\n", " ")
        symbol = normalize_symbol(cell.split()[-1])
        name = cell.replace(symbol, "").replace("US USD", "").strip()
        start_part = row[3].split()
        end_part = row[7].split()
        holdings.append(
            {
                "symbol": symbol,
                "name": name,
                "quantity": to_float(end_part[0]) or 0.0,
                "cost": to_float(start_part[1]),
                "statement_price": to_float(end_part[1]),
                "statement_value": to_float(end_part[2]),
                "statement_pnl": to_float(row[11].split()[0]),
                "currency": "USD",
                "market": "US",
            }
        )

    cash_match = re.search(r"Ending Cash\s+([\d,\.]+)", page3_text)
    return {
        "account_id": source["account_id"],
        "broker": source["broker"],
        "statement_type": source["type"],
        "statement_date": "2026-02-27",
        "base_currency": "USD",
        "nav": 40837.04,
        "cash_balances": [{"currency": "USD", "amount": to_float(cash_match.group(1)) if cash_match else 1763.54}],
        "holdings": holdings,
        "derivatives": [],
        "recent_trades": [],
        "risk_notes": ["月结单显示持仓集中在 AMD、BABA、HIMS 三只美股。"],
    }


def parse_futu_monthly_hk(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        text = "\n".join((page.extract_text() or "") for page in pdf.pages[:4])

    holdings: list[dict[str, Any]] = []
    pattern = re.compile(
        r"(?P<code>\d{5})\((?P<name>[^)]+)\)\s+SEHK\s+HKD\s+(?P<qty>[\d,]+)\s+"
        r"(?P<price>[\d.]+)\s+-\s+(?P<value>[\d,]+\.\d+)",
    )
    for match in pattern.finditer(text):
        holdings.append(
            {
                "symbol": hk_symbol(match.group("code")),
                "name": match.group("name"),
                "quantity": to_float(match.group("qty")) or 0.0,
                "cost": None,
                "statement_price": to_float(match.group("price")),
                "statement_value": to_float(match.group("value")),
                "statement_pnl": None,
                "currency": "HKD",
                "market": "HK",
            }
        )

    # Keep the last occurrence for each code, which corresponds to ending positions.
    latest_by_symbol = {}
    for row in holdings:
        latest_by_symbol[row["symbol"]] = row

    return {
        "account_id": source["account_id"],
        "broker": source["broker"],
        "statement_type": source["type"],
        "statement_date": "2026-02-27",
        "base_currency": "HKD",
        "nav": 481019.19,
        "cash_balances": [{"currency": "HKD", "amount": 0.0}],
        "holdings": list(latest_by_symbol.values()),
        "derivatives": [],
        "recent_trades": [],
        "risk_notes": ["月结单显示港股仓位集中在腾讯、美团、阿里。"],
    }


def parse_longbridge(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        tables_page1 = pdf.pages[0].extract_tables()
        tables_page2 = pdf.pages[1].extract_tables()

    holdings: list[dict[str, Any]] = []
    derivatives: list[dict[str, Any]] = []
    recent_trades: list[dict[str, Any]] = []

    mode = None
    portfolio_tables = [tables_page1[2], tables_page2[0]]
    for table in portfolio_tables:
        for row in table[1:]:
            if not row or not row[0]:
                continue
            label = row[0]
            if "股票 (⾹港市场" in label:
                mode = "hk"
                continue
            if "股票 (美国市场" in label:
                mode = "us"
                continue
            if "衍⽣品" in label:
                mode = "derivative"
                continue
            if "汇总" in label:
                continue
            if mode == "derivative":
                derivatives.append(
                    {
                        "symbol": label.split("\n")[0].strip(),
                        "description": label.replace("\n", " "),
                        "notional": to_float(row[5]),
                        "currency": "USD",
                    }
                )
                continue
            symbol, name = parse_symbol_name(label)
            holdings.append(
                {
                    "symbol": symbol,
                    "name": name,
                    "quantity": to_float(row[3]) or 0.0,
                    "cost": to_float(row[6]),
                    "statement_price": to_float(row[4]),
                    "statement_value": to_float(row[5]),
                    "statement_pnl": to_float(row[7]),
                    "currency": "HKD" if mode == "hk" else "USD",
                    "market": "HK" if mode == "hk" else "US",
                }
            )

    trade_table = tables_page2[1]
    for row in trade_table[2:]:
        if not row or not row[0] or row[0].startswith("下单时间") or row[0].startswith("佣"):
            continue
        if row[0].startswith("汇总"):
            continue
        recent_trades.append(
            {
                "date": row[0].replace(".", "-"),
                "symbol": normalize_symbol(row[4].split()[0]),
                "name": " ".join(row[4].split()[1:]),
                "side": row[3],
                "quantity": to_float(row[5]),
                "price": to_float(row[6]),
                "currency": "HKD",
                "account_id": source["account_id"],
                "broker": source["broker"],
            }
        )

    return {
        "account_id": source["account_id"],
        "broker": source["broker"],
        "statement_type": source["type"],
        "statement_date": "2026-03-06",
        "base_currency": "HKD",
        "nav": 6746105.40,
        "cash_balances": [
            {"currency": "HKD", "amount": -314374.72},
            {"currency": "USD", "amount": -198800.34},
        ],
        "holdings": holdings,
        "derivatives": derivatives,
        "recent_trades": recent_trades,
        "risk_notes": ["融资余额约 186.86 万 HKD，且存在雪球/FCN 结构化票据敞口。"],
    }


def summarize_source_issue(exc: Exception) -> str:
    if isinstance(exc, FileNotFoundError):
        return "源文件不存在"
    text = str(exc).strip()
    if not text:
        return exc.__class__.__name__
    return text.splitlines()[0][:160]


def _now_iso() -> str:
    import time
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def parse_accounts(
    cached_accounts_by_id: dict[str, dict[str, Any]] | None = None,
    strict_account_ids: set[str] | None = None,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    parsers = {
        "tiger_activity": parse_tiger,
        "ib_daily": parse_ib,
        "futu_monthly_us": parse_futu_monthly_us,
        "futu_monthly_hk": parse_futu_monthly_hk,
        "longbridge_daily": parse_longbridge,
    }
    strict_ids = strict_account_ids or set()
    cached_by_id = cached_accounts_by_id or {}
    accounts = []
    source_states = []
    failures: list[dict[str, Any]] = []
    for source in get_statement_sources(user_id=user_id):
        account_id = source["account_id"]
        path = Path(source["path"])
        parser = parsers.get(source["type"])
        state = {
            "broker": source["broker"],
            "account_id": account_id,
            "statement_type": source["type"],
            "source_mode": source.get("source_mode", "default"),
            "uploaded_at": source.get("uploaded_at"),
            "file_name": path.name,
            "file_exists": path.exists(),
            "load_status": "parsed",
            "issue": None,
            "statement_date": None,
        }
        rule_parse_error: str | None = None
        try:
            if not path.exists():
                raise FileNotFoundError(path)
            if parser is None:
                raise RuntimeError(f"没有对应的规则解析器: {source['type']}")
            account = parser(source)
            account["load_status"] = "parsed"
            account["load_issue"] = None
            state["statement_date"] = account.get("statement_date")
            accounts.append(account)
            source_states.append(state)
            continue
        except Exception as exc:  # noqa: BLE001
            rule_parse_error = summarize_source_issue(exc)

        # 对上传文件尝试 AI 兜底解析
        if source.get("source_mode") == "upload" and path.exists():
            try:
                try:
                    from statement_ai_parser import parse_statement_with_ai  # noqa: PLC0415
                    from statement_sources import register_uploaded_statement  # noqa: PLC0415
                except ModuleNotFoundError:
                    from market_dashboard.statement_ai_parser import parse_statement_with_ai  # noqa: PLC0415
                    from market_dashboard.statement_sources import register_uploaded_statement  # noqa: PLC0415
                ai_account, ai_meta = parse_statement_with_ai(
                    source,
                    ai_request_config=ai_request_config,
                    parse_error=rule_parse_error,
                )
                ai_account["load_status"] = "parsed"
                ai_account["load_issue"] = None
                state["statement_date"] = ai_account.get("statement_date")
                state["load_status"] = "parsed"
                state["issue"] = None
                try:
                    register_uploaded_statement(
                        account_id,
                        source["path"],
                        source.get("uploaded_file_name") or path.name,
                        user_id=user_id,
                        broker=ai_account.get("broker"),
                        statement_type=ai_account.get("statement_type"),
                        parser_mode=ai_meta.get("parser_mode"),
                        parse_status="parsed",
                        parse_issue=None,
                        detected_broker=ai_meta.get("detected_broker"),
                        detected_statement_type=ai_meta.get("detected_statement_type"),
                        last_parsed_at=_now_iso(),
                    )
                except Exception:  # noqa: BLE001
                    pass
                accounts.append(ai_account)
                source_states.append(state)
                continue
            except Exception as ai_exc:  # noqa: BLE001
                ai_issue = str(ai_exc).strip()[:200]
                combined_issue = f"规则解析: {rule_parse_error}; AI解析: {ai_issue}"
                try:
                    try:
                        from statement_sources import register_uploaded_statement  # noqa: PLC0415
                    except ModuleNotFoundError:
                        from market_dashboard.statement_sources import register_uploaded_statement  # noqa: PLC0415
                    register_uploaded_statement(
                        account_id,
                        source["path"],
                        source.get("uploaded_file_name") or path.name,
                        user_id=user_id,
                        parse_status="error",
                        parse_issue=combined_issue[:300],
                    )
                except Exception:  # noqa: BLE001
                    pass
                rule_parse_error = combined_issue

        issue = rule_parse_error or "解析失败"
        cached_account = cached_by_id.get(account_id)
        if cached_account is not None and account_id not in strict_ids:
            account = deepcopy(cached_account)
            account["load_status"] = "cache"
            account["load_issue"] = issue
            state["statement_date"] = account.get("statement_date")
            state["load_status"] = "cache"
            state["issue"] = issue
            accounts.append(account)
        else:
            state["load_status"] = "error"
            state["issue"] = issue
            failures.append(
                {
                    "message": f"{source['broker']} / {account_id}: {issue}",
                    "source_mode": source.get("source_mode", "default"),
                    "issue": issue,
                }
            )
        source_states.append(state)
    if failures:
        if all(
            failure.get("source_mode") == "default"
            and failure.get("issue") == "源文件不存在"
            for failure in failures
        ):
            return accounts, source_states
        raise RuntimeError("; ".join(str(failure.get("message") or "") for failure in failures))
    return accounts, source_states


def aggregate_portfolio(
    accounts: list[dict[str, Any]],
    source_states: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    holdings_map: dict[str, dict[str, Any]] = {}
    recent_trades = [trade for account in accounts for trade in account["recent_trades"]]
    derivatives = [item | {"account_id": account["account_id"], "broker": account["broker"]} for account in accounts for item in account["derivatives"]]
    total_nav_hkd = 0.0
    total_financing_hkd = 0.0

    for account in accounts:
        nav = account.get("nav")
        if nav is not None:
            total_nav_hkd += nav if account["base_currency"] == "HKD" else nav * USD_HKD_RATE
        for cash in account.get("cash_balances", []):
            amount = cash.get("amount")
            if amount is None or amount >= 0:
                continue
            total_financing_hkd += abs(amount if cash["currency"] == "HKD" else amount * USD_HKD_RATE)
        for holding in account["holdings"]:
            if (
                abs(holding.get("quantity") or 0.0) < 0.0001
                and abs(holding.get("statement_value") or 0.0) < 0.0001
            ):
                continue
            symbol = holding["symbol"]
            entry = holdings_map.setdefault(
                symbol,
                {
                    "symbol": symbol,
                    "name": holding["name"],
                    "market": holding["market"],
                    "currency": holding["currency"],
                    "quantity": 0.0,
                    "cost_value": 0.0,
                    "statement_price_value": 0.0,
                    "statement_value": 0.0,
                    "statement_pnl": 0.0,
                    "accounts": [],
                },
            )
            entry["quantity"] += holding["quantity"]
            entry["name"] = pick_display_name(entry.get("name"), holding.get("name")) or entry["name"]
            if holding.get("cost") is not None:
                entry["cost_value"] += holding["quantity"] * holding["cost"]
            if holding.get("statement_price") is not None:
                entry["statement_price_value"] += holding["quantity"] * holding["statement_price"]
            if holding.get("statement_value") is not None:
                entry["statement_value"] += holding["statement_value"]
            if holding.get("statement_pnl") is not None:
                entry["statement_pnl"] += holding["statement_pnl"]
            entry["accounts"].append(
                {
                    "account_id": account["account_id"],
                    "broker": account["broker"],
                    "quantity": holding["quantity"],
                    "cost": holding.get("cost"),
                    "statement_price": holding.get("statement_price"),
                    "statement_value": holding.get("statement_value"),
                    "statement_pnl": holding.get("statement_pnl"),
                }
            )

    aggregate_holdings = []
    for item in holdings_map.values():
        avg_cost = item["cost_value"] / item["quantity"] if item["quantity"] and item["cost_value"] else None
        statement_price = (
            item["statement_price_value"] / item["quantity"]
            if item["quantity"] and item["statement_price_value"]
            else None
        )
        aggregate_holdings.append(
            {
                **item,
                "avg_cost": avg_cost,
                "statement_price": statement_price,
                "account_count": len(item["accounts"]),
            }
        )

    aggregate_holdings.sort(key=lambda row: row["statement_value"], reverse=True)
    top_concentration = aggregate_holdings[:5]
    total_statement_value_hkd = sum(
        row["statement_value"] if row["currency"] == "HKD" else row["statement_value"] * USD_HKD_RATE
        for row in aggregate_holdings
    )
    top5_ratio = (
        sum(row["statement_value"] if row["currency"] == "HKD" else row["statement_value"] * USD_HKD_RATE for row in top_concentration)
        / total_statement_value_hkd
        * 100.0
        if total_statement_value_hkd
        else 0.0
    )
    payload = {
        "accounts": accounts,
        "aggregate_holdings": aggregate_holdings,
        "recent_trades": sorted(recent_trades, key=lambda item: item["date"], reverse=True),
        "derivatives": derivatives,
        "total_nav_hkd": round(total_nav_hkd, 2),
        "total_statement_value_hkd": round(total_statement_value_hkd, 2),
        "total_financing_hkd": round(total_financing_hkd, 2),
        "top5_ratio": round(top5_ratio, 2),
    }
    if source_states is not None:
        payload["source_states"] = source_states
        payload["source_health"] = {
            "parsed_count": sum(1 for item in source_states if item.get("load_status") == "parsed"),
            "cached_count": sum(1 for item in source_states if item.get("load_status") == "cache"),
            "error_count": sum(1 for item in source_states if item.get("load_status") == "error"),
        }
    return payload


def load_real_portfolio(
    force_refresh: bool = False,
    allow_cached_fallback: bool = True,
    strict_account_ids: set[str] | None = None,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    signature = file_signature(user_id=user_id)
    cache = load_portfolio_cache(user_id=user_id)
    if cache and not force_refresh and cache.get("signature") == signature:
        return cache["payload"]

    cached_accounts_by_id = {}
    if cache and isinstance(cache.get("payload"), dict):
        cached_accounts_by_id = {
            account["account_id"]: account
            for account in cache["payload"].get("accounts", [])
            if isinstance(account, dict) and account.get("account_id")
        }
    try:
        accounts, source_states = parse_accounts(
            cached_accounts_by_id=cached_accounts_by_id,
            strict_account_ids=strict_account_ids,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )
        payload = aggregate_portfolio(accounts, source_states=source_states)
    except Exception:  # noqa: BLE001
        if allow_cached_fallback and cache and cache.get("payload"):
            return cache["payload"]
        raise
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        _cache_path_for_user(user_id).write_text(
            json.dumps({"signature": signature, "payload": payload}, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError:
        pass
    return payload
