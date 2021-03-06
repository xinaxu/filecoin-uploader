require_relative '../database/database'
require_relative '../client/lotus'
require_relative '../util/sample'
require 'socket'

class DealManager
  def initialize(
                 max_price = 1e10,
                 duration = 518_400,
                 min_copies = 10,
                 miner_blacklist = []
                 )
    @duration = duration
    @max_price = max_price
    @logger = Logger.new(STDOUT)
    @lotus = LotusClient.new 7200
    @min_copies = min_copies
    @miner_blacklist = miner_blacklist
    @host = Socket.gethostname
    @base_path = File.join(ENV['slingshot_data_path'])
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

  def run_once(dataset, wallet)
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
            retrieval_state: 0,
            archive: Archive.find_by(data_cid: deal.data_cid, host: @host),
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

    Archive.where(host: @host, dataset: dataset).shuffle.each do |archive|
      next unless File.exists? File.join(@base_path, archive.dataset, archive.filename)
      make_deal archive, wallet
    end

    @logger.info 'Checking deals complete'
  end

  def make_deal(archive, wallet)
    valid_deals = archive.deals.where.not(state: %w[StorageDealProposalRejected StorageDealProposalNotFound
                                           StorageDealSlashed StorageDealError])
                      .where(slashed: false).count
    return if valid_deals >= @min_copies

    miners = get_miners_for_sealing(1, @max_price, archive.piece_size,
                                    archive.miners.map(&:miner_id))
    miners.each do |miner|
      epoch_price = (miner.price.to_f * archive.piece_size / 1024 / 1024 / 1024 * 1.000001).ceil
      @logger.info("Making deal for #{archive.dataset}/#{archive.filename} with " \
                   "#{miner.miner_id} and total price #{epoch_price * @duration / 1e18} (#{miner.price.to_f} * #{archive.piece_size} * #{@duration})")
      if :timeout == @lotus.client_start_deal(archive.data_cid, wallet, miner.miner_id, epoch_price, @duration)
        raise :timeout
      end
    end
  end

  def get_miners_for_sealing(number, price, piece_size, excluded_miner_ids)
    miners = Miner.where('min_piece_size <= ? AND max_piece_size >= ? AND online = ?', piece_size, piece_size, true)
                 .reject do |miner|
      miner.price.to_i > price.to_i || excluded_miner_ids.include?(miner.miner_id) || @miner_blacklist.include?(miner.miner_id)
    end
    miners = miners.map do |miner|
      [miner, miner.score.to_f]
    end
    weighted_samples(miners, number).reject { |miner, rate| miner.nil? }
  end
end
