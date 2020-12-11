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
    @lotus = LotusClient.new 30
  end

  def run_once
    @logger.info 'Updating retrieval status'
    update_db
    @logger.info 'Starting new retrievals'

    Parallel.each(Deal.joins(:archive).where(archives: {host: @host}, retrieval_state: 0, state: 'StorageDealActive', slashed: false).to_a, in_threads: @num_threads) do |deal|
      archive = deal.archive
      miner = deal.miner
      lotus = LotusClient.new 120
      @logger.info "[#{archive.dataset}/#{archive.filename}] Querying offer with #{miner.miner_id}"
      offer = lotus.client_miner_query_offer(miner.miner_id, archive.data_cid)
      if %i[timeout error].include?(offer)
        @logger.info "[#{archive.dataset}/#{archive.filename}] Querying offer failed with #{offer}"
        deal.update(retrieval_state: -1)
        next
      end
      if offer.min_price.to_i  + offer.unseal_price.to_i > @max_price.to_i 
        @logger.info "[#{archive.dataset}/#{archive.filename}] Skipped because ask price is too high #{offer.min_price} + #{offer.unseal_price} > #{@max_price}"
        next
      end
      @logger.info "[#{archive.dataset}/#{archive.filename}] Start retrieving with #{miner.miner_id} for #{offer.min_price}"
      lotus = LotusClient.new 600
      # Start retrieval and check later
      response = lotus.client_retrieve(offer.data_cid, offer.size, offer.min_price,
                                       offer.unseal_price, offer.payment_interval,
                                       offer.payment_interval_increase, @wallet,
                                       offer.miner_id, offer.peer_address, offer.peer_id,
                                       '/dev/null')
      if response == :error
        deal.update(retrieval_state: -1)
      else
        deal.update(retrieval_state: Time.now.to_i)
      end
    end

    @logger.info 'All retrievals started'
  end

  def update_db
    @lotus.client_list_data_transfers.filter {|transfer| !transfer.is_sender && transfer.is_initiator}.each do |transfer|
      peer_id = transfer.peer_id
      transfer_id = transfer.transfer_id
      data_cid = transfer.data_cid
      archive = Archive.find_by(data_cid: data_cid, host: @host)
      next if archive.nil?
      miner = Miner.find_by(peer_id: peer_id)
      next if miner.nil?
      deal = Deal.find_by(archive: archive, miner: miner)
      next if deal.nil?
      if %i[Cancelled Failed].include? transfer.status
        if deal.retrieval_state >= 0
          @logger.info "[#{archive.dataset}/#{archive.filename}] Retrieval failed with miner #{miner.miner_id}"
          deal.update(retrieval_state: -1) 
        end
      elsif :Completed == transfer.status
        if deal.retrieval_state != 1
          @logger.info "[#{archive.dataset}/#{archive.filename}] Retrieval succeeded with miner #{miner.miner_id}"
          deal.update(retrieval_state: 1) 
        end
      elsif deal.retrieval_state > 1 && Time.now.to_i - deal.retrieval_state > 7 * 24 * 3600
        @lotus.client_cancel_data_transfer transfer_id, peer_id, true
        if deal.retrieval_state >= 0
          @logger.info "[#{archive.dataset}/#{archive.filename}] Retrieval cancelled with miner #{miner.miner_id}"
          deal.update(retrieval_state: -1) 
        end
      elsif deal.retrieval_state > 1 && Time.now.to_i - deal.retrieval_state > 3 * 24 * 3600
        @lotus.client_restart_data_transfer transfer_id, peer_id, true
        @logger.info "[#{archive.dataset}/#{archive.filename}] Retrieval restarted with miner #{miner.miner_id}"
      end
    end
  end
end
