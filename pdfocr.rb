#!/usr/bin/env ruby

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

def shell_escape(str)
  "'" + str.gsub("'", "'\\''") + "'"
end

def sh(cmd, *args)
  outl = []

  unless args.empty?
    cmd = shell_escape(cmd) + ' '
    cmd << args.map { |w| shell_escape(w) }.join(' ')
  end

  IO.popen(cmd) do |f|
    until f.eof?
      tval = f.gets
      puts tval
      outl.push(tval)
    end
  end

  outl.join('')
end

def writef(filename, text)
  File.open(filename, 'w') do |f|
    f.puts(text)
  end
end

def rmdir(dirname)
  Dir.foreach(dirname) do |filename|
    next if filename.in?(['.', '..'])

    filename = File.expand_path("#{dirname}/#{filename}")
    if File.directory?(filename)
      rmdir(filename)
    else
      File.delete(filename)
    end
  end

  Dir.delete(dirname)
end

app_name = 'pdfocr'
version = [0, 1, 4]
infile = nil
outfile = nil
delete_dir = true
delete_files = true
language = 'eng'
check_lang = false
tmp = nil
use_ocropus = false
use_cuneiform = false
use_tesseract = false
run_unpaper = false
outdpi = '300' # Use string, since this is input to commands anyway

optparse = OptionParser.new do |opts|
  opts.banner = <<~USAGE
    Usage: #{app_name} -i input.pdf -o output.pdf
    #{app_name} adds text to PDF files using the ocropus, cuneiform, or tesseract OCR software
  USAGE

  opts.on('-i', '--input [FILE]', 'Specify input PDF file') do |fn|
    infile = fn
  end

  opts.on('-o', '--output [FILE]', 'Specify output PDF file') do |fn|
    outfile = fn
  end

  opts.on('-u', '--unpaper', 'Run unpaper on each page before OCR.') do
    run_unpaper = true
  end

  opts.on('-t', '--tesseract', 'Use tesseract as the OCR engine (default)') do
    use_tesseract = true
  end

  opts.on('-c', '--cuneiform', 'Use cuneiform as the OCR engine') do
    use_cuneiform = true
  end

  opts.on('-p', '--ocropus', 'Use ocropus as the OCR engine') do
    use_ocropus = true
  end

  opts.on('-l', '--lang [LANG]', 'Specify language for the OCR software') do |fn|
    language = fn
    check_lang = true
  end

  opts.on('-L', '--nocheck-lang LANG', 'Suppress checking of language parameter') do |fn|
    language = fn
    check_lang = false
  end

  opts.on('-w', '--workingdir [DIR]', 'Specify directory to store temp files in') do |fn|
    delete_dir = false
    tmp = fn
  end

  opts.on('-k', '--keep', 'Keep temporary files around') do
    delete_files = false
  end

  opts.on_tail('-h', '--help', 'Show this message') do
    puts opts
    exit
  end

  opts.on_tail('-v', '--version', 'Show version') do
    puts version.join('.')
    exit
  end

  opts.on('--dpi DPI', 'Set OCR and output resolution in DPI. Useful to reduce PDF size') do |fn|
    outdpi = fn
  end
end

optparse.parse!(ARGV)

if !infile || infile == ''
  puts optparse
  puts
  puts 'Need to specify an input PDF file'
  exit
end

if infile[-3..-1].casecmp('pdf') != 0
  puts "Input PDF file #{infile} should have a PDF extension"
  exit
end

# baseinfile = infile[0..-5]

# if not baseinfile or baseinfile == ''
#   puts "Input file #{infile} needs to have a name, not just an extension"
#   exit
# end

unless File.file?(infile)
  puts "Input file #{infile} does not exist"
  exit
end

infile = File.expand_path(infile)

if !outfile || outfile == ''
  puts optparse
  puts
  puts 'Need to specify an output PDF file'
  exit
end

if outfile[-3..-1].casecmp('pdf') != 0
  puts 'Output PDF file should have a PDF extension'
  exit
end

if outfile == infile
  puts 'Output PDF file should not be the same as the input PDF file'
  exit
end

if File.file?(outfile)
  puts "Output file #{outfile} already exists"
  exit
end

outfile = File.expand_path(outfile)

if !language || language == ''
  puts 'Need to specify a language'
  exit
end

if `which pdftk` == ''
  puts 'pdftk command is missing. Install the pdftk package'
  exit
end

if `which pdftoppm` == ''
  puts 'pdftoppm command is missing. Install the poppler-utils package'
  exit
end

if use_ocropus
  if `which ocroscript` == ''
    puts 'The ocroscript command is missing. Install the ocropus package.'
    exit
  end
elsif use_cuneiform
  if `which cuneiform` == ''
    puts 'The cuneiform command is missing. Install the cuneiform package.'
    exit
  end
elsif use_tesseract
  if `which tesseract` == ''
    puts 'The tesseract command is missing. Install the tesseract-ocr package and the'
    puts 'language packages you need, e.g. tesseract-ocr-deu, tesseract-ocr-deu-frak,'
    puts 'or tesseract-ocr-eng.'
    exit
  end
