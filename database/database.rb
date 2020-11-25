require 'active_record'

ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = :info
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: File.join(ENV['slingshot_database_path'], 'data.db')
)

ActiveRecord::Schema.define do
  created = create_table :miners, if_not_exists: true do |table|
    table.string  :miner_id
    table.string  :peer_id
    table.integer :sector_size
    table.integer :storage_power
    table.integer :price
    table.integer :verified_price
    table.integer :min_piece_size
    table.integer :max_piece_size
    table.string  :last_update
    table.integer :deal_started
    table.integer :deal_success
    table.integer :retrieval_started
    table.integer :retrieval_success
  end

  create_table :files, if_not_exists: true do |table|
    table.string :dataset
    table.string :filename
    table.string :format
    table.string :state
    table.string :data_cid
    table.string :piece_cid
    table.string :import_id
    table.string :piece_size
  end

  unless index_exists? :miners, :miner_id, unique: true
    add_index :miners, :miner_id, unique: true
    add_index :miners, %i[dataset filename], unique: true
  end
end

class Miner < ActiveRecord::Base
end

class File < ActiveRecord::Base
end