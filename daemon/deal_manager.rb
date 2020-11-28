require_relative '../database/database'
require_relative '../client/lotus'
class DealManager
  def initialize(miner_manager, wallet, max_price = 1e9, duration = 518_400, min_copies = 10, num_threads = 32)
    @duration = duration
    @wallet = wallet
    @max_price = max_price
    @miner_manager = miner_manager
    @logger = Logger.new(STDOUT)
    @lotus = LotusClient.new
    @base_path = File.join(ENV['slingshot_data_path'])
    @min_copies = min_copies
    @current_imported = @lotus.client_list_imports
    Retrieval.where(state: 'started').update(state: 'new')
  end

  def state_error?(deal_state)
    %i[StorageDealProposalRejected StorageDealProposalNotFound
       StorageDealSlashed StorageDealError].include? deal_state
  end

  def state_expired?(deal_state)
    deal_state == :StorageDealExpired
  end

  def state_valid?(deal_state)
    !state_error?(deal_state) && !state_expired?(deal_state)
  end

  def state_success?(deal_state)
    deal_state == :StorageDealActive
  end

  def daemonize(poll_interval = 60)
    Thread.new do
      loop do
        @logger.info 'Checking all current deals'
        current_deals = @lotus.client_list_deals
        deals_by_cid = current_deals.group_by(&:data_cid)
        deals_by_miner = current_deals.group_by(&:miner_id)
        deals_by_miner.each do |miner_id, deals|
          total = deals.length
          valid = deals.count { |deal| state_valid?(deal.state) }
          Miner.where(miner_id: miner_id).update(deal_started: total, deal_success: valid)
        end
        Archive.all.each do |archive|
          case archive.state
          when 'new'
            import archive
          when 'started'
            make_deal archive, deals_by_cid[archive.data_cid] || []
          when 'done'
            check_done archive, deals_by_cid[archive.data_cid]
          end
        end
        @logger.info 'Checking deals complete'
        sleep poll_interval
      end
    end
  end

  def import(archive)
    imported = @current_imported.find do |imported|
      imported.file_path == File.join(@base_path, archive.dataset, archive.filename)
    end
    if imported.nil?
      data_cid, import_id = @lotus.client_import File.join(@base_path, archive.dataset, archive.filename)
    else
      data_cid = imported.data_cid
      import_id = imported.import_id
    end
    @logger.info("Imported to lotus #{archive.dataset}/#{archive.filename} - [#{import_id}] #{data_cid}")
    piece_size, piece_cid = @lotus.client_deal_piece_cid(data_cid)
    archive.update(state: 'started', data_cid: data_cid, piece_cid: piece_cid,
                   import_id: import_id, piece_size: piece_size)
  end

  def make_deal(archive, current_deals)
    success_deals = current_deals.count { |deal| state_success?(deal.state) }
    if success_deals >= @min_copies
      archive.update(state: 'done')
      return
    end

    valid_deals = current_deals.count { |deal| state_valid?(deal.state) }
    return if valid_deals >= @min_copies

    miners = @miner_manager.get_miners_for_sealing(@min_copies - valid_deals, @max_price, archive.piece_size,
                                                    current_deals.map(&:miner_id))
    miners.each do |miner|
      epoch_price = (miner.price.to_f * archive.piece_size / 1024 / 1024 / 1024 * 1.000001).ceil
      @logger.info("Making deal for #{archive.dataset}/#{archive.filename} with " \
                   "#{miner.miner_id} and epoch price #{epoch_price / 1e18}")
      @lotus.client_start_deal(archive.data_cid, @wallet, miner.miner_id, epoch_price, @duration)
    end
  end

  def check_done(archive, current_deals)
    all_complete = current_deals.filter { |deal| state_success?(deal.state) }.all do |deal|
      current_retrieval = Retrieval.find_by(proposal_cid: deal.proposal_cid)
      current_retrieval != nil && %w[success failed].include?(current_retrieval.state)
    end

    if all_complete
      archive.update(state: 'verified')
      return
    end

    current_deals.filter { |deal| state_success?(deal.state) }
                 .each do |deal|
      current_retrieval = Retrieval.find_or_create_by(proposal_cid: deal.proposal_cid) do |retrieval|
        retrieval.miner = Miner.find_by(miner_id: deal.miner_id)
        retrieval.archive = archive
        retrieval.state = 'new'
      end
      next if current_retrieval.state != 'new'

      Thread.new do
        lotus = LotusClient.new(30)
        offer = lotus.client_miner_query_offer(deal.miner_id, deal.data_cid)
        if offer != :timeout
          response = lotus.client_retrieve(offer.data_cid, offer.size, offer.min_price,
                                           offer.unseal_price, offer.payment_interval,
                                           offer.payment_interval_increase, @wallet,
                                           offer.miner_id, offer.peer_address, offer.peer_id,
                                           '/dev/null')
        end
        if offer == :timeout || response == :timeout
          current_retrieval.update(state: 'failed')
        else
          current_retrieval.update(state: 'success')
        end
      end
    end
  end
end