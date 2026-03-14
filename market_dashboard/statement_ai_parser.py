from __future__ import annotations

import base64
import json
import mimetypes
import re
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote
from urllib.request import Request, urlopen

try:
    from ai_insight_model import (
        GEMINI_API_BASE_URL,
        REQUEST_TIMEOUT_SECONDS,
        _clean_json_text,
        _configured_provider_order,
        _extract_gemini_text,
        _extract_openai_compatible_text,
        _provider_label,
        _provider_runtime_settings,
    )
except ModuleNotFoundError:
    from market_dashboard.ai_insight_model import (
        GEMINI_API_BASE_URL,
        REQUEST_TIMEOUT_SECONDS,
        _clean_json_text,
        _configured_provider_order,
        _extract_gemini_text,
        _extract_openai_compatible_text,
        _provider_label,
        _provider_runtime_settings,
    )

try:
    import pdfplumber  # type: ignore
except Exception:  # noqa: BLE001
    pdfplumber = None

try:
    from PIL import Image  # type: ignore
except Exception:  # noqa: BLE001
    Image = None


ANTHROPIC_MEDIA_API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_SUPPORTED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/gif", "image/webp"}
GEMINI_SUPPORTED_IMAGE_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
}
SUPPORTED_UPLOAD_IMAGE_TYPES = ANTHROPIC_SUPPORTED_IMAGE_TYPES | GEMINI_SUPPORTED_IMAGE_TYPES
KNOWN_BROKER_ALIASES = {
    "tiger": "Tiger",
    "tiger brokers": "Tiger",
    "tiger trade": "Tiger",
    "ib": "Interactive Brokers",
    "ibkr": "Interactive Brokers",
    "interactive brokers": "Interactive Brokers",
    "futu": "Futu",
    "moomoo": "Futu",
    "longbridge": "Longbridge",
    "长桥": "Longbridge",
    "老虎": "Tiger",
    "富途": "Futu",
    "盈透": "Interactive Brokers",
}
KNOWN_STATEMENT_TYPES = {
    "tiger_activity",
    "ib_daily",
    "futu_monthly_us",
    "futu_monthly_hk",
    "longbridge_daily",
}


def _trimmed_string(value: Any) -> str:
    return str(value or "").strip()


def _now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _guess_mime_type(path: Path) -> str:
    mime_type = mimetypes.guess_type(path.name)[0]
    if mime_type:
        return mime_type
    if path.suffix.lower() == ".pdf":
        return "application/pdf"
    return "application/octet-stream"


def _normalize_broker_name(value: Any) -> str | None:
    raw = _trimmed_string(value)
    if not raw:
        return None
    normalized = re.sub(r"[^a-zA-Z\u4e00-\u9fff]+", " ", raw).strip().lower()
    if normalized in KNOWN_BROKER_ALIASES:
        return KNOWN_BROKER_ALIASES[normalized]
    for alias, broker in KNOWN_BROKER_ALIASES.items():
        if alias in normalized:
            return broker
    return raw


def _normalize_statement_type(
    raw_value: Any,
    *,
    broker: str | None,
    base_currency: str | None,
    holdings: list[dict[str, Any]] | None,
) -> str | None:
    raw = _trimmed_string(raw_value).lower()
    if raw in KNOWN_STATEMENT_TYPES:
        return raw

    resolved_broker = _normalize_broker_name(broker)
    currency = (_trimmed_string(base_currency).upper() or "").upper()
    holdings = holdings or []
    holdings_are_hk = any(str(item.get("symbol") or "").upper().endswith(".HK") for item in holdings)
    holdings_are_us = any(not str(item.get("symbol") or "").upper().endswith(".HK") for item in holdings)

    if resolved_broker == "Tiger":
        return "tiger_activity"
    if resolved_broker == "Interactive Brokers":
        return "ib_daily"
    if resolved_broker == "Longbridge":
        return "longbridge_daily"
    if resolved_broker == "Futu":
        if "hk" in raw or currency == "HKD" or holdings_are_hk and not holdings_are_us:
            return "futu_monthly_hk"
        if "us" in raw or currency == "USD" or holdings_are_us:
            return "futu_monthly_us"
    return None


