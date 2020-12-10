#!/usr/bin/ruby
require 'csv'
require 'slop'
require 'parallel'
opts = Slop::Options.new
opts.banner = "Usage: retrieval.rb [options]"
opts.string '-c', '--csv', 'CSV file uploaded to the slingshot phase 2 competition', required: true
opts.string '-f', '--filter', 'Regex expression to select the files to download in parallel', required: true
opts.string '-p', '--path', '[Optional] The folder to download the files to, default to current folder'
opts.string '-w', '--wallet', '[Optional] The wallet address to fund the retrieval'
opts.integer '-t', '--threads', '[Optional] The maximum number of threads for data retrieval, default to number of files to download'
opts.float '--price', '[Optional] The max price for each download, default to 0.0001 FIL'
opts.on '-h', '--help', 'print help' do
  puts opts
  exit
end
parser = Slop::Parser.new(opts)
begin
  options = parser.parse(ARGV)
rescue
  puts opts
  exit
end

all_deals = CSV.read(options[:csv], headers: true)
filter = Regexp.new options[:filter]
wallet = options[:wallet] || `lotus wallet default`.strip
puts 'lotus issue' unless $?.success?
files = all_deals.filter{|deal| filter.match(deal[3]) }.group_by{|x|x[3]}
n_threads = options[:threads] || files.count
price = options[:price] || 0.0001
path = options[:path] || Dir.getwd

Parallel.each(files, in_threads: n_threads) do |filename, deals|
  deals.each do |deal|
    miner = deal[1]
    cid = deal[2]
    puts "Retrieving #{filename} from #{miner} to #{path}"
    puts `echo lotus client retrieve --miner #{miner} --maxPrice #{price} #{cid} #{File.expand_path(File.join(path, filename))}`
    `lotus client retrieve --miner #{miner} --maxPrice #{price} #{cid} #{File.expand_path(File.join(path, filename))}`
    break if $?.success?
  end
end
