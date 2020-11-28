#!/usr/bin/ruby
# frozen_string_literal: true

require_relative 'daemon/miner_manager'
require_relative 'daemon/archive_manager'
require_relative 'daemon/deal_manager'
#miner_manager = MinerManager.new
#miner_manager.daemonize
#ArchiveManager.new.daemonize(30, 5)
#wallet = LotusClient.new.wallet_default_address
#DealManager.new(miner_manager, wallet, 1e9, 518_400, 4).daemonize(120)

sleep