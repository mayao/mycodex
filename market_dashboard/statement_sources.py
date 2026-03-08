from __future__ import annotations

import json
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


BASE_DIR = Path(__file__).resolve().parent
UPLOADS_DIR = BASE_DIR / "uploads"
UPLOAD_MANIFEST_PATH = BASE_DIR / "uploaded_statement_sources.json"


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


def _default_source_map() -> dict[str, dict[str, Any]]:
    return {item["account_id"]: deepcopy(item) for item in DEFAULT_STATEMENT_SOURCES}


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
    return [entry for entry in entries if isinstance(entry, dict)]


def _write_manifest_entries(entries: list[dict[str, Any]]) -> None:
    payload = {"sources": entries}
    UPLOAD_MANIFEST_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def get_uploaded_statement_overrides() -> dict[str, dict[str, Any]]:
    source_map = _default_source_map()
    overrides: dict[str, dict[str, Any]] = {}
    for entry in _load_manifest_entries():
        account_id = entry.get("account_id")
        raw_path = entry.get("path")
        if not account_id or account_id not in source_map or not raw_path:
            continue
        base = source_map[account_id]
        overrides[account_id] = {
            **base,
            "path": str(Path(raw_path).expanduser()),
            "source_mode": "upload",
            "uploaded_at": entry.get("uploaded_at"),
            "uploaded_file_name": entry.get("uploaded_file_name") or Path(raw_path).name,
        }
    return overrides


def get_statement_sources() -> list[dict[str, Any]]:
    overrides = get_uploaded_statement_overrides()
    sources: list[dict[str, Any]] = []
    for item in DEFAULT_STATEMENT_SOURCES:
        merged = {
            **deepcopy(item),
            "source_mode": "default",
            "uploaded_at": None,
            "uploaded_file_name": None,
        }
        override = overrides.get(item["account_id"])
        if override:
            merged.update(override)
        sources.append(merged)
    return sources


def get_statement_source_by_account(account_id: str) -> dict[str, Any] | None:
    for item in get_statement_sources():
        if item["account_id"] == account_id:
            return item
    return None


def register_uploaded_statement(account_id: str, stored_path: str, uploaded_file_name: str) -> dict[str, Any]:
    if account_id not in _default_source_map():
        raise KeyError(account_id)

    entries = [entry for entry in _load_manifest_entries() if entry.get("account_id") != account_id]
    entries.append(
        {
            "account_id": account_id,
            "path": stored_path,
            "uploaded_at": datetime.now(timezone.utc).isoformat(),
            "uploaded_file_name": uploaded_file_name,
        }
    )
    _write_manifest_entries(entries)
    source = get_statement_source_by_account(account_id)
    if source is None:
        raise KeyError(account_id)
    return source


def remove_uploaded_statement(account_id: str) -> None:
    entries = [entry for entry in _load_manifest_entries() if entry.get("account_id") != account_id]
    _write_manifest_entries(entries)

