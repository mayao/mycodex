from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

try:
    from statement_sources import OWNER_USER_ID, get_statement_import_templates
except ModuleNotFoundError:
    from market_dashboard.statement_sources import OWNER_USER_ID, get_statement_import_templates


BASE_DIR = Path(__file__).resolve().parent
AUTH_STORE_PATH = BASE_DIR / "user_store.json"
PHONE_CODE_TTL_SECONDS = 5 * 60
SESSION_TTL_DAYS = 30
MOCK_PHONE_NUMBER = "13800138000"
MOCK_VERIFICATION_CODE = "123456"


BROKER_CAPABILITIES = [
    {
        "id": "futu",
        "name": "Futu",
        "cross_app_authorization": "not_direct",
        "official_api_available": True,
        "supports_positions": True,
        "supports_trades": True,
        "connectable_in_app": False,
        "status": "gateway_required",
        "auth_path": "OpenD gateway + Futu account session",
        "summary": "官方 OpenAPI 可读账户与持仓，但接入前必须先部署并登录 OpenD，不是手机间的一键 OAuth 授权。",
        "next_step": "短期继续保留 PDF 结单导入；如果要自动同步，需要额外部署在线 OpenD 服务并维护登录态。",
        "docs_url": "https://openapi.futunn.com/futu-api-doc/intro/intro.html",
        "requirements": [
            "部署 OpenD",
            "富途账户完成 OpenAPI 权限开通",
            "后端长期维护会话与网络可达性",
        ],
    },
    {
        "id": "tiger",
        "name": "Tiger",
        "cross_app_authorization": "not_direct",
        "official_api_available": True,
        "supports_positions": True,
        "supports_trades": True,
        "connectable_in_app": False,
        "status": "developer_credentials",
        "auth_path": "Tiger OpenAPI credentials + private key signature",
        "summary": "Tiger OpenAPI 走开发者凭证和私钥签名链路，需要 tigerId、account、privateKey 等信息，不是移动端跨 App 授权。",
        "next_step": "要做自动同步，需要先完成开发者注册和密钥托管，再补服务端抓取器。",
        "docs_url": "https://quant.itigerup.com/openapi/en/java/quickStart/prepare.html",
        "requirements": [
            "Tiger 账户开通 OpenAPI",
            "开发者注册",
            "私钥、token 与 account 配置",
        ],
    },
    {
        "id": "ibkr",
        "name": "IBKR",
        "cross_app_authorization": "approval_required",
        "official_api_available": True,
        "supports_positions": True,
        "supports_trades": True,
        "connectable_in_app": False,
        "status": "approval_or_gateway",
        "auth_path": "Client Portal Web API / Gateway / approved OAuth",
        "summary": "IBKR 官方 Web API 文档覆盖 OAuth 1.0a / 2.0、portfolio 和 order 相关接口，但第三方正式接入通常仍需要审批和会话管理。",
        "next_step": "面向更多用户正式接入前，建议先准备主体、回调域名和产品说明，再申请 Web API / OAuth 审批。",
        "docs_url": "https://www.interactivebrokers.com/campus/ibkr-api-page/webapi-doc/",
        "requirements": [
            "IBKR 账户与 Web API 能力",
            "若做第三方授权，需走审批流程",
            "服务端维护会话、回调与安全存储",
        ],
    },
    {
        "id": "longbridge",
        "name": "Longbridge",
        "cross_app_authorization": "oauth_supported",
        "official_api_available": True,
        "supports_positions": True,
        "supports_trades": True,
        "connectable_in_app": False,
        "status": "oauth_or_token",
        "auth_path": "OAuth or App Key / App Secret + Access Token",
        "summary": "Longbridge OpenAPI 文档既给了 OAuth 示例，也保留了 App Key / App Secret / Access Token 路线；能力比其他几家更接近正式授权接入。",
        "next_step": "如果后续要做正式自动同步，需要先申请 client_id 或应用凭证，再补 iOS 回调和后端 token 管理。",
        "docs_url": "https://open.longbridge.com/docs/getting-started",
        "requirements": [
            "Longbridge 开户并开通 OpenAPI",
            "获取 OAuth client_id 或 App Key / App Secret",
            "安全存储并轮换 access token / refresh token",
        ],
    },
]


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _load_store() -> dict[str, Any]:
    try:
        payload = json.loads(AUTH_STORE_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        payload = {}

    if not isinstance(payload, dict):
        payload = {}

    payload.setdefault("users", [])
    payload.setdefault("sessions", [])
    payload.setdefault("pending_codes", [])
    _ensure_owner_user(payload)
    return payload


def _write_store(payload: dict[str, Any]) -> None:
    AUTH_STORE_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _ensure_owner_user(payload: dict[str, Any]) -> None:
    users = payload.setdefault("users", [])
    if any(isinstance(item, dict) and item.get("user_id") == OWNER_USER_ID for item in users):
        return
    users.append(
        {
            "user_id": OWNER_USER_ID,
            "display_name": "本机数据拥有者",
            "phone_number": None,
            "auth_provider": "owner",
            "is_owner": True,
            "created_at": _now_iso(),
            "last_login_at": None,
        }
    )


def _mask_phone(phone_number: str | None) -> str | None:
    if not phone_number:
        return None
    if len(phone_number) < 7:
        return phone_number
    return f"{phone_number[:3]}****{phone_number[-4:]}"


def _sanitize_phone(phone_number: str) -> str:
    cleaned = re.sub(r"\D+", "", phone_number or "")
    if len(cleaned) < 6:
        raise ValueError("请输入有效手机号。")
    return cleaned


def _sanitize_device_id(device_id: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9._-]+", "", device_id or "").strip()
    if len(cleaned) < 12:
        raise ValueError("设备标识无效，请重新初始化设备账号。")
    return cleaned


def _sanitize_device_name(device_name: str | None) -> str:
    cleaned = re.sub(r"\s+", " ", str(device_name or "").strip())
    cleaned = cleaned[:48]
    return cleaned or "MyInvAI iPhone"


def _make_device_password() -> str:
    return f"MIA-{uuid4().hex[:10].upper()}"


def _upsert_user(
    payload: dict[str, Any],
    *,
    phone_number: str | None,
    display_name: str,
    auth_provider: str,
    is_owner: bool = False,
) -> dict[str, Any]:
    users = payload.setdefault("users", [])
    normalized_phone = _sanitize_phone(phone_number) if phone_number else None
    for user in users:
        if not isinstance(user, dict):
            continue
        if normalized_phone and user.get("phone_number") == normalized_phone:
            user["display_name"] = display_name or user.get("display_name") or "Invest 用户"
            user["auth_provider"] = auth_provider
            user["last_login_at"] = _now_iso()
            return user

    user = {
        "user_id": f"usr_{uuid4().hex[:12]}",
        "display_name": display_name or "Invest 用户",
        "phone_number": normalized_phone,
        "auth_provider": auth_provider,
        "is_owner": is_owner,
        "created_at": _now_iso(),
        "last_login_at": _now_iso(),
    }
    users.append(user)
    return user


def _find_user_by_device_id(payload: dict[str, Any], device_id: str) -> dict[str, Any] | None:
    normalized = _sanitize_device_id(device_id)
    for user in payload.get("users", []):
        if not isinstance(user, dict):
            continue
        linked_ids = user.get("linked_device_ids") or []
        if isinstance(linked_ids, list) and normalized in linked_ids:
            return user
    return None


def _clean_expired(payload: dict[str, Any]) -> None:
    now = datetime.now(timezone.utc)
    valid_sessions = []
    for session in payload.get("sessions", []):
        try:
            created_at = datetime.fromisoformat(str(session.get("created_at")).replace("Z", "+00:00"))
        except ValueError:
            continue
        if now - created_at <= timedelta(days=SESSION_TTL_DAYS):
            valid_sessions.append(session)
    payload["sessions"] = valid_sessions

    valid_codes = []
    for row in payload.get("pending_codes", []):
        try:
            expires_at = datetime.fromisoformat(str(row.get("expires_at")).replace("Z", "+00:00"))
        except ValueError:
            continue
        if expires_at > now:
            valid_codes.append(row)
    payload["pending_codes"] = valid_codes


def serialize_user(user: dict[str, Any] | None) -> dict[str, Any] | None:
    if not user:
        return None
    return {
        "user_id": user.get("user_id"),
        "display_name": user.get("display_name") or "Invest 用户",
        "phone_number_masked": _mask_phone(user.get("phone_number")),
        "auth_provider": user.get("auth_provider") or "phone",
        "is_owner": bool(user.get("is_owner")),
    }


def resolve_portfolio_user_id(user: dict[str, Any] | None) -> str:
    if not user:
        return OWNER_USER_ID
    portfolio_user_id = str(user.get("portfolio_user_id") or "").strip()
    if portfolio_user_id:
        return portfolio_user_id
    if user.get("auth_provider") == "device":
        return OWNER_USER_ID
    return str(user.get("user_id") or OWNER_USER_ID).strip() or OWNER_USER_ID


def _serialize_device_credentials(
    user: dict[str, Any],
    *,
    device_name: str,
    default_password: str | None,
    is_new_device: bool,
) -> dict[str, Any]:
    return {
        "assigned_user_id": user.get("user_id"),
        "device_name": device_name,
        "default_password": default_password,
        "is_new_device": is_new_device,
    }


def create_or_login_device_session(device_id: str, device_name: str | None = None) -> dict[str, Any]:
    payload = _load_store()
    _clean_expired(payload)
    normalized_device_id = _sanitize_device_id(device_id)
    resolved_device_name = _sanitize_device_name(device_name)

    existing_user = _find_user_by_device_id(payload, normalized_device_id)
    if existing_user is not None:
        existing_user["last_login_at"] = _now_iso()
        existing_user["device_name"] = resolved_device_name
        existing_user.setdefault("portfolio_user_id", OWNER_USER_ID)
        session = _issue_session(payload, existing_user["user_id"])
        _write_store(payload)
        return {
            "session_token": session["token"],
            "user": serialize_user(existing_user),
            "message": "已识别当前设备，正在同步你的个人投资数据。",
            "device_credentials": _serialize_device_credentials(
                existing_user,
                device_name=resolved_device_name,
                default_password=None,
                is_new_device=False,
            ),
        }

    user = {
        "user_id": f"usr_dev_{uuid4().hex[:10]}",
        "display_name": f"{resolved_device_name} 的账户",
        "phone_number": None,
        "auth_provider": "device",
        "is_owner": False,
        "created_at": _now_iso(),
        "last_login_at": _now_iso(),
        "linked_device_ids": [normalized_device_id],
        "device_name": resolved_device_name,
        "device_password": _make_device_password(),
        "portfolio_user_id": OWNER_USER_ID,
    }
    payload.setdefault("users", []).append(user)
    session = _issue_session(payload, user["user_id"])
    _write_store(payload)
    return {
        "session_token": session["token"],
        "user": serialize_user(user),
        "message": "已为当前设备启用安全登录，组合数据已连接到你的个人账户。",
        "device_credentials": _serialize_device_credentials(
            user,
            device_name=resolved_device_name,
            default_password=user["device_password"],
            is_new_device=True,
        ),
    }


def request_phone_code(phone_number: str) -> dict[str, Any]:
    payload = _load_store()
    _clean_expired(payload)

    normalized = _sanitize_phone(phone_number)
    payload["pending_codes"] = [
        row
        for row in payload.get("pending_codes", [])
        if row.get("phone_number") != normalized
    ]
    code = MOCK_VERIFICATION_CODE if normalized == MOCK_PHONE_NUMBER else f"{uuid4().int % 1000000:06d}"
    payload["pending_codes"].append(
        {
            "phone_number": normalized,
            "code": code,
            "expires_at": (datetime.now(timezone.utc) + timedelta(seconds=PHONE_CODE_TTL_SECONDS)).isoformat(),
            "created_at": _now_iso(),
        }
    )
    _write_store(payload)
    return {
        "message": (
            f"验证码已生成，开发模式下请直接输入 {code}"
            + ("；当前 mock 手机号可直接用这个固定验证码登录。" if normalized == MOCK_PHONE_NUMBER else "")
        ),
        "expires_in_seconds": PHONE_CODE_TTL_SECONDS,
        "debug_code": code,
    }


def create_session_for_phone(phone_number: str, code: str) -> dict[str, Any]:
    payload = _load_store()
    _clean_expired(payload)
    normalized = _sanitize_phone(phone_number)
    entered_code = str(code).strip()
    if normalized == MOCK_PHONE_NUMBER and entered_code == MOCK_VERIFICATION_CODE:
        user = _upsert_user(
            payload,
            phone_number=normalized,
            display_name="Mock 用户 8000",
            auth_provider="phone",
        )
        session = _issue_session(payload, user["user_id"])
        _write_store(payload)
        return {
            "session_token": session["token"],
            "user": serialize_user(user),
            "message": "已使用 mock 手机号和固定验证码直接登录。",
        }

    matched = next(
        (
            row
            for row in payload.get("pending_codes", [])
            if row.get("phone_number") == normalized and row.get("code") == entered_code
        ),
        None,
    )
    if matched is None:
        raise ValueError("验证码无效或已过期。")

    user = _upsert_user(
        payload,
        phone_number=normalized,
        display_name=f"用户 {normalized[-4:]}",
        auth_provider="phone",
    )
    payload["pending_codes"] = [
        row
        for row in payload.get("pending_codes", [])
        if not (row.get("phone_number") == normalized and row.get("code") == entered_code)
    ]
    session = _issue_session(payload, user["user_id"])
    _write_store(payload)
    return {
        "session_token": session["token"],
        "user": serialize_user(user),
        "message": "手机号登录成功。",
    }


def create_wechat_dev_session(display_name: str | None = None) -> dict[str, Any]:
    payload = _load_store()
    _clean_expired(payload)
    nickname = (display_name or "").strip() or f"微信用户{uuid4().hex[:4].upper()}"
    user = _upsert_user(
        payload,
        phone_number=None,
        display_name=nickname,
        auth_provider="wechat",
    )
    session = _issue_session(payload, user["user_id"])
    _write_store(payload)
    return {
        "session_token": session["token"],
        "user": serialize_user(user),
        "message": "当前服务未配置真实微信开放平台参数，已使用开发模式模拟微信授权。",
    }


def create_owner_session() -> dict[str, Any]:
    payload = _load_store()
    _clean_expired(payload)
    owner = next(
        user
        for user in payload["users"]
        if isinstance(user, dict) and user.get("user_id") == OWNER_USER_ID
    )
    owner["last_login_at"] = _now_iso()
    session = _issue_session(payload, OWNER_USER_ID)
    _write_store(payload)
    return {"session_token": session["token"], "user": serialize_user(owner)}


def _issue_session(payload: dict[str, Any], user_id: str) -> dict[str, Any]:
    sessions = payload.setdefault("sessions", [])
    token = uuid4().hex
    session = {
        "token": token,
        "user_id": user_id,
        "created_at": _now_iso(),
        "last_seen_at": _now_iso(),
    }
    sessions.append(session)
    return session


def get_session(token: str | None) -> dict[str, Any] | None:
    if not token:
        return None
    payload = _load_store()
    _clean_expired(payload)
    session = next(
        (
            item
            for item in payload.get("sessions", [])
            if isinstance(item, dict) and item.get("token") == token
        ),
        None,
    )
    if session is None:
        _write_store(payload)
        return None
    session["last_seen_at"] = _now_iso()
    user = next(
        (
            item
            for item in payload.get("users", [])
            if isinstance(item, dict) and item.get("user_id") == session.get("user_id")
        ),
        None,
    )
    _write_store(payload)
    if user is None:
        return None
    return {"token": session["token"], "user": user}


def revoke_session(token: str | None) -> None:
    if not token:
        return
    payload = _load_store()
    payload["sessions"] = [
        item
        for item in payload.get("sessions", [])
        if not (isinstance(item, dict) and item.get("token") == token)
    ]
    _write_store(payload)


def get_import_center_payload(user_id: str) -> dict[str, Any]:
    payload = _load_store()
    user = next(
        (
            item
            for item in payload.get("users", [])
            if isinstance(item, dict) and item.get("user_id") == user_id
        ),
        None,
    )
    return {
        "user": serialize_user(user),
        "brokers": [],
        "statement_templates": get_statement_import_templates(),
        "notes": [
            "当前版本只保留稳定可用的结单导入能力，不再展示未落地的券商在线接入配置说明。",
            "上传新的 PDF 结单后，服务会自动重建组合快照与账户视图。",
            "如果 iPhone 支持 Face ID 或 Touch ID，可以把它作为本机解锁入口。",
        ],
    }
