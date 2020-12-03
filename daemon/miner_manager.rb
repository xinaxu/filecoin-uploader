require_relative '../client/lotus'
require_relative '../database/database'
require 'parallel'

class MinerManager
  def initialize(num_threads = 32)
    @lotus = LotusClient.new
    @num_threads = num_threads
    @logger = Logger.new(STDOUT)
  end

  def populate_each(miner_id)
    lotus = LotusClient.new
    sector_size, peer_id = lotus.state_miner_info miner_id
    miner_power = lotus.state_miner_power miner_id
    return unless miner_power.has_min_power

    storage_ask = lotus.client_query_ask peer_id, miner_id
    return if storage_ask == :timeout || storage_ask == :error
    Miner.create(miner_id: miner_id, peer_id: peer_id, sector_size: sector_size,
                 storage_power: miner_power.miner_power, price: storage_ask.price,
                 verified_price: storage_ask.verified_price,
                 min_piece_size: storage_ask.min_piece_size,
                 max_piece_size: storage_ask.max_piece_size,
                 last_update: Time.now.to_i,
                 online: true)
  end

  def update_each(miner)
    lotus = LotusClient.new
    sector_size, peer_id = lotus.state_miner_info miner.miner_id
    miner_power = lotus.state_miner_power miner.miner_id

    storage_ask = lotus.client_query_ask peer_id, miner.miner_id
    if storage_ask == :timeout || storage_ask == :error
      miner.update(online: false, last_update: Time.now.to_i)
    else
      miner.update(peer_id: peer_id, sector_size: sector_size,
                   storage_power: miner_power.miner_power, price: storage_ask.price,
                   verified_price: storage_ask.verified_price,
                   min_piece_size: storage_ask.min_piece_size,
                   max_piece_size: storage_ask.max_piece_size,
                   last_update: Time.now.to_i,
                   online: true)
    end
  end

  def run_once(update_interval = 0)
    @logger.info 'Start updating miners'
    miner_ids = @lotus.state_list_miners
    Parallel.each(miner_ids, in_threads: @num_threads) do |miner_id|
      miner = Miner.find_by(miner_id: miner_id)
      if miner.nil?
        populate_each miner_id
        next
      end

      if Time.now.to_i - miner.last_update > update_interval
        update_each miner
      end
    end
    @logger.info 'Miner update complete'
  end

  def daemonize(check_interval = 3600, update_interval = 86400)
    Thread.new do
      loop do
        run_once update_interval
        sleep check_interval
      end
    end
  end
end