else
  if `which tesseract` != ''
    use_tesseract = true
  elsif `which cuneiform` != ''
    use_cuneiform = true
  elsif `which ocroscript` != ''
    use_ocropus = true
  else
    puts 'The tesseract command is missing. Install the tesseract-ocr package and the'
    puts 'language packages you need, e.g. tesseract-ocr-deu, tesseract-ocr-deu-frak,'
    puts 'or tesseract-ocr-eng.'
    exit
  end
end

if `which hocr2pdf` == ''
  puts 'hocr2pdf command is missing. Install the exactimage package'
  exit
end

if run_unpaper
  if `which unpaper` == ''
    puts 'The unpaper command is missing. Install the unpaper package.'
    exit
  end
end

if delete_dir
  tmp = Dir.mktmpdir
elsif File.directory?(tmp)
  tmp = "#{File.expand_path(tmp)}/pdfocr"
  if File.directory?(tmp)
    puts "Directory #{tmp} already exists - remove it"
    exit
  else
    Dir.mkdir(tmp)
  end
else
  puts "Working directory #{tmp} does not exist"
  exit
end

if check_lang
  langlist = []
  if use_cuneiform
    begin
      langlist = `cuneiform -l`.split("\n")[-1].split(':')[-1].delete('.').split(' ')
    rescue
      puts 'Unable to list supported languages from cuneiform'
    end
  end
  if use_tesseract
    begin
      langlist = `tesseract --list-langs 2>&1`.split("\n")[1..-1]
    rescue
      puts 'Unable to list supported languages from tesseract'
    end
  end
  if langlist && !langlist.empty?
    unless langlist.include?(language)
      puts "Language #{language} is not supported or not installed. Please choose from"
      puts langlist.join(' ')
      exit
    end
  end
end

puts "Input file is #{infile}"
puts "Output file is #{outfile}"
puts "Using working dir #{tmp}"

puts 'Getting info from PDF file'

puts

pdfinfo = sh 'pdftk', infile, 'dump_data'

if !pdfinfo || pdfinfo == ''
  puts "Error: didn't get info from pdftk #{infile} dump_data"
  exit
end

puts

begin
  pdfinfo =~ /NumberOfPages: (\d+)/
  pagenum = Regexp.last_match(1).to_i
rescue
  puts "Error: didn't get page count for #{infile} from pdftk"
  exit
end

if pagenum.zero?
  puts "Error: there are 0 pages in the input PDF file #{infile}"
  exit
end

writef("#{tmp}/pdfinfo.txt", pdfinfo)

puts "Converting #{pagenum} pages"

numdigits = pagenum.to_s.length

Dir.chdir("#{tmp}/") do
  1.upto(pagenum) do |i|
    puts '=========='
    puts "Extracting page #{i}"
    basefn = i.to_s.rjust(numdigits, '0')
    sh 'pdftk', infile, 'cat', i.to_s, 'output', "#{basefn}.pdf"
    unless File.file?("#{basefn}.pdf")
      puts "Error while extracting page #{i}"
      next
    end
    puts "Converting page #{i} to ppm"

    sh "pdftoppm -cropbox -r #{outdpi} #{shell_escape(basefn)}.pdf >#{shell_escape(basefn)}.ppm"
    unless File.file?("#{basefn}.ppm")
      puts "Error while converting page #{i} to ppm"
      next
    end

    if run_unpaper
      puts "Running unpaper on page #{i}"
      sh 'unpaper', "#{basefn}.ppm", "#{basefn}_unpaper.ppm"
      unless File.file?("#{basefn}_unpaper.ppm")
        puts "Error while running unpaper on page #{i}"
        next
      end
      sh 'mv', "#{basefn}_unpaper.ppm", "#{basefn}.ppm"
    end

    puts "Running OCR on page #{i}"
    if use_cuneiform
      sh 'cuneiform', '-l', language, '-f', 'hocr', '-o', "#{basefn}.hocr", "#{basefn}.ppm"
    elsif use_tesseract
      sh 'tesseract', '--dpi', outdpi, '-l', language, "#{basefn}.ppm", "#{basefn}-new", 'pdf'
      unless File.file?("#{basefn}-new.pdf")
        puts "Error while running OCR on page #{i}"
        puts "Input page will be added to output without OCR."
        sh 'mv', "#{basefn}.pdf", "#{basefn}-new.pdf"
      end
    else
      sh "ocroscript recognize #{shell_escape(basefn)}.ppm > #{shell_escape(basefn)}.hocr"
    end

    next if use_tesseract

    unless File.file?("#{basefn}-new.pdf")
      puts "Error while running OCR on page #{i}"
      next
    end
  end
end

puts 'Merging together PDF files'
sh "pdftk \"#{tmp}/\"*-new.pdf cat output \"#{tmp}/merged.pdf\""

puts "Updating PDF info for #{outfile}"

sh 'pdftk', "#{tmp}/merged.pdf", 'update_info', "#{tmp}/pdfinfo.txt", 'output', outfile

if delete_files
  puts 'Cleaning up temporary files'
  rmdir(tmp)
end
