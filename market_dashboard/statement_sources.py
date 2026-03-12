from __future__ import annotations

import json
import re
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4


BASE_DIR = Path(__file__).resolve().parent
UPLOADS_DIR = BASE_DIR / "uploads"
UPLOAD_MANIFEST_PATH = BASE_DIR / "uploaded_statement_sources.json"
OWNER_USER_ID = "usr_owner_local"


DEFAULT_STATEMENT_SOURCES = [
    {
        "account_id": "tiger_4648340",
        "broker": "Tiger",
        "type": "tiger_activity",
        "path": "/Users/xmly/Library/Mobile Documents/com~apple~CloudDocs/科技平权-投资/Tiger0306结单& 地址证明.pdf",
    },
    {
        "account_id": "ib_u13578683",
        "broker": "Interactive Brokers",
        "type": "ib_daily",
        "path": "/Users/xmly/Library/Mobile Documents/com~apple~CloudDocs/科技平权-投资/IB结单U13578683_20260306.pdf",
    },
    {
        "account_id": "futu_7259",
        "broker": "Futu",
        "type": "futu_monthly_us",
        "path": "/Users/xmly/Library/Mobile Documents/com~apple~CloudDocs/科技平权-投资/1007215567057259-6-20260227-1772885902561.pdf",
    },
    {
        "account_id": "futu_9896",
        "broker": "Futu",
        "type": "futu_monthly_hk",
        "path": "/Users/xmly/Library/Mobile Documents/com~apple~CloudDocs/科技平权-投资/1001283380599896-6-20260227-1772885943347.pdf",
    },
    {
        "account_id": "longbridge_h10096545",
        "broker": "Longbridge",
        "type": "longbridge_daily",
        "path": "/Users/xmly/Library/Mobile Documents/com~apple~CloudDocs/科技平权-投资/长桥结单20260306/长桥结单20260306_1-2.pdf",
    },
]

STATEMENT_IMPORT_TEMPLATES = [
    {
        "id": "tiger_activity",
        "broker_id": "tiger",
        "broker": "Tiger",
        "statement_type": "tiger_activity",
        "label": "Tiger Activity Statement",
        "description": "适合 Tiger 活动结单 PDF 导入。",
    },
    {
        "id": "ib_daily",
        "broker_id": "ibkr",
        "broker": "Interactive Brokers",
        "statement_type": "ib_daily",
        "label": "IBKR Daily Statement",
        "description": "适合 Interactive Brokers 日结单 PDF 导入。",
    },
    {
        "id": "futu_monthly_us",
        "broker_id": "futu",
        "broker": "Futu",
        "statement_type": "futu_monthly_us",
        "label": "Futu US Monthly Statement",
        "description": "适合富途美股月结单 PDF 导入。",
    },
    {
        "id": "futu_monthly_hk",
        "broker_id": "futu",
        "broker": "Futu",
        "statement_type": "futu_monthly_hk",
        "label": "Futu HK Monthly Statement",
        "description": "适合富途港股月结单 PDF 导入。",
    },
    {
        "id": "longbridge_daily",
        "broker_id": "longbridge",
        "broker": "Longbridge",
        "statement_type": "longbridge_daily",
        "label": "Longbridge Daily Statement",
        "description": "适合长桥日结单 PDF 导入。",
    },
]

REFERENCE_ANALYSIS_SOURCES = [
    {
        "label": "年度复盘报告",
        "type": "pdf",
        "path": "/Users/xmly/Downloads/01_工作/01_工作_战略规划/2025年度港美股投资复盘报告.pdf",
    },
    {
        "label": "Gemini 复盘建议",
        "type": "docx",
        "path": "/Users/xmly/Downloads/01_工作/04_工作_团队管理/Gemini 投资复盘与2026建议-长桥&tiger.docx",
    },
]


# Backward-compatible export for callers that still expect the original constant.
STATEMENT_SOURCES = DEFAULT_STATEMENT_SOURCES


def _normalize_user_id(user_id: str | None) -> str:
    return (user_id or OWNER_USER_ID).strip() or OWNER_USER_ID


def _default_source_map() -> dict[str, dict[str, Any]]:
    return {item["account_id"]: deepcopy(item) for item in DEFAULT_STATEMENT_SOURCES}


def _statement_template_by_type() -> dict[str, dict[str, Any]]:
    return {item["statement_type"]: deepcopy(item) for item in STATEMENT_IMPORT_TEMPLATES}


def get_statement_import_templates() -> list[dict[str, Any]]:
    return deepcopy(STATEMENT_IMPORT_TEMPLATES)


def get_reference_analysis_sources(user_id: str | None = None) -> list[dict[str, Any]]:
    if _normalize_user_id(user_id) != OWNER_USER_ID:
        return []
    return deepcopy(REFERENCE_ANALYSIS_SOURCES)


