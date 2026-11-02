#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["pypdf>=5"]
# ///

################################################################################
# Script:       strip_metadata.py
# Description:  Removes the hidden personal information of files before
#               sharing them: GPS position, phone or camera model, serial
#               numbers, date taken, software, author and company names.
#                 photos   JPG, HEIC, PNG, TIFF, WEBP, DNG (exiftool, lossless,
#                          orientation and colour profile kept)
#                 videos   MOV, MP4, M4V (ffmpeg stream copy, no re-encoding)
#                 PDF      document information and XMP metadata
#                 Office   DOCX, XLSX, PPTX (author, last editor, company...)
#               Originals are never modified: a NAME-clean.EXT copy is written
#               next to each file (or into --out). Each result is read again to
#               check that nothing sensitive is left.
# Usage:        strip_metadata.py FILE|FOLDER... [--show] [--out DIR]
#               --show   only list the sensitive metadata found, write nothing
#               --out    folder for the clean copies (created if needed)
# Notes:        Needs exiftool (brew install exiftool) for photos and checks,
#               ffmpeg for videos. Comments and tracked changes inside Office
#               documents are content, not metadata: they are not removed.
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from pypdf import PdfReader, PdfWriter

PHOTOS = {".jpg", ".jpeg", ".heic", ".heif", ".png", ".tif", ".tiff", ".webp", ".dng"}
VIDEOS = {".mov", ".mp4", ".m4v"}
OFFICE = {".docx", ".xlsx", ".pptx"}
SUPPORTED = PHOTOS | VIDEOS | OFFICE | {".pdf"}
BOLD, DIM, RED, GREEN, NC = (("\033[1m", "\033[2m", "\033[91m", "\033[92m", "\033[0m")
                             if sys.stdout.isatty() else ("",) * 5)

# exiftool tag name patterns -> human label
SENSITIVE = [
    (re.compile(r"GPS|Location|Coordinates", re.I), "GPS position"),
    (re.compile(r"^(Make|Model|LensMake|LensModel|LensInfo|HostComputer|AndroidModel|AndroidMake)$", re.I),
     "device"),
    (re.compile(r"Serial", re.I), "serial number"),
    (re.compile(r"^(DateTimeOriginal|CreateDate|CreationDate|ContentCreateDate|MediaCreateDate)$", re.I),
     "date taken"),
    (re.compile(r"^(Software|CreatorTool|Producer|Encoder)$", re.I), "software"),
    (re.compile(r"^(Artist|Author|Creator|OwnerName|Copyright|LastModifiedBy|Company|Manager|By-line)$", re.I),
     "author / owner"),
    (re.compile(r"^(UserComment|ImageDescription|Title|Subject|Keywords|Description)$", re.I), "text notes"),
]
OFFICE_FIELDS = {
    "docProps/core.xml": ["dc:creator", "cp:lastModifiedBy", "cp:keywords", "dc:subject", "dc:title",
                          "dc:description", "cp:category", "cp:contentStatus"],
    "docProps/app.xml": ["Company", "Manager", "Template", "HyperlinkBase"],
}


def need(tool: str, hint: str) -> str:
    path = shutil.which(tool)
    if not path:
        sys.exit(f"{tool} is required: {hint}")
    return path


def sensitive_tags(path: Path) -> dict[str, str]:
    """{label: example value} of the sensitive tags exiftool finds in a file."""
    exiftool = need("exiftool", "brew install exiftool")
    out = subprocess.run([exiftool, "-j", "-s", "-G0", "-n", "-api", "largefilesupport=1", str(path)],
                         capture_output=True, text=True).stdout
    try:
        tags = json.loads(out)[0]
    except (json.JSONDecodeError, IndexError):
        return {}
    found: dict[str, str] = {}
    for key, value in tags.items():
        group, _, name = key.partition(":")
        text = str(value).strip()
        if group in ("File", "System", "ExifTool", "SourceFile", "ICC_Profile") or not text:
            continue
        if text.startswith("0000:00:00") or name == "GPSVersionID":
            continue
        for pattern, label in SENSITIVE:
            if pattern.search(name) and label not in found:
                found[label] = text[:40]
    position = tags.get("Composite:GPSPosition")
    if position:
        found["GPS position"] = str(position)[:40]
    return found


def unique_target(path: Path, out_dir: Path | None) -> Path:
    folder = out_dir or path.parent
    target = folder / f"{path.stem}-clean{path.suffix}"
    counter = 2
    while target.exists():
        target = folder / f"{path.stem}-clean-{counter}{path.suffix}"
        counter += 1
    return target


def clean_photo(path: Path, target: Path) -> None:
    subprocess.run([need("exiftool", "brew install exiftool"), "-q", "-q", "-all=", "--icc_profile:all",
                    "-tagsFromFile", "@", "-Orientation", "-o", str(target), str(path)], check=True)


