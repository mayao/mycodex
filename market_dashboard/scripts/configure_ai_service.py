#!/usr/bin/env python3
from __future__ import annotations

import argparse
import getpass
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from market_dashboard.service_ai_config import (  # noqa: E402
    default_service_ai_config_path,
    default_service_ai_request_config,
    infer_kimi_preset,
    kimi_preset_defaults,
    load_service_ai_request_config,
    write_service_ai_request_config,
)


PROVIDERS = ("anthropic", "kimi", "gemini")
KIMI_PRESETS = ("moonshot", "kimi_coding")


def _mask_secret(value: str) -> str:
    trimmed = value.strip()
    if not trimmed:
        return "未配置"
    if len(trimmed) <= 8:
        return "*" * len(trimmed)
    return f"{trimmed[:4]}...{trimmed[-4:]}"


def _prompt_text(label: str, current: str, *, allow_empty: bool = True) -> str:
    suffix = f" [{current}]" if current else ""
    while True:
        value = input(f"{label}{suffix}: ").strip()
        if value:
            return value
        if current or allow_empty:
            return current


def _prompt_bool(label: str, current: bool) -> bool:
    current_label = "Y/n" if current else "y/N"
    while True:
        value = input(f"{label} ({current_label}): ").strip().lower()
        if not value:
            return current
        if value in {"y", "yes", "1", "true"}:
            return True
        if value in {"n", "no", "0", "false"}:
            return False


def _prompt_secret(label: str, current: str) -> str:
    masked = _mask_secret(current)
    value = getpass.getpass(f"{label} [{masked}]，回车保留，输入 !clear 清空: ").strip()
    if not value:
        return current
    if value == "!clear":
        return ""
    return value


def _provider_row(config: dict[str, object], provider: str) -> dict[str, str]:
    for row in config.get("providers", []):
        if isinstance(row, dict) and row.get("provider") == provider:
            return row  # type: ignore[return-value]
    next_row = {"provider": provider, "model": "", "api_key": "", "base_url": "", "preset": ""}
    config.setdefault("providers", []).append(next_row)
    return next_row


def _apply_kimi_preset_defaults(row: dict[str, str]) -> None:
    preset = infer_kimi_preset(
        row.get("preset"),
        base_url=row.get("base_url"),
        model=row.get("model"),
    )
    defaults = kimi_preset_defaults(preset)
    row["preset"] = preset
    if not str(row.get("model") or "").strip():
        row["model"] = defaults["model"]
    if not str(row.get("base_url") or "").strip():
        row["base_url"] = defaults["base_url"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create or update market_dashboard/config/service_ai_config.json")
    parser.add_argument("--path", help="Override output path")
    parser.add_argument("--primary-provider", choices=PROVIDERS)
    parser.add_argument("--enable-fallbacks", action="store_true")
    parser.add_argument("--disable-fallbacks", action="store_true")
    parser.add_argument("--non-interactive", action="store_true")
    parser.add_argument("--print", action="store_true", dest="print_only")
    for provider in PROVIDERS:
        if provider == "kimi":
            parser.add_argument("--kimi-preset", choices=KIMI_PRESETS)
        parser.add_argument(f"--{provider}-model")
        parser.add_argument(f"--{provider}-key")
        parser.add_argument(f"--clear-{provider}-key", action="store_true")
        parser.add_argument(f"--{provider}-base-url")
    return parser.parse_args()


def apply_args(config: dict[str, object], args: argparse.Namespace) -> None:
    if args.primary_provider:
        config["primary_provider"] = args.primary_provider
    if args.enable_fallbacks:
        config["enable_fallbacks"] = True
    if args.disable_fallbacks:
        config["enable_fallbacks"] = False

    for provider in PROVIDERS:
        row = _provider_row(config, provider)
        if provider == "kimi" and args.kimi_preset:
            row["preset"] = args.kimi_preset
        model = getattr(args, f"{provider}_model")
        key = getattr(args, f"{provider}_key")
        clear_key = getattr(args, f"clear_{provider}_key")
        base_url = getattr(args, f"{provider}_base_url")
        if model is not None:
            row["model"] = model.strip()
        if key is not None:
            row["api_key"] = key.strip()
        if clear_key:
            row["api_key"] = ""
        if base_url is not None:
            row["base_url"] = base_url.strip()
        if provider == "kimi":
            _apply_kimi_preset_defaults(row)


def interactive_update(config: dict[str, object]) -> None:
    current_primary = str(config.get("primary_provider") or "anthropic")
    config["primary_provider"] = _prompt_text("首选 provider (anthropic/kimi/gemini)", current_primary, allow_empty=False)
    config["enable_fallbacks"] = _prompt_bool("首选失败时自动回退", bool(config.get("enable_fallbacks", True)))

    for provider in PROVIDERS:
        row = _provider_row(config, provider)
        print(f"\n[{provider}]")
        if provider == "kimi":
            row["preset"] = _prompt_text(
                "Kimi 接入模式 (moonshot/kimi_coding)",
                infer_kimi_preset(row.get("preset"), base_url=row.get("base_url"), model=row.get("model")),
                allow_empty=False,
            )
            row["model"] = ""
            row["base_url"] = ""
            _apply_kimi_preset_defaults(row)
            print(
                f"已套用 {row['preset']} 预设：model={row.get('model') or '(空)'} "
                f"base_url={row.get('base_url') or '(空)'}"
            )
        row["model"] = _prompt_text("模型 ID", str(row.get("model") or ""))
        if provider in {"kimi", "gemini"}:
            row["base_url"] = _prompt_text("Base URL", str(row.get("base_url") or ""))
        row["api_key"] = _prompt_secret("API Key", str(row.get("api_key") or ""))


def main() -> int:
    args = parse_args()
    config = load_service_ai_request_config(args.path) or default_service_ai_request_config()
    apply_args(config, args)
    if not args.non_interactive:
        interactive_update(config)

    if args.print_only:
        print(config)
        return 0

    target_path = write_service_ai_request_config(config, args.path)
    print(f"AI 服务配置已写入: {target_path}")
    print(f"首选 provider: {config.get('primary_provider')}")
    print(f"自动回退: {'开启' if config.get('enable_fallbacks') else '关闭'}")
    for provider in PROVIDERS:
        row = _provider_row(config, provider)
        preset_text = f" preset={row.get('preset')}" if provider == "kimi" and row.get("preset") else ""
        print(
            f"- {provider}:{preset_text} model={row.get('model') or '(空)'} "
            f"key={_mask_secret(str(row.get('api_key') or ''))} "
            f"base_url={row.get('base_url') or '(默认)'}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
