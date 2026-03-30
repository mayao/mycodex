#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import cgi
import ipaddress
import json
import mimetypes
import re
import socket
import subprocess
import tempfile
import time
from datetime import datetime, timedelta, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse
from uuid import uuid4

try:
    from auth_store import (
        create_or_login_device_session,
        create_or_login_apple_session,
        create_owner_session,
        create_session_for_phone,
        create_wechat_dev_session,
        get_import_center_payload,
        get_session,
        request_phone_code,
        revoke_session,
        resolve_portfolio_user_id,
        serialize_user,
    )
    from ai_insight_model import generate_chat_reply, get_ai_service_status
    from mobile_api import (
        build_mobile_ai_chat_context,
        build_mobile_dashboard_ai_payload,
        build_mobile_dashboard_payload,
        build_mobile_stock_detail_ai_payload,
    )
    from holdings_export import (
        build_holdings_export_dataset,
        render_holdings_pdf,
        render_holdings_xlsx,
    )
    from portfolio_analytics import (
        build_dashboard_ai_payload_from_snapshot,
        build_dashboard_payload,
        build_share_payload,
        build_stock_detail_payload,
        validate_payload,
    )
    from statement_parser import summarize_source_issue
    from statement_sources import (
        UPLOADS_DIR,
        get_statement_sources,
        get_statement_source_by_account,
        register_uploaded_statement,
        remove_uploaded_statement,
    )
    from statement_ai_parser import parse_statement_with_ai_best_effort
except ModuleNotFoundError:
    from market_dashboard.auth_store import (
        create_or_login_device_session,
        create_or_login_apple_session,
        create_owner_session,
        create_session_for_phone,
        create_wechat_dev_session,
        get_import_center_payload,
        get_session,
        request_phone_code,
        revoke_session,
        resolve_portfolio_user_id,
        serialize_user,
    )
    from market_dashboard.ai_insight_model import generate_chat_reply, get_ai_service_status
    from market_dashboard.mobile_api import (
        build_mobile_ai_chat_context,
        build_mobile_dashboard_ai_payload,
        build_mobile_dashboard_payload,
        build_mobile_stock_detail_ai_payload,
    )
    from market_dashboard.holdings_export import (
        build_holdings_export_dataset,
        render_holdings_pdf,
        render_holdings_xlsx,
    )
    from market_dashboard.portfolio_analytics import (
        build_dashboard_ai_payload_from_snapshot,
        build_dashboard_payload,
        build_share_payload,
        build_stock_detail_payload,
        validate_payload,
    )
    from market_dashboard.statement_ai_parser import parse_statement_with_ai_best_effort
    from market_dashboard.statement_parser import load_portfolio_cache, summarize_source_issue
    from market_dashboard.statement_sources import (
        UPLOADS_DIR,
        get_statement_sources,
        get_statement_source_by_account,
        register_uploaded_statement,
        remove_uploaded_statement,
    )
else:
    from statement_parser import load_portfolio_cache

try:
    import pdfplumber  # type: ignore
except Exception:  # noqa: BLE001
    pdfplumber = None


BASE_DIR = Path(__file__).resolve().parent
HTML_PATH = BASE_DIR / "dashboard.html"
SHARE_HTML_PATH = BASE_DIR / "share_dashboard.html"
STOCK_DETAIL_HTML_PATH = BASE_DIR / "stock_detail.html"
MAX_UPLOAD_BYTES = 40 * 1024 * 1024
CN_TZ = timezone(timedelta(hours=8))
AI_CONTEXT_TTL_SECONDS = 10 * 60
AI_CONTEXT_MAX_ENTRIES = 8
AI_CONTEXT_CACHE: dict[str, dict[str, Any]] = {}
AI_CONTEXT_LOCK = Lock()
MOBILE_AI_CONFIG_HEADER = "X-MyInvAI-AI-Config"
SUPPORTED_BROKER_ALIASES = {
    "tiger": "Tiger",
    "tiger brokers": "Tiger",
    "老虎": "Tiger",
    "ib": "Interactive Brokers",
    "ibkr": "Interactive Brokers",
    "interactive brokers": "Interactive Brokers",
    "盈透": "Interactive Brokers",
    "futu": "Futu",
    "moomoo": "Futu",
    "富途": "Futu",
    "longbridge": "Longbridge",
    "长桥": "Longbridge",
}


def load_html() -> str:
    return HTML_PATH.read_text(encoding="utf-8")


def load_share_html() -> str:
    return SHARE_HTML_PATH.read_text(encoding="utf-8")


def load_stock_detail_html() -> str:
    return STOCK_DETAIL_HTML_PATH.read_text(encoding="utf-8")


def _prune_ai_context_cache(now: float) -> None:
    expired_keys = [
        key
        for key, entry in AI_CONTEXT_CACHE.items()
        if now - float(entry.get("timestamp") or 0.0) > AI_CONTEXT_TTL_SECONDS
    ]
    for key in expired_keys:
        AI_CONTEXT_CACHE.pop(key, None)

    overflow = len(AI_CONTEXT_CACHE) - AI_CONTEXT_MAX_ENTRIES
    if overflow <= 0:
        return

    oldest_keys = sorted(
        AI_CONTEXT_CACHE,
        key=lambda key: float(AI_CONTEXT_CACHE[key].get("timestamp") or 0.0),
    )[:overflow]
    for key in oldest_keys:
        AI_CONTEXT_CACHE.pop(key, None)


