#!/bin/bash

################################################################################
# Script:       reducePdfSize.sh
# Description:  Reduces the file size of a given PDF using Ghostscript with
#               different quality options.
# Usage:        sh reducePdfSize.sh
# Author:       Pierre LAMOTTE
# Date:         16 SEPT 2024
################################################################################

# Variables
GHOSTSCRIPT=$(which gs)

# Check if Ghostscript is installed
if [[ -z "$GHOSTSCRIPT" ]]; then
    echo "Ghostscript is not installed. Please install it and try again."
    exit 1
fi

# Ask the user if they want to compress a single file or all files in the current directory
echo "Do you want to compress:"
echo "1. A single PDF file"
echo "2. All PDF files in the current directory"
read -p "Enter your choice (1-2): " file_choice

# If user chooses to compress a single file
if [[ "$file_choice" == "1" ]]; then
    # Ask the user for the path of the PDF file
    read -p "Enter the relative path of the PDF file to reduce: " pdf_file

    # Check if the specified file exists
    if [[ ! -f "$pdf_file" ]]; then
        echo "The specified file does not exist: $pdf_file"
        exit 1
    fi

    # Ask the user for the output file name
    read -p "Enter the name of the reduced output PDF file: " output_file

    files_to_process=("$pdf_file")
    output_files=("$output_file")
else
    # Compress all PDF files in the current directory
    files_to_process=(*.pdf)

    if [[ ${#files_to_process[@]} -eq 0 ]]; then
        echo "No PDF files found in the current directory."
        exit 1
    fi

    # Ask for the base name of the compressed files
    read -p "Enter the base name for the reduced PDF files (original names will be used): " base_name

    output_files=()
    for file in "${files_to_process[@]}"; do
        output_files+=("$base_name-$(basename "$file")")
    done
fi

# Present quality options to the user
echo "Select the quality level for the reduced PDFs:"
echo "1. Screen (low quality, smallest file size)"
echo "2. Ebook (medium quality, good for e-readers)"
echo "3. Printer (high quality, larger file size)"
echo "4. Prepress (very high quality, for professional printing)"
echo "5. Default (balanced quality and size)"
read -p "Enter your choice (1-5): " quality_choice

# Set the PDFSETTINGS parameter based on the user's choice
case $quality_choice in
    1) pdf_quality="/screen" ;;
    2) pdf_quality="/ebook" ;;
    3) pdf_quality="/printer" ;;
    4) pdf_quality="/prepress" ;;
    5) pdf_quality="/default" ;;
    *)
        echo "Invalid choice. Using default quality."
        pdf_quality="/default"
        ;;
esac

# Create a backup folder with timestamp for original files
timestamp=$(date +"%Y%m%d_%H%M%S")
backup_folder="PDF_ORIGINALS_$timestamp"
mkdir -p "$backup_folder"

# Process each file
for i in "${!files_to_process[@]}"; do
    pdf_file="${files_to_process[$i]}"
    output_file="${output_files[$i]}"

    echo "Reducing the size of $pdf_file with quality setting: $pdf_quality..."

    # Compress the PDF using Ghostscript
    $GHOSTSCRIPT -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=$pdf_quality \
        -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$output_file" "$pdf_file"

    # Check if the output file was created successfully
    if [[ -f "$output_file" ]]; then
        echo "PDF size reduction successful. Output file: $output_file"
        
        # Move the original file to the backup folder
        mv "$pdf_file" "$backup_folder/"
        echo "Original file moved to $backup_folder/"
    else
        echo "Error reducing the size of $pdf_file. The output file was not created."
    fi
done

echo "All files processed. Script completed."
