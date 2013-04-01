#!/usr/bin/ruby

# Copyright (c) 2010 Geza Kovacs
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'optparse'
require 'tmpdir'

def shell_escape(s)
    "'" + s.gsub("'", "'\\''") + "'"
end

def sh(c, *args)
	outl = []
    if args.length > 0
        c = shell_escape(c) + ' '
        c << args.map {|w| shell_escape(w)}.join(' ')
    end
	IO.popen(c) { |f|
		while not f.eof?
			tval = f.gets
			puts tval
			outl.push(tval)
		end
	}
	return outl.join("")
end

def writef(fn, c)
	File.open(fn, "w") { |f|
		f.puts(c)
	}
end

def rmdir(dirn)
	Dir.foreach(dirn) { |fn|
		if fn == "." or fn == ".."
			next
		end
		fn = File.expand_path(dirn+"/"+fn)
		if File.directory?(fn)
			rmdir(fn)
		else
			File.delete(fn)
		end
	}
	Dir.delete(dirn)
end

appname = 'pdfocr'
version = [0,1,3]
infile = nil
outfile = nil
deletedir = true
deletefiles = true
language = 'eng'
checklang = false
tmp = nil
usecuneiform = false
usetesseract = false

optparse = OptionParser.new { |opts|
opts.banner = <<-eos
Usage: #{appname} -i input.pdf -o output.pdf
#{appname} adds text to PDF files using the ocropus, cuneiform, or tesseract OCR software
eos

	opts.on("-i", "--input [FILE]", "Specify input PDF file") { |fn|
		infile = fn
	}
	
	opts.on("-o", "--output [FILE]", "Specify output PDF file") { |fn|
		outfile = fn
	}
	
	opts.on("-c", "--cuneiform", "Use cuneiform instead of ocropus") {
		usecuneiform = true
	}
	
	opts.on("-t", "--tesseract", "Use tesseract instead of ocropus") {
		usetesseract = true
	}
	
	opts.on("-l", "--lang [LANG]", "Specify language for the OCR software") { |fn|
		language = fn
		checklang = true
	}
	
	opts.on("-w", "--workingdir [DIR]", "Specify directory to store temp files in") { |fn|
		deletedir = false
		tmp = fn
	}
	
	opts.on("-k", "--keep", "Keep temporary files around") {
		deletefiles = false
	}

	opts.on_tail("-h", "--help", "Show this message") {
		puts opts
		exit
	}

	opts.on_tail("-v", "--version", "Show version") {
		puts version.join('.')
		exit
	}

}

optparse.parse!(ARGV)

if not infile or infile == ""
	puts optparse
	puts
	puts "Need to specify an input PDF file"
	exit
end

if infile[-3..-1] != "pdf"
	puts "Input PDF file #{infile} should have a PDF extension"
	exit
end

#baseinfile = infile[0..-5]

#if not baseinfile or baseinfile == ""
#	puts "Input file #{infile} needs to have a name, not just an extension"
#	exit
#end

if not File.file?(infile)
	puts "Input file #{infile} does not exist"
	exit
end

infile = File.expand_path(infile)

if not outfile or outfile == ""
	puts optparse
	puts
	puts "Need to specify an output PDF file"
	exit
end

if outfile[-3..-1] != "pdf"
	puts "Output PDF file should have a PDF extension"
	exit
end

if outfile == infile
	puts "Output PDF file should not be the same as the input PDF file"
	exit
end

if File.file?(outfile)
	puts "Output file #{outfile} already exists"
	exit
end

outfile = File.expand_path(outfile)

if not language or language == ""
	puts "Need to specify a language"
	exit
end

if `which pdftk` == ""
	puts "pdftk command is missing. Install the pdftk package"
	exit
end

if `which pdftoppm` == ""
	puts "pdftoppm command is missing. Install the poppler-utils package"
	exit
end

if usecuneiform
	if `which cuneiform` == ""
		puts "The cuneiform command is missing. Install the cuneiform package."
		exit
	end
elsif usetesseract
	if `which tesseract` == ""
		puts "The tesseract command is missing. Install the tesseract-ocr package and the"
                puts "language packages you need, e.g. tesseract-ocr-deu, tesseract-ocr-deu-frak,"
                puts "or tesseract-ocr-eng."
		exit
	end