def _normalize_currency(value: Any) -> str:
    raw = _trimmed_string(value).upper()
    if raw in {"HKD", "USD", "CNY", "RMB"}:
        return "CNY" if raw == "RMB" else raw
    return raw or "USD"


def _coerce_float(value: Any) -> float | None:
    if value in (None, "", "--", "N/A", "/", "null"):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    cleaned = (
        str(value)
        .replace(",", "")
        .replace("HK$", "")
        .replace("$", "")
        .replace("%", "")
        .replace("—", "-")
        .strip()
    )
    if not cleaned:
        return None
    try:
        return float(cleaned)
    except ValueError:
        return None


def _normalize_symbol(raw_symbol: Any, name: str | None = None, currency: str | None = None) -> str:
    symbol = _trimmed_string(raw_symbol).upper()
    if not symbol and name:
        symbol = _trimmed_string(name).upper()
    symbol = symbol.replace("（", "(").replace("）", ")")
    symbol = re.sub(r"\s+", "", symbol)
    symbol = re.sub(r"^[^A-Z0-9]+|[^A-Z0-9.]+$", "", symbol)
    if symbol.isdigit():
        return f"{symbol.zfill(5)}.HK"
    if re.fullmatch(r"\d{1,5}\.HK", symbol):
        head = symbol.split(".", 1)[0]
        return f"{head.zfill(5)}.HK"
    if currency == "HKD" and re.fullmatch(r"\d{1,5}", symbol):
        return f"{symbol.zfill(5)}.HK"
    return symbol


def _normalize_market(symbol: str, currency: str, raw_value: Any = None) -> str:
    raw = _trimmed_string(raw_value).upper()
    if raw in {"HK", "US"}:
        return raw
    if symbol.endswith(".HK") or currency == "HKD":
        return "HK"
    return "US"


def _normalize_trade_side(value: Any) -> str:
    raw = _trimmed_string(value).lower()
    if any(token in raw for token in ("sell", "卖")):
        return "卖出"
    return "买入"


def _normalize_date(value: Any, fallback: str | None = None) -> str:
    raw = _trimmed_string(value)
    if not raw:
        return fallback or _now_iso()[:10]
    date_match = re.search(r"(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})", raw)
    if date_match:
        year, month, day = date_match.groups()
        return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"
    compact_match = re.search(r"(20\d{2})(\d{2})(\d{2})", raw)
    if compact_match:
        year, month, day = compact_match.groups()
        return f"{year}-{month}-{day}"
    return fallback or raw[:10]


def _extract_pdf_text(path: Path, max_pages: int = 8) -> str:
    if pdfplumber is None:
        return ""
    try:
        with pdfplumber.open(path) as pdf:
            blocks = []
            for page in pdf.pages[:max_pages]:
                text = (page.extract_text() or "").strip()
                if text:
                    blocks.append(text[:5000])
        return "\n\n".join(blocks)[:20000]
    except Exception:  # noqa: BLE001
        return ""


def _render_pdf_preview_images(path: Path, max_pages: int = 4) -> list[Path]:
    with tempfile.TemporaryDirectory(prefix="statement-preview-") as tmp_dir:
        output_prefix = Path(tmp_dir) / "preview"
        command = [
            "pdftoppm",
            "-png",
            "-f",
            "1",
            "-l",
            str(max_pages),
            str(path),
            str(output_prefix),
        ]
        subprocess.run(command, check=True, capture_output=True)
        rendered = sorted(Path(tmp_dir).glob("preview-*.png"))
        if not rendered:
            raise RuntimeError("PDF 页面渲染失败")
        persisted_dir = Path(tempfile.mkdtemp(prefix="statement-preview-persist-"))
        persisted_paths: list[Path] = []
        for item in rendered:
            target = persisted_dir / item.name
            target.write_bytes(item.read_bytes())
            persisted_paths.append(target)
        return persisted_paths


