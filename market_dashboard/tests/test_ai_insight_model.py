import json
import os
import tempfile
import unittest
from pathlib import Path

from market_dashboard import ai_insight_model


class AIInsightModelTests(unittest.TestCase):
    def test_kimi_coding_preset_keeps_compatible_endpoint(self) -> None:
        resolved = ai_insight_model._resolved_ai_request_config(
            {
                "primary_provider": "kimi",
                "enable_fallbacks": True,
                "providers": [
                    {
                        "provider": "kimi",
                        "preset": "kimi_coding",
                        "api_key": "service-kimi-key",
                    }
                ],
            }
        )

        kimi = resolved["providers"]["kimi"]
        self.assertEqual(kimi["preset"], "kimi_coding")
        self.assertEqual(kimi["model"], "kimi-for-coding")
        self.assertEqual(kimi["base_url"], "https://api.kimi.com/coding/v1")

    def test_request_configured_model_is_tried_once_per_provider(self) -> None:
        request_config = {
            "primary_provider": "anthropic",
            "enable_fallbacks": True,
            "providers": [
                {
                    "provider": "anthropic",
                    "model": "claude-picked-by-user",
                    "api_key": "anthropic-key",
                },
                {
                    "provider": "kimi",
                    "model": "moonshot-picked-by-user",
                    "api_key": "kimi-key",
                },
            ],
        }

        anthropic = ai_insight_model._provider_runtime_settings(
            "anthropic",
            ai_request_config=request_config,
        )
        kimi = ai_insight_model._provider_runtime_settings(
            "kimi",
            ai_request_config=request_config,
        )

        self.assertIsNotNone(anthropic)
        self.assertEqual(anthropic["candidate_models"], ["claude-picked-by-user"])
        self.assertIsNotNone(kimi)
        self.assertEqual(kimi["candidate_models"], ["moonshot-picked-by-user"])

    def test_failure_note_surfaces_network_hint(self) -> None:
        result = ai_insight_model._provider_failure_result(
            ["Claude claude-sonnet: <urlopen error timed out>"],
            "chat",
        )

        note = result["engine"]["note"]
        self.assertIn("Claude claude-sonnet", note)
        self.assertIn("外网链路可能不通", note)

    def test_service_config_merges_with_request_preference(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            config_path = Path(tmp_dir) / "service_ai_config.json"
            config_path.write_text(
                json.dumps(
                    {
                        "primary_provider": "kimi",
                        "enable_fallbacks": True,
                        "providers": [
                            {
                                "provider": "anthropic",
                                "model": "claude-from-service",
                                "api_key": "service-anthropic-key",
                            },
                            {
                                "provider": "kimi",
                                "model": "moonshot-from-service",
                                "api_key": "service-kimi-key",
                            },
                        ],
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            previous_path = os.environ.get("MARKET_DASHBOARD_AI_CONFIG_PATH")
            os.environ["MARKET_DASHBOARD_AI_CONFIG_PATH"] = str(config_path)
            try:
                resolved = ai_insight_model._resolved_ai_request_config(
                    {
                        "primary_provider": "anthropic",
                        "enable_fallbacks": True,
                        "providers": [
                            {
                                "provider": "anthropic",
                                "model": "claude-from-request",
                            }
                        ],
                    }
                )
            finally:
                if previous_path is None:
                    os.environ.pop("MARKET_DASHBOARD_AI_CONFIG_PATH", None)
                else:
                    os.environ["MARKET_DASHBOARD_AI_CONFIG_PATH"] = previous_path

        self.assertEqual(resolved["primary_provider"], "anthropic")
        self.assertEqual(resolved["providers"]["anthropic"]["model"], "claude-from-request")
        self.assertEqual(resolved["providers"]["anthropic"]["api_key"], "service-anthropic-key")
        self.assertEqual(resolved["providers"]["kimi"]["api_key"], "service-kimi-key")

    def test_service_status_reports_ready_provider(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            config_path = Path(tmp_dir) / "service_ai_config.json"
            config_path.write_text(
                json.dumps(
                    {
                        "primary_provider": "kimi",
                        "enable_fallbacks": True,
                        "providers": [
                            {
                                "provider": "kimi",
                                "preset": "kimi_coding",
                                "api_key": "service-kimi-key",
                            }
                        ],
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            previous_path = os.environ.get("MARKET_DASHBOARD_AI_CONFIG_PATH")
            os.environ["MARKET_DASHBOARD_AI_CONFIG_PATH"] = str(config_path)
            try:
                payload = ai_insight_model.get_ai_service_status(
                    {
                        "primary_provider": "kimi",
                        "enable_fallbacks": True,
                        "providers": [{"provider": "kimi", "model": "kimi-for-coding"}],
                    }
                )
            finally:
                if previous_path is None:
                    os.environ.pop("MARKET_DASHBOARD_AI_CONFIG_PATH", None)
                else:
                    os.environ["MARKET_DASHBOARD_AI_CONFIG_PATH"] = previous_path

        kimi = next(item for item in payload["providers"] if item["provider"] == "kimi")
        self.assertEqual(payload["primary_provider"], "kimi")
        self.assertEqual(kimi["credential_source"], "service_config")
        self.assertEqual(kimi["access_state"], "ready")
        self.assertEqual(kimi["preset"], "kimi_coding")


if __name__ == "__main__":
    unittest.main()
