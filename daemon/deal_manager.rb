require_relative '../database/database'
require_relative '../client/lotus'
require_relative '../util/sample'

class DealManager
  def initialize(wallet,
                 max_price = 1e9,
                 duration = 518_400,
                 min_copies = 10,
                 miner_blacklist = [])
    @duration = duration
    @wallet = wallet
    @max_price = max_price
    @logger = Logger.new(STDOUT)
    @lotus = LotusClient.new 60
    @min_copies = min_copies
    @miner_blacklist = miner_blacklist
  end

  def state_error?(deal_state)
    %w[StorageDealProposalRejected StorageDealProposalNotFound
       StorageDealSlashed StorageDealError].include? deal_state
  end

  def state_valid?(deal_state)
    !state_error?(deal_state) && !state_expired?(deal_state)
  end

  def state_success?(deal_state)
    deal_state == 'StorageDealActive'
  end

  def state_expired?(deal_state)
    deal_state == 'StorageDealExpired'
  end

  def run_once
    @logger.info 'Checking all current deals'
    current_deals = @lotus.client_list_deals
    # update database
    current_deals.each do |deal|
      d = Deal.find_by(proposal_cid: deal.proposal_cid)
      if d.nil?
        Deal.create(
            proposal_cid: deal.proposal_cid,
            deal_id: deal.deal_id,
            state: deal.state,
            duration: deal.duration,
            creation_time: deal.creation_time,
            slashed: @lotus.deal_slashed?(deal.deal_id),
            retrieval_state: 'new',
            archive: Archive.find_by(data_cid: deal.data_cid),
            miner: Miner.find_by(miner_id: deal.miner_id)
        )
      else
        d.update(
            deal_id: deal.deal_id,
            state: deal.state,
            duration: deal.duration,
            creation_time: deal.creation_time,
            slashed: @lotus.deal_slashed?(deal.deal_id)
        )
      end
    end

    Archive.all.each do |archive|
      make_deal archive
      # check_done archive, deals_by_cid[archive.data_cid]
    end

    @logger.info 'Checking deals complete'
  end

  def daemonize(poll_interval = 600)
    Thread.new do
      loop do
        run_once
        sleep poll_interval
      end
    end
  end


  def make_deal(archive)
    archive.deals.where(state: 'StorageDealActive', slashed: false, retrieval_state: 'new').each do |deal|
      # check_done archive, deal
    end

    valid_deals = archive.deals.where.not(state: %w[StorageDealProposalRejected StorageDealProposalNotFound
                                           StorageDealSlashed StorageDealError])
                      .where(slashed: false).count
    return if valid_deals >= @min_copies

    miners = get_miners_for_sealing(@min_copies - valid_deals, @max_price, archive.piece_size,
                                    archive.miners.map(&:miner_id))
    miners.each do |miner|
      epoch_price = (miner.price.to_f * archive.piece_size / 1024 / 1024 / 1024 * 1.000001).ceil
      @logger.info("Making deal for #{archive.dataset}/#{archive.filename} with " \
                   "#{miner.miner_id} and total price #{epoch_price * @duration / 1e18} (#{miner.price.to_f} * #{archive.piece_size} * #{@duration})")
      @lotus.client_start_deal(archive.data_cid, @wallet, miner.miner_id, epoch_price, @duration)
    end
  end

  def get_miners_for_sealing(number, price, piece_size, excluded_miner_ids)
    miners = Miner.where('min_piece_size <= ? AND max_piece_size >= ? AND online = ?', piece_size, piece_size, true)
                 .reject do |miner|
      miner.price.to_i > price.to_i || excluded_miner_ids.include?(miner.miner_id)
    end
    miners = miners.map do |miner|
      ratio = 1.0 - miner.deals.where('state in (?, ?, ?, ?) or slashed = ? or retrieval_state = ?',
                                      'StorageDealProposalRejected',
                                      'StorageDealProposalNotFound',
                                      'StorageDealSlashed',
                                      'StorageDealError',
                                      true,
                                      'failed').count / (1.0 + miner.deals.count)
      [miner, ratio]
    end
    weighted_samples(miners, number).reject { |miner, rate| miner.nil? }
  end

  def check_done(archive, deal)
    Thread.new do
      lotus = LotusClient.new(300)
      @logger.info "Querying offer with #{deal.miner_id} for #{archive.dataset}/#{archive.filename}"
      offer = lotus.client_miner_query_offer(deal.miner_id, deal.data_cid)
      unless %i[timeout, error].include?(offer)
        @logger.info "Retrieving with #{offer.miner_id} - #{offer.peer_address} for #{archive.dataset}/#{archive.filename}"
        lotus = LotusClient.new(7200)
        response = lotus.client_retrieve(offer.data_cid, offer.size, offer.min_price,
                                         offer.unseal_price, offer.payment_interval,
                                         offer.payment_interval_increase, @wallet,
                                         offer.miner_id, offer.peer_address, offer.peer_id,
                                         '/dev/null')
      end
      if %i[timeout, error].include?(offer) || %i[timeout, error].include?(response)
        deal.update(retrieval_state: 'failed')
      else
        deal.update(retrieval_state: 'success')
      end
    end
  end
end