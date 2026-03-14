from __future__ import annotations

import json
import os
import re
import threading
import time
from hashlib import sha1
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

try:
    from service_ai_config import infer_kimi_preset, load_service_ai_request_config
except ModuleNotFoundError:
    from market_dashboard.service_ai_config import infer_kimi_preset, load_service_ai_request_config


ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
KIMI_API_BASE_URL = "https://api.moonshot.cn/v1"
GEMINI_API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
REQUEST_TIMEOUT_SECONDS = 40.0
AI_CACHE_TTL_SECONDS = 900
AI_CACHE: dict[str, Any] = {"key": "", "timestamp": 0.0, "payload": None}
AI_LOCK = threading.Lock()
AI_PROVIDER_STATUS: dict[str, dict[str, Any]] = {}
AI_PROVIDER_STATUS_LOCK = threading.Lock()
DEFAULT_PROVIDER_ORDER = ("anthropic", "kimi", "gemini")
DEFAULT_ANTHROPIC_MODELS = (
    "claude-sonnet-4-20250514",
    "claude-sonnet-4-5-20250929",
    "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
    "claude-3-haiku-20240307",
)
DEFAULT_KIMI_MODELS = (
    "kimi-for-coding",
    "moonshot-v1-8k",
    "moonshot-v1-32k",
    "moonshot-v1-128k",
)
DEFAULT_GEMINI_MODELS = (
    "gemini-2.5-flash",
    "gemini-2.5-pro",
)


