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

# Ask the user for the path of the PDF file
read -p "Enter the relative path of the PDF file to reduce: " pdf_file

# Check if the specified file exists
if [[ ! -f "$pdf_file" ]]; then
    echo "The specified file does not exist: $pdf_file"
    exit 1
fi

# Ask the user for the output file name
read -p "Enter the name of the reduced output PDF file: " output_file

# Present quality options to the user
echo "Select the quality level for the reduced PDF:"
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

# Compress the PDF using Ghostscript
echo "Reducing the size of $pdf_file with quality setting: $pdf_quality..."
$GHOSTSCRIPT -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=$pdf_quality \
    -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$output_file" "$pdf_file"

# Check if the output file was created successfully
if [[ -f "$output_file" ]]; then
    echo "PDF size reduction successful. Output file: $output_file"
else
    echo "Error reducing the PDF file size. The output file was not created."
    exit 1
fi

echo "Script completed."
