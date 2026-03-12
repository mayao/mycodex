from __future__ import annotations

import json
import os
import re
import threading
import time
from hashlib import sha1
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
REQUEST_TIMEOUT_SECONDS = 40.0
AI_CACHE_TTL_SECONDS = 900
AI_CACHE: dict[str, Any] = {"key": "", "timestamp": 0.0, "payload": None}
AI_LOCK = threading.Lock()
DEFAULT_ANTHROPIC_MODELS = (
    "claude-sonnet-4-20250514",
    "claude-sonnet-4-5-20250929",
    "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
    "claude-3-haiku-20240307",
)


def _cache_key(payload: dict[str, Any], preferred_model: str | None, mode: str) -> str:
    raw = json.dumps({"payload": payload, "preferred_model": preferred_model, "mode": mode}, ensure_ascii=False, sort_keys=True)
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


def _candidate_models(preferred_model: str | None) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    raw_candidates = (
        os.getenv("MARKET_DASHBOARD_AI_MODEL_CANDIDATES")
        or os.getenv("ANTHROPIC_MODEL_CANDIDATES")
        or ""
    )
    values = [
        preferred_model,
        os.getenv("MARKET_DASHBOARD_AI_MODEL"),
        os.getenv("ANTHROPIC_MODEL"),
        *[item.strip() for item in raw_candidates.split(",") if item.strip()],
        *DEFAULT_ANTHROPIC_MODELS,
    ]
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


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