def _store_ai_context(payload: dict[str, Any]) -> str:
    context_id = uuid4().hex
    now = time.time()
    with AI_CONTEXT_LOCK:
        _prune_ai_context_cache(now)
        AI_CONTEXT_CACHE[context_id] = {
            "timestamp": now,
            "payload": payload,
        }
    return context_id


def _load_ai_context(context_id: str) -> dict[str, Any] | None:
    now = time.time()
    with AI_CONTEXT_LOCK:
        _prune_ai_context_cache(now)
        entry = AI_CONTEXT_CACHE.get(context_id)
        return entry.get("payload") if entry else None


def _attach_deferred_ai_context(payload: dict[str, Any]) -> dict[str, Any]:
    response_payload = dict(payload)
    response_payload["ai_context_id"] = _store_ai_context(payload)
    response_payload["ai_status"] = {
        "state": "pending",
        "message": "AI 正在分析组合结构、交易节奏和风险传导，资产与常规信息已优先展示。",
    }
    return response_payload


def _read_mobile_ai_request_config(handler: BaseHTTPRequestHandler) -> dict[str, Any] | None:
    raw_header = str(handler.headers.get(MOBILE_AI_CONFIG_HEADER, "") or "").strip()
    if not raw_header:
        return None
    try:
        padded = raw_header + "=" * (-len(raw_header) % 4)
        decoded = base64.b64decode(padded.encode("utf-8")).decode("utf-8")
        payload = json.loads(decoded)
        return payload if isinstance(payload, dict) else None
    except Exception:
        return None


