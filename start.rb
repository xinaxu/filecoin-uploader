#!/usr/bin/ruby
# frozen_string_literal: true

require_relative 'daemon/miner_manager'
require_relative 'daemon/archive_manager'
require_relative 'daemon/deal_manager'
require_relative 'daemon/retrieval_manager'
MinerManager.new.run_once
ArchiveManager.new.run_once
wallet = 'f3ukscanavfhuk6sm7fslvnwxcp6uw3z42z2t5rzu3lfys4ljfpldax4t75zzyo5memxa6tdtxk34d54c6rpma'
DealManager.new(wallet,
                1e10,
                518_400,
                10,
                ['f064218']).run_once

RetrievalManager.new(wallet).run_once
