from __future__ import annotations

import copy
import json
import os
from pathlib import Path
from typing import Any


BASE_DIR = Path(__file__).resolve().parent
SERVICE_AI_CONFIG_ENV_VAR = "MARKET_DASHBOARD_AI_CONFIG_PATH"
KIMI_PRESET_PROFILES = {
    "moonshot": {
        "model": "moonshot-v1-8k",
        "base_url": "https://api.moonshot.cn/v1",
    },
    "kimi_coding": {
        "model": "kimi-for-coding",
        "base_url": "https://api.kimi.com/coding/v1",
    },
}
DEFAULT_SERVICE_AI_CONFIG = {
    "primary_provider": "anthropic",
    "enable_fallbacks": True,
    "providers": [
        {
            "provider": "anthropic",
            "model": "claude-sonnet-4-5-20250929",
            "api_key": "",
        },
        {
            "provider": "kimi",
            "preset": "moonshot",
            "model": "moonshot-v1-8k",
            "api_key": "",
            "base_url": "https://api.moonshot.cn/v1",
        },
        {
            "provider": "gemini",
            "model": "gemini-2.5-flash",
            "api_key": "",
            "base_url": "https://generativelanguage.googleapis.com/v1beta",
        },
    ],
}


def default_service_ai_request_config() -> dict[str, Any]:
    return copy.deepcopy(DEFAULT_SERVICE_AI_CONFIG)


def service_ai_config_candidates() -> list[Path]:
    explicit_path = str(os.getenv(SERVICE_AI_CONFIG_ENV_VAR, "") or "").strip()
    if explicit_path:
        return [Path(explicit_path).expanduser()]
    return [
        BASE_DIR / "config" / "service_ai_config.local.json",
        BASE_DIR / "config" / "service_ai_config.json",
    ]


def default_service_ai_config_path() -> Path:
    return service_ai_config_candidates()[0]


def infer_kimi_preset(
    preset: Any = None,
    *,
    base_url: Any = None,
    model: Any = None,
    api_key: Any = None,
) -> str:
    normalized = str(preset or "").strip().lower()
    aliases = {
        "moonshot": "moonshot",
        "moonshot_openai": "moonshot",
        "openai": "moonshot",
        "kimi-coding": "kimi_coding",
        "kimi_coding": "kimi_coding",
        "coding": "kimi_coding",
        "code": "kimi_coding",
    }
    lowered_base_url = str(base_url or "").strip().lower()
    lowered_model = str(model or "").strip().lower()
    lowered_api_key = str(api_key or "").strip().lower()
    coding_key_hint = lowered_api_key.startswith("sk-kimi-")
    coding_preset_hint = (
        "api.kimi.com/coding" in lowered_base_url
        or lowered_model == "kimi-for-coding"
        or lowered_model.startswith("kimi-")
        or coding_key_hint
    )

    if normalized in aliases:
        mapped = aliases[normalized]
        # Some users paste a Kimi Coding key while keeping legacy Moonshot preset/model.
        # Prefer the coding channel in this mixed case to avoid systematic 401/403 failures.
        if mapped == "moonshot" and coding_preset_hint:
            return "kimi_coding"
        return mapped

    if coding_preset_hint:
        return "kimi_coding"
    return "moonshot"


def kimi_preset_defaults(preset: str | None = None) -> dict[str, str]:
    resolved_preset = infer_kimi_preset(preset)
    return copy.deepcopy(KIMI_PRESET_PROFILES[resolved_preset])


def _normalize_provider_rows(raw_providers: Any) -> list[dict[str, Any]]:
    if isinstance(raw_providers, dict):
        normalized_rows: list[dict[str, Any]] = []
        for provider, value in raw_providers.items():
            row = {"provider": provider}
            if isinstance(value, dict):
                row.update(value)
            normalized_rows.append(row)
        return normalized_rows
    if isinstance(raw_providers, list):
        return [row for row in raw_providers if isinstance(row, dict)]
    return []


def normalize_service_ai_request_config(raw_payload: Any) -> dict[str, Any] | None:
    if not isinstance(raw_payload, dict):
        return None

    candidate = raw_payload.get("ai_request_config") if isinstance(raw_payload.get("ai_request_config"), dict) else raw_payload
    if not isinstance(candidate, dict):
        return None

    normalized = {
        "primary_provider": str(candidate.get("primary_provider") or "").strip().lower() or None,
        "enable_fallbacks": bool(candidate.get("enable_fallbacks", True)),
        "providers": [],
    }

    for row in _normalize_provider_rows(candidate.get("providers")):
        provider = str(row.get("provider") or "").strip().lower()
        if not provider:
            continue
        normalized_row = {
            "provider": provider,
            "model": str(row.get("model") or "").strip(),
            "api_key": str(row.get("api_key") or "").strip(),
            "base_url": str(row.get("base_url") or "").strip(),
        }
        if provider == "kimi":
            preset = infer_kimi_preset(
                row.get("preset"),
                base_url=normalized_row["base_url"],
                model=normalized_row["model"],
                api_key=normalized_row["api_key"],
            )
            preset_defaults = kimi_preset_defaults(preset)
            normalized_row["preset"] = preset
            if (
                not normalized_row["model"]
                or (preset == "kimi_coding" and normalized_row["model"].lower().startswith("moonshot-"))
            ):
                normalized_row["model"] = preset_defaults["model"]
            # If the config mixes preset/model/base_url, prefer the inferred preset defaults so the
            # runtime doesn't silently hit a mismatched gateway and 401.
            if (
                not normalized_row["base_url"]
                or (preset == "moonshot" and "api.moonshot.cn" not in normalized_row["base_url"].lower())
                or (preset == "kimi_coding" and "api.kimi.com/coding" not in normalized_row["base_url"].lower())
            ):
                normalized_row["base_url"] = preset_defaults["base_url"]
        normalized["providers"].append(normalized_row)
    return normalized


def load_service_ai_request_config(path: str | Path | None = None) -> dict[str, Any] | None:
    candidates = [Path(path).expanduser()] if path else service_ai_config_candidates()
    for candidate in candidates:
        if not candidate.is_file():
            continue
        try:
            payload = json.loads(candidate.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        normalized = normalize_service_ai_request_config(payload)
        if normalized:
            return normalized
    return None


def write_service_ai_request_config(
    payload: dict[str, Any],
    path: str | Path | None = None,
) -> Path:
    normalized = normalize_service_ai_request_config(payload) or default_service_ai_request_config()
    target = Path(path).expanduser() if path else default_service_ai_config_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(normalized, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        os.chmod(target, 0o600)
    except OSError:
        pass
    return target