else
	if `which ocroscript` == ""
		puts "The ocroscript command is missing. Install the ocropus package."
		exit
	end
end

if `which hocr2pdf` == ""
	puts "hocr2pdf command is missing. Install the exactimage package"
	exit
end

if not deletedir
	if not File.directory?(tmp)
		puts "Working directory #{tmp} does not exist"
		exit
	else
		tmp = File.expand_path(tmp)+"/pdfocr"
		if File.directory?(tmp)
			puts "Directory #{tmp} already exists - remove it"
			exit
		else
			Dir.mkdir(tmp)
		end
	end
else
	tmp = Dir.mktmpdir
end

if checklang
	langlist = []
	if usecuneiform
		begin
			langlist = `cuneiform -l`.split("\n")[-1].split(":")[-1].delete(".").split(" ")
		rescue
			puts "Unable to list supported languages from cuneiform"
		end
	end
	if usetesseract
		begin
			langlist = `tesseract --list-langs 2>&1`.split("\n")[1..-1]
		rescue
			puts "Unable to list supported languages from tesseract"
		end
	end
	if langlist and not langlist.empty?()
		if not langlist.include?(language)
			puts "Language #{language} is not supported or not installed. Please choose from"
			puts langlist.join(' ')
			exit
		end
	end
end

puts "Input file is #{infile}"
puts "Output file is #{outfile}"
puts "Using working dir #{tmp}"

puts "Getting info from PDF file"

puts

pdfinfo = sh "pdftk", infile, "dump_data"

if not pdfinfo or pdfinfo == ""
	puts "Error: didn't get info from pdftk #{infile} dump_data"
	exit
end

puts

begin
	pagenum = pdfinfo.split("\n")[-1].split(" ")[-1].to_i
rescue
	puts "Error: didn't get page count for #{infile} from pdftk"
	exit
end

if pagenum == 0
	puts "Error: there are 0 pages in the input PDF file #{infile}"
	exit
end

writef(tmp+"/pdfinfo.txt", pdfinfo)

puts "Converting #{pagenum} pages"

numdigits = pagenum.to_s.length

Dir.chdir(tmp+"/") {

1.upto(pagenum) { |i|
	puts "=========="
	puts "Extracting page #{i}"
	basefn = i.to_s.rjust(numdigits, '0')
	sh "pdftk", infile, "cat", "#{i}", "output", basefn+'.pdf'
	if not File.file?(basefn+'.pdf')
		puts "Error while extracting page #{i}"
		next
	end
	puts "Converting page #{i} to ppm"

	sh "pdftoppm -r 300 #{shell_escape(basefn)}.pdf >#{shell_escape(basefn)}.ppm"
	if not File.file?(basefn+'.ppm')
		puts "Error while converting page #{i} to ppm"
		next
	end
	puts "Running OCR on page #{i}"
	if usecuneiform
		sh "cuneiform", "-l", language, "-f", "hocr", "-o", basefn+'.hocr', basefn+'.ppm'
	elsif usetesseract
		sh "tesseract", "-l", language, basefn+'.ppm', basefn+'.hocr', "hocr"
		sh "mv", basefn+'.hocr.html', basefn+'.hocr'
	else
		sh "ocroscript recognize #{shell_escape(basefn)}.ppm > #{shell_escape(basefn)}.hocr"
	end
	if not File.file?(basefn+'.hocr')
		puts "Error while running OCR on page #{i}"
		next
	end
	puts "Embedding text into PDF for page #{i}"
	sh "hocr2pdf -r 300 -i #{shell_escape(basefn)}.ppm -s -o #{shell_escape(basefn)}-new.pdf < #{shell_escape(basefn)}.hocr"
	if not File.file?(basefn+'-new.pdf')
		puts "Error while embedding text into PDF for page #{i}"
		next
	end
}

}

puts "Merging together PDF files"

sh "pdftk #{tmp+'/'+'*-new.pdf'} cat output #{tmp+'/merged.pdf'}"

puts "Updating PDF info for #{outfile}"

sh "pdftk", tmp+'/merged.pdf', "update_info", tmp+'/pdfinfo.txt', "output", outfile

if deletefiles
	puts "Cleaning up temporary files"
	rmdir(tmp)
end


