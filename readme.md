# pdfocr

pdfocr adds an OCR text layer to scanned PDF files, allowing them to be searched. It currently depends on Ruby 1.8.7 or above, and uses ocropus, cuneiform, or tesseract for performing OCR.

## Using

To use, run:

pdfocr -i input.pdf -o output.pdf

For more details, see the manpage.

## Dependencies

pdfocr requires tesseract and hocr2pdf. These can be provided by installing the packages tesseract-ocr, tesseract-ocr-eng (or other languages you need), and exactimage from your distribution.

## Credits

pdfocr was written by [Geza Kovacs](http://github.com/gkovacs)

pdfocr is hosted at http://github.com/gkovacs/pdfocr

Christian Pietsch added tesseract support.
