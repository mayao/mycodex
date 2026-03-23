from __future__ import annotations

import io
import math
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape

try:
    from mobile_api import build_mobile_dashboard_payload
except ModuleNotFoundError:
    from market_dashboard.mobile_api import build_mobile_dashboard_payload

try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:  # noqa: BLE001
    Image = None
    ImageDraw = None
    ImageFont = None


CN_TZ = timezone(timedelta(hours=8))
_FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/Library/Fonts/Arial Unicode.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJKSC-Regular.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def _safe_float(value: Any) -> float | None:
    try:
        if value is None or value == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _format_number(value: float | None, digits: int = 2) -> str:
    if value is None:
        return "-"
    return f"{value:,.{digits}f}"


def _format_hkd(value: float | None) -> str:
    if value is None:
        return "-"
    return f"HK${value:,.2f}"


def _format_signed_hkd(value: float | None) -> str:
    if value is None:
        return "-"
    sign = "+" if value > 0 else "-" if value < 0 else ""
    return f"{sign}HK${abs(value):,.2f}"


def _format_pct(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.2f}%"


def _format_timestamp_cn(value: str | None) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    try:
        normalized = text.replace("Z", "+00:00")
        dt = datetime.fromisoformat(normalized)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(CN_TZ).strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return text


def _pnl_source_label(value: Any) -> str:
    raw = str(value or "").strip()
    if raw == "statement":
        return "结单原值"
    if raw == "estimated":
        return "估算"
    if raw == "mixed":
        return "结单+估算"
    if raw == "unavailable":
        return "不可计算"
    return raw or "-"


def _truncate(value: Any, limit: int) -> str:
    text = str(value or "")
    if len(text) <= limit:
        return text
    if limit <= 1:
        return text[:limit]
    return text[: limit - 1] + "…"


def build_holdings_export_dataset(
    *,
    force_refresh: bool = False,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = build_mobile_dashboard_payload(
        force_refresh=force_refresh,
        include_live=True,
        allow_cached_fallback=True,
        include_ai=False,
        user_id=user_id,
        ai_request_config=ai_request_config,
    )

    positions = list(payload.get("positions") or [])
    positions.sort(key=lambda row: float(row.get("statement_value_hkd") or 0.0), reverse=True)
    recent_trades = list(payload.get("recent_trades") or [])

    holdings_rows: list[dict[str, Any]] = []
    total_market_value_hkd = 0.0
    total_pnl_hkd = 0.0
    total_cost_hkd = 0.0
    calculable_position_count = 0

    for item in positions:
        market_value_hkd = _safe_float(item.get("statement_value_hkd")) or 0.0
        pnl_hkd = _safe_float(item.get("statement_pnl_hkd"))
        pnl_pct = _safe_float(item.get("statement_pnl_pct"))
        quantity = _safe_float(item.get("quantity"))
        total_market_value_hkd += market_value_hkd
        if pnl_hkd is not None:
            total_pnl_hkd += pnl_hkd
            total_cost_hkd += market_value_hkd - pnl_hkd
            calculable_position_count += 1

        holdings_rows.append(
            {
                "symbol": str(item.get("symbol") or ""),
                "name": str(item.get("name") or ""),
                "market": str(item.get("market") or ""),
                "currency": str(item.get("currency") or ""),
                "quantity": quantity,
                "statement_value_hkd": market_value_hkd,
                "statement_pnl_hkd": pnl_hkd,
                "statement_pnl_pct": pnl_pct,
                "category_name": str(item.get("category_name") or ""),
                "pnl_source": str(item.get("pnl_source") or ""),
                "account_count": int(item.get("account_count") or 0),
            }
        )

    total_pnl_pct = (total_pnl_hkd / total_cost_hkd * 100.0) if total_cost_hkd > 0 else None
    export_time = datetime.now(CN_TZ)
    export_time_cn = export_time.strftime("%Y-%m-%d %H:%M")

    trade_rows = [
        {
            "date": str(item.get("date") or ""),
            "side": str(item.get("side") or ""),
            "symbol": str(item.get("symbol") or ""),
            "name": str(item.get("name") or ""),
            "quantity": _safe_float(item.get("quantity")),
            "price": _safe_float(item.get("price")),
            "currency": str(item.get("currency") or ""),
            "broker": str(item.get("broker") or ""),
            "account_id": str(item.get("account_id") or ""),
        }
        for item in recent_trades
    ]

    return {
        "generated_at": str(payload.get("generated_at") or export_time.isoformat()),
        "generated_at_cn": _format_timestamp_cn(payload.get("generated_at")) or export_time_cn,
        "snapshot_date": str(payload.get("snapshot_date") or ""),
        "analysis_date_cn": str(payload.get("analysis_date_cn") or ""),
        "exported_at_cn": export_time_cn,
        "summary": {
            "holding_count": len(holdings_rows),
            "trade_count": len(trade_rows),
            "total_market_value_hkd": round(total_market_value_hkd, 2),
            "total_pnl_hkd": round(total_pnl_hkd, 2),
            "total_cost_hkd": round(total_cost_hkd, 2),
            "total_pnl_pct": round(total_pnl_pct, 2) if total_pnl_pct is not None else None,
            "calculable_position_count": calculable_position_count,
            "position_count": len(holdings_rows),
        },
        "holdings": holdings_rows,
        "recent_trades": trade_rows,
    }


def _sheet_xml(rows: list[list[str]], widths: list[int] | None = None) -> str:
    row_xml: list[str] = []
    for row_index, row in enumerate(rows, start=1):
        cell_xml: list[str] = []
        for col_index, value in enumerate(row, start=1):
            ref = f"{_excel_col_name(col_index)}{row_index}"
            escaped = escape(str(value or ""))
            style_attr = ' s="1"' if row_index == 1 else ""
            cell_xml.append(
                f'<c r="{ref}" t="inlineStr"{style_attr}><is><t xml:space="preserve">{escaped}</t></is></c>'
            )
        row_xml.append(f'<row r="{row_index}">{"".join(cell_xml)}</row>')

    cols_xml = ""
    if widths:
        pieces = [
            f'<col min="{idx}" max="{idx}" width="{width}" customWidth="1"/>'
            for idx, width in enumerate(widths, start=1)
        ]
        cols_xml = f"<cols>{''.join(pieces)}</cols>"

    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        "<sheetViews><sheetView workbookViewId=\"0\"/></sheetViews>"
        f"{cols_xml}"
        f"<sheetData>{''.join(row_xml)}</sheetData>"
        "</worksheet>"
    )


