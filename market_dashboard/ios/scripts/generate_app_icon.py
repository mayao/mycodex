#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
ICONSET_DIR = ROOT_DIR / "ios" / "PortfolioWorkbenchIOS" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
MASTER_PATH = ICONSET_DIR / "AppIcon-1024.png"
SOURCE_ICON_PATH = ROOT_DIR / "ios" / "source_assets" / "invest-icon-original.png"
FALLBACK_PREVIEW_PATH = ROOT_DIR / "output" / "icon_preview" / "crop-800-1024.png"
FALLBACK_ART_PATH = ROOT_DIR / "ios" / "scripts" / "app_icon_attachment.html"
OUTPUT_SIZES = {
    "AppIcon-20@2x.png": 40,
    "AppIcon-20@3x.png": 60,
    "AppIcon-29@2x.png": 58,
    "AppIcon-29@3x.png": 87,
    "AppIcon-40@2x.png": 80,
    "AppIcon-40@3x.png": 120,
    "AppIcon-60@2x.png": 120,
    "AppIcon-60@3x.png": 180,
    "AppIcon-76@2x.png": 152,
    "AppIcon-83.5@2x.png": 167,
}


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def render_fallback_master(temp_dir: Path) -> Path:
    run([
        "qlmanage",
        "-t",
        "-s",
        "1024",
        "-o",
        str(temp_dir),
        str(FALLBACK_ART_PATH),
    ])
    output = temp_dir / f"{FALLBACK_ART_PATH.name}.png"
    if not output.exists():
        raise FileNotFoundError(output)
    return output


def render_input_master(source: Path, temp_dir: Path) -> Path:
    if not source.exists():
        raise FileNotFoundError(source)
    output = temp_dir / "AppIcon-1024.png"
    run([
        "sips",
        "-z",
        "1024",
        "1024",
        str(source),
        "--out",
        str(output),
    ])
    return output


def center_crop_master(source: Path, temp_dir: Path, crop_size: int) -> Path:
    cropped = temp_dir / f"AppIcon-crop-{crop_size}.png"
    normalized = temp_dir / "AppIcon-1024-cropped.png"
    run([
        "sips",
        "--cropToHeightWidth",
        str(crop_size),
        str(crop_size),
        str(source),
        "--out",
        str(cropped),
    ])
    run([
        "sips",
        "-z",
        "1024",
        "1024",
        str(cropped),
        "--out",
        str(normalized),
    ])
    return normalized


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate iOS AppIcon assets.")
    parser.add_argument("--input", type=Path, help="Optional square source image path.")
    parser.add_argument("--crop-size", type=int, help="Optional centered square crop size before generating the icon set.")
    args = parser.parse_args()

    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as temp_root:
        temp_dir = Path(temp_root)
        if args.input:
            master_source = render_input_master(args.input, temp_dir)
        elif SOURCE_ICON_PATH.exists():
            master_source = render_input_master(SOURCE_ICON_PATH, temp_dir)
        elif FALLBACK_PREVIEW_PATH.exists():
            master_source = render_input_master(FALLBACK_PREVIEW_PATH, temp_dir)
        else:
            master_source = render_fallback_master(temp_dir)
        if args.crop_size:
            master_source = center_crop_master(master_source, temp_dir, args.crop_size)
        shutil.copyfile(master_source, MASTER_PATH)

        for filename, size in OUTPUT_SIZES.items():
            run([
                "sips",
                "-z",
                str(size),
                str(size),
                str(master_source),
                "--out",
                str(ICONSET_DIR / filename),
            ])


if __name__ == "__main__":
    main()
