#!/usr/bin/ruby
require 'csv'
require 'slop'
require 'parallel'
require_relative 'client/lotus'
require 'fileutils'
opts = Slop::Options.new
opts.banner = "Usage: retrieval.rb [options]"
opts.string '-c', '--csv', 'CSV file uploaded to the slingshot phase 2 competition', required: true
opts.string '-f', '--filter', 'Regex expression to select the files to download in parallel', required: true
opts.string '-p', '--path', '[Optional] The folder to download the files to, default to current folder'
opts.string '-w', '--wallet', '[Optional] The wallet address to fund the retrieval'
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
wallet = options[:wallet] || LotusClient.new.wallet_default_address
files = all_deals.filter{|deal| filter.match(deal[3]) }.group_by{|x|x[3]}
price = options[:price] || 0.0001
path = options[:path] || Dir.getwd

files.each do |filename, deals|
  puts "Retrieving #{filename}"
  Parallel.each(deals, in_threads: deals.count) do |deal|
    miner = deal[1]
    cid = deal[2]
    offer = LotusClient.new(60).client_miner_query_offer(miner, cid)
    if %i[timeout error].include? offer
      puts "#{miner} query offer failed with #{offer}"
      next
    end
    if offer.min_price.to_i + offer.unseal_price.to_i > price * 1e18
      puts "#{miner} asks for too high prices min: #{offer.min_price} unseal: #{offer.unseal_price}"
      next
    end
    FileUtils.mkdir_p File.join(path, 'tmp', miner)
    response = LotusClient.new(3600).client_retrieve(offer.data_cid, offer.size, offer.min_price,
                                       offer.unseal_price, offer.payment_interval,
                                       offer.payment_interval_increase, wallet,
                                       offer.miner_id, offer.peer_address, offer.peer_id,
                                       File.expand_path(File.join(path, 'tmp', miner, filename)))
    unless %i[timeout error].include?(response)
      puts "#{filename} retrieved from #{miner}"
      FileUtils.mv(File.join(path, 'tmp', miner, filename), File.join(path))
      raise Parallel::Kill
    end
  end
end