def _ensure_supported_image(path: Path, mime_type: str, *, provider: str) -> tuple[bytes, str]:
    raw_bytes = path.read_bytes()
    supported_types = ANTHROPIC_SUPPORTED_IMAGE_TYPES if provider == "anthropic" else GEMINI_SUPPORTED_IMAGE_TYPES
    if mime_type in supported_types:
        return raw_bytes, mime_type
    if Image is None:
        raise RuntimeError("图片格式不受支持，且当前环境无法自动转换")
    try:
        with Image.open(path) as image:
            converted = image.convert("RGB")
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as temp_file:
                temp_path = Path(temp_file.name)
            converted.save(temp_path, format="PNG")
            data = temp_path.read_bytes()
            temp_path.unlink(missing_ok=True)
            return data, "image/png"
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(f"图片格式转换失败：{exc}") from exc


def _anthropic_media_request(
    *,
    provider_settings: dict[str, Any],
    prompt_text: str,
    media_paths: list[Path],
) -> tuple[str, str]:
    content_blocks: list[dict[str, Any]] = []
    for path in media_paths:
        mime_type = _guess_mime_type(path)
        media_bytes, normalized_mime = _ensure_supported_image(path, mime_type, provider="anthropic")
        content_blocks.append(
            {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": normalized_mime,
                    "data": base64.b64encode(media_bytes).decode("utf-8"),
                },
            }
        )
    content_blocks.append({"type": "text", "text": prompt_text})
    payload = {
        "model": provider_settings["candidate_models"][0],
        "max_tokens": 3200,
        "temperature": 0.1,
        "system": (
            "你是券商结单结构化解析器。"
            "你必须只输出 JSON。"
            "所有字段都必须基于输入页面内容，不允许编造看不到的数字。"
        ),
        "messages": [{"role": "user", "content": content_blocks}],
    }
    request = Request(
        ANTHROPIC_MEDIA_API_URL,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "x-api-key": provider_settings["api_key"],
            "anthropic-version": "2023-06-01",
        },
    )
    with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        response_payload = json.loads(response.read().decode("utf-8"))
    content = response_payload.get("content") or []
    text = "\n".join(
        block.get("text", "")
        for block in content
        if isinstance(block, dict) and block.get("type") == "text"
    ).strip()
    return text, str(response_payload.get("model") or provider_settings["candidate_models"][0])


def _gemini_media_request(
    *,
    provider_settings: dict[str, Any],
    prompt_text: str,
    media_paths: list[Path],
) -> tuple[str, str]:
    parts: list[dict[str, Any]] = []
    for path in media_paths:
        mime_type = _guess_mime_type(path)
        media_bytes, normalized_mime = _ensure_supported_image(path, mime_type, provider="gemini")
        parts.append(
            {
                "inlineData": {
                    "mimeType": normalized_mime,
                    "data": base64.b64encode(media_bytes).decode("utf-8"),
                }
            }
        )
    parts.append({"text": prompt_text})
    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 3200},
        "systemInstruction": {
            "parts": [
                {
                    "text": (
                        "你是券商结单结构化解析器。"
                        "你必须只输出 JSON。"
                        "所有字段都必须基于输入页面内容，不允许编造看不到的数字。"
                    )
                }
            ]
        },
    }
    request = Request(
        f"{provider_settings['base_url'].rstrip('/') or GEMINI_API_BASE_URL}/models/{quote(provider_settings['candidate_models'][0], safe='')}:generateContent?key={quote(provider_settings['api_key'], safe='')}",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        response_payload = json.loads(response.read().decode("utf-8"))
    return _extract_gemini_text(response_payload), provider_settings["candidate_models"][0]


def _text_only_request(
    *,
    provider_settings: dict[str, Any],
    prompt_text: str,
    extracted_text: str,
) -> tuple[str, str]:
    request_body = json.dumps(
        {
            "model": provider_settings["candidate_models"][0],
            "max_tokens": 3200,
            "temperature": 0.1,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "你是券商结单结构化解析器。"
                        "你必须只输出 JSON。"
                        "所有字段都必须基于输入文本，不允许编造看不到的数字。"
                    ),
                },
                {
                    "role": "user",
                    "content": f"{prompt_text}\n\n文档文本摘录：\n{extracted_text[:24000]}",
                },
            ],
        },
        ensure_ascii=False,
    ).encode("utf-8")
    request = Request(
        f"{provider_settings['base_url'].rstrip('/')}/chat/completions",
        data=request_body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {provider_settings['api_key']}",
        },
    )
    with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        response_payload = json.loads(response.read().decode("utf-8"))
    return _extract_openai_compatible_text(response_payload), str(response_payload.get("model") or provider_settings["candidate_models"][0])


