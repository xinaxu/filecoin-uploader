require 'jsonrpc-client'

MinerPower = Struct.new(:miner_power, :total_power, :has_min_power)
StorageAsk = Struct.new(:price, :verified_price, :min_piece_size, :max_piece_size)
DealInfo = Struct.new(:proposal_id, :state, :miner_id, :data_cid, :piece_cid, :piece_size,
                      :price_per_epoch, :duration, :deal_id, :creation_time, :verified)

class LotusClient
  @@deal_state_map = %i[
    StorageDealUnknown
    StorageDealProposalNotFound
    StorageDealProposalRejected
    StorageDealProposalAccepted
    StorageDealStaged
    StorageDealSealing
    StorageDealFinalizing
    StorageDealActive
    StorageDealExpired
    StorageDealSlashed
    StorageDealRejecting
    StorageDealFailing
    StorageDealFundsReserved
    StorageDealCheckForAcceptance
    StorageDealValidating
    StorageDealAcceptWait
    StorageDealStartDataTransfer
    StorageDealTransferring
    StorageDealWaitingForData
    StorageDealVerifyData
    StorageDealReserveProviderFunds
    StorageDealReserveClientFunds
    StorageDealProviderFunding
    StorageDealClientFunding
    StorageDealPublish
    StorageDealPublishing
    StorageDealError
    StorageDealProviderTransferRestart
    StorageDealClientTransferRestart
  ]
  def initialize(timeout = 15)
    connection = Faraday.new { |connection|
      connection.adapter Faraday.default_adapter
      connection.authorization(:Bearer, ENV['lotus_token'])
      connection.options.timeout = 15
      # connection.response :logger, @logger, :bodies => true
    }
    @client = JSONRPC::Client.new('http://127.0.0.1:1234/rpc/v0', { connection: connection })
  end

  def wallet_default_address
    @client.invoke('Filecoin.WalletDefaultAddress', [])
  end

  def wallet_balance(wallet)
    @client.invoke('Filecoin.WalletBalance', [wallet]).to_f
  end

  def state_list_miners
    @client.invoke('Filecoin.StateListMiners', [nil])
  end

  def state_miner_power(miner_id)
    response = @client.invoke('Filecoin.StateMinerPower', [miner_id, nil])
    MinerPower.new(response['MinerPower'], response['TotalPower'], response['HasMinPower'])
  end

  def state_miner_peer_id(miner_id)
    @client.invoke('Filecoin.StateMinerInfo', [miner_id, nil])['PeerId']
  end

  # @return storage ask
  def client_query_ask(peer_id, miner_id)
    response = @client.invoke('Filecoin.ClientQueryAsk', [peer_id, miner_id])
    StorageAsk.new(response['Price'].to_f, response['VerifiedPrice'].to_f,
                   response['MinPieceSize'].to_i, response['MaxPieceSize'].to_i)
  end

  # @return [data_cid, import_id]
  def client_import(path, is_car = false)
    response = @client.invoke('Filecoin.ClientImport', [Path: path, IsCAR: is_car])
    [response['Root']['/'], response['ImportID']]
  end

  # @return [piece_size, piece_cid]
  def client_deal_piece_cid(data_cid)
    response = @client.invoke('Filecoin.ClientDealPieceCID', [{ '/' => data_cid }])
    [response['PieceSize'], response['PieceCID']['/']]
  end

  # @return proposal_cid
  def client_start_deal(data_cid, wallet, miner_id, epoch_price, duration)
    @client.invoke('Filecoin.ClientStartDeal', [
                     Data: {
                         TransferType: 'graphsync',
                         Root: {
                             '/' => data_cid
                         }
                     },
                     Wallet: wallet,
                     Miner: miner_id,
                     EpochPrice: epoch_price.to_i.to_s,
                     MinBlocksDuration: duration,
                     FastRetrieval: true
                   ])['/']
  end

  # @return list of DealInfo
  def client_list_deals
    @client.invoke('Filecoin.ClientListDeals', []).map do |deal|
      DealInfo.new(deal['ProposalCid']['/'], @@deal_state_map[deal['State']], deal['Provider'], deal['DataRef']['Root']['/'],
                   deal['PieceCID']['/'], deal['Size'], deal['PricePerEpoch'].to_f, deal['Duration'],
                   deal['DealID'], deal['CreationTime'], deal['Verified'])
    end
  end
end