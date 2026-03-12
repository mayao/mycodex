from pathlib import Path

from reportlab.lib.colors import Color, HexColor
from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfgen import canvas


ROOT = Path("/Users/xmly/Library/Mobile Documents/com~apple~CloudDocs/MyCodex")
OUTPUT = ROOT / "output" / "pdf" / "vital-command-summary-cn.pdf"

PAGE_WIDTH, PAGE_HEIGHT = landscape(A4)
MARGIN = 28
GAP = 16
TITLE_H = 58
COL_GAP = 18
LEFT_W = 365
RIGHT_W = PAGE_WIDTH - MARGIN * 2 - COL_GAP - LEFT_W
RIGHT_X = MARGIN + LEFT_W + COL_GAP

FONT = "STSong-Light"
FONT_LATIN_BOLD = "Helvetica-Bold"


def register_fonts() -> None:
    pdfmetrics.registerFont(UnicodeCIDFont(FONT))


def text_width(text: str, font_name: str, font_size: float) -> float:
    return pdfmetrics.stringWidth(text, font_name, font_size)


def wrap_text(text: str, font_name: str, font_size: float, max_width: float) -> list[str]:
    if not text:
        return [""]

    lines: list[str] = []
    line = ""

    for char in text:
        if char == "\n":
            lines.append(line.rstrip())
            line = ""
            continue
        trial = line + char
        if line and text_width(trial, font_name, font_size) > max_width:
            lines.append(line.rstrip())
            line = char.lstrip()
        else:
            line = trial

    if line or not lines:
        lines.append(line.rstrip())

    return lines


def draw_wrapped_text(
    c: canvas.Canvas,
    x: float,
    y_top: float,
    width: float,
    text: str,
    *,
    font_name: str = FONT,
    font_size: float = 10.4,
    leading: float = 14.0,
    color=HexColor("#183153"),
) -> float:
    c.setFont(font_name, font_size)
    c.setFillColor(color)
    lines = wrap_text(text, font_name, font_size, width)
    y = y_top
    for line in lines:
        c.drawString(x, y, line)
        y -= leading
    return y


def draw_bullets(
    c: canvas.Canvas,
    x: float,
    y_top: float,
    width: float,
    items: list[str],
    *,
    font_name: str = FONT,
    font_size: float = 9.6,
    leading: float = 12.5,
    bullet_gap: float = 12,
    color=HexColor("#183153"),
) -> float:
    c.setFont(font_name, font_size)
    c.setFillColor(color)
    y = y_top
    text_w = width - bullet_gap

    for item in items:
        lines = wrap_text(item, font_name, font_size, text_w)
        c.drawString(x, y, "-")
        c.drawString(x + bullet_gap, y, lines[0])
        y -= leading
        for line in lines[1:]:
            c.drawString(x + bullet_gap, y, line)
            y -= leading
        y -= 3

    return y


def draw_card(
    c: canvas.Canvas,
    x: float,
    y_top: float,
    width: float,
    height: float,
    title: str,
) -> float:
    c.setFillColor(HexColor("#F7F4EE"))
    c.setStrokeColor(HexColor("#D9D1C3"))
    c.roundRect(x, y_top - height, width, height, 12, fill=1, stroke=1)
    c.setFillColor(HexColor("#8C5A2B"))
    c.rect(x, y_top - 34, width, 34, fill=1, stroke=0)
    c.setFillColor(HexColor("#FFFDF7"))
    c.setFont(FONT, 14)
    c.drawString(x + 14, y_top - 22, title)
    return y_top - 48


