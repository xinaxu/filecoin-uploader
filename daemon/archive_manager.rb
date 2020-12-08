require_relative '../database/database'
require 'socket'

class ArchiveManager
  def initialize
    @logger = Logger.new(STDOUT)
    @lotus = LotusClient.new
    @base_path = File.join(ENV['slingshot_data_path'])
    @host = Socket.gethostname
  end

  def run_once(modified_before = 5)
    @current_imported = @lotus.client_list_imports
    @logger.info 'Polling data folder for change'
    base_path = File.join(ENV['slingshot_data_path'])
    Dir.each_child(base_path) do |data_set|
      unless File.directory? File.join(base_path, data_set)
        @logger.warn "Skipping file #{data_set} in the root folder."
        next
      end

      Dir.each_child(File.join(base_path, data_set)) do |file_name|
        file_path = File.join(base_path, data_set, file_name)
        unless File.file? file_path
          @logger.warn "Skipping nested folder #{file_name} in folder #{data_set}."
          next
        end

        if Time.now - File.mtime(file_path) < modified_before
          @logger.debug "Skip file created too recently #{data_set}/#{file_name}"
          next
        end

        db_import data_set, file_name
      end
    end
    @logger.info 'Polling data complete'
  end

  def get_format(file_name)
    segments = file_name.split('.')
    return 'binary' if segments.length == 1

    if /[0-9]+/ =~ segments[-1]
      if segments.length == 2
        'binary'
      else
        segments[-2]
      end
    else
      segments[-1]
    end
  end

  def db_import(data_set, file_name)
    return unless Archive.find_by(dataset: data_set, filename: file_name, host: @host).nil?

    format = get_format(file_name)
    @logger.info "Import to database #{data_set}/#{file_name}, format: #{format}"

    imported = @current_imported.find do |imported|
      imported.file_path == File.join(@base_path, data_set, file_name)
    end
    if imported.nil?
      data_cid, import_id = @lotus.client_import File.join(@base_path, data_set, file_name)
      @logger.info("Imported to lotus #{data_set}/#{file_name} - [#{import_id}] #{data_cid}")
    else
      data_cid = imported.data_cid
      import_id = imported.import_id
    end
    piece_size, piece_cid = @lotus.client_deal_piece_cid(data_cid)
    Archive.create(dataset: data_set, filename: file_name, format: format,
                   data_cid: data_cid, piece_cid: piece_cid,
                   import_id: import_id, piece_size: piece_size,
                   host: @host)
  end
end

