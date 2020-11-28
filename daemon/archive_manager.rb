require_relative '../database/database'

class ArchiveManager
  def initialize
    @logger = Logger.new(STDOUT)
  end

  def daemonize(poll_interval = 60, modified_before = 5)
    Thread.new do
      base_path = File.join(ENV['slingshot_data_path'])
      loop do
        # @logger.info 'Polling data folder for change'
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
        # @logger.info 'Polling data complete'
        sleep poll_interval
      end
    end
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
    if Archive.find_by(dataset: data_set, filename: file_name).nil?
      format = get_format(file_name)
      @logger.info "Import to database #{data_set}/#{file_name}, format: #{format}"
      Archive.create(dataset: data_set, filename: file_name, state: 'new', format: format)
    end
  end
end

