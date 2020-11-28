require 'jsonrpc-client'

MinerPower = Struct.new(:miner_power, :total_power, :has_min_power)
StorageAsk = Struct.new(:price, :verified_price, :min_piece_size, :max_piece_size)
DealInfo = Struct.new(:proposal_cid, :state, :miner_id, :data_cid, :piece_cid, :piece_size,
                      :price_per_epoch, :duration, :deal_id, :creation_time, :verified)
Import = Struct.new(:import_id, :data_cid, :file_path)
QueryOffer = Struct.new(:data_cid, :size, :min_price, :unseal_price, :payment_interval,
                        :payment_interval_increase, :miner_id, :peer_address, :peer_id)

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

  # @return string
  def wallet_default_address
    @client.invoke('Filecoin.WalletDefaultAddress', [])
  end

  # @return string
  def wallet_balance(wallet)
    @client.invoke('Filecoin.WalletBalance', [wallet])
  end

  # @return string[]
  def state_list_miners
    @client.invoke('Filecoin.StateListMiners', [nil])
  end

  # @return string
  def state_miner_power(miner_id)
    response = @client.invoke('Filecoin.StateMinerPower', [miner_id, nil])
    MinerPower.new(response['MinerPower']['QualityAdjPower'], response['TotalPower']['QualityAdjPower'], response['HasMinPower'])
  end

  # @return sector_size(int) and peer_id(string)
  def state_miner_info(miner_id)
    response = @client.invoke('Filecoin.StateMinerInfo', [miner_id, nil])
    [response['SectorSize'], response['PeerId']]
  end

  # @return price: string, size: int
  def client_query_ask(peer_id, miner_id)
    response = @client.invoke('Filecoin.ClientQueryAsk', [peer_id, miner_id])
    StorageAsk.new(response['Price'], response['VerifiedPrice'],
                   response['MinPieceSize'], response['MaxPieceSize'])
  rescue Faraday::TimeoutError
    :timeout
  end

  # @return data_cid(string), import_id(int)
  def client_import(path, is_car = false)
    response = @client.invoke('Filecoin.ClientImport', [Path: path, IsCAR: is_car])
    [response['Root']['/'], response['ImportID']]
  end

  # @return piece_size(int), piece_cid(string)
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

  # @return list of DealInfo, size and duration is int. others are string.
  def client_list_deals
    @client.invoke('Filecoin.ClientListDeals', []).map do |deal|
      DealInfo.new(deal['ProposalCid']['/'], @@deal_state_map[deal['State']], deal['Provider'], deal['DataRef']['Root']['/'],
                   deal['PieceCID']['/'], deal['Size'], deal['PricePerEpoch'], deal['Duration'],
                   deal['DealID'], deal['CreationTime'], deal['Verified'])
    end
  end

  # @return list of Import
  def client_list_imports
    @client.invoke('Filecoin.ClientListImports', [])
           .filter { |import| import['Source'] == 'import' }.map do |import|
      Import.new(import['Key'], import['Root']['/'], import['FilePath'])
    end
  end

  def client_miner_query_offer(miner_id, data_cid)
    response = @client.invoke('Filecoin.ClientMinerQueryOffer', [miner_id, {'/': data_cid}, nil])
    QueryOffer.new(response['Root']['/'], response['Size'], response['MinPrice'],
                   response['UnsealPrice'], response['PaymentInterval'], response['PaymentIntervalIncrease'],
                   response['Miner'], response['MinerPeer']['Address'], response['MinerPeer']['ID'])
  rescue Faraday::TimeoutError
    :timeout
  end

  def client_retrieve(data_cid, size, price, unseal_price, payment_interval, payment_interval_increase,
                      wallet, miner_id, miner_peer_address, miner_peer_id, file_path)
    @client.invoke('Filecoin.ClientRetrieve',[{
                   Root: {'/': data_cid},
                   Piece: nil,
                   Size: size,
                   Total: price.to_i.to_s,
                   UnsealPrice: unseal_price.to_i.to_s,
                   PaymentInterval: payment_interval,
                   PaymentIntervalIncrease: payment_interval_increase,
                   Client: wallet,
                   Miner: miner_id,
                   MinerPeer: {
                     Address: miner_peer_address,
                     ID: miner_peer_id,
                     PieceCID: nil
                   }
                 }, {
                   Path: file_path,
                   IsCAR: false
                 }])
  rescue Faraday::TimeoutError
    :timeout
  end
end
