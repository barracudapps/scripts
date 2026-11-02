#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["pymupdf>=1.24,<2"]
# ///

################################################################################
# Script:       id_watermark.py
# Description:  Watermarks an identity document (ID card, passport, payslip,
#               tax notice...) before sending it: a diagonal text repeated over
#               the whole page saying who receives it, when, and what for.
#               A stolen copy can then not be reused elsewhere.
#               The result is flattened (each page becomes an image), so the
#               watermark cannot be removed by editing the PDF, and the
#               metadata of the original are not copied. Originals are never
#               modified. Accepts PDF and images (JPG, PNG, HEIC...); several
#               inputs can be merged into one PDF (recto/verso).
# Usage:        id_watermark.py FILE... --to RECIPIENT [--for PURPOSE]
#                   [-o OUTPUT.pdf] [--text TEXT] [--opacity 0.3] [--dpi 150]
#               --to     who receives the copy (agency, landlord, bank...)
#               --for    what it is for ("rental file", "account opening"...)
#               --text   full custom text instead of the default sentence
#               -o       merge every input into this PDF (default: one
#                        NAME-watermarked.pdf per input)
# Example:      id_watermark.py id-front.heic id-back.heic --to "Agence Dupont" \
#                   --for "dossier location" -o id-agence-dupont.pdf
# Notes:        Default text (French): "Copie destinée à X - usage : Y - date".
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import argparse
import math
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

import pymupdf

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".gif", ".webp"}
CONVERT_SUFFIXES = {".heic", ".heif"}       # converted to JPEG with sips first
FONT = "helv"


def open_source(path: Path, workdir: Path) -> pymupdf.Document:
    suffix = path.suffix.lower()
    if suffix in CONVERT_SUFFIXES:
        converted = workdir / f"{path.stem}.jpg"
        result = subprocess.run(["sips", "-s", "format", "jpeg", str(path), "--out", str(converted)],
                                capture_output=True)
        if result.returncode != 0:
            sys.exit(f"Cannot convert {path} (sips failed)")
        path, suffix = converted, ".jpg"
    if suffix in IMAGE_SUFFIXES:
        # One page per photo, its longest side as long as an A4 page, so the
        # watermark keeps a readable size whatever the photo resolution
        image = pymupdf.open(path)
        width, height = image[0].rect.width, image[0].rect.height
        image.close()
        scale = 842 / max(width, height)
        pdf = pymupdf.open()
        page = pdf.new_page(width=width * scale, height=height * scale)
        page.insert_image(page.rect, filename=str(path))
        return pdf
    if suffix == ".pdf":
        document = pymupdf.open(path)
        if document.needs_pass:
            sys.exit(f"{path} is password-protected: open it and save an unprotected copy first")
        return document
    sys.exit(f"Unsupported file type: {path}")


def stamp(page: pymupdf.Page, text: str, opacity: float) -> None:
    """Diagonal text repeated over the whole page."""
    rect = page.rect
    fontsize = max(8.0, min(rect.width, rect.height) / 28)
    line = f"{text}   •   "
    width = pymupdf.get_text_length(line, fontname=FONT, fontsize=fontsize)
    repeat = max(1, math.ceil(math.hypot(rect.width, rect.height) * 2 / width))
    line *= repeat
    angle = 30
    centre = pymupdf.Point(rect.width / 2, rect.height / 2)
    rotation = pymupdf.Matrix(angle)
    diagonal = math.hypot(rect.width, rect.height)
    step = fontsize * 3.2
    offset = -diagonal
    while offset < diagonal:
        start = pymupdf.Point(centre.x - diagonal, centre.y + offset)
        page.insert_text(start, line, fontname=FONT, fontsize=fontsize, color=(0.2, 0.2, 0.2),
                         fill_opacity=opacity, morph=(centre, rotation), overlay=True)
        offset += step


def flatten(source: pymupdf.Document, target: pymupdf.Document, dpi: int) -> None:
    for page in source:
        pixmap = page.get_pixmap(dpi=dpi)
        new_page = target.new_page(width=page.rect.width, height=page.rect.height)
        new_page.insert_image(new_page.rect, stream=pixmap.tobytes("jpeg", jpg_quality=82))


def main() -> int:
    parser = argparse.ArgumentParser(description="Watermark an identity document before sending it.")
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--to", dest="recipient", help="who receives the copy")
    parser.add_argument("--for", dest="purpose", help="what the copy is for")
    parser.add_argument("--text", help="custom watermark text")
    parser.add_argument("-o", "--output", type=Path, help="merge everything into this PDF")
    parser.add_argument("--opacity", type=float, default=0.3)
    parser.add_argument("--dpi", type=int, default=150)
    args = parser.parse_args()
    if not args.text and not args.recipient:
        parser.error("give --to RECIPIENT (or a full --text)")
    for path in args.files:
        if not path.is_file():
            sys.exit(f"Not found: {path}")

    text = args.text or " - ".join(filter(None, [
        f"Copie destinée à {args.recipient}",
        f"usage : {args.purpose}" if args.purpose else "usage unique",
        date.today().strftime("%d/%m/%Y"),
    ]))
    outputs: list[tuple[Path, list[Path]]]
    if args.output:
        target = args.output if args.output.suffix.lower() == ".pdf" else args.output.with_suffix(".pdf")
        outputs = [(target, args.files)]
    else:
        outputs = [(p.with_name(f"{p.stem}-watermarked.pdf"), [p]) for p in args.files]

    with tempfile.TemporaryDirectory() as workdir:
        for target, sources in outputs:
            if any(target.resolve() == s.resolve() for s in sources):
                sys.exit("The output must differ from the input files")
            result = pymupdf.open()
            for source_path in sources:
                source = open_source(source_path, Path(workdir))
                for page in source:
                    stamp(page, text, args.opacity)
                flatten(source, result, args.dpi)
                source.close()
            result.set_metadata({"title": text, "producer": "", "creator": ""})
            result.save(target, garbage=4, deflate=True)
            result.close()
            print(f"Written: {target}  ({target.stat().st_size / 1024:.0f} KB)")
    print(f"Watermark: \"{text}\"")
    print("Check the result before sending it: the text must cross the photo and the important data.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