def _statement_prompt(
    *,
    source: dict[str, Any],
    extracted_text: str,
    parse_error: str | None,
) -> str:
    expected_broker = _trimmed_string(source.get("broker"))
    expected_type = _trimmed_string(source.get("type"))
    uploaded_name = Path(source.get("path") or "").name
    return (
        "请识别这份券商结单或截图，并返回严格 JSON。\n"
        "如果是截图，只提取图片里真正可见的字段；看不清或不存在的字段用 null 或空数组。\n"
        "不要输出 Markdown，不要输出解释。\n"
        "字段格式必须是：\n"
        "{"
        "\"broker\":\"Tiger|Interactive Brokers|Futu|Longbridge|Unknown\","
        "\"statement_type\":\"tiger_activity|ib_daily|futu_monthly_us|futu_monthly_hk|longbridge_daily|unknown\","
        "\"statement_date\":\"YYYY-MM-DD|null\","
        "\"base_currency\":\"HKD|USD|null\","
        "\"nav\":number|null,"
        "\"cash_balances\":[{\"currency\":\"HKD|USD\",\"amount\":number|null}],"
        "\"holdings\":[{\"symbol\":\"...\",\"name\":\"...\",\"quantity\":number|null,\"cost\":number|null,\"statement_price\":number|null,\"statement_value\":number|null,\"statement_pnl\":number|null,\"currency\":\"HKD|USD|null\",\"market\":\"HK|US|null\"}],"
        "\"derivatives\":[{\"symbol\":\"...\",\"description\":\"...\",\"quantity\":number|null,\"market_value\":number|null,\"unrealized_pnl\":number|null,\"estimated_notional\":number|null,\"currency\":\"HKD|USD|null\",\"underlyings\":[\"...\"]}],"
        "\"recent_trades\":[{\"date\":\"YYYY-MM-DD|null\",\"symbol\":\"...\",\"name\":\"...\",\"side\":\"买入|卖出\",\"quantity\":number|null,\"price\":number|null,\"currency\":\"HKD|USD|null\"}],"
        "\"risk_notes\":[\"...\"],"
        "\"parser_notes\":[\"...\"]"
        "}\n"
        f"已知目标账户 broker 提示：{expected_broker or '未知'}。\n"
        f"已知目标账户 statement_type 提示：{expected_type or '未知'}。\n"
        f"上传文件名：{uploaded_name or '未知'}。\n"
        f"上一轮本地解析失败原因：{parse_error or '无'}。\n"
        "如果识别到文件更像其他券商或其他结单类型，请在 broker / statement_type 中如实填写，并在 parser_notes 说明。\n"
        "symbol 需要尽量标准化：港股写成 5 位数字加 .HK，美股保持大写代码。\n"
        "recent_trades 只保留最近可见的交易；derivatives 只保留文档中明确出现的期权、FCN、雪球或结构化票据。\n"
        f"辅助文本摘录（可能不完整）：\n{extracted_text[:12000]}"
    )


def _load_json_from_model(text: str) -> dict[str, Any]:
    cleaned = _clean_json_text(text)
    try:
        payload = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"模型返回的 JSON 无法解析：{exc}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("模型返回结果不是 JSON 对象")
    return payload


