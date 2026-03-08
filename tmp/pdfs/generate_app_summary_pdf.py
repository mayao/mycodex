from pathlib import Path

def hex_utf16be(text: str) -> str:
    return text.encode('utf-16-be').hex().upper()


def make_line(text: str, x: int, y: int, size: int = 11) -> str:
    return f"BT /F1 {size} Tf 1 0 0 1 {x} {y} Tm <{hex_utf16be(text)}> Tj ET"


output_path = Path('output/pdf/app_summary_zh.pdf')

lines = []
y = 800

lines.append(make_line('应用概览 - Snake (Classic)', 50, y, 17)); y -= 30

lines.append(make_line('1) 它是什么', 50, y, 13)); y -= 18
lines.append(make_line('这是一个基于浏览器的经典贪吃蛇小游戏，采用原生 HTML/CSS/JavaScript 实现。', 60, y)); y -= 16
lines.append(make_line('项目定位是最小可运行示例，覆盖移动、碰撞、计分、暂停与重开。', 60, y)); y -= 24

lines.append(make_line('2) 面向谁', 50, y, 13)); y -= 18
lines.append(make_line('主要用户/画像: 想快速体验或学习网格游戏逻辑的前端初学者与教学演示场景。', 60, y)); y -= 24

lines.append(make_line('3) 它能做什么（关键功能）', 50, y, 13)); y -= 18
features = [
    '- 16x16 网格蛇移动，固定 tick 驱动（src/app.js）。',
    '- 键盘 Arrow/WASD 与屏幕方向按钮输入（index.html, src/app.js）。',
    '- 吃到食物后蛇身+1，分数+1（src/snake.js）。',
    '- 防止 180 度反向输入，避免直接回头（src/snake.js）。',
    '- 撞墙或撞自身即游戏结束，并更新状态显示（src/snake.js, src/app.js）。',
    '- 支持暂停/恢复与重开（P/R 键与按钮）（src/app.js）。',
    '- 内置 Node 测试覆盖核心规则（src/snake.test.js）。',
]
for item in features:
    lines.append(make_line(item, 60, y)); y -= 16

y -= 8
lines.append(make_line('4) 如何工作（仅基于仓库证据）', 50, y, 13)); y -= 18
arch = [
    '- 组件: UI 壳层(index.html) + 样式层(styles.css) + 应用层(src/app.js) + 规则引擎(src/snake.js)。',
    '- 数据流: 用户输入 -> queueDirection/togglePause -> 定时 tick -> 新 state -> renderBoard/renderHUD。',
    '- 状态对象: cols/rows/snake/direction/food/score/alive/paused。',
    '- 服务层: Not found in repo。',
    '- 后端 API / 数据库 / 持久化: Not found in repo。',
]
for item in arch:
    lines.append(make_line(item, 60, y)); y -= 16

y -= 8
lines.append(make_line('5) 如何运行（最小步骤）', 50, y, 13)); y -= 18
run_steps = [
    '- 在仓库根目录启动静态服务: python3 -m http.server 8000',
    '- 浏览器打开: http://localhost:8000/index.html',
    '- 可选测试: node --test',
]
for item in run_steps:
    lines.append(make_line(item, 60, y)); y -= 16

content = "\n".join(lines) + "\n"
content_bytes = content.encode('ascii')

objects = []

# 1 Catalog
objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
# 2 Pages
objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
# 3 Page
objects.append(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>")
# 4 Content stream
objects.append(b"<< /Length " + str(len(content_bytes)).encode('ascii') + b" >>\nstream\n" + content_bytes + b"endstream")
# 5 Font (CJK)
objects.append(b"<< /Type /Font /Subtype /Type0 /BaseFont /STSong-Light /Encoding /UniGB-UCS2-H /DescendantFonts [6 0 R] >>")
# 6 Descendant CIDFont
objects.append(b"<< /Type /Font /Subtype /CIDFontType0 /BaseFont /STSong-Light /CIDSystemInfo << /Registry (Adobe) /Ordering (GB1) /Supplement 4 >> /DW 1000 >>")

pdf = bytearray()
pdf.extend(b"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n")
offsets = [0]
for i, obj in enumerate(objects, start=1):
    offsets.append(len(pdf))
    pdf.extend(f"{i} 0 obj\n".encode('ascii'))
    pdf.extend(obj)
    pdf.extend(b"\nendobj\n")

xref_start = len(pdf)
pdf.extend(f"xref\n0 {len(objects)+1}\n".encode('ascii'))
pdf.extend(b"0000000000 65535 f \n")
for off in offsets[1:]:
    pdf.extend(f"{off:010d} 00000 n \n".encode('ascii'))
pdf.extend(b"trailer\n")
pdf.extend(f"<< /Size {len(objects)+1} /Root 1 0 R >>\n".encode('ascii'))
pdf.extend(b"startxref\n")
pdf.extend(f"{xref_start}\n".encode('ascii'))
pdf.extend(b"%%EOF\n")

output_path.write_bytes(pdf)
print(output_path)