def _excel_col_name(index: int) -> str:
    result = ""
    current = index
    while current > 0:
        current, remainder = divmod(current - 1, 26)
        result = chr(65 + remainder) + result
    return result


def render_holdings_xlsx(dataset: dict[str, Any]) -> bytes:
    summary = dataset["summary"]
    summary_rows = [
        ["字段", "值"],
        ["导出时间", dataset["exported_at_cn"]],
        ["首页数据时间", dataset["generated_at_cn"]],
        ["结单快照日期", dataset["snapshot_date"] or "-"],
        ["持仓数量", str(summary["holding_count"])],
        ["附带交易数", str(summary["trade_count"])],
        ["总市值(HKD)", _format_hkd(summary["total_market_value_hkd"])],
        ["总盈亏(HKD)", _format_signed_hkd(summary["total_pnl_hkd"])],
        ["总盈亏比例", _format_pct(summary["total_pnl_pct"])],
        ["可计算盈亏持仓", f'{summary["calculable_position_count"]}/{summary["position_count"]}'],
    ]
    holdings_rows = [
        ["股票", "名称", "持仓数量", "币种", "当前市值(HKD)", "盈亏(HKD)", "盈亏比例", "市场", "主题", "盈亏口径", "涉及账户数"],
        *[
            [
                item["symbol"],
                item["name"],
                _format_number(item["quantity"], digits=4),
                item["currency"],
                _format_hkd(item["statement_value_hkd"]),
                _format_signed_hkd(item["statement_pnl_hkd"]),
                _format_pct(item["statement_pnl_pct"]),
                item["market"],
                item["category_name"],
                _pnl_source_label(item["pnl_source"]),
                str(item["account_count"]),
            ]
            for item in dataset["holdings"]
        ],
    ]
    trade_rows = [
        ["日期", "买卖", "股票", "名称", "数量", "成交价", "币种", "券商", "账户"],
        *[
            [
                item["date"],
                item["side"],
                item["symbol"],
                item["name"],
                _format_number(item["quantity"], digits=4),
                _format_number(item["price"], digits=4),
                item["currency"],
                item["broker"],
                item["account_id"],
            ]
            for item in dataset["recent_trades"]
        ],
    ]

    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
