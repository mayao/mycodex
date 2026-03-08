#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

try:
    from portfolio_analytics import build_dashboard_payload, validate_payload
except ModuleNotFoundError:
    from market_dashboard.portfolio_analytics import build_dashboard_payload, validate_payload


BASE_DIR = Path(__file__).resolve().parent
HTML_PATH = BASE_DIR / "dashboard.html"


def load_html() -> str:
    return HTML_PATH.read_text(encoding="utf-8")


class DashboardHandler(BaseHTTPRequestHandler):
    def _send_bytes(
        self,
        body: bytes,
        content_type: str,
        status: HTTPStatus = HTTPStatus.OK,
    ) -> None:
        try:
            self.send_response(status.value)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            return

    def _send_html(self, html_text: str, status: HTTPStatus = HTTPStatus.OK) -> None:
        self._send_bytes(html_text.encode("utf-8"), "text/html; charset=utf-8", status=status)

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send_bytes(body, "application/json; charset=utf-8", status=status)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            self._send_html(load_html())
            return
        if path == "/favicon.ico":
            self._send_bytes(b"", "image/x-icon", status=HTTPStatus.NO_CONTENT)
            return
        if path == "/api/market-data":
            force_refresh = "refresh=1" in self.path
            self._send_json(build_dashboard_payload(force_refresh=force_refresh, include_live=True))
            return
        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: Any) -> None:
        return


def run_check() -> int:
    payload = build_dashboard_payload(force_refresh=True, include_live=False)
    errors = validate_payload(payload)
    summary = payload["summary"]

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
    if errors:
        print(f"Overall: FAIL ({'; '.join(errors)})")
        return 1
    print("Overall: PASS")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Personal portfolio workbench")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8008, help="Bind port (default: 8008)")
    parser.add_argument("--check", action="store_true", help="Run local validation and exit")
    args = parser.parse_args()

    if args.check:
        raise SystemExit(run_check())

    server = ThreadingHTTPServer((args.host, args.port), DashboardHandler)
    print(f"Dashboard is running at http://{args.host}:{args.port}")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
