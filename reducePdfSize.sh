#!/bin/bash

################################################################################
# Script:       reducePdfSize.sh
# Description:  Reduces the file size of a given PDF (or of all PDFs in the
#               current directory) using Ghostscript with different quality
#               options. Originals are moved to a timestamped backup folder,
#               except when the "reduced" file is not smaller (then it is
#               discarded and the original is kept in place).
# Usage:        bash ~/Documents/scripts/reducePdfSize.sh [file.pdf]
# Author:       Pierre LAMOTTE
# Date:         16 SEPT 2024
################################################################################

shopt -s nullglob nocaseglob

# Variables
GHOSTSCRIPT=$(command -v gs)

# Check if Ghostscript is installed
if [[ -z "$GHOSTSCRIPT" ]]; then
    echo "Ghostscript is not installed. Install it with: brew install ghostscript" >&2
    exit 1
fi

file_size() { stat -f%z "$1"; }
human_size() { du -h "$1" | cut -f1 | tr -d ' '; }

# A file given as argument means "single file" mode
if [[ -n "$1" ]]; then
    file_choice=1
    pdf_file="$1"
else
    echo "Do you want to compress:"
    echo "1. A single PDF file"
    echo "2. All PDF files in the current directory"
    read -rp "Enter your choice (1-2): " file_choice
fi

if [[ "$file_choice" == "1" ]]; then
    [[ -z "$pdf_file" ]] && read -rp "Enter the relative path of the PDF file to reduce: " pdf_file
    pdf_file="${pdf_file/#\~/$HOME}"

    if [[ ! -f "$pdf_file" ]]; then
        echo "The specified file does not exist: $pdf_file" >&2
        exit 1
    fi

    default_output="${pdf_file%.*}-reduced.pdf"
    read -rp "Enter the name of the reduced output PDF file (default: $default_output): " output_file
    output_file="${output_file:-$default_output}"
    [[ "$output_file" == *.[pP][dD][fF] ]] || output_file+=".pdf"

    if [[ "$output_file" -ef "$pdf_file" || "$output_file" == "$pdf_file" ]]; then
        echo "The output file must be different from the input file." >&2
        exit 1
    fi

    files_to_process=("$pdf_file")
    output_files=("$output_file")
else
    read -rp "Enter the prefix for the reduced PDF files (default: reduced): " base_name
    base_name="${base_name:-reduced}"

    files_to_process=()
    output_files=()
    for file in *.pdf; do
        # Skip the outputs of a previous run
        [[ "$file" == "$base_name"-* ]] && continue
        files_to_process+=("$file")
        output_files+=("$base_name-$file")
    done

    if [[ ${#files_to_process[@]} -eq 0 ]]; then
        echo "No PDF files found in the current directory." >&2
        exit 1
    fi
    echo "${#files_to_process[@]} PDF file(s) to process."
fi

# Present quality options to the user
echo "Select the quality level for the reduced PDFs:"
echo "1. Screen (72 dpi, smallest file size)"
echo "2. Ebook (150 dpi, good for e-readers and e-mail)"
echo "3. Printer (300 dpi, larger file size)"
echo "4. Prepress (300 dpi, color preserving, for professional printing)"
echo "5. Default (balanced quality and size)"
read -rp "Enter your choice (1-5, default 2): " quality_choice

case "${quality_choice:-2}" in
    1) pdf_quality="/screen" ;;
    2) pdf_quality="/ebook" ;;
    3) pdf_quality="/printer" ;;
    4) pdf_quality="/prepress" ;;
    5) pdf_quality="/default" ;;
    *)
        echo "Invalid choice. Using ebook quality."
        pdf_quality="/ebook"
        ;;
esac

# Backup folder (created only when an original has to be moved)
timestamp=$(date +"%Y%m%d_%H%M%S")
backup_folder="PDF_ORIGINALS_$timestamp"

for i in "${!files_to_process[@]}"; do
    pdf_file="${files_to_process[$i]}"
    output_file="${output_files[$i]}"

    echo "Reducing the size of $pdf_file with quality setting: $pdf_quality..."

    if ! "$GHOSTSCRIPT" -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dPDFSETTINGS="$pdf_quality" \
        -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$output_file" "$pdf_file" || [[ ! -s "$output_file" ]]; then
        echo "Error reducing the size of $pdf_file. The output file was not created." >&2
        rm -f "$output_file"
        continue
    fi

    before=$(file_size "$pdf_file")
    after=$(file_size "$output_file")
    if (( after >= before )); then
        echo "No gain for $pdf_file ($(human_size "$pdf_file") -> $(human_size "$output_file")): original kept."
        rm -f "$output_file"
        continue
    fi

    echo "PDF size reduction successful: $(human_size "$pdf_file") -> $(human_size "$output_file") ($(( (before - after) * 100 / before ))% smaller). Output file: $output_file"
    mkdir -p "$backup_folder"
    mv "$pdf_file" "$backup_folder/"
    echo "Original file moved to $backup_folder/"
done

echo "All files processed. Script completed."