"""
    root_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
"""
    workbook = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Summary" sheetId="1" r:id="rId1"/>
    <sheet name="Holdings" sheetId="2" r:id="rId2"/>
    <sheet name="RecentTrades" sheetId="3" r:id="rId3"/>
  </sheets>
</workbook>
"""
    workbook_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"""
    styles = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Aptos"/></font>
    <font><b/><sz val="11"/><name val="Aptos"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFE9F2FF"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="1">
    <border><left/><right/><top/><bottom/><diagonal/></border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
  </cellXfs>
  <cellStyles count="1">
    <cellStyle name="Normal" xfId="0" builtinId="0"/>
  </cellStyles>
</styleSheet>
"""
    created_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    core = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:dcterms="http://purl.org/dc/terms/"
 xmlns:dcmitype="http://purl.org/dc/dcmitype/"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>MyInvAI Holdings Export</dc:title>
  <dc:creator>MyInvAI</dc:creator>
  <cp:lastModifiedBy>MyInvAI</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">{created_at}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">{created_at}</dcterms:modified>
</cp:coreProperties>
"""
    app = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
 xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>MyInvAI</Application>
</Properties>
"""

    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types)
        archive.writestr("_rels/.rels", root_rels)
        archive.writestr("xl/workbook.xml", workbook)
        archive.writestr("xl/_rels/workbook.xml.rels", workbook_rels)
        archive.writestr("xl/styles.xml", styles)
        archive.writestr("xl/worksheets/sheet1.xml", _sheet_xml(summary_rows, widths=[22, 24]))
        archive.writestr(
            "xl/worksheets/sheet2.xml",
            _sheet_xml(holdings_rows, widths=[14, 22, 14, 10, 16, 16, 12, 10, 16, 12, 10]),
        )
        archive.writestr(
            "xl/worksheets/sheet3.xml",
            _sheet_xml(trade_rows, widths=[14, 10, 12, 22, 14, 14, 10, 16, 16]),
        )
        archive.writestr("docProps/core.xml", core)
        archive.writestr("docProps/app.xml", app)
    return output.getvalue()


def _load_font(size: int) -> Any:
    if ImageFont is None:
        raise RuntimeError("服务器缺少 Pillow，暂时无法生成 PDF。")
    for path in _FONT_CANDIDATES:
        font_path = Path(path)
        if not font_path.exists():
            continue
        try:
            return ImageFont.truetype(str(font_path), size=size)
        except Exception:  # noqa: BLE001
            continue
    return ImageFont.load_default()


def _draw_vertical_gradient(image: Any, top_color: tuple[int, int, int], bottom_color: tuple[int, int, int]) -> None:
    if ImageDraw is None:
        return
    draw = ImageDraw.Draw(image)
    width, height = image.size
    for y in range(height):
        ratio = y / max(height - 1, 1)
        color = tuple(
            int(top_color[index] + (bottom_color[index] - top_color[index]) * ratio)
            for index in range(3)
        )
        draw.line((0, y, width, y), fill=color)


def _draw_cover_page(dataset: dict[str, Any]) -> Any:
    if Image is None or ImageDraw is None:
        raise RuntimeError("服务器缺少 Pillow，暂时无法生成 PDF。")

    width = 2200
    height = 1550
    image = Image.new("RGB", (width, height), color=(8, 26, 52))
    _draw_vertical_gradient(image, (7, 23, 47), (18, 62, 118))
    draw = ImageDraw.Draw(image)

    title_font = _load_font(88)
    subtitle_font = _load_font(34)
    card_value_font = _load_font(42)
    card_label_font = _load_font(24)
    body_font = _load_font(26)
    tiny_font = _load_font(20)

    draw.ellipse((1480, -120, 2220, 620), fill=(34, 124, 214))
    draw.ellipse((1620, 30, 2140, 550), fill=(23, 182, 204))
    draw.ellipse((160, 1180, 720, 1740), fill=(12, 90, 156))

    draw.text((120, 118), "MyInvAI", fill=(255, 255, 255), font=title_font)
    draw.text((120, 220), "Portfolio Export", fill=(188, 220, 255), font=subtitle_font)
    draw.text((120, 310), "当前持仓、盈亏与最近交易汇总", fill=(227, 239, 255), font=subtitle_font)
    draw.text(
        (120, 390),
        f'导出时间 {dataset["exported_at_cn"]}  ·  结单快照 {dataset["snapshot_date"] or "-"}',
        fill=(192, 212, 236),
        font=body_font,
    )

    summary = dataset["summary"]
    cards = [
        ("总市值", _format_hkd(summary["total_market_value_hkd"]), (39, 210, 255)),
        ("组合盈亏", _format_signed_hkd(summary["total_pnl_hkd"]), (94, 239, 182)),
        ("盈亏比例", _format_pct(summary["total_pnl_pct"]), (255, 209, 107)),
        ("最近交易", f'{summary["trade_count"]} 笔', (156, 173, 255)),
    ]
    card_width = 445
    card_height = 188
    start_x = 120
    start_y = 560
    gap = 28
    for index, (label, value, rgb) in enumerate(cards):
        x = start_x + index * (card_width + gap)
        y = start_y
        draw.rounded_rectangle(
            (x, y, x + card_width, y + card_height),
            radius=34,
            fill=(255, 255, 255),
            outline=(255, 255, 255),
            width=2,
        )
        draw.rounded_rectangle(
            (x + 26, y + 26, x + 90, y + 90),
            radius=18,
            fill=rgb,
        )
        draw.text((x + 28, y + 116), label, fill=(76, 96, 126), font=card_label_font)
        draw.text((x + 28, y + 146), value, fill=(14, 35, 66), font=card_value_font)

    highlight_x = 120
    highlight_y = 820
    highlight_width = 1960
    highlight_height = 460
    draw.rounded_rectangle(
        (highlight_x, highlight_y, highlight_x + highlight_width, highlight_y + highlight_height),
        radius=42,
        fill=(244, 248, 255),
    )
    draw.text((highlight_x + 40, highlight_y + 38), "本次导出包含", fill=(13, 36, 68), font=_load_font(38))
    notes = [
        f'1. 当前持仓 {summary["holding_count"]} 个标的，已按当前市值从高到低排序。',
        f'2. 已汇总可计算盈亏持仓 {summary["calculable_position_count"]}/{summary["position_count"]} 个。',
        "3. 附带最近交易记录，便于复盘最近的调仓动作。",
        "4. 盈亏口径与 App 首页保持一致，便于对外分享或归档。",
    ]
    note_y = highlight_y + 112
    for note in notes:
        draw.rounded_rectangle((highlight_x + 42, note_y + 8, highlight_x + 58, note_y + 24), radius=8, fill=(26, 111, 193))
        draw.text((highlight_x + 82, note_y), note, fill=(42, 61, 87), font=body_font)
        note_y += 74

    draw.text(
        (120, 1450),
        "Generated by MyInvAI · 适合用于投资复盘、归档与分享",
        fill=(203, 220, 242),
        font=tiny_font,
    )
    return image


def _draw_table_page(
    *,
    title: str,
    subtitle: str,
    columns: list[tuple[str, int]],
    rows: list[list[str]],
    footnote: str | None = None,
) -> list[Any]:
    if Image is None or ImageDraw is None:
        raise RuntimeError("服务器缺少 Pillow，暂时无法生成 PDF。")

    width = 2200
    height = 1550
    margin_x = 90
    margin_y = 72
    header_font = _load_font(54)
    subtitle_font = _load_font(24)
    column_font = _load_font(22)
    body_font = _load_font(20)
    footnote_font = _load_font(18)
    row_height = 52
    header_height = 58
    table_top = 270
    pages: list[Any] = []
    available_height = height - table_top - margin_y - 80
    max_rows = max(int((available_height - header_height) / row_height), 1)

    row_chunks = [rows[index : index + max_rows] for index in range(0, len(rows), max_rows)] or [[]]
    for page_index, chunk in enumerate(row_chunks, start=1):
        image = Image.new("RGB", (width, height), color=(244, 248, 255))
        _draw_vertical_gradient(image, (244, 248, 255), (235, 243, 252))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((margin_x, margin_y - 6, width - margin_x, 198), radius=38, fill=(13, 39, 76))
        draw.rounded_rectangle((width - 410, margin_y + 26, width - 120, margin_y + 84), radius=22, fill=(26, 88, 161))
        draw.text((width - 380, margin_y + 36), "Structured Export", fill=(229, 240, 255), font=_load_font(22))
        draw.text((margin_x + 26, margin_y + 18), title, fill=(255, 255, 255), font=header_font)
        subtitle_text = subtitle if len(row_chunks) == 1 else f"{subtitle}  ·  第 {page_index}/{len(row_chunks)} 页"
        draw.text((margin_x + 26, margin_y + 94), subtitle_text, fill=(200, 218, 241), font=subtitle_font)

        x = margin_x
        y = table_top
        draw.rounded_rectangle((margin_x, y, width - margin_x, y + header_height), radius=18, fill=(224, 234, 247))
        for label, col_width in columns:
            draw.text((x + 12, y + 14), label, fill=(24, 43, 72), font=column_font)
            x += col_width

        y += header_height + 8
        for row_index, row in enumerate(chunk):
            row_fill = (255, 255, 255) if row_index % 2 == 0 else (247, 250, 255)
            draw.rounded_rectangle((margin_x, y, width - margin_x, y + row_height - 4), radius=12, fill=row_fill)
            x = margin_x
            for cell, (_label, col_width) in zip(row, columns):
                text = _truncate(cell, max(4, int(col_width / 16)))
                draw.text((x + 12, y + 12), text, fill=(27, 39, 62), font=body_font)
                x += col_width
            y += row_height

        if footnote:
            draw.text((margin_x, height - margin_y - 30), footnote, fill=(110, 124, 146), font=footnote_font)

        pages.append(image)
    return pages


def render_holdings_pdf(dataset: dict[str, Any]) -> bytes:
    if Image is None or ImageDraw is None:
        raise RuntimeError("服务器缺少 Pillow，暂时无法生成 PDF。")

    summary = dataset["summary"]
    summary_lines = [
        ["导出时间", dataset["exported_at_cn"]],
        ["首页数据时间", dataset["generated_at_cn"]],
        ["结单快照日期", dataset["snapshot_date"] or "-"],
        ["持仓数量", str(summary["holding_count"])],
        ["附带交易数", str(summary["trade_count"])],
        ["总市值(HKD)", _format_hkd(summary["total_market_value_hkd"])],
        ["总盈亏(HKD)", _format_signed_hkd(summary["total_pnl_hkd"])],
        ["总盈亏比例", _format_pct(summary["total_pnl_pct"])],
        ["可计算盈亏持仓", f'{summary["calculable_position_count"]}/{summary["position_count"]}'],
    ]
    holdings_rows = [
        [
            f'{item["symbol"]} {item["name"]}',
            _format_number(item["quantity"], digits=4),
            _format_hkd(item["statement_value_hkd"]),
            _format_signed_hkd(item["statement_pnl_hkd"]),
            _format_pct(item["statement_pnl_pct"]),
            item["market"],
            item["category_name"],
            _pnl_source_label(item["pnl_source"]),
        ]
        for item in dataset["holdings"]
    ]
    trade_rows = [
        [
            item["date"],
            item["side"],
            f'{item["symbol"]} {item["name"]}',
            _format_number(item["quantity"], digits=4),
            _format_number(item["price"], digits=4),
            item["currency"],
            item["broker"],
        ]
        for item in dataset["recent_trades"]
    ]

    pages: list[Any] = []
    pages.append(_draw_cover_page(dataset))
    pages.extend(
        _draw_table_page(
            title="MyInvAI Portfolio Export",
            subtitle="当前持仓汇总",
            columns=[("字段", 460), ("值", 1560)],
            rows=summary_lines,
            footnote="金额基于当前首页持仓与最新行情；盈亏沿用 App 当前汇总口径。",
        )
    )
    pages.extend(
        _draw_table_page(
            title="MyInvAI Portfolio Export",
            subtitle="持仓明细",
            columns=[
                ("股票", 520),
                ("数量", 190),
                ("市值(HKD)", 260),
                ("盈亏(HKD)", 260),
                ("盈亏%", 170),
                ("市场", 140),
                ("主题", 320),
                ("口径", 160),
            ],
            rows=holdings_rows,
            footnote="若某些标的缺少结单原始盈亏，系统会按当前规则做估算或标记不可计算。",
        )
    )
    if trade_rows:
        pages.extend(
            _draw_table_page(
                title="MyInvAI Portfolio Export",
                subtitle="最近交易记录",
                columns=[
                    ("日期", 250),
                    ("买卖", 130),
                    ("股票", 520),
                    ("数量", 240),
                    ("成交价", 240),
                    ("币种", 140),
                    ("券商", 500),
                ],
                rows=trade_rows,
                footnote="交易记录以当前首页展示的最近交易为准。",
            )
        )

    output = io.BytesIO()
    rgb_pages = [image.convert("RGB") for image in pages]
    rgb_pages[0].save(output, format="PDF", save_all=True, append_images=rgb_pages[1:], resolution=160.0)
    return output.getvalue()
