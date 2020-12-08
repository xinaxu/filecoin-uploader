require_relative '../database/database'
require_relative '../client/lotus'
require_relative '../util/sample'
require 'socket'

class RetrievalManager
  def initialize(wallet,
                 max_price = 1e15,
                 n_threads = 16)
    @wallet = wallet
    @max_price = max_price
    @logger = Logger.new(STDOUT)
    @n_threads = n_threads
    @host = Socket.gethostname
  end

  def run_once
    @logger.info 'Starting retrieval tests'
    count = 0
    Parallel.each(Deal.where(retrieval_state: 0, state: 'StorageDealActive', slashed: false).to_a, in_threads: @num_threads) do |deal|
      archive = deal.archive
      next if archive.nil? || archive.host != @host

      miner = deal.miner
      lotus = LotusClient.new 120
      @logger.info "[#{archive.dataset}/#{archive.filename}] Querying offer with #{miner.miner_id}"
      offer = lotus.client_miner_query_offer(miner.miner_id, archive.data_cid)
      if %i[timeout error].include?(offer)
        @logger.info "[#{archive.dataset}/#{archive.filename}] Querying offer failed with #{offer}"
        deal.increment!(:retrieval_state)
        next
      end
      if offer.min_price.to_i > @max_price.to_i 
        @logger.info "[#{archive.dataset}/#{archive.filename}] Skipped because ask price is too high #{offer.min_price} > #{@max_price}"
        next
      end
      if offer.unseal_price.to_i > @max_price.to_i 
        @logger.info "[#{archive.dataset}/#{archive.filename}] Skipped because unseal price is too high #{offer.unseal_price} > #{@max_price}"
        next
      end
      @logger.info "[#{archive.dataset}/#{archive.filename}] Start retrieving with #{offer.peer_address} for #{offer.min_price}"
      count += 1

      # Allow 3 hours for retrieval
      lotus = LotusClient.new 10_800
      response = lotus.client_retrieve(offer.data_cid, offer.size, offer.min_price,
                                       offer.unseal_price, offer.payment_interval,
                                       offer.payment_interval_increase, @wallet,
                                       offer.miner_id, offer.peer_address, offer.peer_id,
                                       '/dev/null')
      if %i[timeout error].include?(response)
        @logger.info "[#{archive.dataset}/#{archive.filename}] Retrieval failed with #{response}"
        deal.increment!(:retrieval_state)
        next
      end
      @logger.info "[#{archive.dataset}/#{archive.filename}] Retrieval succeeded."
      deal.update(retrieval_state: -1)
    end

    @logger.info 'Retrieval complete'
    count
  end
end
