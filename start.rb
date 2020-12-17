#!/usr/bin/ruby
# frozen_string_literal: true

require_relative 'daemon/miner_manager'
require_relative 'daemon/archive_manager'
require_relative 'daemon/deal_manager'
require_relative 'daemon/retrieval_manager'
Thread.abort_on_exception = true
wallet = 'f3ukscanavfhuk6sm7fslvnwxcp6uw3z42z2t5rzu3lfys4ljfpldax4t75zzyo5memxa6tdtxk34d54c6rpma'

miner_manager = MinerManager.new
archive_manager = ArchiveManager.new
deal_manager = DealManager.new(wallet,
                               1e10,
                               1051200,
                               10,
                               ['f064218'])
retrieval_manager = RetrievalManager.new(wallet)

Thread.new do
  loop do
    miner_manager.run_once
    sleep(3600 * 24)
  end
end

loop do
  begin
    archive_manager.run_once
    deal_manager.run_once
    retrieval_manager.run_once
    sleep 600
  rescue Faraday::ConnectionFailed
    sleep 600
  end
end
