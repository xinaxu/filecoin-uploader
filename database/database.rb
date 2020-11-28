require 'active_record'

ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = :info
ActiveRecord::Base.establish_connection(
  adapter: 'mysql2',
  host: 'localhost',
  database: 'lotus',
  username: 'root',
  password: 'password',
  pool: 64,
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
    table.integer :deal_started
    table.integer :deal_success
  end

  create_table :archives, if_not_exists: true do |table|
    table.string :dataset
    table.string :filename
    table.string :format
    table.string :state # new, started, done, verified
    table.string :data_cid
    table.string :piece_cid
    table.integer :import_id
    table.integer :piece_size
  end

  create_table :retrievals, if_not_exists: true do |table|
    table.belongs_to :miner
    table.belongs_to :archive
    table.string :proposal_cid
    table.string :state # new, started, success, failed
  end

  change_column :miners, :sector_size, 'BIGINT UNSIGNED'
  change_column :miners, :min_piece_size, 'BIGINT UNSIGNED'
  change_column :miners, :max_piece_size, 'BIGINT UNSIGNED'
  change_column :archives, :piece_size, 'BIGINT UNSIGNED'

  add_index :miners, :miner_id, unique: true
  add_index :archives, %i[dataset filename], unique: true
  add_index :retrievals, :proposal_cid, unique: true
end

class Miner < ActiveRecord::Base
  has_many :retrievals
end

class Archive < ActiveRecord::Base
  has_many :retrievals
end

class Retrieval < ActiveRecord::Base
end
