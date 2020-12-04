#!/usr/bin/ruby
# frozen_string_literal: true

require_relative 'daemon/miner_manager'
require_relative 'daemon/archive_manager'
require_relative 'daemon/deal_manager'
require_relative 'daemon/retrieval_manager'
wallet = 'f3ukscanavfhuk6sm7fslvnwxcp6uw3z42z2t5rzu3lfys4ljfpldax4t75zzyo5memxa6tdtxk34d54c6rpma'
shutdown = false
Signal.trap("INT") {
  shutdown = true
}

loop do
  exit if shutdown
  MinerManager.new.run_once
  exit if shutdown
  ArchiveManager.new.run_once
  exit if shutdown
  DealManager.new(wallet,
                  1e10,
                  518_400,
                  10,
                  ['f064218']).run_once
  exit if shutdown
  RetrievalManager.new(wallet).run_once
  exit if shutdown
  sleep 1800
end