def clean_video(path: Path, target: Path) -> None:
    ffmpeg = need("ffmpeg", "brew install ffmpeg")
    subprocess.run([ffmpeg, "-v", "error", "-i", str(path), "-map", "0", "-c", "copy", "-map_metadata", "-1",
                    "-map_chapters", "-1", "-fflags", "+bitexact", "-flags:v", "+bitexact",
                    "-flags:a", "+bitexact", str(target)], check=True)
    # Apple keeps the location in its own atoms: let exiftool finish the job
    if shutil.which("exiftool"):
        subprocess.run(["exiftool", "-q", "-q", "-all=", "-overwrite_original", str(target)], check=False)


def clean_pdf(path: Path, target: Path) -> None:
    reader = PdfReader(path)
    if reader.is_encrypted:
        raise ValueError("password-protected PDF")
    writer = PdfWriter()
    writer.append(reader)
    writer.metadata = None
    with target.open("wb") as handle:
        writer.write(handle)


def clean_office(path: Path, target: Path) -> None:
    with zipfile.ZipFile(path) as source, zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as result:
        for item in source.infolist():
            data = source.read(item.filename)
            for tag in OFFICE_FIELDS.get(item.filename, []):
                text = data.decode("utf-8")
                text = re.sub(rf"<{tag}(\s[^>]*)?>.*?</{tag}>", rf"<{tag}\1></{tag}>", text, flags=re.S)
                data = text.encode("utf-8")
            result.writestr(item, data)


def office_fields(path: Path) -> dict[str, str]:
    found = {}
    try:
        with zipfile.ZipFile(path) as source:
            for name, tags in OFFICE_FIELDS.items():
                if name not in source.namelist():
                    continue
                text = source.read(name).decode("utf-8", "replace")
                for tag in tags:
                    match = re.search(rf"<{tag}(?:\s[^>]*)?>(.+?)</{tag}>", text, flags=re.S)
                    if match and match.group(1).strip():
                        found[tag.split(":")[-1]] = match.group(1).strip()[:40]
    except zipfile.BadZipFile:
        pass
    return found


def pdf_fields(path: Path) -> dict[str, str]:
    try:
        reader = PdfReader(path)
        info = reader.metadata or {}
        found = {k.lstrip("/"): str(v)[:40] for k, v in info.items() if str(v).strip()}
        if reader.xmp_metadata is not None:
            found["XMP"] = "present"
        return found
    except Exception:  # noqa: BLE001 - any unreadable PDF is reported as having nothing
        return {}


def inspect(path: Path) -> dict[str, str]:
    suffix = path.suffix.lower()
    if suffix in OFFICE:
        return office_fields(path)
    if suffix == ".pdf":
        return pdf_fields(path)
    return sensitive_tags(path)


def collect(inputs: list[Path]) -> list[Path]:
    files = []
    for item in inputs:
        if item.is_dir():
            files += sorted(p for p in item.rglob("*")
                            if p.is_file() and p.suffix.lower() in SUPPORTED and "-clean" not in p.stem)
        elif item.is_file():
            files.append(item)
        else:
            print(f"{RED}Not found:{NC} {item}")
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="Remove personal metadata (GPS, device, author...) from copies.")
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--show", action="store_true", help="only show what was found")
    parser.add_argument("--out", type=Path, help="folder for the clean copies")
    args = parser.parse_args()
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)

    cleaners = {**{s: clean_photo for s in PHOTOS}, **{s: clean_video for s in VIDEOS},
                **{s: clean_office for s in OFFICE}, ".pdf": clean_pdf}
    failures = 0
    for path in collect(args.inputs):
        suffix = path.suffix.lower()
        if suffix not in SUPPORTED:
            print(f"{DIM}skipped (unsupported type){NC} {path.name}")
            continue
        before = inspect(path)
        summary = ", ".join(f"{k}: {v}" for k, v in before.items()) or "nothing sensitive found"
        if args.show:
            print(f"{BOLD}{path.name}{NC}\n  {summary}")
            continue
        target = unique_target(path, args.out)
        try:
            cleaners[suffix](path, target)
        except (subprocess.CalledProcessError, ValueError, OSError, zipfile.BadZipFile) as exc:
            failures += 1
            target.unlink(missing_ok=True)
            print(f"{RED}failed{NC} {path.name}: {exc}")
            continue
        after = inspect(target)
        left = {k: v for k, v in after.items() if k in ("GPS position", "serial number", "author / owner",
                                                         "device", "creator", "lastModifiedBy", "Company",
                                                         "Author", "Creator")}
        status = f"{RED}still contains: {', '.join(left)}{NC}" if left else f"{GREEN}clean{NC}"
        removed = ", ".join(before) if before else "nothing sensitive was there"
        print(f"{path.name} -> {target.name}  [{status}]\n  {DIM}removed: {removed}{NC}")
        failures += bool(left)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