def draw() -> Path:
    register_fonts()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUTPUT), pagesize=landscape(A4))
    c.setTitle("Vital Command 应用概览")
    c.setAuthor("Codex")

    # Background
    c.setFillColor(HexColor("#F2EEE6"))
    c.rect(0, 0, PAGE_WIDTH, PAGE_HEIGHT, fill=1, stroke=0)

    # Header
    c.setFillColor(HexColor("#1E3A4C"))
    c.roundRect(MARGIN, PAGE_HEIGHT - MARGIN - TITLE_H, PAGE_WIDTH - MARGIN * 2, TITLE_H, 16, fill=1, stroke=0)
    c.setFillColor(HexColor("#FFFDF8"))
    title_x = MARGIN + 18
    title_y = PAGE_HEIGHT - MARGIN - 24
    english_title = "Vital Command"
    c.setFont(FONT_LATIN_BOLD, 22)
    c.drawString(title_x, title_y, english_title)
    c.setFont(FONT, 22)
    c.drawString(title_x + text_width(english_title, FONT_LATIN_BOLD, 22) + 18, title_y, "应用概览")
    c.setFont(FONT, 10.5)
    c.drawString(
        MARGIN + 18,
        PAGE_HEIGHT - MARGIN - 42,
        "基于 `Health/` 仓库证据整理: README、package.json、src/app、src/server、docs"
    )

    left_y = PAGE_HEIGHT - MARGIN - TITLE_H - GAP
    right_y = left_y

    # Left column
    top = left_y
    cursor = draw_card(c, MARGIN, top, LEFT_W, 98, "它是什么")
    cursor = draw_wrapped_text(
        c,
        MARGIN + 14,
        cursor,
        LEFT_W - 28,
        "一个面向单用户、local-first 的健康数据管理与经营系统原型，用于把体检、血液、体脂和运动数据统一导入、标准化、分析并生成摘要。",
        font_size=10.4,
        leading=14,
    )
    draw_wrapped_text(
        c,
        MARGIN + 14,
        cursor - 2,
        LEFT_W - 28,
        "当前工程把 Next.js 前端、Route Handlers、服务层和 SQLite 收敛在同一仓库中。",
        font_size=10.4,
        leading=14,
    )

    top -= 98 + 12
    cursor = draw_card(c, MARGIN, top, LEFT_W, 84, "适用对象")
    draw_wrapped_text(
        c,
        MARGIN + 14,
        cursor,
        LEFT_W - 28,
        "主要面向希望长期管理个人健康指标的单个用户，尤其适合需要把多来源体检、复查、体脂秤和运动记录汇总到本地并持续观察趋势的人。",
        font_size=10.1,
        leading=13.5,
    )

    top -= 84 + 12
    cursor = draw_card(c, MARGIN, top, LEFT_W, 252, "核心能力")
    draw_bullets(
        c,
        MARGIN + 16,
        cursor,
        LEFT_W - 32,
        [
            "导入体检、血液检查、体脂秤、运动 CSV/Excel，并做字段映射、单位标准化和异常标记。",
            "记录 `import_task` 与 `import_row_log`，保留失败行追踪和脱敏审计信息。",
            "用规则引擎产出结构化 insights，覆盖趋势、异常和联动观察。",
            "首页展示总览卡片、提醒、趋势图、分维度分析和最新 AI 摘要。",
            "生成日摘要、周报、月报，并把 `report_snapshot` 保存到 SQLite。",
            "提供文件上传导入 API，以及报告列表和报告详情读取能力。",
            "默认使用 mock provider，也预留 OpenAI-compatible LLM 接口。",
        ],
        font_size=9.55,
        leading=12.2,
    )

    # Right column
    top = right_y
    cursor = draw_card(c, RIGHT_X, top, RIGHT_W, 250, "如何工作")
    draw_bullets(
        c,
        RIGHT_X + 16,
        cursor,
        RIGHT_W - 32,
        [
            "表现层: Next.js App Router 页面 `/`、`/reports`、`/reports/[snapshotId]`，以及 `/api/dashboard`、`/api/imports`、`/api/reports`。",
            "服务层: `health-home-service` 聚合首页数据，`report-service` 生成摘要与报告，`holistic-insight-service` 合并规则、体检和基因洞察。",
            "数据层: `getDatabase()` 初始化 `data/health-system.sqlite`，执行 schema、seed 和迁移；repositories 负责统一查询。",
            "导入流: 上传文件 -> `importHealthData` -> importer registry / tabular reader -> 标准化指标、导入日志写入 SQLite。",
            "分析流: repositories 取数 -> 结构化规则引擎 -> 可选 LLM 摘要 -> `report_snapshot` 回写 -> 页面/API 输出。",
        ],
        font_size=9.5,
        leading=12.2,
    )

    top -= 250 + 12
    cursor = draw_card(c, RIGHT_X, top, RIGHT_W, 148, "如何运行")
    draw_bullets(
        c,
        RIGHT_X + 16,
        cursor,
        RIGHT_W - 32,
        [
            "进入 `Health/`，使用 Node.js 22.x 与 npm 10+；README 和 `package.json` 都要求支持 `node:sqlite`。",
            "执行 `npm install`。",
            "执行 `npm run dev`，打开 `http://localhost:3000`。",
            "首次启动会创建 `data/health-system.sqlite`、注入 mock 数据并执行迁移；默认 `HEALTH_LLM_PROVIDER=mock`，无需额外配置。",
        ],
        font_size=9.55,
        leading=12.2,
    )

    top -= 148 + 12
    cursor = draw_card(c, RIGHT_X, top, RIGHT_W, 70, "仓库未见")
    draw_bullets(
        c,
        RIGHT_X + 16,
        cursor,
        RIGHT_W - 32,
        [
            "生产部署方案: Not found in repo.",
            "独立认证 / 多用户权限设计: Not found in repo.",
        ],
        font_size=9.3,
        leading=12,
    )

    # Footer
    c.setFillColor(Color(0, 0, 0, alpha=0.16))
    c.line(MARGIN, 22, PAGE_WIDTH - MARGIN, 22)
    c.setFillColor(HexColor("#5F6B75"))
    c.setFont(FONT, 8.8)
    c.drawString(
        MARGIN,
        10,
        "备注: README 明确声明该项目为“非医疗诊断”，输出用于健康数据整理、趋势解释与生活方式管理。"
    )

    c.showPage()
    c.save()
    return OUTPUT


if __name__ == "__main__":
    path = draw()
    print(path)