def _normalize_cash_balances(rows: Any) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        currency = _normalize_currency(row.get("currency"))
        amount = _coerce_float(row.get("amount"))
        if not currency:
            continue
        normalized.append({"currency": currency, "amount": amount})
    return normalized


def _normalize_holdings(rows: Any) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        currency = _normalize_currency(row.get("currency"))
        symbol = _normalize_symbol(row.get("symbol"), row.get("name"), currency)
        name = _trimmed_string(row.get("name")) or symbol
        if not symbol:
            continue
        normalized.append(
            {
                "symbol": symbol,
                "name": name,
                "quantity": _coerce_float(row.get("quantity")) or 0.0,
                "cost": _coerce_float(row.get("cost")),
                "statement_price": _coerce_float(row.get("statement_price")),
                "statement_value": _coerce_float(row.get("statement_value")),
                "statement_pnl": _coerce_float(row.get("statement_pnl")),
                "currency": currency,
                "market": _normalize_market(symbol, currency, row.get("market")),
            }
        )
    return normalized


def _normalize_derivatives(rows: Any) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        description = _trimmed_string(row.get("description"))
        symbol = _normalize_symbol(row.get("symbol"), description)
        if not description and not symbol:
            continue
        underlyings = [
            _normalize_symbol(item)
            for item in row.get("underlyings") or []
            if _normalize_symbol(item)
        ]
        normalized.append(
            {
                "symbol": symbol or description[:32],
                "description": description or symbol,
                "quantity": _coerce_float(row.get("quantity")),
                "market_value": _coerce_float(row.get("market_value")),
                "unrealized_pnl": _coerce_float(row.get("unrealized_pnl")),
                "estimated_notional": _coerce_float(row.get("estimated_notional") or row.get("notional")),
                "currency": _normalize_currency(row.get("currency")),
                "underlyings": underlyings,
            }
        )
    return normalized


def _normalize_recent_trades(rows: Any, *, source: dict[str, Any]) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        currency = _normalize_currency(row.get("currency"))
        symbol = _normalize_symbol(row.get("symbol"), row.get("name"), currency)
        if not symbol:
            continue
        normalized.append(
            {
                "date": _normalize_date(row.get("date")),
                "symbol": symbol,
                "name": _trimmed_string(row.get("name")) or symbol,
                "side": _normalize_trade_side(row.get("side")),
                "quantity": _coerce_float(row.get("quantity")),
                "price": _coerce_float(row.get("price")),
                "currency": currency,
                "account_id": source["account_id"],
                "broker": source["broker"],
            }
        )
    return normalized


def _normalize_risk_notes(rows: Any, parser_notes: Any) -> list[str]:
    notes: list[str] = []
    for collection in (rows or [], parser_notes or []):
        if isinstance(collection, str):
            text = collection.strip()
            if text:
                notes.append(text[:220])
            continue
        for row in collection if isinstance(collection, list) else []:
            text = _trimmed_string(row)
            if text:
                notes.append(text[:220])
    deduped: list[str] = []
    seen: set[str] = set()
    for note in notes:
        if note in seen:
            continue
        seen.add(note)
        deduped.append(note)
    return deduped[:6]


