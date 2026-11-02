#!/bin/bash

################################################################################
# Script:       pdf_ocr.sh
# Description:  Makes scanned PDFs searchable and copyable (adds an invisible
#               OCR text layer with OCRmyPDF/Tesseract). Pages that already
#               contain text are kept as is; pages are auto-rotated and
#               deskewed. Writes <name>-ocr.pdf next to each original, or
#               replaces the originals (moved to PDF_ORIGINALS_<date>/).
# Usage:        bash ~/Documents/scripts/pdf_ocr.sh [file.pdf ...] [-l fra+eng] [--replace]
#               Without file: asks for one file or all PDFs of the current directory.
#               -l / --lang   Tesseract languages (default: fra+eng, or $OCR_LANG)
#               --replace     replace the originals (kept in PDF_ORIGINALS_<date>/)
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

shopt -s nullglob nocaseglob

langs="${OCR_LANG:-fra+eng}"
replace=false
files=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--lang) langs="$2"; shift 2 ;;
        --replace) replace=true; shift ;;
        -h|--help) sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) files+=("$1"); shift ;;
    esac
done

if ! command -v tesseract >/dev/null 2>&1; then
    echo "Tesseract is required: brew install tesseract" >&2
    exit 1
fi

# OCRmyPDF: installed binary, or run through uv without installing anything
if command -v ocrmypdf >/dev/null 2>&1; then
    OCRMYPDF=(ocrmypdf)
elif command -v uvx >/dev/null 2>&1; then
    OCRMYPDF=(uvx --quiet ocrmypdf)
else
    echo "OCRmyPDF is required: brew install uv (it is then run with uvx), or brew install ocrmypdf" >&2
    exit 1
fi

# Keep only the languages installed for Tesseract
installed_langs=$(tesseract --list-langs 2>/dev/null | tail -n +2)
usable=()
missing=()
IFS='+' read -ra wanted <<<"$langs"
for l in "${wanted[@]}"; do
    if grep -qx "$l" <<<"$installed_langs"; then usable+=("$l"); else missing+=("$l"); fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[WARN] Tesseract language(s) not installed: ${missing[*]} (brew install tesseract-lang)" >&2
fi
if [[ ${#usable[@]} -eq 0 ]]; then
    usable=(eng)
    echo "[WARN] Falling back to English OCR." >&2
fi
langs=$(IFS=+; echo "${usable[*]}")

if [[ ${#files[@]} -eq 0 ]]; then
    echo "Do you want to OCR:"
    echo "1. A single PDF file"
    echo "2. All PDF files in the current directory"
    read -rp "Enter your choice (1-2): " choice
    if [[ "$choice" == "1" ]]; then
        read -rp "Enter the relative path of the PDF file: " f
        files=("${f/#\~/$HOME}")
    else
        for f in *.pdf; do
            [[ "$f" == *-ocr.pdf ]] || files+=("$f")
        done
    fi
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No PDF files found." >&2
    exit 1
fi

backup_folder="PDF_ORIGINALS_$(date +%Y%m%d_%H%M%S)"
ok=0
failed=0

for pdf in "${files[@]}"; do
    if [[ ! -f "$pdf" ]]; then
        echo "File not found: $pdf" >&2
        failed=$((failed + 1))
        continue
    fi
    output="${pdf%.*}-ocr.pdf"
    echo "OCR ($langs): $pdf"
    "${OCRMYPDF[@]}" --language "$langs" --skip-text --rotate-pages --deskew \
        --optimize 1 --output-type pdf --quiet "$pdf" "$output"
    status=$?
    if [[ $status -ne 0 || ! -s "$output" ]]; then
        echo "  OCR failed for $pdf (ocrmypdf exit code $status)" >&2
        rm -f "$output"
        failed=$((failed + 1))
        continue
    fi

    if $replace; then
        mkdir -p "$backup_folder"
        mv "$pdf" "$backup_folder/"
        mv "$output" "$pdf"
        echo "  Done: $pdf (original moved to $backup_folder/)"
    else
        echo "  Done: $output"
    fi
    ok=$((ok + 1))
done

echo "OCR completed: $ok file(s) processed, $failed failure(s)."
[[ $failed -eq 0 ]]