def _call_anthropic_json(
    *,
    payload: dict[str, Any],
    preferred_model: str | None,
    system_prompt: str,
    user_prompt: str,
    max_tokens: int,
    temperature: float,
    max_model_attempts: int | None = None,
    salvage_parser: Any | None = None,
) -> dict[str, Any]:
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        return {
            "ok": False,
            "engine": {
                "mode": "rules",
                "provider": "local",
                "model": None,
                "label": "本地规则引擎",
                "note": "未检测到外部大模型密钥，已回退为本地结构化规则引擎。",
            },
        }

    configured_model = preferred_model or os.getenv("MARKET_DASHBOARD_AI_MODEL") or os.getenv("ANTHROPIC_MODEL")
    errors: list[str] = []
    candidate_models = _candidate_models(preferred_model)
    if max_model_attempts is not None:
        candidate_models = candidate_models[:max_model_attempts]
    for model in candidate_models:
        request_body = json.dumps(
            {
                "model": model,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "system": system_prompt,
                "messages": [{"role": "user", "content": user_prompt}],
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
        try:
            started_at = time.time()
            with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                response_payload = json.loads(response.read().decode("utf-8"))
            content = response_payload.get("content") or []
            text = "\n".join(
                block.get("text", "")
                for block in content
                if isinstance(block, dict) and block.get("type") == "text"
            ).strip()
            cleaned_text = _clean_json_text(text)
            try:
                parsed = json.loads(cleaned_text)
            except json.JSONDecodeError:
                if salvage_parser:
                    parsed = salvage_parser(cleaned_text)
                    if parsed:
                        return {
                            "ok": True,
                            "parsed": parsed,
                            "engine": {
                                "mode": "llm",
                                "provider": "anthropic",
                                "model": response_payload.get("model") or model,
                                "label": f"Anthropic {response_payload.get('model') or model}",
                                "latency_ms": int((time.time() - started_at) * 1000),
                                "note": "外部大模型已返回结果，原始 JSON 存在轻微格式问题，系统已自动容错解析。",
                            },
                        }
                raise
            return {
                "ok": True,
                "parsed": parsed,
                "engine": {
                    "mode": "llm",
                    "provider": "anthropic",
                    "model": response_payload.get("model") or model,
                    "label": f"Anthropic {response_payload.get('model') or model}",
                    "latency_ms": int((time.time() - started_at) * 1000),
                    "note": (
                        "先用本地结构化框架整理上下文，再由外部大模型生成深度诊断与执行建议。"
                        if configured_model
                        else "未显式配置模型名，系统已自动探测可用 Claude 模型并生成深度诊断。"
                    ),
                },
            }
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError, ValueError, OSError, Exception) as exc:
            errors.append(f"{model}: {exc}")

    return {
        "ok": False,
        "engine": {
            "mode": "rules",
            "provider": "local",
            "model": None,
            "label": "本地规则引擎",
            "note": "外部大模型调用失败，已自动回退为本地规则引擎。",
            "errors": errors,
        },
    }


def _call_anthropic_text(
    *,
    preferred_model: str | None,
    system_prompt: str,
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float,
) -> dict[str, Any]:
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        return {
            "ok": False,
            "engine": {
                "mode": "rules",
                "provider": "local",
                "model": None,
                "label": "本地规则引擎",
                "note": "未检测到外部大模型密钥，无法发起自由对话。",
            },
        }

    configured_model = preferred_model or os.getenv("MARKET_DASHBOARD_AI_MODEL") or os.getenv("ANTHROPIC_MODEL")
    errors: list[str] = []
    for model in _candidate_models(preferred_model):
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
        try:
            started_at = time.time()
            with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                response_payload = json.loads(response.read().decode("utf-8"))
            content = response_payload.get("content") or []
            text = "\n".join(
                block.get("text", "")
                for block in content
                if isinstance(block, dict) and block.get("type") == "text"
            ).strip()
            if not text:
                raise ValueError("empty response")
            return {
                "ok": True,
                "reply": text,
                "engine": {
                    "mode": "llm",
                    "provider": "anthropic",
                    "model": response_payload.get("model") or model,
                    "label": f"Anthropic {response_payload.get('model') or model}",
                    "latency_ms": int((time.time() - started_at) * 1000),
                    "note": (
                        "自由对话走当前已配置的大模型。"
                        if configured_model
                        else "未显式配置模型名，系统已自动探测可用 Claude 模型。"
                    ),
                },
            }
        except (HTTPError, URLError, TimeoutError, ValueError, OSError, Exception) as exc:
            errors.append(f"{model}: {exc}")

    return {
        "ok": False,
        "engine": {
            "mode": "rules",
            "provider": "local",
            "model": None,
            "label": "本地规则引擎",
            "note": "外部大模型调用失败，当前无法继续自由对话。",
            "errors": errors,
        },
    }


def _call_dashboard_overlay(payload: dict[str, Any], preferred_model: str | None = None) -> dict[str, Any]:
    raw = _call_anthropic_json(
        payload=payload,
        preferred_model=preferred_model,
        system_prompt=_dashboard_system_prompt(),
        user_prompt=_dashboard_user_prompt(payload),
        max_tokens=1600,
        temperature=0.2,
        max_model_attempts=None,
        salvage_parser=None,
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


def _call_stock_detail_overlay(payload: dict[str, Any], preferred_model: str | None = None) -> dict[str, Any]:
    raw = _call_anthropic_json(
        payload=payload,
        preferred_model=preferred_model,
        system_prompt=_stock_detail_system_prompt(),
        user_prompt=_stock_detail_user_prompt(payload),
        max_tokens=1500,
        temperature=0.05,
        max_model_attempts=1,
        salvage_parser=_salvage_stock_detail_output,
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
    anthropic_messages = [
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
    raw = _call_anthropic_text(
        preferred_model=preferred_model,
        system_prompt=_chat_system_prompt(context_payload),
        messages=anthropic_messages,
        max_tokens=1400,
        temperature=0.2,
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


def generate_ai_overlay(payload: dict[str, Any], preferred_model: str | None = None) -> dict[str, Any]:
    key = _cache_key(payload, preferred_model, "dashboard")
    with AI_LOCK:
        cached = AI_CACHE.get("payload")
        if cached and AI_CACHE.get("key") == key and (time.time() - AI_CACHE.get("timestamp", 0.0)) < AI_CACHE_TTL_SECONDS:
            return cached

    result = _call_dashboard_overlay(payload, preferred_model=preferred_model)
    with AI_LOCK:
        AI_CACHE["key"] = key
        AI_CACHE["timestamp"] = time.time()
        AI_CACHE["payload"] = result
    return result


def generate_stock_detail_overlay(payload: dict[str, Any], preferred_model: str | None = None) -> dict[str, Any]:
    key = _cache_key(payload, preferred_model, "stock_detail")
    with AI_LOCK:
        cached = AI_CACHE.get("payload")
        if cached and AI_CACHE.get("key") == key and (time.time() - AI_CACHE.get("timestamp", 0.0)) < AI_CACHE_TTL_SECONDS:
            return cached

    result = _call_stock_detail_overlay(payload, preferred_model=preferred_model)
    with AI_LOCK:
        AI_CACHE["key"] = key
        AI_CACHE["timestamp"] = time.time()
        AI_CACHE["payload"] = result
    return result