def _normalize_ai_account_payload(
    raw_payload: dict[str, Any],
    *,
    source: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    detected_broker = _normalize_broker_name(raw_payload.get("broker"))
    expected_broker = _normalize_broker_name(source.get("broker"))
    if expected_broker and detected_broker and detected_broker != expected_broker:
        raise RuntimeError(f"识别到上传资料更像 {detected_broker} 结单，与当前账户 {expected_broker} 不匹配")

    holdings = _normalize_holdings(raw_payload.get("holdings"))
    recent_trades = _normalize_recent_trades(raw_payload.get("recent_trades"), source=source)
    derivatives = _normalize_derivatives(raw_payload.get("derivatives"))
    base_currency = _normalize_currency(raw_payload.get("base_currency"))
    detected_statement_type = _normalize_statement_type(
        raw_payload.get("statement_type"),
        broker=detected_broker or expected_broker,
        base_currency=base_currency,
        holdings=holdings,
    )
    expected_type = _trimmed_string(source.get("type"))
    if expected_type and detected_statement_type and detected_statement_type != expected_type:
        raise RuntimeError(f"识别到上传资料更像 {detected_statement_type}，与当前账户类型 {expected_type} 不匹配")

    if not holdings and not recent_trades and not derivatives:
        raise RuntimeError("大模型未提取到有效持仓、交易或衍生品字段")

    broker = expected_broker or detected_broker or "Unknown"
    statement_type = expected_type or detected_statement_type or "unknown"
    statement_date = _normalize_date(raw_payload.get("statement_date"), fallback=_now_iso()[:10])
    account = {
        "account_id": source["account_id"],
        "broker": broker,
        "statement_type": statement_type,
        "statement_date": statement_date,
        "base_currency": base_currency,
        "nav": _coerce_float(raw_payload.get("nav")),
        "cash_balances": _normalize_cash_balances(raw_payload.get("cash_balances")),
        "holdings": holdings,
        "derivatives": derivatives,
        "recent_trades": recent_trades,
        "risk_notes": _normalize_risk_notes(raw_payload.get("risk_notes"), raw_payload.get("parser_notes")),
        "load_status": "parsed",
        "load_issue": None,
    }
    return account, {
        "detected_broker": detected_broker,
        "detected_statement_type": detected_statement_type,
        "parser_mode": "llm",
    }


def parse_statement_with_ai(
    source: dict[str, Any],
    *,
    ai_request_config: dict[str, Any] | None = None,
    parse_error: str | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    path = Path(source["path"])
    if not path.exists():
        raise FileNotFoundError(path)

    mime_type = _guess_mime_type(path)
    is_pdf = mime_type == "application/pdf" or path.suffix.lower() == ".pdf"
    extracted_text = _extract_pdf_text(path) if is_pdf else ""
    prompt_text = _statement_prompt(source=source, extracted_text=extracted_text, parse_error=parse_error)

    media_paths: list[Path] = []
    if is_pdf:
        media_paths = _render_pdf_preview_images(path)
    elif mime_type.startswith("image/"):
        media_paths = [path]

    errors: list[str] = []
    try:
        for provider in _configured_provider_order(ai_request_config):
            provider_settings = _provider_runtime_settings(provider, ai_request_config=ai_request_config)
            if provider_settings is None:
                continue

            try:
                if media_paths and provider == "anthropic":
                    response_text, resolved_model = _anthropic_media_request(
                        provider_settings=provider_settings,
                        prompt_text=prompt_text,
                        media_paths=media_paths,
                    )
                elif media_paths and provider == "gemini":
                    response_text, resolved_model = _gemini_media_request(
                        provider_settings=provider_settings,
                        prompt_text=prompt_text,
                        media_paths=media_paths,
                    )
                elif extracted_text:
                    response_text, resolved_model = _text_only_request(
                        provider_settings=provider_settings,
                        prompt_text=prompt_text,
                        extracted_text=extracted_text,
                    )
                else:
                    raise RuntimeError("当前模型通道不支持图片直接识别")

                raw_payload = _load_json_from_model(response_text)
                account, meta = _normalize_ai_account_payload(raw_payload, source=source)
                return account, {
                    **meta,
                    "provider": provider,
                    "provider_label": _provider_label(provider),
                    "model": resolved_model,
                    "uploaded_media_type": mime_type,
                }
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{_provider_label(provider)}: {str(exc).strip() or exc.__class__.__name__}")
        raise RuntimeError("；".join(errors)[:500] or "未找到可用的大模型文档解析通道")
    finally:
        for item in media_paths:
            try:
                item.unlink()
            except OSError:
                pass
            try:
                item.parent.rmdir()
            except OSError:
                pass
