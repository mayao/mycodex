from __future__ import annotations

import json
import re
import sys
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEPS_DIR = Path(__file__).resolve().parent / ".deps"
if str(DEPS_DIR) not in sys.path:
    sys.path.insert(0, str(DEPS_DIR))

import pdfplumber  # type: ignore

try:
    from statement_sources import OWNER_USER_ID, get_statement_sources, update_uploaded_statement_parse_result
except ModuleNotFoundError:
    from market_dashboard.statement_sources import OWNER_USER_ID, get_statement_sources, update_uploaded_statement_parse_result


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


def _realized_entries_from_currency_map(pnl_by_currency: dict[str, float]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for currency, amount in pnl_by_currency.items():
        normalized_currency = str(currency or "").strip().upper()
        if not normalized_currency:
            continue
        entries.append(
            {
                "amount": round(float(amount), 2),
                "currency": normalized_currency,
                "source": "statement",
            }
        )
    return entries


def _append_realized_entry(
    entries: list[dict[str, Any]],
    *,
    amount: float | None,
    currency: str | None,
    source: str,
    category: str | None = None,
    label: str | None = None,
) -> None:
    if amount is None:
        return
    normalized_currency = str(currency or "").strip().upper()
    if not normalized_currency:
        return
    payload: dict[str, Any] = {
        "amount": round(float(amount), 2),
        "currency": normalized_currency,
        "source": source,
    }
    if category:
        payload["category"] = category
    if label:
        payload["label"] = label
    entries.append(payload)


def _merge_realized_entries(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        amount = to_float(entry.get("amount"))
        if amount is None:
            continue
        currency = str(entry.get("currency") or "").strip().upper()
        source = str(entry.get("source") or "statement").strip() or "statement"
        category = str(entry.get("category") or "").strip()
        label = str(entry.get("label") or "").strip()
        if not currency:
            continue
        key = (currency, source, category, label)
        existing = merged.get(key)
        if existing is None:
            payload: dict[str, Any] = {
                "amount": round(float(amount), 2),
                "currency": currency,
                "source": source,
            }
            if category:
                payload["category"] = category
            if label:
                payload["label"] = label
            merged[key] = payload
            continue
        existing["amount"] = round(float(existing.get("amount") or 0.0) + float(amount), 2)
    return list(merged.values())


def _extract_ib_realized_summary(pages: list[Any]) -> tuple[float | None, float | None, float | None]:
    for page in pages:
        tables = page.extract_tables() or []
        for table in tables:
            if not table:
                continue
            header_text = " ".join(str(item or "") for item in (table[0] or []))
            if "已实现和未实现的表现总结" not in header_text:
                continue

            total_row: list[Any] | None = None
            for row in reversed(table):
                first_cell = str(row[0] if row else "").replace(" ", "")
                if first_cell.startswith("总数"):
                    total_row = row
                    break

            def parse_row_metrics(row: list[Any]) -> tuple[float | None, float | None, float | None]:
                realized = to_float(row[6] if len(row) > 6 else None)
                unrealized = to_float(row[11] if len(row) > 11 else None)
                total = to_float(row[12] if len(row) > 12 else None)
                return realized, unrealized, total

            if total_row is not None:
                return parse_row_metrics(total_row)

            realized_sum = 0.0
            unrealized_sum = 0.0
            total_sum = 0.0
            matched = 0
            for row in table[3:]:
                realized, unrealized, total = parse_row_metrics(row)
                if realized is None and unrealized is None and total is None:
                    continue
                realized_sum += float(realized or 0.0)
                unrealized_sum += float(unrealized or 0.0)
                total_sum += float(total if total is not None else (realized or 0.0) + (unrealized or 0.0))
                matched += 1
            if matched:
                return round(realized_sum, 2), round(unrealized_sum, 2), round(total_sum, 2)

    return None, None, None


def _extract_ib_cashflow_entries(pages: list[Any]) -> list[dict[str, Any]]:
    label_map = {
        "佣金": ("commission", "交易佣金"),
        "支付和收到的经纪商利息": ("broker_interest", "经纪商利息"),
        "代替股息的支付": ("payment_in_lieu", "代替股息支付"),
        "代扣税款": ("withholding_tax", "代扣税款"),
    }
    entries: list[dict[str, Any]] = []
    for page in pages:
        for table in page.extract_tables() or []:
            if not table:
                continue
            header = str((table[0] or [""])[0] or "").strip()
            if header != "现金报告":
                continue
            for row in table[1:]:
                if not row or not row[0]:
                    continue
                label = str(row[0]).strip()
                if label not in label_map:
                    continue
                amount = to_float(row[1] if len(row) > 1 else None)
                if amount is None or abs(amount) < 0.0001:
                    continue
                category, pretty_label = label_map[label]
                _append_realized_entry(
                    entries,
                    amount=amount,
                    currency="USD",
                    source="statement_cashflow",
                    category=category,
                    label=pretty_label,
                )
    return _merge_realized_entries(entries)


def parse_tiger(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        pages = list(pdf.pages)
        overview_text = "\n".join((page.extract_text() or "") for page in pages[:3])

    holdings: list[dict[str, Any]] = []
    options: list[dict[str, Any]] = []
    recent_trades: list[dict[str, Any]] = []
    realized_pnl_by_currency: dict[str, float] = {}
    financing_interest_by_currency: dict[str, float] = {}
    dividend_net_by_currency: dict[str, float] = {}
    nav: float | None = None

    def table_header(table: list[list[Any]]) -> str:
        return " ".join(str(item or "") for item in (table[0] or []))

    def parse_trade_side(value: str | None) -> str:
        raw = (value or "").strip()
        if "卖" in raw or "做空" in raw:
            return "卖出"
        return "买入"

    with pdfplumber.open(path) as pdf:
        for page in pdf.pages:
            tables = page.extract_tables() or []
            for table in tables:
                if not table:
                    continue
                header = table_header(table)

                if "现金" in header and "股票" in header and "期权" in header and "总数" in header:
                    for row in table[1:]:
                        if not row or not row[0]:
                            continue
                        label = str(row[0]).strip()
                        if label.startswith("期末总览"):
                            nav = to_float(row[-1] if row else None) or nav
                    continue

                if "代码" in header and "市场" in header and "交易类型" in header and "交易价格" in header:
                    for row in table[1:]:
                        if not row or not row[0] or "合计" in str(row[0] or ""):
                            continue
                        symbol, name = parse_symbol_name(str(row[0]))
                        trade_type = str(row[3] if len(row) > 3 else "").strip()
                        if not trade_type:
                            continue
                        trade_date = (
                            str(row[12] if len(row) > 12 else "").strip()
                            or str(row[11] if len(row) > 11 else "").split("\n")[0].strip()
                            or "2026-03-05"
                        )
                        recent_trades.append(
                            {
                                "date": trade_date,
                                "symbol": symbol,
                                "name": name,
                                "side": parse_trade_side(trade_type),
                                "quantity": to_float(row[4] if len(row) > 4 else None),
                                "price": to_float(row[5] if len(row) > 5 else None),
                                "currency": str(row[13] if len(row) > 13 else "").strip() or ("HKD" if symbol.endswith(".HK") else "USD"),
                                "account_id": source["account_id"],
                                "broker": source["broker"],
                            }
                        )
                        realized_value = to_float(row[8] if len(row) > 8 else None)
                        trade_currency = str(row[13] if len(row) > 13 else "").strip() or ("HKD" if symbol.endswith(".HK") else "USD")
                        if realized_value is not None:
                            realized_pnl_by_currency[trade_currency] = float(realized_pnl_by_currency.get(trade_currency, 0.0)) + float(realized_value)
                    continue

                if "代码" in header and "数量" in header and "乘数" in header and "收盘价格" in header and "市值" in header:
                    for row in table[1:]:
                        if not row or not row[0] or "合计" in str(row[0] or ""):
                            continue
                        cell_text = str(row[0])
                        symbol, name = parse_symbol_name(cell_text)
                        currency = str(row[9] if len(row) > 9 else "").strip() or ("HKD" if symbol.endswith(".HK") else "USD")
                        quantity = to_float(row[1] if len(row) > 1 else None)
                        market_value = to_float(row[5] if len(row) > 5 else None)
                        unrealized = to_float(row[6] if len(row) > 6 else None)

                        is_option_row = (
                            "PUT" in cell_text.upper()
                            or "CALL" in cell_text.upper()
                            or bool(re.search(r"\d{8}", cell_text))
                        )
                        if is_option_row:
                            options.append(
                                {
                                    "symbol": symbol or name,
                                    "description": cell_text.replace("\n", " "),
                                    "quantity": quantity,
                                    "market_value": market_value,
                                    "unrealized_pnl": unrealized,
                                    "currency": currency,
                                }
                            )
                        else:
                            holdings.append(
                                {
                                    "symbol": symbol,
                                    "name": name,
                                    "quantity": quantity or 0.0,
                                    "cost": to_float(row[3] if len(row) > 3 else None),
                                    "statement_price": to_float(row[4] if len(row) > 4 else None),
                                    "statement_value": market_value,
                                    "statement_pnl": unrealized,
                                    "currency": currency,
                                    "market": "HK" if currency == "HKD" else "US",
                                }
                            )
                    continue

                if "利息变动项目" in header and "利息金额" in header and "币种" in header:
                    for row in table[1:]:
                        if not row:
                            continue
                        change_item = str(row[2] if len(row) > 2 else "").strip()
                        if "融资利息" not in change_item:
                            continue
                        amount = to_float(row[4] if len(row) > 4 else None)
                        currency = str(row[5] if len(row) > 5 else "").strip().upper()
                        if amount is None or not currency:
                            continue
                        financing_interest_by_currency[currency] = float(financing_interest_by_currency.get(currency, 0.0)) + float(amount)
                    continue

                if "分红投资计划" in header and "现金净值" in header and "币种" in header:
                    for row in table[1:]:
                        if not row:
                            continue
                        date_cell = str(row[0] if len(row) > 0 else "").strip()
                        if not re.match(r"20\d{2}-\d{2}-\d{2}", date_cell):
                            continue
                        amount = to_float(row[9] if len(row) > 9 else None)
                        currency = str(row[10] if len(row) > 10 else "").strip().upper()
                        if amount is None or not currency:
                            continue
                        dividend_net_by_currency[currency] = float(dividend_net_by_currency.get(currency, 0.0)) + float(amount)
                    continue

    nav_match = re.search(r"期末总览.*?([\d,\-.]+)\s*$", overview_text, re.M)
    usd_cash_match = re.search(r"按货币分类: USD.*?期末现金\s+([-\d,\.]+)", overview_text, re.S)
    hkd_cash_match = re.search(r"按货币分类: HKD.*?期末现金\s+([-\d,\.]+)", overview_text, re.S)
    statement_range_match = re.search(r"活动报表\s*:\s*(20\d{2})\.(\d{2})\.(\d{2})\s*-\s*(20\d{2})\.(\d{2})\.(\d{2})", overview_text)
    statement_date = "2026-03-05"
    if statement_range_match:
        statement_date = f"{statement_range_match.group(4)}-{statement_range_match.group(5)}-{statement_range_match.group(6)}"

    if not holdings and not options:
        raise RuntimeError("未识别到 Tiger 持仓/期权表格")

    realized_entries = _realized_entries_from_currency_map(realized_pnl_by_currency)
    for currency, amount in financing_interest_by_currency.items():
        _append_realized_entry(
            realized_entries,
            amount=amount,
            currency=currency,
            source="statement_cashflow",
            category="financing_interest",
            label="融资利息",
        )
    for currency, amount in dividend_net_by_currency.items():
        _append_realized_entry(
            realized_entries,
            amount=amount,
            currency=currency,
            source="statement_cashflow",
            category="dividend_net",
            label="分红净额",
        )
    realized_entries = _merge_realized_entries(realized_entries)

    risk_notes = ["卖出看跌期权 7 张，存在被动接股与保证金占用风险。"]
    if financing_interest_by_currency:
        parts = [f"{currency} {amount:+.2f}" for currency, amount in sorted(financing_interest_by_currency.items())]
        risk_notes.append(f"账单利息项显示融资利息：{'，'.join(parts)}。")
    if dividend_net_by_currency:
        parts = [f"{currency} {amount:+.2f}" for currency, amount in sorted(dividend_net_by_currency.items())]
        risk_notes.append(f"账单分红净额：{'，'.join(parts)}。")

    return {
        "account_id": source["account_id"],
        "broker": source["broker"],
        "statement_type": source["type"],
        "statement_date": statement_date,
        "base_currency": "USD",
        "nav": nav or (248837.40 if nav_match else None),
        "cash_balances": [
            {"currency": "USD", "amount": to_float(usd_cash_match.group(1)) if usd_cash_match else None},
            {"currency": "HKD", "amount": to_float(hkd_cash_match.group(1)) if hkd_cash_match else None},
        ],
        "holdings": holdings,
        "derivatives": options,
        "recent_trades": recent_trades,
        "realized_pnl_entries": realized_entries,
        "risk_notes": risk_notes,
    }


def parse_ib(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        pages = list(pdf.pages)
        tables = pages[0].extract_tables()

    nav_table = tables[1]
    perf_table = tables[4]
    realized_pnl, _, _ = _extract_ib_realized_summary(pages)
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
    realized_entries = (
        [
            {
                "amount": round(float(realized_pnl), 2),
                "currency": "USD",
                "source": "statement",
                "category": "trade_realized",
                "label": "交易已实现盈亏",
            }
        ]
        if realized_pnl is not None
        else []
    )
    realized_entries.extend(_extract_ib_cashflow_entries(pages))
    realized_entries = _merge_realized_entries(realized_entries)
    cashflow_entries = [entry for entry in realized_entries if str(entry.get("source") or "") == "statement_cashflow"]
    risk_notes = ["账户现金为负，存在保证金占用压力。"]
    if cashflow_entries:
        notes = [f"{entry.get('label') or entry.get('category')}: {float(entry.get('amount') or 0.0):+.2f} {entry.get('currency')}" for entry in cashflow_entries]
        risk_notes.append(f"账单现金项：{'；'.join(notes)}。")

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
        "realized_pnl_entries": realized_entries,
        "risk_notes": risk_notes,
    }


def parse_futu_monthly_us(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        page1_tables = pdf.pages[0].extract_tables()
        page2_tables = pdf.pages[1].extract_tables()
        page2_text = pdf.pages[1].extract_text() or ""
        page3_text = pdf.pages[2].extract_text() or ""

    holdings: list[dict[str, Any]] = []
    has_sell_or_transfer_out = False
    has_quantity_drop = False
    rows = [page1_tables[3][4], page2_tables[0][4], page2_tables[0][5]]
    for row in rows:
        cell = row[0].replace("\n", " ")
        symbol = normalize_symbol(cell.split()[-1])
        name = cell.replace(symbol, "").replace("US USD", "").strip()
        start_part = row[3].split()
        end_part = row[7].split()
        start_qty = to_float(start_part[0]) or 0.0
        end_qty = to_float(end_part[0]) or 0.0
        change_tokens = str(row[11] or "").split()
        statement_pnl = to_float(change_tokens[0] if len(change_tokens) > 0 else None)
        buy_qty = to_float(change_tokens[1] if len(change_tokens) > 1 else None) or 0.0
        sell_qty = to_float(change_tokens[2] if len(change_tokens) > 2 else None) or 0.0
        transfer_out_qty = to_float(change_tokens[4] if len(change_tokens) > 4 else None) or 0.0
        if sell_qty > 0 or transfer_out_qty > 0:
            has_sell_or_transfer_out = True
        if end_qty + 0.0001 < start_qty and buy_qty <= 0.0:
            has_quantity_drop = True
        holdings.append(
            {
                "symbol": symbol,
                "name": name,
                "quantity": end_qty,
                "cost": to_float(start_part[1]),
                "statement_price": to_float(end_part[1]),
                "statement_value": to_float(end_part[2]),
                "statement_pnl": statement_pnl,
                "currency": "USD",
                "market": "US",
            }
        )

    cash_match = re.search(r"Ending Cash\s+([\d,\.]+)", page3_text)
    cash_plus_match = re.search(r"Changes in Cash[\s\S]{0,600}?USD Total\s+([+-]?[\d,\.]+)", page2_text)
    cash_plus_amount = to_float(cash_plus_match.group(1)) if cash_plus_match else None
    realized_entries = (
        [{"amount": 0.0, "currency": "USD", "source": "inferred_zero"}]
        if (not has_sell_or_transfer_out and not has_quantity_drop)
        else []
    )
    if cash_plus_amount is not None and abs(cash_plus_amount) > 0.0001:
        _append_realized_entry(
            realized_entries,
            amount=cash_plus_amount,
            currency="USD",
            source="statement_cashflow",
            category="cash_plus_interest",
            label="现金归集利息",
        )
    realized_entries = _merge_realized_entries(realized_entries)
    risk_notes = ["月结单显示持仓集中在 AMD、BABA、HIMS 三只美股。"]
    if cash_plus_amount is not None and abs(cash_plus_amount) > 0.0001:
        risk_notes.append(f"现金归集利息约 {cash_plus_amount:+.2f} USD。")
    if realized_entries:
        risk_notes.append("本月未识别到卖出/转出，已实现盈亏按 0 推断。")
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
        "realized_pnl_entries": realized_entries,
        "risk_notes": risk_notes,
    }


def parse_futu_monthly_hk(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    with pdfplumber.open(path) as pdf:
        text = "\n".join((page.extract_text() or "") for page in pdf.pages[:4])

    holdings: list[dict[str, Any]] = []
    quantity_history_by_symbol: dict[str, list[float]] = {}
    pattern = re.compile(
        r"(?P<code>\d{5})\((?P<name>[^)]+)\)\s+SEHK\s+HKD\s+(?P<qty>[\d,]+)\s+"
        r"(?P<price>[\d.]+)\s+-\s+(?P<value>[\d,]+\.\d+)",
    )
    for match in pattern.finditer(text):
        symbol = hk_symbol(match.group("code"))
        quantity = to_float(match.group("qty")) or 0.0
        quantity_history_by_symbol.setdefault(symbol, []).append(quantity)
        holdings.append(
            {
                "symbol": symbol,
                "name": match.group("name"),
                "quantity": quantity,
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

    no_turnover = bool(quantity_history_by_symbol) and all(
        len(series) >= 2 and abs(float(series[-1]) - float(series[0])) < 0.0001
        for series in quantity_history_by_symbol.values()
    )
    realized_entries = (
        [{"amount": 0.0, "currency": "HKD", "source": "inferred_zero"}]
        if no_turnover
        else []
    )
    interest_match = re.search(r"月度利息扣除\s+HKD\s+(-?[\d,\.]+)", text)
    interest_amount = to_float(interest_match.group(1)) if interest_match else None
    if interest_amount is not None and abs(interest_amount) > 0.0001:
        _append_realized_entry(
            realized_entries,
            amount=interest_amount,
            currency="HKD",
            source="statement_cashflow",
            category="interest_deduction",
            label="月度利息扣除",
        )
    realized_entries = _merge_realized_entries(realized_entries)
    risk_notes = ["月结单显示港股仓位集中在腾讯、美团、阿里。"]
    if interest_amount is not None:
        risk_notes.append(f"账单记录利息扣除约 {interest_amount:+.2f} HKD。")
    if realized_entries:
        risk_notes.append("持仓数量未发生变动，已实现盈亏按 0 推断。")

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
        "realized_pnl_entries": realized_entries,
        "risk_notes": risk_notes,
    }


def _normalize_longbridge_label(value: str | None) -> str:
    return (value or "").replace("\n", " ").replace("⻓", "长").replace("⾹", "香").replace("⽅", "方").replace("⽣", "生").replace("⻋", "车").strip()


def _longbridge_trade_currency_from_row(row: list[Any]) -> str | None:
    text = " ".join(str(item or "") for item in row)
    if "港元" in text:
        return "HKD"
    if "美元" in text:
        return "USD"
    return None


def _estimate_longbridge_realized_entries(
    holdings: list[dict[str, Any]],
    trades: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    trade_stats: dict[str, dict[str, float]] = {}
    for trade in trades:
        symbol = str(trade.get("symbol") or "").strip()
        if not symbol:
            continue
        stat = trade_stats.setdefault(
            symbol,
            {
                "sell_qty": 0.0,
                "buy_qty": 0.0,
                "sell_cash_change": 0.0,
            },
        )
        qty = float(trade.get("quantity") or 0.0)
        side = str(trade.get("side") or "")
        if "卖" in side:
            stat["sell_qty"] += qty
            cash_change = trade.get("cash_change")
            if cash_change is not None:
                stat["sell_cash_change"] += float(cash_change)
            elif trade.get("trade_amount") is not None:
                stat["sell_cash_change"] += float(trade.get("trade_amount") or 0.0)
        elif "买" in side:
            stat["buy_qty"] += qty

    entries: list[dict[str, Any]] = []
    for holding in holdings:
        symbol = str(holding.get("symbol") or "").strip()
        if not symbol:
            continue
        start_qty = float(holding.get("start_quantity") or 0.0)
        end_qty = float(holding.get("end_quantity") or holding.get("quantity") or 0.0)
        change_qty = float(holding.get("change_quantity") or 0.0)
        if start_qty <= 0.0 or end_qty > 0.0001 or change_qty >= -0.0001:
            continue
        stat = trade_stats.get(symbol)
        if not stat:
            continue
        if stat["buy_qty"] > 0.0001 or stat["sell_qty"] <= 0.0001:
            continue
        cost = holding.get("cost")
        if cost is None:
            continue
        cost_per_share = abs(float(cost))
        estimated_realized = stat["sell_cash_change"] - cost_per_share * stat["sell_qty"]
        entries.append(
            {
                "amount": round(estimated_realized, 2),
                "currency": str(holding.get("currency") or "HKD"),
                "source": "estimated",
            }
        )

    return entries


def parse_longbridge(source: dict[str, Any]) -> dict[str, Any]:
    path = Path(source["path"])
    holdings: list[dict[str, Any]] = []
    derivatives: list[dict[str, Any]] = []
    recent_trades: list[dict[str, Any]] = []
    cash_balances: list[dict[str, Any]] = []
    margin_interest_by_currency: dict[str, float] = {}
    daily_interest_by_currency: dict[str, float] = {}
    nav = None
    statement_date = None

    portfolio_mode: str | None = None
    trade_currency: str | None = None

    with pdfplumber.open(path) as pdf:
        if pdf.pages:
            first_page_text = pdf.pages[0].extract_text() or ""
            date_match = re.search(r"(20\d{2})\.(\d{2})\.(\d{2})", first_page_text)
            if date_match:
                statement_date = f"{date_match.group(1)}-{date_match.group(2)}-{date_match.group(3)}"

        for page in pdf.pages:
            tables = page.extract_tables() or []
            for table in tables:
                if not table:
                    continue
                header_text = " ".join(str(item or "") for item in (table[0] or []))

                if "资⾦余额" in header_text and "总资产" in header_text and len(table) > 1:
                    nav = to_float(table[1][2]) if len(table[1]) > 2 else nav
                    continue

                if "币种" in header_text and "期末资⾦余额" in header_text:
                    for row in table[1:]:
                        if not row or not row[0]:
                            continue
                        label = str(row[0]).strip()
                        if label.startswith("汇总"):
                            continue
                        ending_balance = None
                        for candidate_index in (3, 8, 2):
                            if candidate_index < len(row) and to_float(row[candidate_index]) is not None:
                                ending_balance = to_float(row[candidate_index])
                                break
                        currency = "HKD" if "港" in label else "USD" if "美" in label else str(row[0]).strip()
                        cash_balances.append({"currency": currency, "amount": ending_balance})
                    continue

                if "项⽬" in header_text and "期末持仓" in header_text and "持仓市值" in header_text:
                    for row in table[1:]:
                        if not row or not row[0]:
                            continue
                        label = _normalize_longbridge_label(str(row[0]))
                        if not label:
                            continue
                        if "股票 (香港市场" in label or "股票 (⾹港市场" in label or "股票 (港股市场" in label:
                            portfolio_mode = "hk"
                            continue
                        if "股票 (美国市场" in label:
                            portfolio_mode = "us"
                            continue
                        if "衍生品" in label or "衍⽣品" in label:
                            portfolio_mode = "derivative"
                            continue
                        if label.startswith("汇总"):
                            continue

                        if portfolio_mode == "derivative":
                            derivatives.append(
                                {
                                    "symbol": label.split()[0],
                                    "description": label,
                                    "notional": to_float(row[5] if len(row) > 5 else None),
                                    "currency": "USD",
                                }
                            )
                            continue

                        symbol, name = parse_symbol_name(str(row[0]))
                        holdings.append(
                            {
                                "symbol": symbol,
                                "name": name,
                                "quantity": to_float(row[3] if len(row) > 3 else None) or 0.0,
                                "start_quantity": to_float(row[1] if len(row) > 1 else None) or 0.0,
                                "change_quantity": to_float(row[2] if len(row) > 2 else None) or 0.0,
                                "end_quantity": to_float(row[3] if len(row) > 3 else None) or 0.0,
                                "cost": to_float(row[6] if len(row) > 6 else None),
                                "statement_price": to_float(row[4] if len(row) > 4 else None),
                                "statement_value": to_float(row[5] if len(row) > 5 else None),
                                "statement_pnl": to_float(row[7] if len(row) > 7 else None),
                                "currency": "HKD" if portfolio_mode == "hk" else "USD",
                                "market": "HK" if portfolio_mode == "hk" else "US",
                            }
                        )
                    continue

                if "交易⽇期" in header_text and "买/卖" in header_text and "平均价格" in header_text:
                    for row in table[1:]:
                        if not row:
                            continue
                        detected_currency = _longbridge_trade_currency_from_row(row)
                        if detected_currency:
                            trade_currency = detected_currency
                            continue

                        first_cell = str(row[0] or "").strip()
                        if not first_cell:
                            continue
                        if (
                            first_cell.startswith("下单时间")
                            or first_cell.startswith("佣")
                            or first_cell.startswith("印花税")
                            or first_cell.startswith("平台费")
                            or first_cell.startswith("交收费")
                            or first_cell.startswith("交易征费")
                            or first_cell.startswith("交易费")
                            or first_cell.startswith("会财局交易征费")
                            or first_cell.startswith("其他交易费")
                            or first_cell.startswith("汇总")
                        ):
                            continue
                        if not re.match(r"20\d{2}\.\d{2}\.\d{2}$", first_cell):
                            continue

                        item_text = str(row[4] if len(row) > 4 else "").strip()
                        symbol, name = parse_symbol_name(item_text)
                        recent_trades.append(
                            {
                                "date": first_cell.replace(".", "-"),
                                "symbol": symbol,
                                "name": name,
                                "side": str(row[3] if len(row) > 3 else "").strip(),
                                "quantity": to_float(row[5] if len(row) > 5 else None),
                                "price": to_float(row[6] if len(row) > 6 else None),
                                "trade_amount": to_float(row[7] if len(row) > 7 else None),
                                "cash_change": to_float(row[8] if len(row) > 8 else None),
                                "currency": trade_currency or "HKD",
                                "account_id": source["account_id"],
                                "broker": source["broker"],
                            }
                        )
                    continue

                if "融资利率" in header_text and "当⽉累计利息" in header_text:
                    for row in table[1:]:
                        if not row:
                            continue
                        currency_label = str(row[1] if len(row) > 1 else "").strip()
                        daily_amount = to_float(row[3] if len(row) > 3 else None)
                        amount = to_float(row[4] if len(row) > 4 else None)
                        if amount is None and daily_amount is None:
                            continue
                        currency = "HKD" if "港" in currency_label else "USD" if "美" in currency_label else currency_label
                        if not currency:
                            continue
                        if amount is not None:
                            margin_interest_by_currency[currency] = float(margin_interest_by_currency.get(currency, 0.0)) + float(amount)
                        if daily_amount is not None:
                            daily_interest_by_currency[currency] = float(daily_interest_by_currency.get(currency, 0.0)) + float(daily_amount)

    if not holdings and not derivatives:
        raise RuntimeError("未识别到长桥持仓表格")

    # Deduplicate continuation-page rows while preserving the latest snapshot for each symbol.
    deduped_holdings: list[dict[str, Any]] = []
    seen_holding_keys: set[tuple[str, float]] = set()
    for row in holdings:
        key = (row["symbol"], float(row.get("quantity") or 0.0))
        if key in seen_holding_keys:
            continue
        seen_holding_keys.add(key)
        deduped_holdings.append(row)

    deduped_derivatives: list[dict[str, Any]] = []
    seen_derivative_symbols: set[str] = set()
    for row in derivatives:
        symbol = str(row.get("symbol") or "")
        if symbol in seen_derivative_symbols:
            continue
        seen_derivative_symbols.add(symbol)
        deduped_derivatives.append(row)

    deduped_trades: list[dict[str, Any]] = []
    seen_trade_ids: set[tuple[str, str, float | None, float | None, str, float | None, float | None]] = set()
    for row in recent_trades:
        key = (
            row["date"],
            row["symbol"],
            row.get("quantity"),
            row.get("price"),
            row["side"],
            row.get("trade_amount"),
            row.get("cash_change"),
        )
        if key in seen_trade_ids:
            continue
        seen_trade_ids.add(key)
        deduped_trades.append(row)

    realized_entries = _estimate_longbridge_realized_entries(deduped_holdings, deduped_trades)
    for currency, amount in daily_interest_by_currency.items():
        # 利息表展示为费用口径，纳入已实现现金项时按负值处理。
        _append_realized_entry(
            realized_entries,
            amount=-abs(float(amount)),
            currency=currency,
            source="statement_cashflow",
            category="financing_interest",
            label="当日融资利息",
        )
    realized_entries = _merge_realized_entries(realized_entries)
    risk_notes = ["融资余额约 186.86 万 HKD，且存在雪球/FCN 结构化票据敞口。"]
    if daily_interest_by_currency:
        interest_parts = [f"{currency} {-abs(float(amount)):+.2f}" for currency, amount in daily_interest_by_currency.items()]
        risk_notes.append(f"账单显示当日融资利息：{'，'.join(interest_parts)}。")
    if margin_interest_by_currency:
        interest_parts = [f"{currency} {amount:,.2f}" for currency, amount in margin_interest_by_currency.items()]
        risk_notes.append(f"账单显示当月融资利息累计：{'，'.join(interest_parts)}。")
    if realized_entries:
        risk_notes.append("已对“仅卖出且当期清仓”的标的估算已实现盈亏，可能与券商税务口径存在差异。")

    return {
        "account_id": source["account_id"],
        "broker": source["broker"],
        "statement_type": source["type"],
        "statement_date": statement_date or "2026-03-06",
        "base_currency": "HKD",
        "nav": nav or 6746105.40,
        "cash_balances": cash_balances or [
            {"currency": "HKD", "amount": -314374.72},
            {"currency": "USD", "amount": -198800.34},
        ],
        "holdings": deduped_holdings,
        "derivatives": deduped_derivatives,
        "recent_trades": deduped_trades,
        "realized_pnl_entries": realized_entries,
        "risk_notes": risk_notes,
    }


def summarize_source_issue(exc: Exception) -> str:
    if isinstance(exc, FileNotFoundError):
        return "源文件不存在"
    text = str(exc).strip()
    lowered = text.lower()
    compact = lowered.replace(" ", "")
    if "list index out of range" in lowered:
        return "结单格式与当前解析模板不匹配"
    if "tuple index out of range" in lowered:
        return "结单格式与当前解析模板不匹配"
    if "no /root object" in lowered or "is this really a pdf" in lowered:
        return "PDF 文件损坏或格式无效"
    if "pdftoppm" in lowered or "pdf 页面渲染失败" in lowered:
        return "PDF 渲染失败，请确认文件可正常打开"
    if "connectionresetbypeer" in compact or "connection reset by peer" in lowered:
        return "AI 服务连接中断，请稍后重试"
    if "http error 401" in lowered or "unauthorized" in lowered:
        return "AI 服务鉴权失败，请检查模型配置"
    if "http error 404" in lowered:
        return "AI 服务地址或模型配置错误"
    if "ai解析失败" in lowered and "结单格式与当前解析模板不匹配" in text:
        return "结单格式与当前解析模板不匹配，且 AI 解析暂不可用"
    if "ai解析失败" in lowered:
        return "AI 解析暂不可用，请稍后重试或切换模型"
    if not text:
        return exc.__class__.__name__
    return text.splitlines()[0][:160]


def _load_parsed_payload(path: Path) -> dict[str, Any] | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    if not isinstance(payload, dict):
        return None
    # A minimal sanity check to avoid loading random JSON.
    if not isinstance(payload.get("holdings"), list):
        return None
    return payload


def _parsed_payload_path_for_source(source: dict[str, Any]) -> Path:
    raw = str(source.get("parsed_payload_path") or "").strip()
    if raw:
        return Path(raw).expanduser()
    # Keep payload colocated with uploaded file so it's easy to ship/inspect.
    return Path(source["path"]).with_suffix(".parsed.json")


def _should_attempt_ai_parse(source: dict[str, Any]) -> bool:
    # Only auto-parse uploads. Default monitored PDFs should remain deterministic.
    if str(source.get("source_mode") or "").strip() != "upload":
        return False
    # If the user uploaded an image, the rule-based PDF parsers will never work.
    media_type = str(source.get("uploaded_media_type") or "").lower()
    if media_type.startswith("image/"):
        return True
    # For PDFs, we only do AI when local parsing fails.
    return True


def _parse_with_ai(source: dict[str, Any], *, user_id: str | None, parse_error: str | None) -> dict[str, Any]:
    try:
        from statement_ai_parser import parse_statement_with_ai_best_effort
    except ModuleNotFoundError:
        from market_dashboard.statement_ai_parser import parse_statement_with_ai_best_effort

    account, meta, warnings = parse_statement_with_ai_best_effort(source, parse_error=parse_error)
    parsed_payload_path = _parsed_payload_path_for_source(source)
    try:
        parsed_payload_path.write_text(json.dumps(account, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError:
        # If persistence fails, we can still return the parsed account to satisfy this request.
        parsed_payload_path = Path("")

    try:
        update_uploaded_statement_parse_result(
            source["account_id"],
            user_id=user_id,
            parser_mode=str(meta.get("parser_mode") or "llm"),
            parse_status="parsed",
            parse_issue="；".join(warnings)[:500] if warnings else "",
            llm_provider=str(meta.get("provider") or ""),
            llm_model=str(meta.get("model") or ""),
            parsed_payload_path=str(parsed_payload_path) if str(parsed_payload_path) else None,
            detected_broker=str(meta.get("detected_broker") or ""),
            detected_statement_type=str(meta.get("detected_statement_type") or ""),
            last_parsed_at=datetime.now(timezone.utc).isoformat(),
            uploaded_media_type=str(meta.get("uploaded_media_type") or ""),
        )
    except Exception:
        # Non-fatal: parsing succeeded, but metadata update can fail in read-only environments.
        pass

    return account


def parse_accounts(
    cached_accounts_by_id: dict[str, dict[str, Any]] | None = None,
    strict_account_ids: set[str] | None = None,
    user_id: str | None = None,
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
            "last_parsed_at": source.get("last_parsed_at"),
            "parser_mode": source.get("parser_mode"),
            "parse_status": source.get("parse_status"),
            "parse_issue": source.get("parse_issue"),
            "llm_provider": source.get("llm_provider"),
            "llm_model": source.get("llm_model"),
            "file_name": path.name,
            "file_exists": path.exists(),
            "load_status": "parsed",
            "issue": None,
            "statement_date": None,
        }
        try:
            parsed_payload_path = _parsed_payload_path_for_source(source)
            pre_parsed = _load_parsed_payload(parsed_payload_path)
            if pre_parsed is not None:
                account = deepcopy(pre_parsed)
                account["account_id"] = source["account_id"]
                account["broker"] = source["broker"]
                account["statement_type"] = source["type"]
                account["load_status"] = "parsed"
                account["load_issue"] = None
                state["statement_date"] = account.get("statement_date")
                state["load_status"] = "parsed"
                accounts.append(account)
                source_states.append(state)
                continue

            if not path.exists():
                raise FileNotFoundError(path)
            if parser is None:
                raise KeyError(f"unsupported statement_type: {source.get('type')}")
            account = parser(source)
            account["load_status"] = "parsed"
            account["load_issue"] = None
            state["statement_date"] = account.get("statement_date")
            accounts.append(account)
            if account_id in strict_ids and str(source.get("source_mode") or "") == "upload":
                try:
                    update_uploaded_statement_parse_result(
                        account_id,
                        user_id=user_id,
                        parser_mode="local",
                        parse_status="parsed",
                        parse_issue="",
                        last_parsed_at=datetime.now(timezone.utc).isoformat(),
                        uploaded_media_type=str(source.get("uploaded_media_type") or ""),
                    )
                except Exception:
                    pass
        except Exception as exc:  # noqa: BLE001
            issue = summarize_source_issue(exc)
            # Uploaded files can be parsed via LLM as a fallback to handle new PDF versions or screenshots.
            if account_id in strict_ids and _should_attempt_ai_parse(source) and path.exists():
                try:
                    account = _parse_with_ai(source, user_id=user_id, parse_error=issue)
                    account["load_status"] = "parsed"
                    account["load_issue"] = None
                    state["statement_date"] = account.get("statement_date")
                    state["load_status"] = "parsed"
                    state["issue"] = None
                    accounts.append(account)
                    source_states.append(state)
                    continue
                except Exception as ai_exc:  # noqa: BLE001
                    issue = f"{issue}；AI解析失败：{summarize_source_issue(ai_exc)}"
                    try:
                        update_uploaded_statement_parse_result(
                            account_id,
                            user_id=user_id,
                            parser_mode="llm",
                            parse_status="error",
                            parse_issue=issue,
                            last_parsed_at=datetime.now(timezone.utc).isoformat(),
                            uploaded_media_type=str(source.get("uploaded_media_type") or ""),
                        )
                    except Exception:
                        pass

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
                    "statement_value_present_count": 0,
                    "statement_pnl_present_count": 0,
                    "cost_present_count": 0,
                    "accounts": [],
                },
            )
            entry["quantity"] += holding["quantity"]
            entry["name"] = pick_display_name(entry.get("name"), holding.get("name")) or entry["name"]
            if holding.get("cost") is not None:
                entry["cost_value"] += holding["quantity"] * holding["cost"]
                entry["cost_present_count"] += 1
            if holding.get("statement_price") is not None:
                entry["statement_price_value"] += holding["quantity"] * holding["statement_price"]
            if holding.get("statement_value") is not None:
                entry["statement_value"] += holding["statement_value"]
                entry["statement_value_present_count"] += 1
            if holding.get("statement_pnl") is not None:
                entry["statement_pnl"] += holding["statement_pnl"]
                entry["statement_pnl_present_count"] += 1
            entry["accounts"].append(
                {
                    "account_id": account["account_id"],
                    "broker": account["broker"],
                    "currency": holding.get("currency"),
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
