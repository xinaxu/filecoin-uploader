require 'active_record'

ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = :info
ActiveRecord::Base.establish_connection(
  adapter: 'mysql2',
  host: 'localhost',
  database: 'lotus',
  username: 'root',
  password: 'password',
  pool: 128,
  timeout: 30
)

ActiveRecord::Schema.define do
  break if table_exists? :miners

  create_table :miners, if_not_exists: true do |table|
    table.string  :miner_id
    table.string  :peer_id
    table.integer :sector_size
    table.string  :storage_power
    table.string  :price
    table.string  :verified_price
    table.integer :min_piece_size
    table.integer :max_piece_size
    table.integer :last_update
    table.boolean :online
  end

  create_table :archives, if_not_exists: true do |table|
    table.string :dataset
    table.string :filename
    table.string :format
    table.string :data_cid
    table.string :piece_cid
    table.integer :import_id
    table.integer :piece_size
    table.string :host
  end

  create_table :deals, if_not_exists: true do |table|
    table.string  :proposal_cid
    table.integer :deal_id
    table.string  :state
    table.integer :duration
    table.string :creation_time
    table.boolean :slashed
    table.integer :retrieval_state # 0: new, -1: success, n: failed times
    table.belongs_to :archive
    table.belongs_to :miner
  end

  change_column :miners, :sector_size, 'BIGINT UNSIGNED'
  change_column :miners, :min_piece_size, 'BIGINT UNSIGNED'
  change_column :miners, :max_piece_size, 'BIGINT UNSIGNED'
  change_column :archives, :piece_size, 'BIGINT UNSIGNED'

  add_index :miners, :miner_id, unique: true
  add_index :archives, %i[dataset filename], unique: true
  add_index :archives, :data_cid
  add_index :deals, :proposal_cid, unique: true
end

class Miner < ActiveRecord::Base
  has_many :deals
end

class Archive < ActiveRecord::Base
  has_many :deals
  has_many :miners, through: :deals
end

class Deal < ActiveRecord::Base
  belongs_to :archive
  belongs_to :miner
end
