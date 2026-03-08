#!/usr/bin/env python3
from __future__ import annotations

import argparse
import cgi
import json
import re
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

try:
    from portfolio_analytics import build_dashboard_payload, validate_payload
    from statement_sources import (
        UPLOADS_DIR,
        get_uploaded_statement_overrides,
        get_statement_source_by_account,
        register_uploaded_statement,
        remove_uploaded_statement,
    )
except ModuleNotFoundError:
    from market_dashboard.portfolio_analytics import build_dashboard_payload, validate_payload
    from market_dashboard.statement_sources import (
        UPLOADS_DIR,
        get_uploaded_statement_overrides,
        get_statement_source_by_account,
        register_uploaded_statement,
        remove_uploaded_statement,
    )


BASE_DIR = Path(__file__).resolve().parent
HTML_PATH = BASE_DIR / "dashboard.html"
MAX_UPLOAD_BYTES = 40 * 1024 * 1024


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
            try:
                payload = build_dashboard_payload(force_refresh=force_refresh, include_live=True)
            except Exception as exc:  # noqa: BLE001
                self._send_json({"error": f"工作台数据生成失败：{exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            self._send_json(payload)
            return
        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/api/upload-statement":
            self._handle_statement_upload()
            return
        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def _handle_statement_upload(self) -> None:
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
        account_id = (form.getfirst("account_id") or "").strip()
        file_item = form["statement_file"] if "statement_file" in form else None
        source = get_statement_source_by_account(account_id) if account_id else None
        if source is None:
            self._send_json({"error": "请选择要替换结单的账户。"}, status=HTTPStatus.BAD_REQUEST)
            return
        if file_item is None or not getattr(file_item, "filename", ""):
            self._send_json({"error": "请选择要上传的结单 PDF。"}, status=HTTPStatus.BAD_REQUEST)
            return

        UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
        original_name = Path(file_item.filename).name
        safe_name = re.sub(r"[\\/]+", "_", original_name).strip() or "statement.pdf"
        account_dir = UPLOADS_DIR / account_id
        account_dir.mkdir(parents=True, exist_ok=True)
        stored_path = account_dir / safe_name
        with stored_path.open("wb") as handle:
            handle.write(file_item.file.read())

        previous_override = get_uploaded_statement_overrides().get(account_id)
        try:
            register_uploaded_statement(account_id, str(stored_path), safe_name)
            payload = build_dashboard_payload(
                force_refresh=True,
                include_live=True,
                allow_cached_fallback=False,
                strict_account_ids={account_id},
            )
        except Exception as exc:  # noqa: BLE001
            if previous_override:
                register_uploaded_statement(
                    account_id,
                    previous_override["path"],
                    previous_override.get("uploaded_file_name") or Path(previous_override["path"]).name,
                )
            else:
                remove_uploaded_statement(account_id)
            try:
                stored_path.unlink()
            except OSError:
                pass
            self._send_json({"error": f"结单已上传，但解析失败：{exc}"}, status=HTTPStatus.BAD_REQUEST)
            return

        self._send_json(
            {
                "message": f"{source['broker']} / {account_id} 的新结单已接入并刷新。",
                "payload": payload,
            }
        )

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