def _build_mobile_dashboard_with_fallback(
    force_refresh: bool,
    include_live: bool = True,
    *,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        return build_mobile_dashboard_payload(
            force_refresh=force_refresh,
            include_live=include_live,
            allow_cached_fallback=True,
            include_ai=False,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )
    except Exception:
        return build_mobile_dashboard_payload(
            force_refresh=False,
            include_live=False,
            allow_cached_fallback=True,
            include_ai=False,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )


def _build_mobile_dashboard_ai_with_fallback(
    force_refresh: bool,
    *,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        return build_mobile_dashboard_ai_payload(
            force_refresh=force_refresh,
            allow_cached_fallback=True,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )
    except Exception:
        return build_mobile_dashboard_ai_payload(
            force_refresh=False,
            allow_cached_fallback=True,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )


def _build_stock_detail_with_fallback(
    symbol: str,
    force_refresh: bool,
    share_mode: bool,
    *,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        return build_stock_detail_payload(
            symbol=symbol,
            force_refresh=force_refresh,
            include_live=True,
            allow_cached_fallback=True,
            share_mode=share_mode,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )
    except Exception:
        return build_stock_detail_payload(
            symbol=symbol,
            force_refresh=False,
            include_live=False,
            allow_cached_fallback=True,
            share_mode=share_mode,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )


def _build_stock_detail_ai_with_fallback(
    symbol: str,
    force_refresh: bool,
    share_mode: bool,
    *,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        return build_mobile_stock_detail_ai_payload(
            symbol=symbol,
            force_refresh=force_refresh,
            allow_cached_fallback=True,
            share_mode=share_mode,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )
    except Exception:
        return build_mobile_stock_detail_ai_payload(
            symbol=symbol,
            force_refresh=False,
            allow_cached_fallback=True,
            share_mode=share_mode,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )


def _build_mobile_ai_chat_context_with_fallback(
    context_type: str,
    *,
    symbol: str | None = None,
    force_refresh: bool = False,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        return build_mobile_ai_chat_context(
            context_type=context_type,
            symbol=symbol,
            force_refresh=force_refresh,
            allow_cached_fallback=True,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )
    except Exception:
        return build_mobile_ai_chat_context(
            context_type=context_type,
            symbol=symbol,
            force_refresh=False,
            allow_cached_fallback=True,
            user_id=user_id,
            ai_request_config=ai_request_config,
        )


def _build_mobile_discovery_payload(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    host_header = str(handler.headers.get("Host", "") or "").strip()
    host_without_port = host_header.split(":", 1)[0].strip() if host_header else ""
    server_port = int(handler.server.server_address[1])
    lan_ip = _detect_primary_lan_ip()
    suggested_host = host_without_port or lan_ip or "127.0.0.1"
    return {
        "service": "portfolio-workbench",
        "app_name": "MyInvAI",
        "bind_host": str(handler.server.server_address[0]),
        "port": server_port,
        "suggested_base_url": f"http://{suggested_host}:{server_port}/",
        "detected_lan_ip": lan_ip,
        "available_paths": [
            "/api/mobile/discovery",
            "/api/mobile/auth/device/bootstrap",
            "/api/mobile/dashboard",
            "/api/mobile/ai-service-status",
            "/api/mobile/export/holdings",
            "/api/mobile/stock-detail",
            "/api/mobile/upload-statement",
        ],
    }


def _normalize_broker_for_match(value: str | None) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    normalized = re.sub(r"[^a-zA-Z0-9\u4e00-\u9fff]+", " ", raw).strip().lower()
    if not normalized:
        return ""
    if normalized in SUPPORTED_BROKER_ALIASES:
        return SUPPORTED_BROKER_ALIASES[normalized]
    for alias, broker in SUPPORTED_BROKER_ALIASES.items():
        if alias in normalized:
            return broker
    return raw


def _normalize_statement_type_for_match(value: str | None) -> str:
    return str(value or "").strip().lower()


def _find_unique_source_by_broker_type(
    sources: list[dict[str, Any]],
    *,
    broker: str | None,
    statement_type: str | None,
) -> tuple[dict[str, Any] | None, str | None]:
    normalized_broker = _normalize_broker_for_match(broker)
    normalized_type = _normalize_statement_type_for_match(statement_type)
    if not normalized_broker or not normalized_type:
        return None, "识别结果不完整，无法定位到唯一券商子项。"

    matched = [
        item
        for item in sources
        if _normalize_broker_for_match(item.get("broker")) == normalized_broker
        and _normalize_statement_type_for_match(item.get("type")) == normalized_type
    ]
    if len(matched) == 1:
        return matched[0], None
    if not matched:
        return None, f"未找到与 {normalized_broker} / {normalized_type} 对应的券商子项。"
    return None, f"{normalized_broker} / {normalized_type} 存在多个候选子项，请在设置页指定具体子项后再上传。"


def _source_matches_broker_type(
    source: dict[str, Any] | None,
    *,
    broker: str | None,
    statement_type: str | None,
) -> bool:
    if source is None:
        return False
    return (
        _normalize_broker_for_match(source.get("broker")) == _normalize_broker_for_match(broker)
        and _normalize_statement_type_for_match(source.get("type")) == _normalize_statement_type_for_match(statement_type)
    )


def _parse_iso_date(value: str | None) -> str | None:
    text = str(value or "").strip()
    if not text:
        return None
    match = re.search(r"(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})", text)
    if match:
        year, month, day = match.groups()
        try:
            return datetime(int(year), int(month), int(day)).date().isoformat()
        except ValueError:
            return None
    compact = re.search(r"(20\d{2})(\d{2})(\d{2})", text)
    if compact:
        year, month, day = compact.groups()
        try:
            return datetime(int(year), int(month), int(day)).date().isoformat()
        except ValueError:
            return None
    return None


def _extract_statement_date_hint(path: Path, *, uploaded_media_type: str | None = None) -> str | None:
    candidates: set[str] = set()
    from_file_name = _parse_iso_date(path.name)
    if from_file_name:
        candidates.add(from_file_name)

    media_type = str(uploaded_media_type or "").lower()
    is_pdf = media_type == "application/pdf" or path.suffix.lower() == ".pdf"
    if is_pdf and pdfplumber is not None:
        try:
            with pdfplumber.open(path) as pdf:
                text = "\n".join((page.extract_text() or "") for page in pdf.pages[:4])
            for match in re.finditer(r"(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})", text):
                year, month, day = match.groups()
                parsed = _parse_iso_date(f"{year}-{month}-{day}")
                if parsed:
                    candidates.add(parsed)
        except Exception:  # noqa: BLE001
            pass

    if not candidates:
        return None
    return sorted(candidates)[-1]


def _cached_statement_date_for_account(account_id: str, *, user_id: str | None) -> str | None:
    cache = load_portfolio_cache(user_id=user_id)
    if not isinstance(cache, dict):
        return None
    payload = cache.get("payload")
    if not isinstance(payload, dict):
        return None
    for account in payload.get("accounts") or []:
        if not isinstance(account, dict):
            continue
        if str(account.get("account_id") or "") != account_id:
            continue
        parsed = _parse_iso_date(str(account.get("statement_date") or ""))
        if parsed:
            return parsed
    return None


class DashboardHandler(BaseHTTPRequestHandler):
    def _send_bytes(
        self,
        body: bytes,
        content_type: str,
        status: HTTPStatus = HTTPStatus.OK,
        *,
        filename: str | None = None,
    ) -> None:
        try:
            self.send_response(status.value)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            if filename:
                self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            return

    def _send_html(self, html_text: str, status: HTTPStatus = HTTPStatus.OK) -> None:
        self._send_bytes(html_text.encode("utf-8"), "text/html; charset=utf-8", status=status)

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send_bytes(body, "application/json; charset=utf-8", status=status)

    def _read_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0") or 0)
        if content_length <= 0:
            return {}
        try:
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
        except Exception as exc:  # noqa: BLE001
            raise ValueError(f"请求体解析失败：{exc}") from exc
        if not isinstance(payload, dict):
            raise ValueError("请求体必须是 JSON 对象。")
        return payload

    def _session_token(self) -> str | None:
        authorization = str(self.headers.get("Authorization", "")).strip()
        if authorization.lower().startswith("bearer "):
            return authorization.split(" ", 1)[1].strip()
        for header_name in ("X-Session-Token", "X-Session"):
            value = str(self.headers.get(header_name, "")).strip()
            if value:
                return value
        return None

    def _is_loopback_client(self) -> bool:
        host = str(self.client_address[0] or "").split("%", 1)[0]
        try:
            return ipaddress.ip_address(host).is_loopback
        except ValueError:
            return host in {"localhost"}

    def _require_mobile_session(self) -> dict[str, Any] | None:
        token = self._session_token()
        token_length = len(token or "")
        token_prefix = f"{token[:8]}..." if token else "none"
        print(
            f"[MOBILE-AUTH] route={self.path} client={self.client_address[0]} "
            f"token_len={token_length} token_prefix={token_prefix}"
        )
        session = get_session(token)
        if session is None:
            print(f"[MOBILE-AUTH] unauthorized route={self.path}")
            self._send_json(
                {"error": {"id": "unauthorized", "message": "请先登录，再访问个人投资数据。"}},
                status=HTTPStatus.UNAUTHORIZED,
            )
            return None
        user = session.get("user") or {}
        print(
            f"[MOBILE-AUTH] authorized route={self.path} "
            f"user={user.get('user_id', 'unknown')}"
        )
        return session

    def _portfolio_user_id_for_session(self, session: dict[str, Any] | None) -> str | None:
        if session is None:
            return None
        return resolve_portfolio_user_id(session.get("user"))

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        if path in ("/", "/index.html"):
            self._send_html(load_html())
            return
        if path in ("/share", "/share.html"):
            self._send_html(load_share_html())
            return
        if path.startswith("/stock/") or path.startswith("/share/stock/"):
            self._send_html(load_stock_detail_html())
            return
        if path == "/favicon.ico":
            self._send_bytes(b"", "image/x-icon", status=HTTPStatus.NO_CONTENT)
            return
        if path == "/api/market-data":
            force_refresh = "refresh=1" in self.path
            defer_ai = (query.get("defer_ai") or ["0"])[0].lower() in {"1", "true", "yes"}
            try:
                payload = build_dashboard_payload(
                    force_refresh=force_refresh,
                    include_live=True,
                    include_ai=not defer_ai,
                )
                if defer_ai:
                    payload = _attach_deferred_ai_context(payload)
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"工作台数据生成失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            self._send_json(payload)
            return
        if path == "/api/market-data-ai":
            force_refresh = "refresh=1" in self.path
            context_id = (query.get("context_id") or [""])[0].strip()
            try:
                snapshot_payload = _load_ai_context(context_id) if context_id else None
                if snapshot_payload is None:
                    snapshot_payload = build_dashboard_payload(
                        force_refresh=force_refresh,
                        include_live=True,
                        include_ai=False,
                    )
                payload = build_dashboard_ai_payload_from_snapshot(snapshot_payload)
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"AI 洞察生成失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            self._send_json(payload)
            return
        if path == "/api/mobile/auth/session":
            session = self._require_mobile_session()
            if session is None:
                return
            self._send_json({"user": serialize_user(session["user"])})
            return
        if path == "/api/mobile/discovery":
            self._send_json(_build_mobile_discovery_payload(self))
            return
        if path == "/api/mobile/import-center":
            session = self._require_mobile_session()
            if session is None:
                return
            self._send_json(get_import_center_payload(session["user"]["user_id"]))
            return
        if path == "/api/mobile/dashboard":
            session = self._require_mobile_session()
            if session is None:
                return
            force_refresh = "refresh=1" in self.path
            fast_mode = (query.get("fast") or ["0"])[0].lower() in {"1", "true", "yes"}
            ai_request_config = _read_mobile_ai_request_config(self)
            try:
                payload = _build_mobile_dashboard_with_fallback(
                    force_refresh=force_refresh,
                    include_live=not fast_mode,
                    user_id=self._portfolio_user_id_for_session(session),
                    ai_request_config=ai_request_config,
                )
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"移动端数据生成失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            self._send_json(payload)
            return
        if path == "/api/mobile/dashboard-ai":
            session = self._require_mobile_session()
            if session is None:
                return
            force_refresh = "refresh=1" in self.path
            ai_request_config = _read_mobile_ai_request_config(self)
            try:
                payload = _build_mobile_dashboard_ai_with_fallback(
                    force_refresh=force_refresh,
                    user_id=self._portfolio_user_id_for_session(session),
                    ai_request_config=ai_request_config,
                )
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"移动端 AI 洞察生成失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            self._send_json(payload)
            return
        if path == "/api/mobile/ai-service-status":
            session = self._require_mobile_session()
            if session is None:
                return
            ai_request_config = _read_mobile_ai_request_config(self)
            probe = (query.get("probe") or ["0"])[0].lower() in {"1", "true", "yes", "on"}
            self._send_json(get_ai_service_status(ai_request_config=ai_request_config, probe=probe))
            return
        if path == "/api/mobile/export/holdings":
            session = self._require_mobile_session()
            if session is None:
                return
            fmt = str((query.get("format") or ["xlsx"])[0] or "xlsx").strip().lower()
            if fmt not in {"xlsx", "pdf"}:
                self._send_json({"error": "仅支持导出 xlsx 或 pdf。"}, status=HTTPStatus.BAD_REQUEST)
                return
            ai_request_config = _read_mobile_ai_request_config(self)
            try:
                dataset = build_holdings_export_dataset(
                    force_refresh=False,
                    user_id=self._portfolio_user_id_for_session(session),
                    ai_request_config=ai_request_config,
                )
                if fmt == "pdf":
                    body = render_holdings_pdf(dataset)
                    content_type = "application/pdf"
                else:
                    body = render_holdings_xlsx(dataset)
                    content_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"导出失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            timestamp = datetime.now(CN_TZ).strftime("%Y%m%d-%H%M")
            file_name = f"myinvai-holdings-{timestamp}.{fmt}"
            self._send_bytes(body, content_type, filename=file_name)
            return
        if path == "/api/share-data":
            force_refresh = "refresh=1" in self.path
            try:
                payload = build_share_payload(force_refresh=force_refresh, include_live=True)
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"分享页数据生成失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            self._send_json(payload)
            return
        if path in {"/api/stock-detail", "/api/mobile/stock-detail"}:
            raw_symbol = (query.get("symbol") or [""])[0]
            symbol = unquote(raw_symbol).strip()
            share_mode = (query.get("share") or ["0"])[0].lower() in {"1", "true", "yes"}
            if not symbol:
                self._send_json({"error": "缺少股票代码。"}, status=HTTPStatus.BAD_REQUEST)
                return
            session_user_id = None
            if path == "/api/mobile/stock-detail":
                session = self._require_mobile_session()
                if session is None:
                    return
                session_user_id = self._portfolio_user_id_for_session(session)
            ai_request_config = _read_mobile_ai_request_config(self) if path == "/api/mobile/stock-detail" else None
            try:
                payload = _build_stock_detail_with_fallback(
                    symbol=symbol,
                    force_refresh="refresh=1" in self.path,
                    share_mode=share_mode,
                    user_id=session_user_id,
                    ai_request_config=ai_request_config,
                )
            except KeyError:
                self._send_json({"error": f"未找到股票 {symbol} 的详情。"}, status=HTTPStatus.NOT_FOUND)
                return
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"个股详情生成失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            self._send_json(payload)
            return
        if path == "/api/mobile/stock-detail-ai":
            session = self._require_mobile_session()
            if session is None:
                return
            raw_symbol = (query.get("symbol") or [""])[0]
            symbol = unquote(raw_symbol).strip()
            share_mode = (query.get("share") or ["0"])[0].lower() in {"1", "true", "yes"}
            if not symbol:
                self._send_json({"error": "缺少股票代码。"}, status=HTTPStatus.BAD_REQUEST)
                return
            ai_request_config = _read_mobile_ai_request_config(self)
            try:
                payload = _build_stock_detail_ai_with_fallback(
                    symbol=symbol,
                    force_refresh="refresh=1" in self.path,
                    share_mode=share_mode,
                    user_id=self._portfolio_user_id_for_session(session),
                    ai_request_config=ai_request_config,
                )
            except KeyError:
                self._send_json({"error": f"未找到股票 {symbol} 的详情。"}, status=HTTPStatus.NOT_FOUND)
                return
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"个股 AI 洞察生成失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            self._send_json(payload)
            return
        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/api/mobile/auth/device/bootstrap":
            self._handle_mobile_device_bootstrap()
            return
        if path == "/api/mobile/auth/phone/request-code":
            self._handle_mobile_phone_code_request()
            return
        if path == "/api/mobile/auth/phone/verify":
            self._handle_mobile_phone_verify()
            return
        if path == "/api/mobile/auth/wechat/login":
            self._handle_mobile_wechat_login()
            return
        if path == "/api/mobile/auth/apple/login":
            self._handle_mobile_apple_login()
            return
        if path == "/api/mobile/auth/dev/owner":
            self._handle_mobile_owner_dev_login()
            return
        if path == "/api/mobile/auth/logout":
            self._handle_mobile_logout()
            return
        if path in {"/api/upload-statement", "/api/mobile/upload-statement"}:
            self._handle_statement_upload()
            return
        if path == "/api/mobile/ai-chat":
            self._handle_mobile_ai_chat()
            return
        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def _handle_mobile_device_bootstrap(self) -> None:
        try:
            body = self._read_json_body()
            device_id = str(body.get("device_id") or "").strip()
            device_name = str(body.get("device_name") or "").strip() or None
            payload = create_or_login_device_session(device_id=device_id, device_name=device_name)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(payload)

    def _handle_mobile_phone_code_request(self) -> None:
        try:
            body = self._read_json_body()
            phone_number = str(body.get("phone_number") or "").strip()
            payload = request_phone_code(phone_number)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(payload)

    def _handle_mobile_phone_verify(self) -> None:
        try:
            body = self._read_json_body()
            phone_number = str(body.get("phone_number") or "").strip()
            code = str(body.get("code") or "").strip()
            payload = create_session_for_phone(phone_number, code)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(payload)

    def _handle_mobile_wechat_login(self) -> None:
        try:
            body = self._read_json_body()
            display_name = str(body.get("display_name") or "").strip() or None
            payload = create_wechat_dev_session(display_name=display_name)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(payload)

    def _handle_mobile_apple_login(self) -> None:
        try:
            body = self._read_json_body()
            user_identifier = str(body.get("user_identifier") or body.get("userIdentifier") or "").strip()
            display_name = str(body.get("display_name") or body.get("displayName") or "").strip() or None
            email_address = str(body.get("email_address") or body.get("emailAddress") or "").strip() or None
            payload = create_or_login_apple_session(
                user_identifier=user_identifier,
                display_name=display_name,
                email_address=email_address,
            )
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(payload)

    def _handle_mobile_owner_dev_login(self) -> None:
        if not self._is_loopback_client():
            self._send_json(
                {"error": "本机 Owner 调试登录只允许当前 Mac 本机访问。"},
                status=HTTPStatus.FORBIDDEN,
            )
            return

        payload = create_owner_session()
        payload["message"] = "已进入本机 Owner 调试会话，仅供当前 Mac 的本地联调用。"
        self._send_json(payload)

    def _handle_mobile_logout(self) -> None:
        revoke_session(self._session_token())
        self._send_json({"message": "已退出登录。"})

    def _handle_statement_upload(self) -> None:
        is_mobile_request = self.path.split("?", 1)[0] == "/api/mobile/upload-statement"
        session_user_id: str | None = None
        if is_mobile_request:
            session = self._require_mobile_session()
            if session is None:
                return
            session_user_id = self._portfolio_user_id_for_session(session)

        content_length = int(self.headers.get("Content-Length", "0") or 0)
        if content_length <= 0:
            self._send_json({"error": "未接收到上传内容。"}, status=HTTPStatus.BAD_REQUEST)
            return
        if content_length > MAX_UPLOAD_BYTES:
            self._send_json({"error": "文件过大，请控制在 40MB 以内。"}, status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
            return

        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            self._send_json({"error": "上传格式错误，请使用表单文件上传。"}, status=HTTPStatus.BAD_REQUEST)
            return

        form = cgi.FieldStorage(
            fp=self.rfile,
            headers=self.headers,
            environ={
                "REQUEST_METHOD": "POST",
                "CONTENT_TYPE": content_type,
                "CONTENT_LENGTH": str(content_length),
            },
        )
        account_id = (form.getfirst("account_id") or "").strip() or None
        broker = (form.getfirst("broker") or "").strip() or None
        statement_type = (form.getfirst("statement_type") or "").strip() or None
        file_item = form["statement_file"] if "statement_file" in form else None
        source = get_statement_source_by_account(account_id, user_id=session_user_id) if account_id else None
        if source is None and not (broker and statement_type):
            self._send_json({"error": "请选择已有账户，或提供券商与结单类型后新建导入。"}, status=HTTPStatus.BAD_REQUEST)
            return
        if file_item is None or not getattr(file_item, "filename", ""):
            self._send_json({"error": "请选择要上传的结单文件（PDF 或截图）。"}, status=HTTPStatus.BAD_REQUEST)
            return

        UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
        original_name = Path(file_item.filename).name
        safe_name = re.sub(r"[\\/]+", "_", original_name).strip() or "statement.pdf"
        uploaded_media_type = str(getattr(file_item, "type", "") or "").strip()
        if not uploaded_media_type:
            uploaded_media_type = mimetypes.guess_type(safe_name)[0] or ""
        normalized_media_type = uploaded_media_type.lower()
        supported_image_exts = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".gif"}
        is_pdf_like = normalized_media_type == "application/pdf" or safe_name.lower().endswith(".pdf")
        is_image_like = normalized_media_type.startswith("image/") or Path(safe_name).suffix.lower() in supported_image_exts
        if not (is_pdf_like or is_image_like):
            self._send_json({"error": "仅支持上传 PDF 或图片格式（JPG/PNG/WEBP/HEIC）。"}, status=HTTPStatus.BAD_REQUEST)
            return
        file_bytes = file_item.file.read()
        if not file_bytes:
            self._send_json({"error": "上传文件为空，请重新选择。"}, status=HTTPStatus.BAD_REQUEST)
            return

        staged_path: Path | None = None
        committed_path: Path | None = None
        resolved_source: dict[str, Any] | None = None
        previous_override: dict[str, Any] | None = None
        resolved_account_id: str | None = None
        resolved_broker: str | None = None
        resolved_statement_type: str | None = None
        detected_broker: str | None = None
        detected_statement_type: str | None = None
        detected_statement_date: str | None = None
        routing_action = "target"
        rejection_reason: str | None = None
        sources = get_statement_sources(user_id=session_user_id)

        suffix = Path(safe_name).suffix or ".pdf"
        with tempfile.NamedTemporaryFile(prefix="statement-staging-", suffix=suffix, delete=False) as staged_file:
            staged_file.write(file_bytes)
            staged_path = Path(staged_file.name)

        try:
            staging_source = {
                "account_id": (source or {}).get("account_id") or "staging_upload",
                "broker": (source or {}).get("broker") or broker or "Unknown",
                "type": (source or {}).get("type") or statement_type or "unknown",
                "path": str(staged_path),
                "uploaded_media_type": uploaded_media_type or None,
                "source_mode": "upload",
            }
            parsed_account, parsed_meta, _warnings = parse_statement_with_ai_best_effort(staging_source, parse_error=None)
            detected_broker = str(parsed_meta.get("detected_broker") or parsed_account.get("broker") or "").strip() or None
            detected_statement_type = (
                str(parsed_meta.get("detected_statement_type") or parsed_account.get("statement_type") or "").strip() or None
            )
            detected_statement_date = _extract_statement_date_hint(staged_path, uploaded_media_type=uploaded_media_type)
            if not detected_statement_date and str(parsed_meta.get("parser_mode") or "") == "llm":
                detected_statement_date = _parse_iso_date(str(parsed_account.get("statement_date") or ""))

            if source is not None:
                if _source_matches_broker_type(
                    source,
                    broker=detected_broker or source.get("broker"),
                    statement_type=detected_statement_type or source.get("type"),
                ):
                    resolved_source = source
                    routing_action = "target"
                else:
                    rerouted_source, route_issue = _find_unique_source_by_broker_type(
                        sources,
                        broker=detected_broker,
                        statement_type=detected_statement_type,
                    )
                    if rerouted_source is None:
                        routing_action = "rejected"
                        rejection_reason = route_issue or "无法自动定位到唯一券商子项。"
                        raise ValueError(rejection_reason)
                    resolved_source = rerouted_source
                    routing_action = "rerouted"
            else:
                requested_source, route_issue = _find_unique_source_by_broker_type(
                    sources,
                    broker=broker,
                    statement_type=statement_type,
                )
                if requested_source is not None:
                    resolved_source = requested_source
                    routing_action = "target"
                else:
                    rerouted_source, reroute_issue = _find_unique_source_by_broker_type(
                        sources,
                        broker=detected_broker,
                        statement_type=detected_statement_type,
                    )
                    if rerouted_source is None:
                        routing_action = "rejected"
                        rejection_reason = reroute_issue or route_issue or "无法定位目标券商子项。"
                        raise ValueError(rejection_reason)
                    resolved_source = rerouted_source
                    routing_action = "rerouted"

            resolved_account_id = str((resolved_source or {}).get("account_id") or "").strip()
            resolved_broker = str((resolved_source or {}).get("broker") or "").strip() or None
            resolved_statement_type = str((resolved_source or {}).get("type") or "").strip() or None
            if not resolved_account_id or not resolved_broker or not resolved_statement_type:
                routing_action = "rejected"
                rejection_reason = "目标券商子项信息不完整，请在设置页重新同步后再上传。"
                raise ValueError(rejection_reason)

            if detected_statement_date:
                current_statement_date = _cached_statement_date_for_account(resolved_account_id, user_id=session_user_id)
                if current_statement_date and detected_statement_date < current_statement_date:
                    routing_action = "rejected"
                    rejection_reason = (
                        f"识别到结单日期 {detected_statement_date} 早于当前记录 {current_statement_date}，"
                        "为避免旧单覆盖新数据，本次上传已拒绝。"
                    )
                    raise ValueError(rejection_reason)

            account_dir_name = re.sub(r"[^a-zA-Z0-9_.-]+", "_", resolved_account_id).strip("_") or "statement"
            account_dir = UPLOADS_DIR / (session_user_id or "shared") / account_dir_name
            account_dir.mkdir(parents=True, exist_ok=True)
            committed_path = account_dir / safe_name
            with committed_path.open("wb") as handle:
                handle.write(file_bytes)

            previous_override = (
                resolved_source
                if resolved_source and str(resolved_source.get("source_mode") or "") == "upload"
                else None
            )
            resolved_source = register_uploaded_statement(
                resolved_account_id,
                str(committed_path),
                safe_name,
                user_id=session_user_id,
                broker=resolved_broker,
                statement_type=resolved_statement_type,
                uploaded_media_type=uploaded_media_type or None,
                parser_mode="staging",
                parse_status="pending",
                parse_issue="",
                detected_broker=detected_broker,
                detected_statement_type=detected_statement_type,
            )
            validation_payload = build_dashboard_payload(
                force_refresh=True,
                include_live=False,
                allow_cached_fallback=False,
                strict_account_ids={resolved_source["account_id"]},
                include_ai=False,
                user_id=session_user_id,
                refresh_portfolio=True,
            )
            payload: dict[str, Any] | None = None
            if is_mobile_request:
                payload = _build_mobile_dashboard_with_fallback(
                    force_refresh=False,
                    include_live=False,
                    user_id=session_user_id,
                )
            else:
                payload = _attach_deferred_ai_context(validation_payload)
        except Exception as exc:  # noqa: BLE001
            issue_summary = summarize_source_issue(exc)
            if previous_override and resolved_account_id:
                register_uploaded_statement(
                    resolved_account_id,
                    previous_override["path"],
                    previous_override.get("uploaded_file_name") or Path(previous_override["path"]).name,
                    user_id=session_user_id,
                    broker=previous_override.get("broker"),
                    statement_type=previous_override.get("type"),
                    uploaded_media_type=previous_override.get("uploaded_media_type"),
                    parser_mode=previous_override.get("parser_mode"),
                    parse_status=previous_override.get("parse_status"),
                    parse_issue=previous_override.get("parse_issue"),
                    llm_provider=previous_override.get("llm_provider"),
                    llm_model=previous_override.get("llm_model"),
                    parsed_payload_path=previous_override.get("parsed_payload_path"),
                    detected_broker=previous_override.get("detected_broker"),
                    detected_statement_type=previous_override.get("detected_statement_type"),
                    last_parsed_at=previous_override.get("last_parsed_at"),
                )
            elif resolved_account_id:
                remove_uploaded_statement(resolved_account_id, user_id=session_user_id)
            try:
                if committed_path is not None:
                    committed_path.unlink()
            except OSError:
                pass
            response_error = rejection_reason or issue_summary
            self._send_json(
                {
                    "error": f"结单上传未生效：{response_error}",
                    "resolved_account_id": resolved_account_id,
                    "resolved_broker": resolved_broker,
                    "resolved_statement_type": resolved_statement_type,
                    "detected_broker": detected_broker,
                    "detected_statement_type": detected_statement_type,
                    "detected_statement_date": detected_statement_date,
                    "routing_action": routing_action if routing_action in {"target", "rerouted", "rejected"} else "rejected",
                    "rejection_reason": response_error,
                },
                status=HTTPStatus.BAD_REQUEST,
            )
            if staged_path is not None:
                try:
                    staged_path.unlink()
                except OSError:
                    pass
            return
        finally:
            if staged_path is not None:
                try:
                    staged_path.unlink()
                except OSError:
                    pass

        route_note = ""
        if routing_action == "rerouted" and source is not None and resolved_source is not None:
            route_note = f"已按识别结果自动路由到 {resolved_source['broker']} / {resolved_source['account_id']}。"
        self._send_json(
            {
                "message": (
                    f"{resolved_source['broker']} / {resolved_source['account_id']} 的结单已接入并刷新。{route_note}"
                    if resolved_source
                    else "结单已接入并刷新。"
                ),
                "payload": payload,
                "resolved_account_id": resolved_source.get("account_id") if resolved_source else None,
                "resolved_broker": resolved_source.get("broker") if resolved_source else None,
                "resolved_statement_type": resolved_source.get("type") if resolved_source else None,
                "detected_broker": detected_broker,
                "detected_statement_type": detected_statement_type,
                "detected_statement_date": detected_statement_date,
                "routing_action": routing_action,
                "rejection_reason": None,
            }
        )

    def _handle_mobile_ai_chat(self) -> None:
        session = self._require_mobile_session()
        if session is None:
            return

        try:
            body = self._read_json_body()
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return

        context_type = str(body.get("context_type") or "dashboard").strip().lower()
        symbol = str(body.get("symbol") or "").strip() or None
        messages = body.get("messages") or []
        if not isinstance(messages, list):
            self._send_json({"error": "messages 必须是数组。"}, status=HTTPStatus.BAD_REQUEST)
            return
        if context_type == "holding" and not symbol:
            self._send_json({"error": "持仓对话缺少股票代码。"}, status=HTTPStatus.BAD_REQUEST)
            return

        ai_request_config = _read_mobile_ai_request_config(self)
        try:
            context_payload = _build_mobile_ai_chat_context_with_fallback(
                context_type=context_type,
                symbol=symbol,
                force_refresh=False,
                user_id=self._portfolio_user_id_for_session(session),
                ai_request_config=ai_request_config,
            )
            reply_payload = generate_chat_reply(context_payload, messages, ai_request_config=ai_request_config)
        except KeyError:
            self._send_json({"error": f"未找到股票 {symbol} 的详情。"}, status=HTTPStatus.NOT_FOUND)
            return
        except Exception as exc:  # noqa: BLE001
            self._send_json({"error": f"AI 对话失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        engine = reply_payload.get("engine") or {}
        self._send_json(
            {
                "reply": reply_payload.get("reply") or "",
                "engine_label": engine.get("label"),
                "status_message": reply_payload.get("status_message") or "AI 已回复。",
            }
        )

    def log_message(self, format: str, *args: Any) -> None:
        return


def run_check() -> int:
    payload = build_dashboard_payload(force_refresh=True, include_live=False, allow_cached_fallback=True, refresh_portfolio=True)
    errors = validate_payload(payload)
    summary = payload["summary"]
    source_health = payload.get("source_health") or {}
    parsed_count = int(source_health.get("parsed_count") or 0)
    cached_count = int(source_health.get("cached_count") or 0)
    error_count = int(source_health.get("error_count") or 0)

    print("== Check Report ==")
    print(f"Generated at: {payload['generated_at']}")
    print(f"Analysis date (CN): {payload['analysis_date_cn']}")
    print(f"Statement window: {summary['statement_start_date']} -> {summary['statement_end_date']}")
    print(f"Accounts: {summary['account_count']}")
    print(f"Holdings: {summary['holding_count']}")
    print(f"Trades: {summary['trade_count']}")
    print(f"Derivatives: {summary['derivative_count']}")
    print(f"Net asset value (HKD): {summary['total_nav_hkd']:.2f}")
    print(f"Statement value (HKD): {summary['total_statement_value_hkd']:.2f}")
    print(f"Top 5 ratio: {summary['top5_ratio']:.2f}%")
    print(f"Source health: parsed {parsed_count} / cache {cached_count} / error {error_count}")
    if errors:
        print(f"Overall: FAIL ({'; '.join(errors)})")
        return 1
    if error_count > 0:
        print("Overall: PASS (with source warnings)")
    elif cached_count > 0:
        print("Overall: PASS (using cached statement fallback)")
    else:
        print("Overall: PASS")
    return 0


def _detect_primary_lan_ip() -> str | None:
    candidate_interfaces: list[str] = []
    try:
        route_output = subprocess.check_output(
            ["route", "-n", "get", "default"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        for line in route_output.splitlines():
            if "interface:" not in line:
                continue
            iface = line.split("interface:", 1)[1].strip()
            if iface and not iface.startswith("utun"):
                candidate_interfaces.append(iface)
                break
    except (OSError, subprocess.CalledProcessError):
        pass

    candidate_interfaces.extend(["en0", "en1", "en2"])
    seen: set[str] = set()
    for iface in candidate_interfaces:
        if not iface or iface in seen:
            continue
        seen.add(iface)
        try:
            ip_address = subprocess.check_output(
                ["ipconfig", "getifaddr", iface],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        except (OSError, subprocess.CalledProcessError):
            continue
        if ip_address and not ip_address.startswith(("127.", "169.254.")):
            return ip_address

    return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Personal portfolio workbench")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8008, help="Bind port (default: 8008)")
    parser.add_argument("--public", action="store_true", help="Bind 0.0.0.0 for phone access on the same LAN")
    parser.add_argument("--check", action="store_true", help="Run local validation and exit")
    args = parser.parse_args()

    if args.check:
        raise SystemExit(run_check())

    host = "0.0.0.0" if args.public and args.host == "127.0.0.1" else args.host
    server = ThreadingHTTPServer((host, args.port), DashboardHandler)
    print(f"Dashboard is running at http://{host}:{args.port}")
    if host == "0.0.0.0":
        lan_ip = _detect_primary_lan_ip()
        print(f"Local preview: http://127.0.0.1:{args.port}")
        if lan_ip:
            print(f"Phone overview: http://{lan_ip}:{args.port}/")
            print(f"Phone share view: http://{lan_ip}:{args.port}/share")
        else:
            print(f"Phone preview: http://<this-mac-lan-ip>:{args.port}/")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