def _cache_key(
    payload: dict[str, Any],
    preferred_model: str | None,
    mode: str,
    ai_request_config: dict[str, Any] | None = None,
) -> str:
    normalized_request_config = _resolved_ai_request_config(ai_request_config)
    raw = json.dumps(
        {
            "payload": payload,
            "preferred_model": preferred_model,
            "mode": mode,
            "ai_request_config": normalized_request_config,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    return sha1(raw.encode("utf-8")).hexdigest()


def _clean_json_text(text: str) -> str:
    fenced = re.search(r"```(?:json)?\s*(\{.*\})\s*```", text, flags=re.DOTALL)
    if fenced:
        return fenced.group(1)
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1]
    return text


def _normalize_cards(cards: list[dict[str, Any]] | None) -> list[dict[str, str]]:
    normalized: list[dict[str, str]] = []
    for card in cards or []:
        title = str(card.get("title") or "").strip()
        detail = str(card.get("detail") or "").strip()
        tone = str(card.get("tone") or "warn").strip().lower()
        if not title or not detail:
            continue
        if tone not in {"up", "warn", "down"}:
            tone = "warn"
        normalized.append({"title": title[:30], "detail": detail[:440], "tone": tone})
    return normalized[:4]


def _normalize_playbook(rows: list[Any] | None) -> list[str]:
    values: list[str] = []
    for row in rows or []:
        if isinstance(row, dict):
            parts = [
                str(row.get("action") or "").strip(),
                str(row.get("trigger") or "").strip(),
                str(row.get("verification") or row.get("condition") or "").strip(),
            ]
            text = "；".join(part for part in parts if part)
        else:
            text = str(row or "").strip()
        if text:
            values.append(text[:220])
    return values[:6]


def _normalize_sections(rows: list[dict[str, Any]] | None, limit: int = 5) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for row in rows or []:
        title = str(row.get("title") or "").strip()
        summary = str(row.get("summary") or row.get("detail") or row.get("body") or "").strip()
        bullets: list[str] = []
        for bullet in row.get("bullets") or row.get("points") or row.get("actions") or []:
            text = str(bullet or "").strip()
            if text:
                bullets.append(text[:220])
        if not title or (not summary and not bullets):
            continue
        normalized.append(
            {
                "title": title[:36],
                "summary": summary[:520],
                "bullets": bullets[:4],
            }
        )
    return normalized[:limit]


def _normalize_position_actions(rows: list[dict[str, Any]] | None) -> list[dict[str, str]]:
    normalized: list[dict[str, str]] = []
    for row in rows or []:
        symbol = str(row.get("symbol") or "").strip()
        name = str(row.get("name") or "").strip()
        stance = str(row.get("stance") or "").strip()
        thesis = str(row.get("thesis") or "").strip()
        trigger = str(row.get("trigger") or row.get("watch") or "").strip()
        risk = str(row.get("risk") or "").strip()
        action = str(row.get("action") or "").strip()
        if not symbol or not (stance or action or thesis):
            continue
        normalized.append(
            {
                "symbol": symbol[:18],
                "name": name[:40],
                "stance": stance[:20],
                "thesis": thesis[:300],
                "trigger": trigger[:240],
                "risk": risk[:240],
                "action": action[:260],
            }
        )
    return normalized[:8]


def _normalize_text_rows(rows: list[Any] | None, limit: int = 6, max_len: int = 220) -> list[str]:
    values: list[str] = []
    for row in rows or []:
        text = str(row or "").strip()
        if text:
            values.append(text[:max_len])
    return values[:limit]


def _decode_json_string(value: str) -> str:
    try:
        return json.loads(f"\"{value}\"")
    except Exception:
        return value


def _extract_string_field(text: str, key: str) -> str:
    match = re.search(rf'"{re.escape(key)}"\s*:\s*"((?:[^"\\]|\\.)*)"', text, flags=re.DOTALL)
    return _decode_json_string(match.group(1)).strip() if match else ""


def _extract_list_block(text: str, key: str, next_keys: list[str]) -> str:
    start_match = re.search(rf'"{re.escape(key)}"\s*:\s*\[', text)
    if not start_match:
        return ""
    start = start_match.end()
    candidates = [text.find(f'"{next_key}"', start) for next_key in next_keys]
    candidates = [index for index in candidates if index != -1]
    end = min(candidates) if candidates else len(text)
    return text[start:end]


def _extract_string_list(text: str, key: str, next_keys: list[str], limit: int = 4) -> list[str]:
    block = _extract_list_block(text, key, next_keys)
    if not block:
        return []
    values = [
        _decode_json_string(item).strip()
        for item in re.findall(r'"((?:[^"\\]|\\.)*)"', block, flags=re.DOTALL)
    ]
    return [item for item in values if item][:limit]


def _salvage_sections(text: str) -> list[dict[str, Any]]:
    block = _extract_list_block(text, "sections", ["bull_case", "bear_case", "watchlist", "action_plan", "position_actions"])
    if not block:
        return []
    sections: list[dict[str, Any]] = []
    pattern = re.compile(
        r'\{\s*"title"\s*:\s*"((?:[^"\\]|\\.)*)".*?"summary"\s*:\s*"((?:[^"\\]|\\.)*)".*?"bullets"\s*:\s*\[(.*?)\]',
        flags=re.DOTALL,
    )
    for match in pattern.finditer(block):
        bullets = [
            _decode_json_string(item).strip()
            for item in re.findall(r'"((?:[^"\\]|\\.)*)"', match.group(3), flags=re.DOTALL)
        ]
        sections.append(
            {
                "title": _decode_json_string(match.group(1)).strip(),
                "summary": _decode_json_string(match.group(2)).strip(),
                "bullets": [item for item in bullets if item][:3],
            }
        )
    return sections[:3]


def _salvage_stock_detail_output(text: str) -> dict[str, Any] | None:
    salvaged = {
        "headline": _extract_string_field(text, "headline"),
        "deep_summary": _extract_string_field(text, "deep_summary"),
        "executive_summary": _extract_string_list(text, "executive_summary", ["sections", "bull_case", "bear_case", "watchlist", "action_plan"], limit=4),
        "sections": _salvage_sections(text),
        "bull_case": _extract_string_list(text, "bull_case", ["bear_case", "watchlist", "action_plan"], limit=3),
        "bear_case": _extract_string_list(text, "bear_case", ["watchlist", "action_plan"], limit=3),
        "watchlist": _extract_string_list(text, "watchlist", ["action_plan"], limit=4),
        "action_plan": _extract_string_list(text, "action_plan", [], limit=4),
    }
    if not any([salvaged["headline"], salvaged["deep_summary"], salvaged["sections"], salvaged["action_plan"]]):
        return None
    return salvaged


def _normalize_provider_name(value: str | None) -> str | None:
    normalized = str(value or "").strip().lower()
    aliases = {
        "anthropic": "anthropic",
        "claude": "anthropic",
        "kimi": "kimi",
        "moonshot": "kimi",
        "gemini": "gemini",
        "google": "gemini",
    }
    return aliases.get(normalized)


def _provider_label(provider: str) -> str:
    if provider == "anthropic":
        return "Claude"
    if provider == "kimi":
        return "Kimi"
    if provider == "gemini":
        return "Gemini"
    return provider


def _trimmed_string(value: Any) -> str:
    return str(value or "").strip()


def _now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _single_model_or_candidates(
    configured_model: str | None,
    candidate_builder: Any,
) -> list[str]:
    trimmed = _trimmed_string(configured_model)
    if trimmed:
        return [trimmed]
    return candidate_builder(None)


def _coerce_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _normalize_ai_request_config(ai_request_config: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(ai_request_config, dict):
        return {"primary_provider": None, "enable_fallbacks": True, "providers": {}}

    providers: dict[str, dict[str, Any]] = {}
    for item in ai_request_config.get("providers") or []:
        if not isinstance(item, dict):
            continue
        provider = _normalize_provider_name(item.get("provider"))
        if not provider:
            continue
        providers[provider] = {
            "provider": provider,
            "api_key": _trimmed_string(item.get("api_key")),
            "model": _trimmed_string(item.get("model")),
            "base_url": _trimmed_string(item.get("base_url")),
            "preset": _trimmed_string(item.get("preset")),
        }

    return {
        "primary_provider": _normalize_provider_name(ai_request_config.get("primary_provider")),
        "enable_fallbacks": _coerce_bool(ai_request_config.get("enable_fallbacks"), default=True),
        "providers": providers,
    }


def _resolved_ai_request_config(ai_request_config: dict[str, Any] | None) -> dict[str, Any]:
    request_source = ai_request_config if isinstance(ai_request_config, dict) else None
    request_config = _normalize_ai_request_config(request_source)
    service_config = _normalize_ai_request_config(load_service_ai_request_config())

    provider_names: list[str] = []
    for provider in [
        *DEFAULT_PROVIDER_ORDER,
        *(service_config.get("providers") or {}).keys(),
        *(request_config.get("providers") or {}).keys(),
    ]:
        normalized_provider = _normalize_provider_name(provider)
        if not normalized_provider or normalized_provider in provider_names:
            continue
        provider_names.append(normalized_provider)

    providers: dict[str, dict[str, Any]] = {}
    for provider in provider_names:
        service_provider = (service_config.get("providers") or {}).get(provider) or {}
        request_provider = (request_config.get("providers") or {}).get(provider) or {}
        providers[provider] = {
            "provider": provider,
            "api_key": _trimmed_string(request_provider.get("api_key")) or _trimmed_string(service_provider.get("api_key")),
            "model": _trimmed_string(request_provider.get("model")) or _trimmed_string(service_provider.get("model")),
            "base_url": _trimmed_string(request_provider.get("base_url")) or _trimmed_string(service_provider.get("base_url")),
            "preset": _trimmed_string(request_provider.get("preset")) or _trimmed_string(service_provider.get("preset")),
        }

    primary_provider = request_config.get("primary_provider") or service_config.get("primary_provider")
    enable_fallbacks = (
        _coerce_bool(request_source.get("enable_fallbacks"), default=service_config.get("enable_fallbacks", True))
        if request_source is not None
        else service_config.get("enable_fallbacks", True)
    )

    return {
        "primary_provider": primary_provider,
        "enable_fallbacks": enable_fallbacks,
        "providers": providers,
    }


def _candidate_models(
    preferred_model: str | None,
    *,
    env_names: tuple[str, ...],
    candidate_env_names: tuple[str, ...],
    defaults: tuple[str, ...],
) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    raw_candidates = ""
    for env_name in candidate_env_names:
        raw_candidates = os.getenv(env_name) or raw_candidates
        if raw_candidates:
            break
    env_models = [os.getenv(env_name) for env_name in env_names]
    values = [preferred_model, *env_models, *[item.strip() for item in raw_candidates.split(",") if item.strip()], *defaults]
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


def _anthropic_candidate_models(preferred_model: str | None) -> list[str]:
    return _candidate_models(
        preferred_model,
        env_names=("MARKET_DASHBOARD_AI_MODEL", "ANTHROPIC_MODEL"),
        candidate_env_names=("MARKET_DASHBOARD_AI_MODEL_CANDIDATES", "ANTHROPIC_MODEL_CANDIDATES"),
        defaults=DEFAULT_ANTHROPIC_MODELS,
    )


def _kimi_candidate_models(preferred_model: str | None) -> list[str]:
    return _candidate_models(
        preferred_model,
        env_names=("KIMI_MODEL", "MOONSHOT_MODEL"),
        candidate_env_names=("KIMI_MODEL_CANDIDATES", "MOONSHOT_MODEL_CANDIDATES"),
        defaults=DEFAULT_KIMI_MODELS,
    )


def _gemini_candidate_models(preferred_model: str | None) -> list[str]:
    return _candidate_models(
        preferred_model,
        env_names=("GEMINI_MODEL",),
        candidate_env_names=("GEMINI_MODEL_CANDIDATES",),
        defaults=DEFAULT_GEMINI_MODELS,
    )


def _configured_provider_order(ai_request_config: dict[str, Any] | None) -> list[str]:
    normalized = _resolved_ai_request_config(ai_request_config)
    configured_primary = normalized.get("primary_provider") or _normalize_provider_name(os.getenv("MARKET_DASHBOARD_AI_PROVIDER")) or "anthropic"
    ordered = [configured_primary]
    if normalized.get("enable_fallbacks", True):
        ordered.extend(DEFAULT_PROVIDER_ORDER)

    seen: set[str] = set()
    result: list[str] = []
    for provider in ordered:
        normalized_provider = _normalize_provider_name(provider)
        if not normalized_provider or normalized_provider in seen:
            continue
        seen.add(normalized_provider)
        result.append(normalized_provider)
    return result


def _provider_status_snapshot(provider: str) -> dict[str, Any] | None:
    with AI_PROVIDER_STATUS_LOCK:
        payload = AI_PROVIDER_STATUS.get(provider)
        return dict(payload) if payload else None


def _record_provider_status(
    provider: str,
    *,
    label: str,
    state: str,
    message: str,
    model: str | None = None,
    base_url: str | None = None,
    latency_ms: int | None = None,
) -> None:
    with AI_PROVIDER_STATUS_LOCK:
        AI_PROVIDER_STATUS[provider] = {
            "provider": provider,
            "label": label,
            "state": state,
            "message": message,
            "model": _trimmed_string(model),
            "base_url": _trimmed_string(base_url),
            "latency_ms": latency_ms,
            "checked_at": _now_iso(),
        }


def _provider_api_key_from_environment(provider: str) -> str:
    if provider == "anthropic":
        return _trimmed_string(os.getenv("ANTHROPIC_API_KEY"))
    if provider == "kimi":
        return _trimmed_string(os.getenv("KIMI_API_KEY")) or _trimmed_string(os.getenv("MOONSHOT_API_KEY"))
    if provider == "gemini":
        return _trimmed_string(os.getenv("GEMINI_API_KEY"))
    return ""


def _provider_credential_source(provider: str, ai_request_config: dict[str, Any] | None = None) -> str:
    request_config = _normalize_ai_request_config(ai_request_config)
    service_config = _normalize_ai_request_config(load_service_ai_request_config())
    request_provider = (request_config.get("providers") or {}).get(provider) or {}
    service_provider = (service_config.get("providers") or {}).get(provider) or {}
    if _trimmed_string(request_provider.get("api_key")):
        return "request"
    if _trimmed_string(service_provider.get("api_key")):
        return "service_config"
    if _provider_api_key_from_environment(provider):
        return "environment"
    return "missing"


def _provider_runtime_settings(
    provider: str,
    *,
    ai_request_config: dict[str, Any] | None,
    preferred_model: str | None = None,
) -> dict[str, Any] | None:
    normalized_request_config = _resolved_ai_request_config(ai_request_config)
    request_provider = (normalized_request_config.get("providers") or {}).get(provider) or {}

    if provider == "anthropic":
        api_key = _trimmed_string(request_provider.get("api_key")) or _trimmed_string(os.getenv("ANTHROPIC_API_KEY"))
        if not api_key:
            return None
        configured_model = _trimmed_string(request_provider.get("model")) or _trimmed_string(preferred_model)
        candidate_models = _single_model_or_candidates(configured_model, _anthropic_candidate_models)
        configured_model = configured_model or _trimmed_string(os.getenv("MARKET_DASHBOARD_AI_MODEL")) or _trimmed_string(os.getenv("ANTHROPIC_MODEL"))
        return {
            "provider": provider,
            "label": _provider_label(provider),
            "api_key": api_key,
            "candidate_models": candidate_models,
            "configured_model": configured_model,
            "base_url": ANTHROPIC_API_URL,
        }

    if provider == "kimi":
        api_key = (
            _trimmed_string(request_provider.get("api_key"))
            or _trimmed_string(os.getenv("KIMI_API_KEY"))
            or _trimmed_string(os.getenv("MOONSHOT_API_KEY"))
        )
        if not api_key:
            return None
        configured_model = _trimmed_string(request_provider.get("model")) or _trimmed_string(preferred_model)
        candidate_models = _single_model_or_candidates(configured_model, _kimi_candidate_models)
        configured_model = configured_model or _trimmed_string(os.getenv("KIMI_MODEL")) or _trimmed_string(os.getenv("MOONSHOT_MODEL"))
        preset = infer_kimi_preset(
            request_provider.get("preset"),
            base_url=request_provider.get("base_url"),
            model=configured_model,
        )
        base_url = (
            _trimmed_string(request_provider.get("base_url"))
            or _trimmed_string(os.getenv("KIMI_BASE_URL"))
            or _trimmed_string(os.getenv("MOONSHOT_BASE_URL"))
            or KIMI_API_BASE_URL
        )
        return {
            "provider": provider,
            "label": _provider_label(provider),
            "api_key": api_key,
            "candidate_models": candidate_models,
            "configured_model": configured_model,
            "base_url": base_url.rstrip("/"),
            "preset": preset,
        }

    if provider == "gemini":
        api_key = _trimmed_string(request_provider.get("api_key")) or _trimmed_string(os.getenv("GEMINI_API_KEY"))
        if not api_key:
            return None
        configured_model = _trimmed_string(request_provider.get("model")) or _trimmed_string(preferred_model)
        candidate_models = _single_model_or_candidates(configured_model, _gemini_candidate_models)
        configured_model = configured_model or _trimmed_string(os.getenv("GEMINI_MODEL"))
        base_url = _trimmed_string(request_provider.get("base_url")) or _trimmed_string(os.getenv("GEMINI_BASE_URL")) or GEMINI_API_BASE_URL
        return {
            "provider": provider,
            "label": _provider_label(provider),
            "api_key": api_key,
            "candidate_models": candidate_models,
            "configured_model": configured_model,
            "base_url": base_url.rstrip("/"),
        }

    return None


def _dashboard_system_prompt() -> str:
    return (
        "你是买方投资总监兼组合经理。"
        "你只根据给定数据做组合诊断，不能编造新的持仓、交易、新闻、业绩或估值。"
        "输出必须是 JSON，不要使用 Markdown。"
        "语言必须是简体中文，风格专业、直接、具体、可执行。"
        "避免空泛建议，必须明确指出风险传导链、验证指标、失效条件和下一步动作。"
        "先做组合层判断，再落到关键持仓的逐只建议。"
    )


def _dashboard_user_prompt(payload: dict[str, Any]) -> str:
    return (
        "请基于下面的结构化组合信息，生成一份真正可执行的投资工作台深度分析。\n"
        "要求：\n"
        "1. headline 要指出真正决定组合净值弹性的核心矛盾。\n"
        "2. cards 和 playbook 由本地规则引擎生成，你不要输出这两个字段。\n"
        "3. deep_summary 输出 2-3 句总结，强调组合结构、风险传导和资金下一步落点。\n"
        "4. sections 只输出 3 段深度拆解，每段包含 title、summary、bullets。必须覆盖：组合结构诊断、宏观与新闻、下一周执行框架。每段 bullets 固定 2 条，且每条不超过 28 个汉字。\n"
        "5. position_actions 只输出 4 个重点持仓建议，每项包含 symbol、name、stance、thesis、trigger、risk、action。stance 必须是明确处理意见，例如“继续持有”“分批增持”“观察持有”“减仓降风险”“只做交易仓”。各字段都要简洁，thesis/trigger/risk/action 尽量控制在 36 个汉字以内。\n"
        "6. 所有字符串值里禁止出现 ASCII 双引号 `\"`，如需强调请改用中文引号或直接陈述，避免破坏 JSON。\n"
        "7. 细节必须引用输入里的标的、权重、信号、趋势、新闻、宏观主题、基本面验证点、衍生品和融资信息，不要写泛泛而谈的投资鸡汤。\n"
        "8. 如果输入里已经有规则引擎结论，可以在此基础上深化，但不要简单复述。\n"
        "9. 绝对不要建议用户去做输入中不存在的资产，也不要杜撰盈利预测数值。\n"
        "10. 整体输出要短而硬，不要为了完整而展开成长文。\n\n"
        "返回格式示例：\n"
        "{"
        "\"headline\":\"...\","
        "\"deep_summary\":\"...\","
        "\"sections\":[{\"title\":\"组合结构诊断\",\"summary\":\"...\",\"bullets\":[\"...\",\"...\"]}],"
        "\"position_actions\":[{\"symbol\":\"NVDA\",\"name\":\"英伟达\",\"stance\":\"继续持有\",\"thesis\":\"...\",\"trigger\":\"...\",\"risk\":\"...\",\"action\":\"...\"}]"
        "}\n\n"
        f"输入数据：\n{json.dumps(payload, ensure_ascii=False, sort_keys=True)}"
    )


def _stock_detail_system_prompt() -> str:
    return (
        "你是买方研究主管，负责把单只持仓的业务逻辑、交易逻辑和组合角色统一起来。"
        "你只能基于输入数据分析，不能编造新的业绩、估值、事件或仓位。"
        "输出必须是 JSON，不要使用 Markdown。"
        "语言必须是简体中文，风格冷静、专业、直接。"
        "重点是让用户知道：为什么持有、什么情况下加减仓、最先盯什么验证点。"
    )


def _stock_detail_user_prompt(payload: dict[str, Any]) -> str:
    return (
        "请基于下面的单股详情输入，生成一份高质量、可执行的个股深度分析。\n"
        "要求：\n"
        "1. headline 用一句话指出这只股票当前最关键的矛盾。\n"
        "2. deep_summary 输出 2-3 句，把业务逻辑、盘面状态、组合角色串起来。\n"
        "3. executive_summary 输出 4 条要点，每条 50 字以内。\n"
        "4. sections 输出 3 段深度拆解，每段包含 title、summary、bullets。必须覆盖：业务与催化、盘面与交易、风险与执行。每段 bullets 固定 2 条。\n"
        "5. bull_case、bear_case、watchlist、action_plan 都输出字符串数组，各 3 条，简洁可执行。\n"
        "6. 必须引用输入中的基本面验证点、新闻、宏观、趋势、交易记录、同主题对照和组合角色，不要泛泛而谈。\n"
        "7. 所有字符串值里禁止出现 ASCII 双引号 `\"`。\n"
        "8. 不要输出输入中没有的资产建议，不要编造财务数据。\n\n"
        "返回格式示例：\n"
        "{"
        "\"headline\":\"...\","
        "\"deep_summary\":\"...\","
        "\"executive_summary\":[\"...\"],"
        "\"sections\":[{\"title\":\"业务与催化\",\"summary\":\"...\",\"bullets\":[\"...\",\"...\"]}],"
        "\"bull_case\":[\"...\"],"
        "\"bear_case\":[\"...\"],"
        "\"watchlist\":[\"...\"],"
        "\"action_plan\":[\"...\"]"
        "}\n\n"
        f"输入数据：\n{json.dumps(payload, ensure_ascii=False, sort_keys=True)}"
    )


def _extract_anthropic_text(response_payload: dict[str, Any]) -> str:
    content = response_payload.get("content") or []
    return "\n".join(
        block.get("text", "")
        for block in content
        if isinstance(block, dict) and block.get("type") == "text"
    ).strip()


def _extract_openai_compatible_text(response_payload: dict[str, Any]) -> str:
    choices = response_payload.get("choices") or []
    if not choices:
        return ""
    message = (choices[0] or {}).get("message") or {}
    content = message.get("content") or ""
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                text = item.get("text") or item.get("content") or ""
                if text:
                    parts.append(str(text))
            elif item:
                parts.append(str(item))
        return "\n".join(parts).strip()
    return str(content).strip()


def _extract_gemini_text(response_payload: dict[str, Any]) -> str:
    candidates = response_payload.get("candidates") or []
    if not candidates:
        return ""
    content = (candidates[0] or {}).get("content") or {}
    parts = content.get("parts") or []
    texts = [str(part.get("text") or "").strip() for part in parts if isinstance(part, dict)]
    return "\n".join(item for item in texts if item).strip()


def _build_openai_chat_completions_url(base_url: str) -> str:
    normalized = base_url.rstrip("/")
    if normalized.endswith("/chat/completions"):
        return normalized
    return normalized + "/chat/completions"


def _request_anthropic_response(
    *,
    api_key: str,
    model: str,
    system_prompt: str,
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float,
) -> tuple[str, str, int]:
    request_body = json.dumps(
        {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "system": system_prompt,
            "messages": messages,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    request = Request(
        ANTHROPIC_API_URL,
        data=request_body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
    )
    started_at = time.time()
    with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        response_payload = json.loads(response.read().decode("utf-8"))
    text = _extract_anthropic_text(response_payload)
    latency_ms = int((time.time() - started_at) * 1000)
    return text, str(response_payload.get("model") or model), latency_ms


def _request_openai_compatible_response(
    *,
    base_url: str,
    api_key: str,
    model: str,
    system_prompt: str,
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float,
) -> tuple[str, str, int]:
    request_messages: list[dict[str, str]] = []
    if system_prompt:
        request_messages.append({"role": "system", "content": system_prompt})
    request_messages.extend(messages)
    request_body = json.dumps(
        {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "messages": request_messages,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    request = Request(
        _build_openai_chat_completions_url(base_url),
        data=request_body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    started_at = time.time()
    with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        response_payload = json.loads(response.read().decode("utf-8"))
    text = _extract_openai_compatible_text(response_payload)
    latency_ms = int((time.time() - started_at) * 1000)
    return text, str(response_payload.get("model") or model), latency_ms


def _request_gemini_response(
    *,
    base_url: str,
    api_key: str,
    model: str,
    system_prompt: str,
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float,
) -> tuple[str, str, int]:
    request_messages = [
        {
            "role": "model" if message.get("role") == "assistant" else "user",
            "parts": [{"text": message.get("content") or ""}],
        }
        for message in messages
        if message.get("content")
    ]
    request_body = {
        "contents": request_messages,
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": max_tokens,
        },
    }
    if system_prompt:
        request_body["systemInstruction"] = {"parts": [{"text": system_prompt}]}
    request = Request(
        f"{base_url.rstrip('/')}/models/{quote(model, safe='')}:generateContent?key={quote(api_key, safe='')}",
        data=json.dumps(request_body, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    started_at = time.time()
    with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        response_payload = json.loads(response.read().decode("utf-8"))
    text = _extract_gemini_text(response_payload)
    latency_ms = int((time.time() - started_at) * 1000)
    return text, model, latency_ms


def _request_provider_response(
    *,
    provider_settings: dict[str, Any],
    model: str,
    system_prompt: str,
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float,
) -> tuple[str, str, int]:
    provider = provider_settings["provider"]
    if provider == "anthropic":
        return _request_anthropic_response(
            api_key=provider_settings["api_key"],
            model=model,
            system_prompt=system_prompt,
            messages=messages,
            max_tokens=max_tokens,
            temperature=temperature,
        )
    if provider == "kimi":
        return _request_openai_compatible_response(
            base_url=provider_settings["base_url"],
            api_key=provider_settings["api_key"],
            model=model,
            system_prompt=system_prompt,
            messages=messages,
            max_tokens=max_tokens,
            temperature=temperature,
        )
    if provider == "gemini":
        return _request_gemini_response(
            base_url=provider_settings["base_url"],
            api_key=provider_settings["api_key"],
            model=model,
            system_prompt=system_prompt,
            messages=messages,
            max_tokens=max_tokens,
            temperature=temperature,
        )
    raise ValueError(f"unsupported provider: {provider}")


def _success_note(
    *,
    provider_settings: dict[str, Any],
    entrypoint: str,
    initial_provider: str | None,
    configured_model: str | None,
    salvage_used: bool = False,
) -> str:
    fallback_prefix = ""
    if initial_provider and initial_provider != provider_settings["provider"]:
        fallback_prefix = f"首选 {_provider_label(initial_provider)} 不可用，已自动切换到 {provider_settings['label']}。"

    if entrypoint == "chat":
        body = (
            f"自由对话当前走 {provider_settings['label']}。"
            if configured_model
            else f"未显式配置 {provider_settings['label']} 模型名，系统已自动尝试可用候选。"
        )
    else:
        body = (
            f"先用本地结构化框架整理上下文，再由 {provider_settings['label']} 生成深度诊断与执行建议。"
            if configured_model
            else f"未显式配置 {provider_settings['label']} 模型名，系统已自动尝试可用候选。"
        )
    if salvage_used:
        body += " 模型已返回结果，原始 JSON 存在轻微格式问题，系统已自动容错解析。"
    return (fallback_prefix + body).strip()


def _no_external_provider_result(entrypoint: str) -> dict[str, Any]:
    note = "未检测到可用的大模型密钥，已回退为本地结构化规则引擎。" if entrypoint == "json" else "未检测到可用的大模型密钥，无法发起自由对话。"
    return {
        "ok": False,
        "engine": {
            "mode": "rules",
            "provider": "local",
            "model": None,
            "label": "本地规则引擎",
            "note": note,
        },
    }


def _provider_error_detail(raw_error: str) -> str:
    lowered = raw_error.lower()
    if any(token in lowered for token in ("timed out", "timeout", "deadline exceeded")):
        return "请求超时，远程服务器到模型服务的外网链路可能不通。"
    if any(token in lowered for token in ("name or service not known", "temporary failure in name resolution", "nodename nor servname")):
        return "域名解析失败，远程服务器当前可能无法访问对应模型域名。"
    if any(token in lowered for token in ("unauthorized", "forbidden", "invalid_api_key", "invalid x-api-key", "authentication")):
        return "鉴权失败，请检查当前模型的 API Key 是否正确。"
    if any(token in lowered for token in ("connection refused", "network is unreachable", "connection reset", "ssl")):
        return "网络连接失败，远程服务器到模型服务的链路异常。"
    return raw_error[:140] if raw_error else "访问失败。"


def _provider_failure_result(errors: list[str], entrypoint: str) -> dict[str, Any]:
    note = "外部大模型调用失败，已自动回退为本地规则引擎。" if entrypoint == "json" else "外部大模型调用失败，当前无法继续自由对话。"
    if errors:
        first_error = str(errors[0]).strip()
        provider_label, _, raw_error = first_error.partition(":")
        provider_label = provider_label.strip()
        raw_error = raw_error.strip()
        detail = _provider_error_detail(raw_error)
        if provider_label:
            note = f"{note} 最近失败：{provider_label}，{detail}"
        else:
            note = f"{note} 最近失败：{detail}"
    return {
        "ok": False,
        "engine": {
            "mode": "rules",
            "provider": "local",
            "model": None,
            "label": "本地规则引擎",
            "note": note,
            "errors": errors,
        },
    }


def get_ai_service_status(ai_request_config: dict[str, Any] | None = None) -> dict[str, Any]:
    resolved = _resolved_ai_request_config(ai_request_config)
    service_config = _normalize_ai_request_config(load_service_ai_request_config())
    provider_order = _configured_provider_order(ai_request_config)
    provider_names: list[str] = []
    for provider in [*provider_order, *DEFAULT_PROVIDER_ORDER, *(resolved.get("providers") or {}).keys()]:
        normalized_provider = _normalize_provider_name(provider)
        if not normalized_provider or normalized_provider in provider_names:
            continue
        provider_names.append(normalized_provider)

    providers_payload: list[dict[str, Any]] = []
    for provider in provider_names:
        runtime = _provider_runtime_settings(provider, ai_request_config=ai_request_config)
        provider_config = (resolved.get("providers") or {}).get(provider) or {}
        service_provider = (service_config.get("providers") or {}).get(provider) or {}
        cached_status = _provider_status_snapshot(provider) or {}
        effective_model = (
            _trimmed_string(provider_config.get("model"))
            or _trimmed_string(cached_status.get("model"))
            or (runtime.get("configured_model") if runtime else "")
            or ((runtime.get("candidate_models") or [""])[0] if runtime else "")
        )
        effective_base_url = (
            _trimmed_string(provider_config.get("base_url"))
            or _trimmed_string(cached_status.get("base_url"))
            or (runtime.get("base_url") if runtime else "")
        )
        preset = _trimmed_string(provider_config.get("preset")) or (
            infer_kimi_preset(
                service_provider.get("preset"),
                base_url=effective_base_url,
                model=effective_model,
            )
            if provider == "kimi"
            else ""
        )
        if cached_status:
            access_state = str(cached_status.get("state") or "ready")
            access_message = str(cached_status.get("message") or "服务端已配置，可发起访问。").strip()
            checked_at = cached_status.get("checked_at")
            latency_ms = cached_status.get("latency_ms")
        elif runtime is None:
            access_state = "missing_key"
            access_message = "服务端未配置可用 API Key。"
            checked_at = None
            latency_ms = None
        else:
            access_state = "ready"
            access_message = "服务端已配置，可发起访问。"
            checked_at = None
            latency_ms = None

        providers_payload.append(
            {
                "provider": provider,
                "label": _provider_label(provider),
                "model": effective_model or None,
                "base_url": effective_base_url or None,
                "preset": preset or None,
                "credential_source": _provider_credential_source(provider, ai_request_config=ai_request_config),
                "access_state": access_state,
                "access_message": access_message,
                "checked_at": checked_at,
                "latency_ms": latency_ms,
            }
        )

    return {
        "primary_provider": resolved.get("primary_provider"),
        "enable_fallbacks": resolved.get("enable_fallbacks", True),
        "provider_order": provider_order,
        "uses_service_config": load_service_ai_request_config() is not None,
        "providers": providers_payload,
        "note": "App 端仅切换 provider 与模型，真正的 API Key 由服务端托管。",
    }


def _call_llm_json(
    *,
    preferred_model: str | None,
    system_prompt: str,
    user_prompt: str,
    max_tokens: int,
    temperature: float,
    max_model_attempts: int | None = None,
    salvage_parser: Any | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    provider_order = _configured_provider_order(ai_request_config)
    initial_provider = provider_order[0] if provider_order else None
    errors: list[str] = []
    has_external_provider = False

    for provider in provider_order:
        provider_settings = _provider_runtime_settings(
            provider,
            ai_request_config=ai_request_config,
            preferred_model=preferred_model if provider == initial_provider else None,
        )
        if not provider_settings:
            continue
        has_external_provider = True
        candidate_models = provider_settings["candidate_models"]
        if max_model_attempts is not None:
            candidate_models = candidate_models[:max_model_attempts]

        for model in candidate_models:
            try:
                text, resolved_model, latency_ms = _request_provider_response(
                    provider_settings=provider_settings,
                    model=model,
                    system_prompt=system_prompt,
                    messages=[{"role": "user", "content": user_prompt}],
                    max_tokens=max_tokens,
                    temperature=temperature,
                )
                cleaned_text = _clean_json_text(text)
                salvage_used = False
                try:
                    parsed = json.loads(cleaned_text)
                except json.JSONDecodeError:
                    if not salvage_parser:
                        raise
                    parsed = salvage_parser(cleaned_text)
                    if not parsed:
                        raise
                    salvage_used = True
                success_note = _success_note(
                    provider_settings=provider_settings,
                    entrypoint="json",
                    initial_provider=initial_provider,
                    configured_model=provider_settings.get("configured_model"),
                    salvage_used=salvage_used,
                )
                _record_provider_status(
                    provider_settings["provider"],
                    label=provider_settings["label"],
                    state="success",
                    message=success_note,
                    model=resolved_model,
                    base_url=provider_settings.get("base_url"),
                    latency_ms=latency_ms,
                )

                return {
                    "ok": True,
                    "parsed": parsed,
                    "engine": {
                        "mode": "llm",
                        "provider": provider_settings["provider"],
                        "model": resolved_model,
                        "label": f"{provider_settings['label']} {resolved_model}",
                        "latency_ms": latency_ms,
                        "note": success_note,
                    },
                }
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError, ValueError, OSError, Exception) as exc:
                _record_provider_status(
                    provider_settings["provider"],
                    label=provider_settings["label"],
                    state="error",
                    message=f"{provider_settings['label']} 访问失败：{_provider_error_detail(str(exc))}",
                    model=model,
                    base_url=provider_settings.get("base_url"),
                )
                errors.append(f"{provider_settings['label']} {model}: {exc}")

    if not has_external_provider:
        return _no_external_provider_result("json")
    return _provider_failure_result(errors, "json")


def _call_llm_text(
    *,
    preferred_model: str | None,
    system_prompt: str,
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float,
    max_model_attempts: int | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    provider_order = _configured_provider_order(ai_request_config)
    initial_provider = provider_order[0] if provider_order else None
    errors: list[str] = []
    has_external_provider = False

    for provider in provider_order:
        provider_settings = _provider_runtime_settings(
            provider,
            ai_request_config=ai_request_config,
            preferred_model=preferred_model if provider == initial_provider else None,
        )
        if not provider_settings:
            continue
        has_external_provider = True
        candidate_models = provider_settings["candidate_models"]
        if max_model_attempts is not None:
            candidate_models = candidate_models[:max_model_attempts]
        for model in candidate_models:
            try:
                text, resolved_model, latency_ms = _request_provider_response(
                    provider_settings=provider_settings,
                    model=model,
                    system_prompt=system_prompt,
                    messages=messages,
                    max_tokens=max_tokens,
                    temperature=temperature,
                )
                if not text:
                    raise ValueError("empty response")
                success_note = _success_note(
                    provider_settings=provider_settings,
                    entrypoint="chat",
                    initial_provider=initial_provider,
                    configured_model=provider_settings.get("configured_model"),
                )
                _record_provider_status(
                    provider_settings["provider"],
                    label=provider_settings["label"],
                    state="success",
                    message=success_note,
                    model=resolved_model,
                    base_url=provider_settings.get("base_url"),
                    latency_ms=latency_ms,
                )
                return {
                    "ok": True,
                    "reply": text,
                    "engine": {
                        "mode": "llm",
                        "provider": provider_settings["provider"],
                        "model": resolved_model,
                        "label": f"{provider_settings['label']} {resolved_model}",
                        "latency_ms": latency_ms,
                        "note": success_note,
                    },
                }
            except (HTTPError, URLError, TimeoutError, ValueError, OSError, Exception) as exc:
                _record_provider_status(
                    provider_settings["provider"],
                    label=provider_settings["label"],
                    state="error",
                    message=f"{provider_settings['label']} 访问失败：{_provider_error_detail(str(exc))}",
                    model=model,
                    base_url=provider_settings.get("base_url"),
                )
                errors.append(f"{provider_settings['label']} {model}: {exc}")

    if not has_external_provider:
        return _no_external_provider_result("chat")
    return _provider_failure_result(errors, "chat")


def _call_dashboard_overlay(
    payload: dict[str, Any],
    preferred_model: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    raw = _call_llm_json(
        preferred_model=preferred_model,
        system_prompt=_dashboard_system_prompt(),
        user_prompt=_dashboard_user_prompt(payload),
        max_tokens=1600,
        temperature=0.2,
        max_model_attempts=1,
        salvage_parser=None,
        ai_request_config=ai_request_config,
    )
    if not raw.get("ok"):
        return raw
    parsed = raw.get("parsed") or {}
    return {
        "ok": True,
        "headline": str(parsed.get("headline") or "").strip(),
        "deep_summary": str(parsed.get("deep_summary") or "").strip(),
        "cards": _normalize_cards(parsed.get("cards")),
        "playbook": _normalize_playbook(parsed.get("playbook")),
        "sections": _normalize_sections(parsed.get("sections"), limit=3),
        "position_actions": _normalize_position_actions(parsed.get("position_actions")),
        "engine": raw.get("engine"),
    }


def _call_stock_detail_overlay(
    payload: dict[str, Any],
    preferred_model: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    raw = _call_llm_json(
        preferred_model=preferred_model,
        system_prompt=_stock_detail_system_prompt(),
        user_prompt=_stock_detail_user_prompt(payload),
        max_tokens=1500,
        temperature=0.05,
        max_model_attempts=1,
        salvage_parser=_salvage_stock_detail_output,
        ai_request_config=ai_request_config,
    )
    if not raw.get("ok"):
        return raw
    parsed = raw.get("parsed") or {}
    return {
        "ok": True,
        "headline": str(parsed.get("headline") or "").strip(),
        "deep_summary": str(parsed.get("deep_summary") or "").strip(),
        "executive_summary": _normalize_text_rows(parsed.get("executive_summary"), limit=4, max_len=180),
        "sections": _normalize_sections(parsed.get("sections"), limit=3),
        "bull_case": _normalize_text_rows(parsed.get("bull_case"), limit=3, max_len=180),
        "bear_case": _normalize_text_rows(parsed.get("bear_case"), limit=3, max_len=180),
        "watchlist": _normalize_text_rows(parsed.get("watchlist"), limit=4, max_len=180),
        "action_plan": _normalize_text_rows(parsed.get("action_plan"), limit=4, max_len=200),
        "engine": raw.get("engine"),
    }


def _normalize_chat_messages(messages: list[dict[str, Any]] | None, limit: int = 12) -> list[dict[str, str]]:
    normalized: list[dict[str, str]] = []
    for row in messages or []:
        role = str(row.get("role") or "").strip().lower()
        content = str(row.get("content") or "").strip()
        if role not in {"user", "assistant"} or not content:
            continue
        content = content[:1600]
        if normalized and normalized[-1]["role"] == role:
            normalized[-1]["content"] = f"{normalized[-1]['content']}\n\n{content}"[:2400]
        else:
            normalized.append({"role": role, "content": content})
    return normalized[-limit:]


def _chat_system_prompt(context_payload: dict[str, Any]) -> str:
    context_type = context_payload.get("context_type") or "dashboard"
    title = context_payload.get("context_title") or "MyInvAI"
    return (
        "你是 MyInvAI 里的资深买方研究员兼组合经理助理。"
        "你必须只基于给定上下文回答，不能编造新的持仓、价格、新闻、财报、宏观数据或交易。"
        "如果上下文不足以支持结论，必须直接说“当前上下文不足，建议刷新数据或补充问题范围”。"
        "语言使用简体中文，输出不使用 Markdown 表格。"
        "答案要直接、可执行、围绕仓位、催化、风险传导、验证点和下一步动作。"
        "优先回答用户真正关心的判断，不要复读上下文。"
        f"当前会话上下文类型：{context_type}。上下文标题：{title}。"
    )


def _local_chat_fallback_reply(context_payload: dict[str, Any]) -> str:
    if (context_payload.get("context_type") or "dashboard") == "holding":
        action_plan = context_payload.get("action_plan") or []
        watchlist = context_payload.get("watchlist") or []
        hero = context_payload.get("hero") or {}
        opening = f"当前未连上外部大模型，先按 {hero.get('name') or hero.get('symbol') or '该持仓'} 的现有结构化分析回答。"
        focus = action_plan[0] if action_plan else "先确认仓位动作、趋势状态和验证点是否一致。"
        watch = watchlist[0] if watchlist else "优先盯基本面验证点、趋势是否破坏，以及风险预算是否超标。"
        return f"{opening}{focus} 另外，{watch}"

    priority_actions = context_payload.get("priority_actions") or []
    holding_notes = context_payload.get("holding_notes") or []
    opening = "当前未连上外部大模型，先按组合里已有规则结论给出回答。"
    action = ""
    if priority_actions:
        action = str(priority_actions[0].get("title") or "").strip()
    note = ""
    if holding_notes:
        top_holding = holding_notes[0]
        note = f"{top_holding.get('symbol') or top_holding.get('name')} 当前处理意见是 {top_holding.get('stance') or '继续跟踪'}。"
    return f"{opening}{action or '先处理头部风险和仓位集中度。'} {note}".strip()


def generate_chat_reply(
    context_payload: dict[str, Any],
    messages: list[dict[str, Any]] | None,
    preferred_model: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    normalized_messages = _normalize_chat_messages(messages)
    if not normalized_messages:
        return {
            "reply": "可以直接问组合今天最该先处理什么、某只持仓为什么该加减仓，或让 AI 给出更细的执行框架。",
            "engine": {
                "mode": "rules",
                "provider": "local",
                "model": None,
                "label": "对话待开始",
            },
            "status_message": "等待你的问题。",
        }

    context_intro = json.dumps(context_payload, ensure_ascii=False, sort_keys=True)
    llm_messages = [
        {
            "role": "user",
            "content": (
                "以下是当前投资上下文，请你后续回答只能基于这些信息。"
                "如果用户问到上下文里没有的事实，请明确说明不知道，不要补造。\n"
                f"{context_intro}"
            ),
        },
        {
            "role": "assistant",
            "content": "已收到当前投资上下文，我会只基于这些信息回答，并尽量给出可执行的判断。",
        },
        *normalized_messages,
    ]
    raw = _call_llm_text(
        preferred_model=preferred_model,
        system_prompt=_chat_system_prompt(context_payload),
        messages=llm_messages,
        max_tokens=1400,
        temperature=0.2,
        max_model_attempts=1,
        ai_request_config=ai_request_config,
    )
    if raw.get("ok"):
        return {
            "reply": str(raw.get("reply") or "").strip(),
            "engine": raw.get("engine"),
            "status_message": "AI 已基于当前上下文完成回复。",
        }

    return {
        "reply": _local_chat_fallback_reply(context_payload),
        "engine": raw.get("engine"),
        "status_message": (raw.get("engine") or {}).get("note") or "AI 对话暂不可用。",
    }


def generate_ai_overlay(
    payload: dict[str, Any],
    preferred_model: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    key = _cache_key(payload, preferred_model, "dashboard", ai_request_config=ai_request_config)
    with AI_LOCK:
        cached = AI_CACHE.get("payload")
        if cached and AI_CACHE.get("key") == key and (time.time() - AI_CACHE.get("timestamp", 0.0)) < AI_CACHE_TTL_SECONDS:
            return cached

    result = _call_dashboard_overlay(payload, preferred_model=preferred_model, ai_request_config=ai_request_config)
    with AI_LOCK:
        AI_CACHE["key"] = key
        AI_CACHE["timestamp"] = time.time()
        AI_CACHE["payload"] = result
    return result


def generate_stock_detail_overlay(
    payload: dict[str, Any],
    preferred_model: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    key = _cache_key(payload, preferred_model, "stock_detail", ai_request_config=ai_request_config)
    with AI_LOCK:
        cached = AI_CACHE.get("payload")
        if cached and AI_CACHE.get("key") == key and (time.time() - AI_CACHE.get("timestamp", 0.0)) < AI_CACHE_TTL_SECONDS:
            return cached

    result = _call_stock_detail_overlay(payload, preferred_model=preferred_model, ai_request_config=ai_request_config)
    with AI_LOCK:
        AI_CACHE["key"] = key
        AI_CACHE["timestamp"] = time.time()
        AI_CACHE["payload"] = result
    return result
