#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["pypdf>=5"]
# ///

################################################################################
# Script:       pdf_tools.py
# Description:  Everyday PDF operations. The original files are never modified:
#               every command writes a new file.
#                 info      pages, size, text layer, metadata
#                 merge     merge PDFs (one bookmark per source file)
#                 split     one file per page, or per group of N pages
#                 extract   keep some pages (e.g. 1-3,5,8-)
#                 remove    drop some pages
#                 rotate    rotate all or some pages by 90/180/270 degrees
#                 scan      scanned document -> OCR (pdf_ocr.sh) + compression
#                           (Ghostscript, kept only when smaller)
# Usage:        pdf_tools.py info FILE...
#               pdf_tools.py merge OUTPUT INPUT...
#               pdf_tools.py split FILE [--every N]
#               pdf_tools.py extract FILE PAGES [-o OUTPUT]
#               pdf_tools.py remove FILE PAGES [-o OUTPUT]
#               pdf_tools.py rotate FILE {90,180,270} [--pages PAGES] [-o OUTPUT]
#               pdf_tools.py scan FILE... [-l fra+eng]
#               PAGES: "1-3,5,8-" (1-based, "8-" = from 8 to the end)
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter

SCRIPTS_DIR = Path(__file__).resolve().parent


def human(size: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return str(size)


def parse_pages(spec: str, count: int) -> list[int]:
    """'1-3,5,8-' -> 0-based page indexes, in the given order, without duplicates."""
    pages: list[int] = []
    for part in spec.replace(" ", "").split(","):
        if not part:
            continue
        if "-" in part:
            start, end = part.split("-", 1)
            first, last = int(start or 1), int(end or count)
        else:
            first = last = int(part)
        if not (1 <= first <= last <= count):
            sys.exit(f"Invalid page range '{part}' (the document has {count} pages)")
        pages += [p - 1 for p in range(first, last + 1) if p - 1 not in pages]
    if not pages:
        sys.exit("No page selected")
    return pages


def output_path(source: Path, suffix: str, explicit: str | None) -> Path:
    target = Path(explicit) if explicit else source.with_name(f"{source.stem}-{suffix}.pdf")
    if target.resolve() == source.resolve():
        sys.exit("The output must differ from the input file")
    return target


def write(writer: PdfWriter, target: Path) -> None:
    with target.open("wb") as handle:
        writer.write(handle)
    print(f"Written: {target} ({human(target.stat().st_size)})")


def cmd_info(args) -> None:
    for name in args.files:
        path = Path(name)
        reader = PdfReader(path)
        sample = "".join((page.extract_text() or "") for page in reader.pages[:3]).strip()
        box = reader.pages[0].mediabox
        meta = reader.metadata or {}
        print(f"{path}")
        print(f"  pages      {len(reader.pages)}")
        print(f"  size       {human(path.stat().st_size)}")
        print(f"  page size  {float(box.width) * 0.3528:.0f} x {float(box.height) * 0.3528:.0f} mm")
        print(f"  text layer {'yes' if sample else 'no (scanned? try: pdf_tools.py scan)'}")
        print(f"  encrypted  {'yes' if reader.is_encrypted else 'no'}")
        for key in ("/Title", "/Author", "/Producer"):
            if meta.get(key):
                print(f"  {key[1:].lower():<10} {meta[key]}")


def cmd_merge(args) -> None:
    target = Path(args.output)
    if target.exists():
        sys.exit(f"{target} already exists")
    writer = PdfWriter()
    for name in args.inputs:
        page_index = len(writer.pages)
        writer.append(name)
        writer.add_outline_item(Path(name).stem, page_index)
    write(writer, target)


def cmd_split(args) -> None:
    source = Path(args.file)
    reader = PdfReader(source)
    total = len(reader.pages)
    width = len(str(total))
    for start in range(0, total, args.every):
        writer = PdfWriter()
        for index in range(start, min(start + args.every, total)):
            writer.add_page(reader.pages[index])
        last = min(start + args.every, total)
        label = f"{start + 1:0{width}d}" if args.every == 1 else f"{start + 1:0{width}d}-{last:0{width}d}"
        write(writer, source.with_name(f"{source.stem}-p{label}.pdf"))


def cmd_extract(args, keep: bool = True) -> None:
    source = Path(args.file)
    reader = PdfReader(source)
    selected = parse_pages(args.pages, len(reader.pages))
    indexes = selected if keep else [i for i in range(len(reader.pages)) if i not in selected]
    if not indexes:
        sys.exit("No page left")
    writer = PdfWriter()
    for index in indexes:
        writer.add_page(reader.pages[index])
    write(writer, output_path(source, "extract" if keep else "trimmed", args.output))


def cmd_rotate(args) -> None:
    source = Path(args.file)
    reader = PdfReader(source)
    selected = set(parse_pages(args.pages, len(reader.pages))) if args.pages else None
    writer = PdfWriter()
    for index, page in enumerate(reader.pages):
        added = writer.add_page(page)
        if selected is None or index in selected:
            added.rotate(args.angle)
    write(writer, output_path(source, "rotated", args.output))


def cmd_scan(args) -> None:
    gs = shutil.which("gs")
    for name in args.files:
        source = Path(name)
        ocr = source.with_name(f"{source.stem}-ocr.pdf")
        final = source.with_name(f"{source.stem}-scan.pdf")
        result = subprocess.run(["bash", str(SCRIPTS_DIR / "pdf_ocr.sh"), str(source), "-l", args.lang], check=False)
        if result.returncode != 0 or not ocr.exists():
            print(f"OCR failed for {source}", file=sys.stderr)
            continue
        if gs:
            compressed = source.with_name(f"{source.stem}-scan-gs.pdf")
            subprocess.run(
                [gs, "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.5", "-dPDFSETTINGS=/ebook",
                 "-dNOPAUSE", "-dQUIET", "-dBATCH", f"-sOutputFile={compressed}", str(ocr)],
                check=False,
            )
            if compressed.exists() and compressed.stat().st_size < ocr.stat().st_size:
                compressed.replace(final)
                ocr.unlink()
            else:
                compressed.unlink(missing_ok=True)
                ocr.replace(final)
        else:
            ocr.replace(final)
        print(f"Scan ready: {final} ({human(source.stat().st_size)} -> {human(final.stat().st_size)}, searchable)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Everyday PDF operations (originals are never modified).")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("info", help="pages, size, text layer, metadata")
    p.add_argument("files", nargs="+")
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("merge", help="merge PDFs into OUTPUT")
    p.add_argument("output")
    p.add_argument("inputs", nargs="+")
    p.set_defaults(func=cmd_merge)

    p = sub.add_parser("split", help="one file per page (or per N pages)")
    p.add_argument("file")
    p.add_argument("--every", type=int, default=1)
    p.set_defaults(func=cmd_split)

    for name, keep in (("extract", True), ("remove", False)):
        p = sub.add_parser(name, help=f"{'keep' if keep else 'drop'} the given pages")
        p.add_argument("file")
        p.add_argument("pages")
        p.add_argument("-o", "--output")
        p.set_defaults(func=lambda a, keep=keep: cmd_extract(a, keep))

    p = sub.add_parser("rotate", help="rotate pages")
    p.add_argument("file")
    p.add_argument("angle", type=int, choices=(90, 180, 270))
    p.add_argument("--pages")
    p.add_argument("-o", "--output")
    p.set_defaults(func=cmd_rotate)

    p = sub.add_parser("scan", help="OCR + compression of scanned PDFs")
    p.add_argument("files", nargs="+")
    p.add_argument("-l", "--lang", default="fra+eng")
    p.set_defaults(func=cmd_scan)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