def _load_manifest_entries() -> list[dict[str, Any]]:
    try:
        payload = json.loads(UPLOAD_MANIFEST_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return []

    if isinstance(payload, dict):
        entries = payload.get("sources", [])
    elif isinstance(payload, list):
        entries = payload
    else:
        entries = []

    normalized_entries: list[dict[str, Any]] = []
    default_map = _default_source_map()
    template_by_type = _statement_template_by_type()
    for raw in entries:
        if not isinstance(raw, dict):
            continue
        account_id = str(raw.get("account_id") or "").strip()
        raw_path = str(raw.get("path") or "").strip()
        if not account_id or not raw_path:
            continue

        base = default_map.get(account_id, {})
        statement_type = str(raw.get("type") or base.get("type") or "").strip()
        template = template_by_type.get(statement_type, {})
        broker = str(raw.get("broker") or base.get("broker") or template.get("broker") or "").strip()
        if not statement_type or not broker:
            continue

        normalized_entries.append(
            {
                "user_id": _normalize_user_id(str(raw.get("user_id") or "").strip() or None),
                "account_id": account_id,
                "broker": broker,
                "type": statement_type,
                "path": str(Path(raw_path).expanduser()),
                "uploaded_at": raw.get("uploaded_at"),
                "uploaded_file_name": raw.get("uploaded_file_name") or Path(raw_path).name,
            }
        )
    return normalized_entries


def _write_manifest_entries(entries: list[dict[str, Any]]) -> None:
    payload = {"sources": entries}
    UPLOAD_MANIFEST_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def get_uploaded_statement_overrides(user_id: str | None = None) -> dict[str, dict[str, Any]]:
    normalized_user_id = _normalize_user_id(user_id)
    source_map = _default_source_map()
    overrides: dict[str, dict[str, Any]] = {}
    for entry in _load_manifest_entries():
        account_id = entry.get("account_id")
        if entry.get("user_id") != normalized_user_id or account_id not in source_map:
            continue
        base = source_map[account_id]
        overrides[account_id] = {
            **base,
            "path": entry["path"],
            "source_mode": "upload",
            "uploaded_at": entry.get("uploaded_at"),
            "uploaded_file_name": entry.get("uploaded_file_name") or Path(entry["path"]).name,
        }
    return overrides


def get_statement_sources(user_id: str | None = None) -> list[dict[str, Any]]:
    normalized_user_id = _normalize_user_id(user_id)
    entries = [entry for entry in _load_manifest_entries() if entry.get("user_id") == normalized_user_id]
    source_map: dict[str, dict[str, Any]] = {}

    if normalized_user_id == OWNER_USER_ID:
        for item in DEFAULT_STATEMENT_SOURCES:
            source_map[item["account_id"]] = {
                **deepcopy(item),
                "source_mode": "default",
                "uploaded_at": None,
                "uploaded_file_name": None,
            }

    for entry in entries:
        account_id = entry["account_id"]
        base = source_map.get(account_id, {})
        source_map[account_id] = {
            **base,
            "account_id": account_id,
            "broker": entry["broker"],
            "type": entry["type"],
            "path": entry["path"],
            "source_mode": "upload",
            "uploaded_at": entry.get("uploaded_at"),
            "uploaded_file_name": entry.get("uploaded_file_name") or Path(entry["path"]).name,
        }

    if normalized_user_id == OWNER_USER_ID:
        ordered_ids = [item["account_id"] for item in DEFAULT_STATEMENT_SOURCES]
        dynamic_ids = sorted(account_id for account_id in source_map if account_id not in ordered_ids)
        ordered_ids.extend(dynamic_ids)
        return [source_map[account_id] for account_id in ordered_ids if account_id in source_map]

    return [
        source_map[account_id]
        for account_id in sorted(source_map)
    ]


def get_statement_source_by_account(account_id: str, user_id: str | None = None) -> dict[str, Any] | None:
    for item in get_statement_sources(user_id=user_id):
        if item["account_id"] == account_id:
            return item
    return None


def _generate_account_id(broker: str) -> str:
    normalized_broker = re.sub(r"[^a-z0-9]+", "_", broker.lower()).strip("_") or "broker"
    return f"{normalized_broker}_{uuid4().hex[:8]}"


def register_uploaded_statement(
    account_id: str | None,
    stored_path: str,
    uploaded_file_name: str,
    *,
    user_id: str | None = None,
    broker: str | None = None,
    statement_type: str | None = None,
) -> dict[str, Any]:
    normalized_user_id = _normalize_user_id(user_id)
    template_by_type = _statement_template_by_type()
    existing_source = (
        get_statement_source_by_account(account_id, user_id=normalized_user_id)
        if account_id
        else None
    )

    resolved_account_id = (account_id or existing_source.get("account_id") if existing_source else account_id) or ""
    resolved_broker = (broker or existing_source.get("broker") if existing_source else broker) or ""
    resolved_type = (statement_type or existing_source.get("type") if existing_source else statement_type) or ""

    template = template_by_type.get(resolved_type, {})
    resolved_broker = resolved_broker or template.get("broker") or ""

    if existing_source is None and not resolved_type:
        raise KeyError("statement_type")
    if existing_source is None and not resolved_broker:
        raise KeyError("broker")
    if not resolved_account_id:
        resolved_account_id = _generate_account_id(resolved_broker)

    entries = [
        entry
        for entry in _load_manifest_entries()
        if not (
            entry.get("user_id") == normalized_user_id
            and entry.get("account_id") == resolved_account_id
        )
    ]
    entries.append(
        {
            "user_id": normalized_user_id,
            "account_id": resolved_account_id,
            "broker": resolved_broker,
            "type": resolved_type,
            "path": stored_path,
            "uploaded_at": datetime.now(timezone.utc).isoformat(),
            "uploaded_file_name": uploaded_file_name,
        }
    )
    _write_manifest_entries(entries)
    source = get_statement_source_by_account(resolved_account_id, user_id=normalized_user_id)
    if source is None:
        raise KeyError(resolved_account_id)
    return source


def remove_uploaded_statement(account_id: str, user_id: str | None = None) -> None:
    normalized_user_id = _normalize_user_id(user_id)
    entries = [
        entry
        for entry in _load_manifest_entries()
        if not (
            entry.get("user_id") == normalized_user_id
            and entry.get("account_id") == account_id
        )
    ]
    _write_manifest_entries(entries)
