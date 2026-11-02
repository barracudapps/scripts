#!/bin/bash

################################################################################
# Script:       recursivePdf.sh
# Description:  Converts all .doc, .docx, .odt (and .rtf) files in a directory
#               and its sub-directories to PDF with LibreOffice. Optionally
#               combines the converted PDF files into a single one.
# Usage:        bash ~/Documents/scripts/recursivePdf.sh [directory]
# Author:       Pierre LAMOTTE
# Date:         29 MAY 2024
################################################################################

# Variables
LIBRE_OFFICE="/Applications/LibreOffice.app/Contents/MacOS/soffice"
command -v soffice >/dev/null 2>&1 && [[ ! -x "$LIBRE_OFFICE" ]] && LIBRE_OFFICE="$(command -v soffice)"

if [[ ! -x "$LIBRE_OFFICE" ]]; then
    echo "LibreOffice could not be found. Install it with: brew install --cask libreoffice" >&2
    exit 1
fi

# Directory: first argument, or ask the user (default: current directory)
input_folder="$1"
if [[ -z "$input_folder" ]]; then
    read -rp "Enter the path of the directory containing the files to be converted (default: current directory): " input_folder
fi
input_folder="${input_folder:-.}"
input_folder="${input_folder/#\~/$HOME}"   # expand a leading ~ typed by the user

if [[ ! -d "$input_folder" ]]; then
    echo "The specified directory does not exist: $input_folder" >&2
    exit 1
fi

read -rp "Do you want to delete the original files after conversion? (y/n): " delete_originals

converted_pdfs=()
failed=0

# find -print0 handles spaces and special characters in file names
while IFS= read -r -d '' file; do
    folder=$(dirname "$file")
    pdf="${file%.*}.pdf"
    echo "Converting $file to PDF..."
    "$LIBRE_OFFICE" --headless --convert-to pdf "$file" --outdir "$folder" >/dev/null 2>&1

    if [[ -f "$pdf" ]]; then
        converted_pdfs+=("$pdf")
        if [[ "$delete_originals" =~ ^[yY] ]]; then
            echo "PDF conversion successful. Deleting $file..."
            rm "$file"
        else
            echo "PDF conversion successful: $pdf"
        fi
    else
        echo "Error converting $file to PDF. The PDF file was not created." >&2
        failed=$((failed + 1))
    fi
done < <(find "$input_folder" -type f \( -iname '*.docx' -o -iname '*.doc' -o -iname '*.odt' -o -iname '*.rtf' \) ! -name '~$*' -print0 | sort -z)

echo "PDF conversion completed: ${#converted_pdfs[@]} converted, $failed failed."

if [[ ${#converted_pdfs[@]} -lt 2 ]]; then
    echo "Script completed."
    exit 0
fi

read -rp "Do you want to combine the ${#converted_pdfs[@]} converted PDF files? (y/n): " combine_response

if [[ "$combine_response" =~ ^[yY] ]]; then
    if ! command -v gs >/dev/null 2>&1; then
        echo "Ghostscript is required to combine PDFs: brew install ghostscript" >&2
        exit 1
    fi
    read -rp "Enter the name of the combined PDF file: " combined_pdf_file
    combined_pdf_file="${combined_pdf_file:-combined}"
    [[ "$combined_pdf_file" == *.pdf ]] || combined_pdf_file+=".pdf"
    output="$input_folder/$combined_pdf_file"

    if [[ -e "$output" ]]; then
        read -rp "$output already exists. Overwrite it? (y/n): " overwrite
        [[ "$overwrite" =~ ^[yY] ]] || { echo "Aborted."; exit 1; }
    fi

    # Combine only the files converted by this run (sorted by path)
    if gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile="$output" "${converted_pdfs[@]}"; then
        echo "PDF files combined into $output"
    else
        echo "Error while combining the PDF files." >&2
        exit 1
    fi
fi

echo "Script completed."
